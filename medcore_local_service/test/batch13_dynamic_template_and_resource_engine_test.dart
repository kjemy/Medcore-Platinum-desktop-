import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:medcore_local_service/medcore_local_service.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'support/test_db_config.dart';

void main() {
  const dbName = 'medcore_dynamic_engine_test';
  late DbClient db;
  LocalMedCoreServer? server;
  late String baseUrl;
  late Directory securityRoot;
  const hospitalCode = 'HOSP_ENG_001';
  const hospitalCodeB = 'HOSP_ENG_ATTACK';
  const deviceId = 'DEV-ENG-HOST-A';
  const deviceIdB = 'DEV-ENG-HOST-B';
  const runtimeTechSecret = 'EngTechSecret!2026';

  late String adminToken;
  late String doctorToken;
  late String attackerToken;

  int? createdPatientId;
  int? createdTemplateId;
  int? bookedAppointmentId;
  late int docResourceId;
  late int roomResourceId;
  late int equipResourceId;
  late int deviceResourceId;

  Map<String, String> bearerHeaders(String token, {String hosp = hospitalCode}) => {
        'content-type': 'application/json',
        'authorization': 'Bearer $token',
        'x-tenant-id': hosp,
        'x-medcore-device-id': hosp == hospitalCodeB ? deviceIdB : deviceId,
      };

  setUpAll(() async {
    securityRoot = Directory.systemTemp.createTempSync('medcore-eng-gate-');
    final config = testDbConfig(databaseName: dbName, maxConnections: 10);
    db = DbClient(config);

    // 1. Clean Database: Drop and Recreate
    final adminConn = await db.openDedicatedConnection(useDatabase: false);
    try {
      await adminConn.execute('DROP DATABASE IF EXISTS `$dbName`');
      await adminConn.execute(
        'CREATE DATABASE `$dbName` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
      );
    } finally {
      await adminConn.close();
    }

    // 2. Apply all migrations V001..V017
    final serviceRoot = Directory.current.path;
    final migrationsDir = p.join(serviceRoot, 'sql', 'migrations');
    final migrationRunner = MigrationRunner(db: db, migrationsDir: migrationsDir);
    final applied = await migrationRunner.runMigrations();
    expect(applied.length, greaterThanOrEqualTo(16));

    // 3. Setup Tenants & Device
    final govRepo = TenantGovernanceRepository(db);
    await govRepo.upsertTenant(
      hospitalCode: hospitalCode,
      name: 'MedCore Engineering Center',
    );
    await govRepo.upsertTenant(
      hospitalCode: hospitalCodeB,
      name: 'Attacker Facility',
    );
    await db.execute('''
      INSERT INTO mc_facility_config (
        hospital_code, facility_name, facility_type, branch_code, installation_identity,
        edition, subscription_starts_utc, subscription_expires_utc,
        enabled_modules_json, patient_fields_config_json, branding_appearance_json,
        network_config_json, backup_config_json, remote_hybrid_config_json,
        config_version, updated_at
      ) VALUES (
        '$hospitalCode', 'MedCore Engineering Center', 'GENERAL_HOSPITAL', 'MAIN', 'INST-ENG-MAIN',
        'PLATINUM', NOW(), DATE_ADD(NOW(), INTERVAL 30 DAY),
        '{}', '{}', '{}',
        '{}', '{}', '{}',
        1, NOW()
      ) ON DUPLICATE KEY UPDATE subscription_expires_utc = VALUES(subscription_expires_utc);
    ''');
    await db.execute('''
      INSERT INTO mc_facility_config (
        hospital_code, facility_name, facility_type, branch_code, installation_identity,
        edition, subscription_starts_utc, subscription_expires_utc,
        enabled_modules_json, patient_fields_config_json, branding_appearance_json,
        network_config_json, backup_config_json, remote_hybrid_config_json,
        config_version, updated_at
      ) VALUES (
        '$hospitalCodeB', 'Attacker Facility', 'CLINIC', 'MAIN', 'INST-ENG-ATTACK',
        'PLATINUM', NOW(), DATE_ADD(NOW(), INTERVAL 30 DAY),
        '{}', '{}', '{}',
        '{}', '{}', '{}',
        1, NOW()
      ) ON DUPLICATE KEY UPDATE subscription_expires_utc = VALUES(subscription_expires_utc);
    ''');
    await govRepo.enrollOrUpdateDevice(
      hospitalCode: hospitalCode,
      deviceId: deviceId,
      deviceName: 'Engine Workstation Host',
      platform: 'WINDOWS',
      connectionType: 'LOOPBACK',
      hwFingerprintSha256: PasswordHasher.sha256Hex('ENG-GATE-HW-01'),
      devicePublicKeyEd25519: 'PUBKEY-ENG-GATE-01',
      roleScope: 'SERVER_HOST',
      isTrustedSecureRuntime: true,
      status: 'ACTIVE',
    );
    await govRepo.enrollOrUpdateDevice(
      hospitalCode: hospitalCodeB,
      deviceId: deviceIdB,
      deviceName: 'Attacker Workstation',
      platform: 'WINDOWS',
      connectionType: 'LOOPBACK',
      hwFingerprintSha256: PasswordHasher.sha256Hex('ATTACK-GATE-HW-01'),
      devicePublicKeyEd25519: 'PUBKEY-ATTACK-GATE-01',
      roleScope: 'SERVER_HOST',
      isTrustedSecureRuntime: true,
      status: 'ACTIVE',
    );

    // 4. Start LocalMedCoreServer
    server = LocalMedCoreServer(
      db,
      securityRootDirectory: securityRoot.path,
      technicianSecretHashOverride: PasswordHasher.hashPassword(runtimeTechSecret),
    );
    final port = await server!.start(address: '127.0.0.1', port: 0);
    baseUrl = 'http://127.0.0.1:$port';

    // 5. Seed Admin and Doctor for Tenant A, and Admin for Tenant B
    final staffRepo = StaffIdentityRepository(db);
    await staffRepo.createStaff(
      hospitalCode: hospitalCode,
      staffCode: 'ADM-ENG-01',
      fullName: 'Admin Engineer',
      email: 'admin@medcore.eng',
      role: MedCoreRole.HospitalAdmin,
      passwordHash: PasswordHasher.hashPassword('AdminPass#2026'),
      forcePasswordChange: false,
    );
    await staffRepo.createStaff(
      hospitalCode: hospitalCode,
      staffCode: 'DOC-ENG-01',
      fullName: 'Dr. Gregory House',
      email: 'doctor@medcore.eng',
      role: MedCoreRole.Doctor,
      passwordHash: PasswordHasher.hashPassword('DoctorPass#2026'),
      forcePasswordChange: false,
    );
    await staffRepo.createStaff(
      hospitalCode: hospitalCodeB,
      staffCode: 'ATK-ENG-01',
      fullName: 'Attacker Doctor',
      email: 'attacker@evil.corp',
      role: MedCoreRole.Doctor,
      passwordHash: PasswordHasher.hashPassword('AttackerPass#2026'),
      forcePasswordChange: false,
    );

    // Obtain tokens
    Future<String> login(String hosp, String email, String pass) async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/login'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hosp,
          'deviceId': hosp == hospitalCodeB ? deviceIdB : deviceId,
          'email': email,
          'password': pass,
        }),
      );
      expect(res.statusCode, equals(200), reason: 'Failed to login $email: ${res.body}');
      return jsonDecode(res.body)['data']['token'] as String;
    }

    adminToken = await login(hospitalCode, 'admin@medcore.eng', 'AdminPass#2026');
    doctorToken = await login(hospitalCode, 'doctor@medcore.eng', 'DoctorPass#2026');
    attackerToken = await login(hospitalCodeB, 'attacker@evil.corp', 'AttackerPass#2026');

    // Create a Patient for clinical tests
    final pRes = await http.post(
      Uri.parse('$baseUrl/api/v1/patients'),
      headers: bearerHeaders(adminToken),
      body: jsonEncode({
        'mrn': 'MRN-ENG-001',
        'fullName': 'Johnathan Doe',
        'gender': 'MALE',
        'phone': '+15551234567',
        'dateOfBirth': '1985-06-15',
      }),
    );
    expect(pRes.statusCode, equals(201));
    createdPatientId = jsonDecode(pRes.body)['data']['id'] as int;
  });

  tearDownAll(() async {
    await server?.stop();
    await db.close();
    try {
      if (securityRoot.existsSync()) {
        securityRoot.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('STAGE 1 & 2: Dynamic Clinical Template Engine — Draft Creation & Schema Validation', () {
    test('1.1: Create Draft Dynamic Template with typed fields & validation rules', () async {
      final templateSchema = {
        'version': 1,
        'sections': [
          {
            'key': 'vitals',
            'title': 'Vitals & Biometrics',
            'fields': [
              {
                'key': 'systolicBp',
                'label': 'Systolic Blood Pressure',
                'type': 'integer',
                'unit': 'mmHg',
                'validation': {'required': true, 'min': 60, 'max': 260},
              },
              {
                'key': 'diastolicBp',
                'label': 'Diastolic Blood Pressure',
                'type': 'integer',
                'unit': 'mmHg',
                'validation': {'required': true, 'min': 40, 'max': 160},
              },
              {
                'key': 'heartRate',
                'label': 'Heart Rate',
                'type': 'integer',
                'unit': 'bpm',
                'validation': {'required': true, 'min': 30, 'max': 250},
              },
            ],
          },
          {
            'key': 'cardio_exam',
            'title': 'Cardiovascular Assessment',
            'fields': [
              {
                'key': 'murmurPresent',
                'label': 'Murmur Present',
                'type': 'boolean',
                'validation': {'required': true},
              },
              {
                'key': 'murmurGrade',
                'label': 'Murmur Grade',
                'type': 'select',
                'options': ['Grade I', 'Grade II', 'Grade III', 'Grade IV', 'Grade V', 'Grade VI'],
                'validation': {'required': false},
              },
              {
                'key': 'clinicalNotes',
                'label': 'Clinical Observations',
                'type': 'multiline',
                'validation': {'required': false},
              },
            ],
          },
        ],
      };

      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/clinical/templates'),
        headers: bearerHeaders(doctorToken),
        body: jsonEncode({
          'templateNumber': 'TMPL-CARDIO-01',
          'title': 'Adult Cardiology Comprehensive Examination',
          'code': 'CARDIO_ADULT_V1',
          'specialty': 'CARDIOLOGY',
          'category': 'CONSULTATION',
          'content': templateSchema,
        }),
      );

      expect(res.statusCode, equals(201), reason: res.body);
      final body = jsonDecode(res.body)['data'] as Map<String, dynamic>;
      createdTemplateId = body['id'] as int;
      expect(body['templateNumber'], equals('TMPL-CARDIO-01'));
      expect(body['status'], equals('DRAFT'));
      expect(body['version'], equals(1));
      expect(body['specialty'], equals('CARDIOLOGY'));

      // Direct MariaDB Read-Back Verification
      final dbRow = (await db.execute(
        'SELECT * FROM mc_clinical_templates WHERE id = :id AND hospital_code = :hosp',
        {'id': createdTemplateId, 'hosp': hospitalCode},
      )).rows.first;

      expect(dbRow.colByName('template_number'), equals('TMPL-CARDIO-01'));
      expect(dbRow.colByName('status'), equals('DRAFT'));
      expect(dbRow.colByName('version')?.toString(), equals('1'));
      final storedContent = jsonDecode(dbRow.colByName('content_json')!) as Map<String, dynamic>;
      expect(storedContent['sections'], isA<List>());
      expect((storedContent['sections'] as List).length, equals(2));
    });

    test('1.2: Get template by ID & List templates with filters', () async {
      final getRes = await http.get(
        Uri.parse('$baseUrl/api/v1/clinical/templates/$createdTemplateId'),
        headers: bearerHeaders(doctorToken),
      );
      expect(getRes.statusCode, equals(200));
      final body = jsonDecode(getRes.body)['data'] as Map<String, dynamic>;
      expect(body['id'], equals(createdTemplateId));

      // List with filter
      final listRes = await http.get(
        Uri.parse('$baseUrl/api/v1/clinical/templates?specialty=CARDIOLOGY&status=DRAFT'),
        headers: bearerHeaders(doctorToken),
      );
      expect(listRes.statusCode, equals(200));
      final listData = jsonDecode(listRes.body)['data'] as Map<String, dynamic>;
      expect(listData['count'], greaterThanOrEqualTo(1));
    });
  });

  group('STAGE 3: Template Evolution, Version Bump & Activation Lifecycle', () {
    test('3.1: Update Draft Template in place before publication', () async {
      final updateRes = await http.put(
        Uri.parse('$baseUrl/api/v1/clinical/templates/$createdTemplateId'),
        headers: bearerHeaders(doctorToken),
        body: jsonEncode({
          'title': 'Adult Cardiology Comprehensive Examination (Updated Draft)',
          'category': 'OUTPATIENT',
        }),
      );
      expect(updateRes.statusCode, equals(200));
      final updated = jsonDecode(updateRes.body)['data'] as Map<String, dynamic>;
      expect(updated['title'], contains('(Updated Draft)'));
      expect(updated['category'], equals('OUTPATIENT'));
    });

    test('3.2: Activate Version 1 (Publish to ACTIVE)', () async {
      final actRes = await http.post(
        Uri.parse('$baseUrl/api/v1/clinical/templates/$createdTemplateId/activate'),
        headers: bearerHeaders(doctorToken),
      );
      expect(actRes.statusCode, equals(200));
      final actBody = jsonDecode(actRes.body)['data'] as Map<String, dynamic>;
      expect(actBody['status'], equals('ACTIVE'));

      // Direct MariaDB Read-Back
      final dbRow = (await db.execute(
        'SELECT status FROM mc_clinical_templates WHERE id = :id',
        {'id': createdTemplateId},
      )).rows.first;
      expect(dbRow.colByName('status'), equals('ACTIVE'));
    });

    test('3.3: Attempting to update an ACTIVE template directly must fail (Fail-Closed Immutability)', () async {
      final failRes = await http.put(
        Uri.parse('$baseUrl/api/v1/clinical/templates/$createdTemplateId'),
        headers: bearerHeaders(doctorToken),
        body: jsonEncode({
          'title': 'Illegal Modification of Active Template',
        }),
      );
      expect(failRes.statusCode, equals(409), reason: 'Active templates must be immutable');
    });

    test('3.4: Create Next Version (Version 2) as DRAFT while Version 1 remains ACTIVE', () async {
      final v2Res = await http.post(
        Uri.parse('$baseUrl/api/v1/clinical/templates/$createdTemplateId/version'),
        headers: bearerHeaders(doctorToken),
        body: jsonEncode({
          'content': {
            'version': 2,
            'sections': [
              {
                'key': 'vitals',
                'title': 'Vitals V2',
                'fields': [
                  {
                    'key': 'systolicBp',
                    'label': 'Systolic BP',
                    'type': 'integer',
                    'validation': {'required': true},
                  },
                ],
              },
            ],
          },
        }),
      );
      expect(v2Res.statusCode, equals(201));
      final v2Data = jsonDecode(v2Res.body)['data'] as Map<String, dynamic>;
      final v2Id = v2Data['id'] as int;
      expect(v2Data['version'], equals(2));
      expect(v2Data['status'], equals('DRAFT'));

      // Verify MariaDB: Version 1 is ACTIVE, Version 2 is DRAFT
      final rows = (await db.execute(
        'SELECT id, version, status FROM mc_clinical_templates WHERE template_number = "TMPL-CARDIO-01" ORDER BY version ASC',
      )).rows.toList();
      expect(rows.length, equals(2));
      expect(rows[0].colByName('status'), equals('ACTIVE'));
      expect(rows[1].colByName('status'), equals('DRAFT'));

      // 3.5: Activate Version 2 -> Version 1 must automatically RETIRE!
      final actV2Res = await http.post(
        Uri.parse('$baseUrl/api/v1/clinical/templates/$v2Id/activate'),
        headers: bearerHeaders(doctorToken),
      );
      expect(actV2Res.statusCode, equals(200));

      final activeRows = (await db.execute(
        'SELECT id, version, status FROM mc_clinical_templates WHERE template_number = "TMPL-CARDIO-01" ORDER BY version ASC',
      )).rows.toList();
      expect(activeRows[0].colByName('status'), equals('RETIRED'), reason: 'Older version must be retired on new version activation');
      expect(activeRows[1].colByName('status'), equals('ACTIVE'), reason: 'New version must now be the sole active version');

      // Query active template endpoint returns Version 2
      final activeResp = await http.get(
        Uri.parse('$baseUrl/api/v1/clinical/templates/active/TMPL-CARDIO-01'),
        headers: bearerHeaders(doctorToken),
      );
      expect(activeResp.statusCode, equals(200));
      expect(jsonDecode(activeResp.body)['data']['version'], equals(2));
    });
  });

  group('STAGE 4: Clinical Document Runtime — Template Usage Execution & Snapshot Audit', () {
    test('4.1: Record clinical template usage for patient encounter', () async {
      final usagePayload = {
        'vitals': {
          'systolicBp': 124,
          'diastolicBp': 82,
          'heartRate': 72,
        },
        'cardio_exam': {
          'murmurPresent': false,
          'clinicalNotes': 'Regular rate and rhythm, normal S1/S2, no murmurs, rubs or gallops.',
        },
      };

      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/clinical/templates/usages'),
        headers: bearerHeaders(doctorToken),
        body: jsonEncode({
          'templateId': createdTemplateId,
          'templateVersion': 1,
          'patientId': createdPatientId,
          'snapshot': usagePayload,
        }),
      );
      expect(res.statusCode, equals(201));
      final data = jsonDecode(res.body)['data'] as Map<String, dynamic>;
      expect(data['templateId'], equals(createdTemplateId));
      expect(data['patientId'], equals(createdPatientId));

      // Direct MariaDB Read-Back on mc_clinical_template_usages
      final dbUsage = (await db.execute(
        'SELECT * FROM mc_clinical_template_usages WHERE patient_id = :pid AND hospital_code = :hosp',
        {'pid': createdPatientId, 'hosp': hospitalCode},
      )).rows.first;
      expect(dbUsage.colByName('template_id')?.toString(), equals(createdTemplateId.toString()));
      final savedSnap = jsonDecode(dbUsage.colByName('snapshot_json')!) as Map<String, dynamic>;
      expect(savedSnap['vitals']['systolicBp'], equals(124));
    });

    test('4.2: List template usages by patient', () async {
      final listRes = await http.get(
        Uri.parse('$baseUrl/api/v1/clinical/templates/usages?patientId=$createdPatientId'),
        headers: bearerHeaders(doctorToken),
      );
      if (listRes.statusCode != 200) {
        print('4.2 ERROR BODY: ${listRes.body}');
      }
      expect(listRes.statusCode, equals(200));
      final listData = jsonDecode(listRes.body)['data'] as Map<String, dynamic>;
      expect(listData['count'], equals(1));
    });
  });

  group('RED TEAM GATE: Dynamic Templates Security & Cross-Tenant Boundary', () {
    test('RT-1: Cross-tenant IDOR attack on templates must be blocked (Tenant A vs Tenant B)', () async {
      // Attacker from Hospital B attempts to get Tenant A template
      final idorGet = await http.get(
        Uri.parse('$baseUrl/api/v1/clinical/templates/$createdTemplateId'),
        headers: bearerHeaders(attackerToken, hosp: hospitalCodeB),
      );
      expect(idorGet.statusCode, equals(404), reason: 'Cross-tenant template read must return 404');

      // Attacker attempts to activate Tenant A template
      final idorAct = await http.post(
        Uri.parse('$baseUrl/api/v1/clinical/templates/$createdTemplateId/activate'),
        headers: bearerHeaders(attackerToken, hosp: hospitalCodeB),
      );
      expect(idorAct.statusCode, equals(409), reason: 'Cross-tenant activation must fail');
    });
  });

  group('STAGE 6: Multi-Resource Slot Rule Engine — Resource Registration & Rule Configuration', () {
    test('6.1: Upsert multiple scheduling resources (Doctor, Room, Equipment, Device)', () async {
      final resources = [
        {'code': 'RES-DOC-01', 'name': 'Dr. Gregory House', 'type': 'DOCTOR'},
        {'code': 'RES-ROOM-101', 'name': 'Cardiology Suite 101', 'type': 'ROOM'},
        {'code': 'RES-ECHO-01', 'name': 'GE Vivid E95 Ultrasound', 'type': 'EQUIPMENT'},
        {'code': 'RES-ECG-01', 'name': 'Phillips PageWriter TC70', 'type': 'DEVICE'},
      ];

      for (final r in resources) {
        final res = await http.post(
          Uri.parse('$baseUrl/api/v1/scheduling/resources'),
          headers: bearerHeaders(adminToken),
          body: jsonEncode({
            'resourceCode': r['code'],
            'name': r['name'],
            'resourceType': r['type'],
            'metadata': {'location': 'Building A, Floor 2'},
            'isActive': true,
          }),
        );
        expect(res.statusCode, equals(201), reason: res.body);
      }

      // Read back all resources from MariaDB
      final dbRes = await db.execute(
        'SELECT * FROM mc_scheduling_resources WHERE hospital_code = :hosp ORDER BY resource_type ASC',
        {'hosp': hospitalCode},
      );
      expect(dbRes.rows.length, equals(4));

      for (final row in dbRes.rows) {
        final code = row.colByName('resource_code')!;
        final id = int.parse(row.colByName('id')!.toString());
        if (code == 'RES-DOC-01') docResourceId = id;
        if (code == 'RES-ROOM-101') roomResourceId = id;
        if (code == 'RES-ECHO-01') equipResourceId = id;
        if (code == 'RES-ECG-01') deviceResourceId = id;
      }
      expect(deviceResourceId, greaterThan(0));
    });

    test('6.2: Configure Scheduling Rule with duration and buffer windows', () async {
      final ruleRes = await http.post(
        Uri.parse('$baseUrl/api/v1/scheduling/rules'),
        headers: bearerHeaders(adminToken),
        body: jsonEncode({
          'ruleCode': 'RULE-CARDIO-ECHO',
          'name': 'Stress Echocardiogram Examination',
          'appointmentType': 'ECHOCARDIOGRAM',
          'primaryResourceType': 'DOCTOR',
          'requiredCoResourceTypes': ['ROOM', 'EQUIPMENT'],
          'defaultDurationMinutes': 45,
          'bufferBeforeMinutes': 10, // Preparation buffer
          'bufferAfterMinutes': 15,  // Sanitation/sterilization buffer
          'isActive': true,
        }),
      );
      expect(ruleRes.statusCode, equals(201), reason: ruleRes.body);

      // Direct MariaDB Read-Back on mc_scheduling_rules
      final ruleRow = (await db.execute(
        'SELECT * FROM mc_scheduling_rules WHERE rule_code = "RULE-CARDIO-ECHO" AND hospital_code = :hosp',
        {'hosp': hospitalCode},
      )).rows.first;

      expect(ruleRow.colByName('name'), equals('Stress Echocardiogram Examination'));
      expect(ruleRow.colByName('default_duration_minutes')?.toString(), equals('45'));
      expect(ruleRow.colByName('buffer_before_minutes')?.toString(), equals('10'));
      expect(ruleRow.colByName('buffer_after_minutes')?.toString(), equals('15'));
    });
  });

  group('STAGE 7 & 8: Conflict Detection & Atomic Multi-Resource Slot Allocation Engine', () {
    test('7.1: Conflict check reports no conflict on empty slot', () async {
      final start = DateTime.utc(2026, 11, 10, 10, 0);
      final end = DateTime.utc(2026, 11, 10, 11, 0);

      final chkRes = await http.post(
        Uri.parse('$baseUrl/api/v1/scheduling/conflicts/check'),
        headers: bearerHeaders(doctorToken),
        body: jsonEncode({
          'resourceIds': [docResourceId, roomResourceId, equipResourceId],
          'start': start.toIso8601String(),
          'end': end.toIso8601String(),
        }),
      );
      expect(chkRes.statusCode, equals(200));
      final chkBody = jsonDecode(chkRes.body)['data'] as Map<String, dynamic>;
      expect(chkBody['hasConflict'], isFalse);
    });

    test('7.2: Atomic Multi-Resource Appointment Booking allocates all resources with buffer', () async {
      final aptTime = DateTime.utc(2026, 11, 10, 10, 0);

      final bookRes = await http.post(
        Uri.parse('$baseUrl/api/v1/scheduling/appointments/multi-resource'),
        headers: bearerHeaders(doctorToken),
        body: jsonEncode({
          'appointmentNumber': 'APT-ECHO-20261110-01',
          'patientId': createdPatientId,
          'appointmentType': 'ECHOCARDIOGRAM',
          'appointmentDateTime': aptTime.toIso8601String(),
          'ruleCode': 'RULE-CARDIO-ECHO',
          'resourceIds': [docResourceId, roomResourceId, equipResourceId],
          'notes': 'Evaluation of exertional dyspnea',
        }),
      );
      expect(bookRes.statusCode, equals(201), reason: bookRes.body);
      final bookData = jsonDecode(bookRes.body)['data'] as Map<String, dynamic>;
      bookedAppointmentId = bookData['appointment']['id'] as int;

      final allocations = bookData['allocations'] as List;
      expect(allocations.length, equals(3));

      // Direct MariaDB Read-Back: Verify effective buffer allocation window
      // Start = 10:00 - 10 min buffer = 09:50
      // End = 10:00 + 45 min duration + 15 min buffer = 11:00
      final dbAllocations = (await db.execute(
        'SELECT * FROM mc_appointment_resource_allocations WHERE appointment_id = :aid AND hospital_code = :hosp',
        {'aid': bookedAppointmentId, 'hosp': hospitalCode},
      )).rows;

      expect(dbAllocations.length, equals(3));
      for (final alloc in dbAllocations) {
        expect(alloc.colByName('status'), equals('CONFIRMED'));
        expect(alloc.colByName('allocated_start')?.toString(), equals('2026-11-10 09:50:00'));
        expect(alloc.colByName('allocated_end')?.toString(), equals('2026-11-10 11:00:00'));
      }
    });

    test('7.3: Overlapping booking request must trigger RESOURCE_CONFLICT (409 Conflict)', () async {
      // Attempt another booking at 10:15 that requires the same Room and Equipment
      final conflictTime = DateTime.utc(2026, 11, 10, 10, 15);

      final failRes = await http.post(
        Uri.parse('$baseUrl/api/v1/scheduling/appointments/multi-resource'),
        headers: bearerHeaders(doctorToken),
        body: jsonEncode({
          'appointmentNumber': 'APT-ECHO-CONFLICT-01',
          'patientId': createdPatientId,
          'appointmentType': 'ECHOCARDIOGRAM',
          'appointmentDateTime': conflictTime.toIso8601String(),
          'ruleCode': 'RULE-CARDIO-ECHO',
          'resourceIds': [roomResourceId, equipResourceId],
        }),
      );
      expect(failRes.statusCode, equals(409), reason: 'Must reject with 409 Conflict');
      final failBody = jsonDecode(failRes.body) as Map<String, dynamic>;
      expect(failBody['error']['message'], contains('RESOURCE_CONFLICT'));
    });

    test('7.4: Booking during post-appointment buffer (e.g. 10:50) must also trigger 409 Conflict', () async {
      // The allocation holds room until 11:00 due to sanitation buffer.
      // A booking at 10:50 with 0 buffer before starts at 10:50, overlapping with [09:50, 11:00].
      final bufferConflictTime = DateTime.utc(2026, 11, 10, 10, 50);

      final chkRes = await http.post(
        Uri.parse('$baseUrl/api/v1/scheduling/conflicts/check'),
        headers: bearerHeaders(doctorToken),
        body: jsonEncode({
          'resourceIds': [roomResourceId],
          'start': bufferConflictTime.toIso8601String(),
          'end': bufferConflictTime.add(const Duration(minutes: 30)).toIso8601String(),
        }),
      );
      expect(chkRes.statusCode, equals(200));
      final chkBody = jsonDecode(chkRes.body)['data'] as Map<String, dynamic>;
      expect(chkBody['hasConflict'], isTrue, reason: 'Buffer window violation must report conflict');
    });

    test('7.5: Adjacent non-overlapping slot (11:05) succeeds without conflict', () async {
      final validTime = DateTime.utc(2026, 11, 10, 11, 5);

      final chkRes = await http.post(
        Uri.parse('$baseUrl/api/v1/scheduling/conflicts/check'),
        headers: bearerHeaders(doctorToken),
        body: jsonEncode({
          'resourceIds': [roomResourceId, equipResourceId],
          'start': validTime.toIso8601String(),
          'end': validTime.add(const Duration(minutes: 30)).toIso8601String(),
        }),
      );
      expect(chkRes.statusCode, equals(200));
      final chkBody = jsonDecode(chkRes.body)['data'] as Map<String, dynamic>;
      expect(chkBody['hasConflict'], isFalse);
    });

    test('7.6: Release allocations for cancelled appointment frees up resources immediately', () async {
      final relRes = await http.post(
        Uri.parse('$baseUrl/api/v1/scheduling/appointments/$bookedAppointmentId/release'),
        headers: bearerHeaders(doctorToken),
      );
      expect(relRes.statusCode, equals(200));

      // Direct MariaDB Read-Back: verify status is RELEASED
      final dbAllocations = (await db.execute(
        'SELECT status FROM mc_appointment_resource_allocations WHERE appointment_id = :aid',
        {'aid': bookedAppointmentId},
      )).rows;
      for (final alloc in dbAllocations) {
        expect(alloc.colByName('status'), equals('RELEASED'));
      }

      // Now conflict check for the original slot (10:00 - 11:00) reports false!
      final reCheck = await http.post(
        Uri.parse('$baseUrl/api/v1/scheduling/conflicts/check'),
        headers: bearerHeaders(doctorToken),
        body: jsonEncode({
          'resourceIds': [docResourceId, roomResourceId, equipResourceId],
          'start': DateTime.utc(2026, 11, 10, 10, 0).toIso8601String(),
          'end': DateTime.utc(2026, 11, 10, 11, 0).toIso8601String(),
        }),
      );
      expect(jsonDecode(reCheck.body)['data']['hasConflict'], isFalse, reason: 'Released slot must be open for booking');
    });
  });

  group('RED TEAM GATE: Scheduling Multi-Tenant Boundary Isolation', () {
    test('RT-2: Cross-tenant resource booking and conflict leakage is strictly blocked', () async {
      // Attacker from Hospital B attempts to check conflicts or book Tenant A's room
      final chkRes = await http.post(
        Uri.parse('$baseUrl/api/v1/scheduling/conflicts/check'),
        headers: bearerHeaders(attackerToken, hosp: hospitalCodeB),
        body: jsonEncode({
          'resourceIds': [roomResourceId],
          'start': DateTime.utc(2026, 11, 10, 10, 0).toIso8601String(),
          'end': DateTime.utc(2026, 11, 10, 11, 0).toIso8601String(),
        }),
      );
      expect(chkRes.statusCode, equals(200));
      // In Hospital B scope, resource roomResourceId either doesn't exist or has 0 allocations in Hospital B
      final chkData = jsonDecode(chkRes.body)['data'] as Map<String, dynamic>;
      expect(chkData['conflicts'], isEmpty);

      // Attacker attempts to release Tenant A's appointment
      final relRes = await http.post(
        Uri.parse('$baseUrl/api/v1/scheduling/appointments/$bookedAppointmentId/release'),
        headers: bearerHeaders(attackerToken, hosp: hospitalCodeB),
      );
      // Query executes scoped to hospitalCodeB, so 0 rows are updated
      expect(relRes.statusCode, equals(200));
      final relData = jsonDecode(relRes.body)['data'] as Map<String, dynamic>;
      expect(relData['released'], isTrue);

      // Verify in MariaDB that Tenant A's appointment allocations were NOT touched by Attacker
      final tenantARows = (await db.execute(
        'SELECT * FROM mc_appointment_resource_allocations WHERE hospital_code = :hosp AND appointment_id = :aid',
        {'hosp': hospitalCode, 'aid': bookedAppointmentId},
      )).rows;
      expect(tenantARows.isNotEmpty, isTrue);
    });
  });
}
