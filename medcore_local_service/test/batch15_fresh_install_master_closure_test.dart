import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:medcore_local_service/medcore_local_service.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'support/test_db_config.dart';

void main() {
  const dbName = 'medcore_fresh_install_closure';
  late DbClient db;
  late MigrationRunner migrationRunner;
  LocalMedCoreServer? server;
  late String baseUrl;
  late Directory securityRoot;

  const hospitalCode = 'HOSP_CLOSURE_01';
  const deviceId = 'DEV-CLOSURE-HOST';

  final serviceRoot = Directory.current.path;
  final migrationsDir = p.join(serviceRoot, 'sql', 'migrations');

  late String commissioningSecret;
  late String techToken;
  late String sessionUuid;
  const adminTempPassword = 'ClosureTempAdminPass#2026';
  const adminPermanentPassword = 'PermanentClosureAdmin#2026';
  late String adminToken;
  late String doctorToken;
  late String receptionistToken;

  Map<String, String> techHeaders({String? token, String? hosp, String? dev}) => {
        'content-type': 'application/json',
        'x-medcore-tech-token': token ?? techToken,
        'x-tenant-id': hosp ?? hospitalCode,
        'x-medcore-device-id': dev ?? deviceId,
      };

  Map<String, String> bearerHeaders(String token, {String? hosp, String? dev}) => {
        'content-type': 'application/json',
        'authorization': 'Bearer $token',
        'x-tenant-id': hosp ?? hospitalCode,
        'x-medcore-device-id': dev ?? deviceId,
      };

  setUpAll(() async {
    securityRoot = Directory.systemTemp.createTempSync('medcore-closure-root-');
    final config = testDbConfig(databaseName: dbName, maxConnections: 15);
    db = DbClient(config);

    // 1. Clean Database Setup: Drop & Recreate isolated test database
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
    migrationRunner = MigrationRunner(db: db, migrationsDir: migrationsDir);
    final applied = await migrationRunner.runMigrations();
    expect(applied.length, greaterThanOrEqualTo(16));

    // 3. Register Tenant & Host Device
    final govRepo = TenantGovernanceRepository(db);
    await govRepo.upsertTenant(
      hospitalCode: hospitalCode,
      name: 'MedCore Closure General Hospital',
    );
    await govRepo.enrollOrUpdateDevice(
      hospitalCode: hospitalCode,
      deviceId: deviceId,
      deviceName: 'Master Server Host Workstation',
      platform: 'WINDOWS',
      connectionType: 'LOOPBACK',
      hwFingerprintSha256: PasswordHasher.sha256Hex('CLOSURE-HW-01'),
      devicePublicKeyEd25519: 'PUBKEY-CLOSURE-01',
      roleScope: 'SERVER_HOST',
      isTrustedSecureRuntime: true,
      status: 'ACTIVE',
    );

    // 4. Start LocalMedCoreServer with autoBootstrapCommissioningSecret: true
    server = LocalMedCoreServer(
      db,
      securityRootDirectory: securityRoot.path,
      autoBootstrapCommissioningSecret: true,
    );
    final port = await server!.start(address: '127.0.0.1', port: 0);
    baseUrl = 'http://127.0.0.1:$port';

    final slipFile = File(p.join(securityRoot.path, 'FIRST_RUN_COMMISSIONING_SECRET.txt'));
    final slipContent = slipFile.readAsStringSync();
    final match = RegExp(r'Commissioning Secret\s+:\s+(TECH-COMM-[^\r\n\s]+)').firstMatch(slipContent);
    commissioningSecret = match!.group(1)!;
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

  group('STAGE 21: Full Fresh Installation Simulation & Master Lifecycle', () {
    test('Step 1: Database baseline has exactly ZERO staff accounts', () async {
      final res = await db.execute('SELECT COUNT(*) AS c FROM mc_staff');
      expect(int.parse(res.rows.first.colByName('c')!), equals(0));
    });

    test('Step 2: Auto-bootstrap generates one-time commissioning slip and PBKDF2 hash', () async {
      final slipFile = File(p.join(securityRoot.path, 'FIRST_RUN_COMMISSIONING_SECRET.txt'));
      final hashFile = File(p.join(securityRoot.path, 'technician_secret.json'));

      expect(slipFile.existsSync(), isTrue);
      expect(hashFile.existsSync(), isTrue);
      expect(hashFile.readAsStringSync(), isNot(contains(commissioningSecret)));
    });

    test('Step 3: Technician opens authenticated session & slip is deleted upon login', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/session/open'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'deviceId': deviceId,
          'technicianSecret': commissioningSecret,
        }),
      );
      expect(res.statusCode, equals(201));
      final body = jsonDecode(res.body)['data'] as Map<String, dynamic>;
      techToken = body['technicianToken'] as String;
      sessionUuid = body['session']['sessionUuid'] as String;

      final slipFile = File(p.join(securityRoot.path, 'FIRST_RUN_COMMISSIONING_SECRET.txt'));
      expect(slipFile.existsSync(), isFalse, reason: 'Slip file must be consumed and deleted on first login');
    });

    test('Step 4: Technician configures hospital facility, edition & enabled modules', () async {
      final res = await http.put(
        Uri.parse('$baseUrl/api/v1/technician/config'),
        headers: techHeaders(),
        body: jsonEncode({
          'facilityName': 'MedCore Closure Regional Medical Center',
          'facilityType': 'GENERAL_HOSPITAL',
          'edition': 'PLATINUM',
          'enabledModules': [
            'EMR',
            'CLINICAL',
            'PATIENTS',
            'APPOINTMENTS',
            'FINANCIAL_POSTINGS',
            'CLINICAL_TEMPLATES',
            'RESOURCE_SCHEDULING'
          ],
        }),
      );
      expect(res.statusCode, equals(200));

      final row = await db.execute(
        'SELECT facility_name, edition FROM mc_facility_config WHERE hospital_code = :hosp',
        {'hosp': hospitalCode},
      );
      expect(row.rows.first.colByName('facility_name'), equals('MedCore Closure Regional Medical Center'));
      expect(row.rows.first.colByName('edition'), equals('PLATINUM'));
    });

    test('Step 5: Technician provisions Initial Hospital Administrator with forced password change', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/initial-admin'),
        headers: techHeaders(),
        body: jsonEncode({
          'staffCode': 'ADM-CLOSURE-001',
          'fullName': 'Dr. Marcus Vance',
          'email': 'marcus.vance@closure.hospital',
          'password': adminTempPassword,
          'phone': '+15550299',
        }),
      );
      expect(res.statusCode, equals(201));
      final body = jsonDecode(res.body)['data'] as Map<String, dynamic>;
      expect(body['admin']['staffCode'], equals('ADM-CLOSURE-001'));
      expect(body['admin']['role'], equals('HospitalAdmin'));
      expect(body['forcePasswordChange'], isTrue);

      // Verify MariaDB mc_staff record
      final staff = await db.execute(
        "SELECT force_password_change, is_active FROM mc_staff WHERE staff_code = 'ADM-CLOSURE-001'",
      );
      expect(staff.rows.first.colByName('force_password_change'), equals('1'));
      expect(staff.rows.first.colByName('is_active'), equals('1'));
    });

    test('Step 6: Technician closes session (clean hand-off)', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/session/close'),
        headers: techHeaders(),
      );
      expect(res.statusCode, equals(200));

      final sess = await db.execute(
        'SELECT is_active FROM mc_technician_sessions WHERE session_uuid = :uuid',
        {'uuid': sessionUuid},
      );
      expect(sess.rows.first.colByName('is_active'), equals('0'));
    });

    test('Step 7: Admin logs in with temporary password -> forcePasswordChange = true', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/login'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'deviceId': deviceId,
          'identifier': 'marcus.vance@closure.hospital',
          'password': adminTempPassword,
        }),
      );
      expect(res.statusCode, equals(200));
      final body = jsonDecode(res.body)['data'] as Map<String, dynamic>;
      adminToken = body['token'] as String;
      expect(body['user']['forcePasswordChange'], isTrue);
    });

    test('Step 8: Admin updates password to permanent password -> forcePasswordChange = 0', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/change-password'),
        headers: bearerHeaders(adminToken),
        body: jsonEncode({
          'oldPassword': adminTempPassword,
          'newPassword': adminPermanentPassword,
        }),
      );
      expect(res.statusCode, equals(200));

      // MariaDB check
      final staff = await db.execute(
        "SELECT force_password_change FROM mc_staff WHERE staff_code = 'ADM-CLOSURE-001'",
      );
      expect(staff.rows.first.colByName('force_password_change'), equals('0'));

      // Invalidation check: old temporary password fails
      final retryOld = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/login'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'deviceId': deviceId,
          'identifier': 'marcus.vance@closure.hospital',
          'password': adminTempPassword,
        }),
      );
      expect(retryOld.statusCode, equals(401));

      // New permanent password succeeds
      final loginNew = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/login'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'deviceId': deviceId,
          'identifier': 'marcus.vance@closure.hospital',
          'password': adminPermanentPassword,
        }),
      );
      expect(loginNew.statusCode, equals(200));
      adminToken = (jsonDecode(loginNew.body)['data'] as Map)['token'] as String;
    });

    late int createdDoctorId;

    test('Step 9: Admin provisions Doctor and Receptionist staff roles', () async {
      // 1. Doctor
      final docRes = await http.post(
        Uri.parse('$baseUrl/api/v1/admin/employees'),
        headers: bearerHeaders(adminToken),
        body: jsonEncode({
          'staffCode': 'DOC-CLOSURE-101',
          'fullName': 'Dr. Gregory House',
          'email': 'house@closure.hospital',
          'password': 'DoctorPass#2026',
          'role': 'Doctor',
        }),
      );
      expect(docRes.statusCode, anyOf(equals(200), equals(201)));
      final docBody = jsonDecode(docRes.body)['data'] as Map<String, dynamic>;
      createdDoctorId = int.parse(docBody['id'].toString());

      // 2. Receptionist
      final recRes = await http.post(
        Uri.parse('$baseUrl/api/v1/admin/employees'),
        headers: bearerHeaders(adminToken),
        body: jsonEncode({
          'staffCode': 'REC-CLOSURE-201',
          'fullName': 'Pam Beesly',
          'email': 'pam@closure.hospital',
          'password': 'ReceptionPass#2026',
          'role': 'Receptionist',
        }),
      );
      expect(recRes.statusCode, anyOf(equals(200), equals(201)));

      // Authenticate Doctor
      final docLogin = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/login'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'deviceId': deviceId,
          'identifier': 'house@closure.hospital',
          'password': 'DoctorPass#2026',
        }),
      );
      expect(docLogin.statusCode, equals(200));
      doctorToken = (jsonDecode(docLogin.body)['data'] as Map)['token'] as String;

      // Authenticate Receptionist
      final recLogin = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/login'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'deviceId': deviceId,
          'identifier': 'pam@closure.hospital',
          'password': 'ReceptionPass#2026',
        }),
      );
      expect(recLogin.statusCode, equals(200));
      receptionistToken = (jsonDecode(recLogin.body)['data'] as Map)['token'] as String;
    });

    late int createdPatientId;

    test('Step 10: Receptionist registers Patient & books Appointment', () async {
      final patRes = await http.post(
        Uri.parse('$baseUrl/api/v1/patients'),
        headers: bearerHeaders(receptionistToken),
        body: jsonEncode({
          'mrn': 'MRN-CLOSURE-777',
          'fullName': 'John Doe',
          'dateOfBirth': '1985-05-15',
          'gender': 'MALE',
          'phone': '+15559876',
        }),
      );
      expect(patRes.statusCode, anyOf(equals(200), equals(201)));
      final patBody = jsonDecode(patRes.body)['data'] as Map<String, dynamic>;
      createdPatientId = int.parse(patBody['id'].toString());

      final apptRes = await http.post(
        Uri.parse('$baseUrl/api/v1/appointments'),
        headers: bearerHeaders(receptionistToken),
        body: jsonEncode({
          'appointmentNumber': 'APT-CLOSURE-0001',
          'patientId': createdPatientId,
          'doctorId': createdDoctorId.toString(),
          'departmentId': 'DEP_OPD',
          'scheduledAt': '2026-11-01T10:00:00.000Z',
          'appointmentType': 'CONSULTATION',
          'reason': 'Cardiology evaluation',
        }),
      );
      if (apptRes.statusCode != 201) {
        print('APPT ERROR: ${apptRes.statusCode} -> ${apptRes.body}');
      }
      expect(apptRes.statusCode, equals(201));

      final apptDb = await db.execute(
        "SELECT status FROM mc_appointments WHERE appointment_number = 'APT-CLOSURE-0001' AND hospital_code = :hosp",
        {'hosp': hospitalCode},
      );
      expect(apptDb.rows.length, equals(1));
      expect(apptDb.rows.first.colByName('status'), equals('SCHEDULED'));
    });

    test('Step 11: Dynamic Clinical Template V1 created, published and recorded in encounter snapshot', () async {
      // 1. Create Draft Template
      final draftRes = await http.post(
        Uri.parse('$baseUrl/api/v1/clinical/templates'),
        headers: bearerHeaders(doctorToken),
        body: jsonEncode({
          'templateNumber': 'TMPL-CARDIO-01',
          'title': 'Cardiology Examination Template',
          'specialty': 'CARDIOLOGY',
          'description': 'Comprehensive cardiac diagnostic form',
          'content': {
            'version': 1,
            'sections': [
              {
                'id': 'vitals',
                'title': 'Vital Signs',
                'fields': [
                  {'id': 'bp_sys', 'label': 'Systolic BP', 'type': 'NUMBER', 'required': true},
                  {'id': 'bp_dia', 'label': 'Diastolic BP', 'type': 'NUMBER', 'required': true},
                  {'id': 'hr', 'label': 'Heart Rate (bpm)', 'type': 'NUMBER', 'required': true},
                ]
              }
            ]
          }
        }),
      );
      expect(draftRes.statusCode, anyOf(equals(200), equals(201)));
      final tplData = jsonDecode(draftRes.body)['data'] as Map<String, dynamic>;
      final templateId = tplData['id'].toString();

      // 2. Publish Template V1
      final pubRes = await http.post(
        Uri.parse('$baseUrl/api/v1/clinical/templates/$templateId/activate'),
        headers: bearerHeaders(doctorToken),
      );
      expect(pubRes.statusCode, equals(200));

      // 3. Clinical Template Usage Snapshot
      final encRes = await http.post(
        Uri.parse('$baseUrl/api/v1/clinical/templates/usages'),
        headers: bearerHeaders(doctorToken),
        body: jsonEncode({
          'templateId': int.parse(templateId),
          'templateVersion': 1,
          'patientId': createdPatientId,
          'snapshot': {
            'bp_sys': 125,
            'bp_dia': 82,
            'hr': 74,
          },
        }),
      );
      if (encRes.statusCode != 200 && encRes.statusCode != 201) {
        print('ENC ERROR: ${encRes.statusCode} -> ${encRes.body}');
      }
      expect(encRes.statusCode, anyOf(equals(200), equals(201)));

      // 4. Verify MariaDB mc_clinical_templates row
      final tplDb = await db.execute(
        'SELECT status, version FROM mc_clinical_templates WHERE id = :id',
        {'id': templateId},
      );
      expect(tplDb.rows.length, equals(1));
      expect(tplDb.rows.first.colByName('status'), equals('ACTIVE'));
      expect(tplDb.rows.first.colByName('version'), equals('1'));
    });

    test('Step 12: Dynamic Multi-Resource Scheduling & True Concurrency Collision Proof', () async {
      // 1. Register Resources
      final roomRes = await http.post(
        Uri.parse('$baseUrl/api/v1/scheduling/resources'),
        headers: bearerHeaders(adminToken),
        body: jsonEncode({
          'resourceCode': 'ROOM-EXAM-101',
          'name': 'Cardiology Examination Room 101',
          'resourceType': 'ROOM',
          'isActive': true,
        }),
      );
      expect(roomRes.statusCode, equals(201));
      final roomId = int.parse(jsonDecode(roomRes.body)['data']['id'].toString());

      // 2. Set Scheduling Rules: 30m duration, 10m buffer_before, 10m buffer_after
      final ruleRes = await http.post(
        Uri.parse('$baseUrl/api/v1/scheduling/rules'),
        headers: bearerHeaders(adminToken),
        body: jsonEncode({
          'ruleCode': 'RULE-CARDIO-ROOM',
          'name': 'Cardiology Room Booking Rule',
          'appointmentType': 'CARDIOLOGY_VISIT',
          'primaryResourceType': 'ROOM',
          'requiredCoResourceTypes': <String>[],
          'defaultDurationMinutes': 30,
          'bufferBeforeMinutes': 10,
          'bufferAfterMinutes': 10,
          'isActive': true,
        }),
      );
      expect(ruleRes.statusCode, equals(201));

      // 3. True Concurrent Booking on Same Resource at Same Time T
      final aptTime = DateTime.utc(2026, 11, 20, 14, 0);

      final futureReqA = http.post(
        Uri.parse('$baseUrl/api/v1/scheduling/appointments/multi-resource'),
        headers: bearerHeaders(receptionistToken),
        body: jsonEncode({
          'appointmentNumber': 'APT-CLOSURE-RACE-A',
          'patientId': createdPatientId,
          'appointmentType': 'CARDIOLOGY_VISIT',
          'appointmentDateTime': aptTime.toIso8601String(),
          'resourceIds': [roomId],
          'ruleCode': 'RULE-CARDIO-ROOM',
        }),
      );

      final futureReqB = http.post(
        Uri.parse('$baseUrl/api/v1/scheduling/appointments/multi-resource'),
        headers: bearerHeaders(receptionistToken),
        body: jsonEncode({
          'appointmentNumber': 'APT-CLOSURE-RACE-B',
          'patientId': createdPatientId,
          'appointmentType': 'CARDIOLOGY_VISIT',
          'appointmentDateTime': aptTime.toIso8601String(),
          'resourceIds': [roomId],
          'ruleCode': 'RULE-CARDIO-ROOM',
        }),
      );

      final responses = await Future.wait([futureReqA, futureReqB]);
      final statusCodes = responses.map((r) => r.statusCode).toList();

      expect(statusCodes, contains(201), reason: 'Exactly one concurrent booking must succeed');
      expect(statusCodes, contains(409), reason: 'The competing concurrent booking must be rejected with 409 Conflict');

      // Verify MariaDB mc_appointment_resource_allocations contains exactly 1 allocation
      final allocDb = await db.execute(
        'SELECT COUNT(*) AS c FROM mc_appointment_resource_allocations WHERE resource_id = :rid AND hospital_code = :hosp',
        {'rid': roomId, 'hosp': hospitalCode},
      );
      expect(int.parse(allocDb.rows.first.colByName('c')!), equals(1));
    });

    test('Step 13: Stop Server & Restart (Process Restart Survival)', () async {
      await server?.stop();

      // Start new server instance attached to same MariaDB storage
      server = LocalMedCoreServer(
        db,
        securityRootDirectory: securityRoot.path,
        autoBootstrapCommissioningSecret: true,
      );
      final newPort = await server!.start(address: '127.0.0.1', port: 0);
      baseUrl = 'http://127.0.0.1:$newPort';

      // Read back facility configuration from new server instance via public bootstrap
      final readRes = await http.get(
        Uri.parse('$baseUrl/api/v1/product/bootstrap?hospitalCode=$hospitalCode'),
      );
      expect(readRes.statusCode, equals(200));
      final body = jsonDecode(readRes.body)['data'] as Map<String, dynamic>;
      expect(body['facilityName'], equals('MedCore Closure Regional Medical Center'));
      expect(body['edition'], equals('PLATINUM'));
      expect(body['isSubscriptionActive'], isTrue);
    });
  });
}
