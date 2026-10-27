import 'dart:convert';
import 'dart:io';
import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;
import 'package:medcore_local_service/medcore_local_service.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'support/test_db_config.dart';

void main() {
  late DbClient db;
  late MigrationRunner migrationRunner;
  LocalMedCoreServer? server;
  late String baseUrl;
  late Directory securityRoot;

  final serviceRoot = Directory.current.path;
  final migrationsDir = p.join(serviceRoot, 'sql', 'migrations');

  final tokens = <String, String>{};
  final staffIds = <String, int>{};

  setUpAll(() async {
    securityRoot = Directory.systemTemp.createTempSync('medcore-b2-root-');
    final config = testDbConfig(databaseName: 'medcore_test', maxConnections: 10);
    db = DbClient(config);

    final adminConn = await db.openDedicatedConnection(useDatabase: false);
    try {
      await adminConn.execute('DROP DATABASE IF EXISTS `medcore_test`');
      await adminConn.execute(
        'CREATE DATABASE `medcore_test` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
      );
    } finally {
      await adminConn.close();
    }

    migrationRunner = MigrationRunner(db: db, migrationsDir: migrationsDir);
    await migrationRunner.runMigrations();

    server = LocalMedCoreServer(db, securityRootDirectory: securityRoot.path);
    final port = await server!.start(address: '127.0.0.1', port: 0);
    baseUrl = 'http://127.0.0.1:$port';

    // Bootstrap Tenant and Devices
    final govRepo = TenantGovernanceRepository(db);
    await govRepo.upsertTenant(hospitalCode: 'HOSP_MAIN', name: 'MedCore General Hospital');

    for (final dev in ['DEV-RECEPT', 'DEV-DOC1', 'DEV-DOC2', 'DEV-CASHIER', 'DEV-LAB', 'DEV-PHARM', 'DEV-SUPER']) {
      await govRepo.enrollOrUpdateDevice(
        hospitalCode: 'HOSP_MAIN',
        deviceId: dev,
        deviceName: '$dev Terminal',
        platform: 'WINDOWS',
        hwFingerprintSha256: PasswordHasher.sha256Hex(dev),
        devicePublicKeyEd25519: 'PUBKEY-$dev',
        isTrustedSecureRuntime: true,
        status: 'ACTIVE',
      );
    }

    // Bootstrap Staff for roles
    final staffRepo = StaffIdentityRepository(db);

    Future<void> enrollAndLogin({
      required String code,
      required String name,
      required String email,
      required MedCoreRole role,
      required String devId,
      OperationalFlags? flags,
      Set<String>? customPerms,
    }) async {
      final s = await staffRepo.createStaff(
        hospitalCode: 'HOSP_MAIN',
        staffCode: code,
        fullName: name,
        email: email,
        role: role,
        passwordHash: PasswordHasher.hashPassword('Pass123!'),
        permissionsMode: (flags != null || customPerms != null) ? 'custom' : 'default',
        customPermissions: customPerms,
        operationalFlags: flags,
      );
      staffIds[code] = s.id;

      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/login'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': 'HOSP_MAIN',
          'identifier': email,
          'password': 'Pass123!',
          'deviceId': devId,
        }),
      );
      expect(res.statusCode, equals(200), reason: 'Login failed for $code: ${res.body}');
      final body = jsonDecode(res.body);
      tokens[code] = body['data']['token'];
    }

    await enrollAndLogin(
      code: 'REC01',
      name: 'Rana Reception',
      email: 'rana@medcore.local',
      role: MedCoreRole.Receptionist,
      devId: 'DEV-RECEPT',
      customPerms: {'reception', 'reception_QuickCheckIn', 'appointments', 'appointments.write', 'patients', 'patients.write'},
      flags: const OperationalFlags(
        canEdit: true,
        canDelete: false,
        canCollectMoney: false,
        canMakeRefunds: false,
        refundPolicy: RefundPolicy.none,
      ),
    );

    await enrollAndLogin(
      code: 'DOC01',
      name: 'Dr. Tarek Cardiology',
      email: 'tarek@medcore.local',
      role: MedCoreRole.Doctor,
      devId: 'DEV-DOC1',
      customPerms: {
        'doctor', 'clinic', 'clinic_DoctorQueue', 'clinic_DoctorQueue_all',
        'clinic_Prescriptions', 'appointments', 'appointments.write', 'appointments_all', 'patients'
      },
      flags: const OperationalFlags(
        canEdit: true,
        canDelete: false,
        canCollectMoney: false,
        canMakeRefunds: false,
        refundPolicy: RefundPolicy.none,
      ),
    );

    await enrollAndLogin(
      code: 'DOC02',
      name: 'Dr. Nadia Pediatrics',
      email: 'nadia@medcore.local',
      role: MedCoreRole.Doctor,
      devId: 'DEV-DOC2',
      customPerms: {'doctor', 'clinic', 'clinic_DoctorQueue', 'appointments'}, // Own-only scope (no _all)
      flags: const OperationalFlags(
        canEdit: true,
        canDelete: false,
        canCollectMoney: false,
        canMakeRefunds: false,
        refundPolicy: RefundPolicy.none,
      ),
    );

    await enrollAndLogin(
      code: 'CSH01',
      name: 'Karim Cashier',
      email: 'karim@medcore.local',
      role: MedCoreRole.Cashier,
      devId: 'DEV-CASHIER',
      customPerms: {'shifts', 'reception_QuickCheckIn', 'finance_Invoices', 'finance_Settlements', 'finance_Settlements_secure'},
      flags: const OperationalFlags(
        canEdit: true,
        canDelete: false,
        canCollectMoney: true,
        canMakeRefunds: true,
        refundPolicy: RefundPolicy.approval, // Requires dual control
      ),
    );

    await enrollAndLogin(
      code: 'LAB01',
      name: 'Lina Lab Tech',
      email: 'lina@medcore.local',
      role: MedCoreRole.Lab,
      devId: 'DEV-LAB',
      customPerms: {'lab', 'lab_Dashboard', 'lab_ResultsEntry'},
      flags: const OperationalFlags(
        canEdit: true,
        canDelete: false,
        canCollectMoney: false,
        canMakeRefunds: false,
        refundPolicy: RefundPolicy.none,
      ),
    );

    await enrollAndLogin(
      code: 'PHM01',
      name: 'Fady Pharmacist',
      email: 'fady@medcore.local',
      role: MedCoreRole.Pharmacist,
      devId: 'DEV-PHARM',
      customPerms: {'pharmacy_inventory', 'pharmacy_Dispensing', 'inventory_ItemsCatalog', 'inventory_StockBatches'},
      flags: const OperationalFlags(
        canEdit: true,
        canDelete: false,
        canCollectMoney: true,
        canMakeRefunds: false,
        refundPolicy: RefundPolicy.none,
      ),
    );

    await enrollAndLogin(
      code: 'SUP01',
      name: 'Sarah Supervisor',
      email: 'sarah@medcore.local',
      role: MedCoreRole.HospitalAdmin,
      devId: 'DEV-SUPER',
      customPerms: {
        'settings_Permissions', 'inpatient', 'inpatient_BedMap',
        'inpatient_Admissions', 'inpatient_Discharge', 'finance_Settlements',
        'finance_Settlements_secure'
      },
      flags: const OperationalFlags(
        canEdit: true,
        canDelete: true,
        canCollectMoney: true,
        canMakeRefunds: true,
        refundPolicy: RefundPolicy.direct,
      ),
    );
  });

  tearDownAll(() async {
    await server?.stop();
    await db.close();
    if (securityRoot.existsSync()) securityRoot.deleteSync(recursive: true);
  });

  Map<String, String> authHeaders(String code, String devId) => {
        'content-type': 'application/json',
        'authorization': 'Bearer ${tokens[code]}',
        'x-tenant-id': 'HOSP_MAIN',
        'x-medcore-device-id': devId,
      };

  group('BATCH 2 — WORKSTREAM 1: Appointments & Scheduling (CLN-001)', () {
    late int patientId;

    setUpAll(() async {
      final pRes = await http.post(
        Uri.parse('$baseUrl/api/v1/patients'),
        headers: authHeaders('REC01', 'DEV-RECEPT'),
        body: jsonEncode({
          'mrn': 'MRN-APT-001',
          'fullName': 'Ayman Appointment Patient',
          'phone': '01011112222',
        }),
      );
      patientId = jsonDecode(pRes.body)['data']['id'];
    });

    test('1.1 Books new appointment with status SCHEDULED', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/appointments'),
        headers: authHeaders('REC01', 'DEV-RECEPT'),
        body: jsonEncode({
          'appointmentNumber': 'APT-2026-0001',
          'patientId': patientId,
          'doctorId': staffIds['DOC01']!.toString(),
          'scheduledAt': '2026-11-01T10:00:00Z',
          'durationMinutes': 30,
          'reason': 'Routine cardiac checkup',
        }),
      );

      expect(res.statusCode, equals(201), reason: 'POST /appointments failed: ${res.body}');
      final body = jsonDecode(res.body)['data'];
      expect(body['status'], equals('SCHEDULED'));
      expect(body['appointmentNumber'], equals('APT-2026-0001'));

      // Direct MariaDB Read-back verification
      final sqlCheck = await db.execute(
        "SELECT * FROM mc_appointments WHERE hospital_code = 'HOSP_MAIN' AND appointment_number = 'APT-2026-0001'",
      );
      expect(sqlCheck.rows.length, equals(1));
      expect(sqlCheck.rows.first.colByName('status'), equals('SCHEDULED'));
    });

    test('1.2 Enforces Dimension 2 Data Scope on Appointments (Own-Only vs _all)', () async {
      // Create second appointment assigned to DOC02
      await http.post(
        Uri.parse('$baseUrl/api/v1/appointments'),
        headers: authHeaders('REC01', 'DEV-RECEPT'),
        body: jsonEncode({
          'appointmentNumber': 'APT-2026-0002',
          'patientId': patientId,
          'doctorId': staffIds['DOC02']!.toString(),
          'scheduledAt': '2026-11-01T11:00:00Z',
        }),
      );

      // DOC02 has own-only scope -> sees only APT-2026-0002
      final doc2Res = await http.get(
        Uri.parse('$baseUrl/api/v1/appointments'),
        headers: authHeaders('DOC02', 'DEV-DOC2'),
      );
      expect(doc2Res.statusCode, equals(200));
      final doc2Items = jsonDecode(doc2Res.body)['data']['items'] as List;
      expect(doc2Items.any((a) => a['appointmentNumber'] == 'APT-2026-0002'), isTrue);
      expect(doc2Items.any((a) => a['appointmentNumber'] == 'APT-2026-0001'), isFalse);

      // DOC01 has appointments_all -> sees all appointments
      final doc1Res = await http.get(
        Uri.parse('$baseUrl/api/v1/appointments'),
        headers: authHeaders('DOC01', 'DEV-DOC1'),
      );
      expect(doc1Res.statusCode, equals(200));
      final doc1Items = jsonDecode(doc1Res.body)['data']['items'] as List;
      expect(doc1Items.any((a) => a['appointmentNumber'] == 'APT-2026-0001'), isTrue);
      expect(doc1Items.any((a) => a['appointmentNumber'] == 'APT-2026-0002'), isTrue);
    });

    test('1.3 Transitions appointment status to CHECKED_IN with DB verification', () async {
      final aptRow = await db.execute(
        "SELECT id FROM mc_appointments WHERE appointment_number = 'APT-2026-0001'",
      );
      final aptId = aptRow.rows.first.colByName('id');

      final putRes = await http.put(
        Uri.parse('$baseUrl/api/v1/appointments/$aptId/status'),
        headers: authHeaders('REC01', 'DEV-RECEPT'),
        body: jsonEncode({'status': 'CHECKED_IN'}),
      );
      expect(putRes.statusCode, equals(200));
      expect(jsonDecode(putRes.body)['data']['status'], equals('CHECKED_IN'));

      // Direct MariaDB Read-back verification
      final sqlCheck = await db.execute(
        'SELECT status FROM mc_appointments WHERE id = :id',
        {'id': aptId},
      );
      expect(sqlCheck.rows.first.colByName('status'), equals('CHECKED_IN'));
    });
  });

  group('BATCH 2 — WORKSTREAM 2: Cashier Shift Reconciliation (FIN-006)', () {
    late int shiftId;

    test('2.1 Opens shift and checks /shifts/current', () async {
      final openRes = await http.post(
        Uri.parse('$baseUrl/api/v1/shifts/open'),
        headers: authHeaders('CSH01', 'DEV-CASHIER'),
        body: jsonEncode({
          'shiftCode': 'SHF-2026-01',
          'openingBalance': '500.0000',
        }),
      );
      expect(openRes.statusCode, equals(201));
      shiftId = jsonDecode(openRes.body)['data']['id'];

      final curRes = await http.get(
        Uri.parse('$baseUrl/api/v1/shifts/current'),
        headers: authHeaders('CSH01', 'DEV-CASHIER'),
      );
      expect(curRes.statusCode, equals(200));
      final openShift = jsonDecode(curRes.body)['data']['openShift'];
      expect(openShift['shiftCode'], equals('SHF-2026-01'));
      expect(openShift['status'], equals('OPEN'));
    });

    test('2.2 Atomic visit payment updates cash_in and expected_cash', () async {
      // Patient for visit
      final pRes = await http.post(
        Uri.parse('$baseUrl/api/v1/patients'),
        headers: authHeaders('REC01', 'DEV-RECEPT'),
        body: jsonEncode({
          'mrn': 'MRN-VIS-001',
          'fullName': 'Sami Cash Patient',
          'phone': '01022223333',
        }),
      );
      final pid = jsonDecode(pRes.body)['data']['id'];

      // Visit collecting 200.0000 cash
      final vRes = await http.post(
        Uri.parse('$baseUrl/api/v1/visits'),
        headers: authHeaders('CSH01', 'DEV-CASHIER'),
        body: jsonEncode({
          'visitNumber': 'VIS-CSH-0001',
          'idempotencyKey': 'IDEMP-VIS-CSH-0001',
          'patientId': pid,
          'doctorId': staffIds['DOC01'],
          'shiftId': shiftId,
          'serviceLaborGross': '200.0000',
          'consumableGross': '0.0000',
          'consumableFifoCost': '0.0000',
          'discountAmount': '0.0000',
          'insuranceCoveredAmount': '0.0000',
          'paidAmount': '200.0000',
          'doctorCommissionRatePercent': '20.0000',
        }),
      );
      expect(vRes.statusCode, equals(201));

      // Direct MariaDB Read-back on mc_shifts
      final sCheck = await db.execute(
        'SELECT cash_in, expected_cash FROM mc_shifts WHERE id = :id',
        {'id': shiftId},
      );
      expect(Decimal.parse(sCheck.rows.first.colByName('cash_in') ?? '0'), equals(Decimal.parse('200.0000')));
      expect(Decimal.parse(sCheck.rows.first.colByName('expected_cash') ?? '0'), equals(Decimal.parse('700.0000')));
    });

    test('2.3 Closes shift with FIN-006 Reconciliation & Variance Invariant', () async {
      final closeRes = await http.post(
        Uri.parse('$baseUrl/api/v1/shifts/close'),
        headers: authHeaders('CSH01', 'DEV-CASHIER'),
        body: jsonEncode({
          'shiftId': shiftId,
          'countedCash': '700.0000',
          'notes': 'Balanced cash drawer',
        }),
      );
      expect(closeRes.statusCode, equals(200));
      final body = jsonDecode(closeRes.body)['data'];
      expect(body['status'], equals('CLOSED'));
      expect(body['expectedCash'], equals('700.0000'));
      expect(body['countedCash'], equals('700.0000'));
      expect(body['variance'], equals('0.0000'));

      // Direct MariaDB Read-back verification
      final sCheck = await db.execute(
        'SELECT status, counted_cash, variance_amount, closed_by FROM mc_shifts WHERE id = :id',
        {'id': shiftId},
      );
      expect(sCheck.rows.first.colByName('status'), equals('CLOSED'));
      expect(sCheck.rows.first.colByName('variance_amount'), equals('0.0000'));

      // Adversarial: Re-closing a closed shift fails with domain conflict
      final recloseRes = await http.post(
        Uri.parse('$baseUrl/api/v1/shifts/close'),
        headers: authHeaders('CSH01', 'DEV-CASHIER'),
        body: jsonEncode({
          'shiftId': shiftId,
          'countedCash': '700.0000',
        }),
      );
      expect(recloseRes.statusCode, equals(409));
    });
  });

  group('BATCH 2 — WORKSTREAM 3: Doctor Queue & Encounters (CLN-001)', () {
    late int visitId;
    late int patientId;

    setUpAll(() async {
      // Open new shift for Cashier to support visits
      final sRes = await http.post(
        Uri.parse('$baseUrl/api/v1/shifts/open'),
        headers: authHeaders('CSH01', 'DEV-CASHIER'),
        body: jsonEncode({
          'shiftCode': 'SHF-2026-02',
          'openingBalance': '1000.0000',
        }),
      );
      final shiftId = jsonDecode(sRes.body)['data']['id'];

      final pRes = await http.post(
        Uri.parse('$baseUrl/api/v1/patients'),
        headers: authHeaders('REC01', 'DEV-RECEPT'),
        body: jsonEncode({
          'mrn': 'MRN-ENC-001',
          'fullName': 'Mona Encounter Patient',
          'phone': '01033334444',
          'assignedDoctorId': staffIds['DOC01'],
        }),
      );
      patientId = jsonDecode(pRes.body)['data']['id'];

      final vRes = await http.post(
        Uri.parse('$baseUrl/api/v1/visits'),
        headers: authHeaders('CSH01', 'DEV-CASHIER'),
        body: jsonEncode({
          'visitNumber': 'VIS-ENC-0001',
          'idempotencyKey': 'IDEMP-VIS-ENC-0001',
          'patientId': patientId,
          'doctorId': staffIds['DOC01'],
          'shiftId': shiftId,
          'serviceLaborGross': '300.0000',
          'consumableGross': '0.0000',
          'consumableFifoCost': '0.0000',
          'discountAmount': '0.0000',
          'insuranceCoveredAmount': '0.0000',
          'paidAmount': '300.0000',
          'doctorCommissionRatePercent': '30.0000',
        }),
      );
      visitId = jsonDecode(vRes.body)['data']['visitId'];
    });

    test('3.1 Doctor queries queue and sees waiting visit', () async {
      final qRes = await http.get(
        Uri.parse('$baseUrl/api/v1/doctor/queue'),
        headers: authHeaders('DOC01', 'DEV-DOC1'),
      );
      expect(qRes.statusCode, equals(200));
      final items = jsonDecode(qRes.body)['data']['items'] as List;
      expect(items.any((i) => i['visitId'] == visitId), isTrue);
    });

    test('3.2 Doctor creates clinical encounter with SOAP notes and ICD-10 diagnoses', () async {
      final encRes = await http.post(
        Uri.parse('$baseUrl/api/v1/encounters'),
        headers: authHeaders('DOC01', 'DEV-DOC1'),
        body: jsonEncode({
          'visitId': visitId,
          'patientId': patientId,
          'encounterNumber': 'ENC-2026-0001',
          'chiefComplaint': 'Persistent chest tightness and palpitations',
          'vitals': {'bp': '120/80', 'hr': 76, 'spo2': 99, 'temp': 37.1},
          'examination': {'cardiac': 'Regular rate and rhythm, no murmurs', 'lungs': 'Clear bilaterally'},
          'assessment': {'riskLevel': 'Moderate', 'primarySuspect': 'Atypical Angina'},
          'plan': {'medication': 'Beta blocker', 'followUpDays': 7},
          'diagnoses': [
            {'code': 'I20.9', 'name': 'Angina pectoris, unspecified', 'type': 'PRIMARY'},
            {'code': 'I10', 'name': 'Essential hypertension', 'type': 'SECONDARY'},
          ],
          'notes': 'Patient advised to avoid intense physical strain until stress test.',
        }),
      );

      expect(encRes.statusCode, equals(201), reason: 'POST /encounters failed: ${encRes.body}');
      final body = jsonDecode(encRes.body)['data'];
      expect(body['status'], equals('COMPLETED'));

      // Direct MariaDB Read-back verification
      final encSql = await db.execute(
        "SELECT * FROM mc_encounters WHERE hospital_code = 'HOSP_MAIN' AND encounter_number = 'ENC-2026-0001'",
      );
      expect(encSql.rows.length, equals(1));
      final row = encSql.rows.first;
      expect(row.colByName('chief_complaint'), contains('chest tightness'));
      expect(row.colByName('diagnoses_json'), contains('I20.9'));

      // Verify visit clinical_status transitioned to COMPLETED
      final vSql = await db.execute('SELECT clinical_status FROM mc_visits WHERE id = :id', {'id': visitId});
      expect(vSql.rows.first.colByName('clinical_status'), equals('COMPLETED'));
    });
  });

  group('BATCH 2 — WORKSTREAM 4: Electronic Prescriptions (e-Rx)', () {
    late int prescriptionId;

    test('4.1 Doctor creates e-Rx with multiple medication lines', () async {
      // Get visit id from previous test
      final vRes = await db.execute("SELECT id, patient_id FROM mc_visits WHERE visit_number = 'VIS-ENC-0001'");
      final vid = int.parse(vRes.rows.first.colByName('id')!);
      final pid = int.parse(vRes.rows.first.colByName('patient_id')!);

      final rxRes = await http.post(
        Uri.parse('$baseUrl/api/v1/prescriptions'),
        headers: authHeaders('DOC01', 'DEV-DOC1'),
        body: jsonEncode({
          'visitId': vid,
          'patientId': pid,
          'notes': 'Take after meals with plenty of water',
          'items': [
            {
              'medicationCode': 'MED-ASP-100',
              'medicationName': 'Aspirin 100mg Tablet',
              'dose': '100mg',
              'route': 'Oral',
              'frequency': 'Once Daily',
              'duration': '30 days',
              'quantity': '30.0000',
              'instructions': 'Take after breakfast',
            },
            {
              'medicationCode': 'MED-BIS-005',
              'medicationName': 'Bisoprolol 5mg Tablet',
              'dose': '5mg',
              'route': 'Oral',
              'frequency': 'Once Daily',
              'duration': '30 days',
              'quantity': '30.0000',
              'instructions': 'Monitor pulse',
            },
          ],
        }),
      );

      expect(rxRes.statusCode, equals(201), reason: 'POST /prescriptions failed: ${rxRes.body}');
      final body = jsonDecode(rxRes.body)['data'];
      prescriptionId = body['prescriptionId'];
      expect(body['items'].length, equals(2));

      // Direct MariaDB Read-back verification
      final rxSql = await db.execute('SELECT * FROM mc_prescriptions WHERE id = :id', {'id': prescriptionId});
      expect(rxSql.rows.length, equals(1));
      expect(rxSql.rows.first.colByName('status'), equals('ACTIVE'));

      final itemsSql = await db.execute(
        'SELECT * FROM mc_prescription_items WHERE prescription_id = :id ORDER BY id ASC',
        {'id': prescriptionId},
      );
      expect(itemsSql.rows.length, equals(2));
      expect(itemsSql.rows.first.colByName('medication_code'), equals('MED-ASP-100'));
      expect(itemsSql.rows.first.colByName('status'), equals('PENDING'));
    });

    test('4.2 Fetches prescription by ID with full item details', () async {
      final getRes = await http.get(
        Uri.parse('$baseUrl/api/v1/prescriptions/$prescriptionId'),
        headers: authHeaders('DOC01', 'DEV-DOC1'),
      );
      expect(getRes.statusCode, equals(200));
      final data = jsonDecode(getRes.body)['data'];
      expect(data['id'], equals(prescriptionId));
      expect((data['items'] as List).length, equals(2));
    });
  });

  group('BATCH 2 — WORKSTREAM 5: Diagnostic Orders & Results Entry (LIS / RIS - CLN-003)', () {
    late int orderId;
    late int orderItemId;

    test('5.1 Creates Lab Diagnostic Order with order items', () async {
      final pRes = await db.execute("SELECT id FROM mc_patients WHERE mrn = 'MRN-ENC-001'");
      final pid = int.parse(pRes.rows.first.colByName('id')!);

      final oRes = await http.post(
        Uri.parse('$baseUrl/api/v1/orders'),
        headers: authHeaders('DOC01', 'DEV-DOC1'),
        body: jsonEncode({
          'patientId': pid,
          'orderType': 'LAB',
          'priority': 'URGENT',
          'clinicalIndication': 'Evaluate acute cardiac enzymes',
          'items': [
            {
              'itemCode': 'LAB-TROP-I',
              'itemName': 'Troponin I Quantitative',
              'quantity': '1.0000',
              'price': '150.0000',
            },
          ],
        }),
      );

      expect(oRes.statusCode, equals(201), reason: 'POST /orders failed: ${oRes.body}');
      final body = jsonDecode(oRes.body)['data'];
      orderId = body['orderId'];
      orderItemId = body['items'][0]['id'];
      expect(body['orderType'], equals('LAB'));
      expect(body['status'], equals('PENDING'));

      // Direct MariaDB Read-back verification
      final oSql = await db.execute('SELECT * FROM mc_clinical_orders WHERE id = :id', {'id': orderId});
      expect(oSql.rows.length, equals(1));
      expect(oSql.rows.first.colByName('priority'), equals('URGENT'));
    });

    test('5.2 Lab Tech lists orders and enters Result with CLN-003 Critical Panic Alert', () async {
      final listRes = await http.get(
        Uri.parse('$baseUrl/api/v1/orders?orderType=LAB&status=PENDING'),
        headers: authHeaders('LAB01', 'DEV-LAB'),
      );
      expect(listRes.statusCode, equals(200));
      final items = jsonDecode(listRes.body)['data']['items'] as List;
      expect(items.any((o) => o['id'] == orderId), isTrue);

      // Enter result with critical panic flag = true (Troponin > cutoff)
      final resRes = await http.post(
        Uri.parse('$baseUrl/api/v1/orders/$orderId/results'),
        headers: authHeaders('LAB01', 'DEV-LAB'),
        body: jsonEncode({
          'orderItemId': orderItemId,
          'resultType': 'NUMERIC',
          'resultJson': {
            'parameter': 'Troponin I',
            'value': 2.45,
            'unit': 'ng/mL',
            'referenceRange': '0.00 - 0.04',
            'flag': 'HH_CRITICAL',
          },
          'isCriticalPanic': true,
          'notes': 'Called ER Dr. on duty immediately at 14:15.',
        }),
      );

      expect(resRes.statusCode, equals(200));
      final resBody = jsonDecode(resRes.body)['data'];
      expect(resBody['status'], equals('COMPLETED'));
      expect(resBody['criticalFlag'], isTrue);

      // Direct MariaDB Read-back verification
      final rSql = await db.execute(
        'SELECT critical_flag, status FROM mc_clinical_results WHERE order_id = :id',
        {'id': orderId},
      );
      expect(rSql.rows.length, equals(1));
      expect(rSql.rows.first.colByName('critical_flag'), equals('1'));

      final oSql = await db.execute('SELECT status FROM mc_clinical_orders WHERE id = :id', {'id': orderId});
      expect(oSql.rows.first.colByName('status'), equals('COMPLETED'));
    });
  });

  group('BATCH 2 — WORKSTREAM 6: FIFO Inventory & Pharmacy Dispense (CLN-004 & FIN-004)', () {
    late int inventoryItemId;
    late int batch1Id;
    late int prescriptionId;
    late int prescriptionItemId;
    late int activeShiftId;

    setUpAll(() async {
      final sRes = await db.execute("SELECT id FROM mc_shifts WHERE shift_code = 'SHF-2026-02'");
      activeShiftId = int.parse(sRes.rows.first.colByName('id')!);

      // Seed Master Inventory Item
      final iRes = await db.execute('''
        INSERT INTO mc_inventory_items (
          hospital_code, public_id, tenant_id, item_number,
          item_code, name, unit, tracking_type, status
        ) VALUES (
          'HOSP_MAIN', 'PUB-INV-001', 'HOSP_MAIN', 'ITEM-001',
          'MED-ASP-100', 'Aspirin 100mg Tablet', 'BOX', 'BATCH', 'ACTIVE'
        )
      ''');
      inventoryItemId = iRes.lastInsertID.toInt();

      // Seed 2 batches (FIFO: Batch 1 expires next month, Batch 2 expires next year)
      final b1Res = await db.execute('''
        INSERT INTO mc_inventory_batches (
          hospital_code, public_id, tenant_id, item_id,
          batch_number, expiry_date, unit_cost, currency
        ) VALUES (
          'HOSP_MAIN', 'PUB-BAT-001', 'HOSP_MAIN', $inventoryItemId,
          'BATCH-2026-A', DATE_ADD(CURDATE(), INTERVAL 30 DAY), '15.0000', 'EGP'
        )
      ''');
      batch1Id = b1Res.lastInsertID.toInt();

      await db.execute('''
        INSERT INTO mc_inventory_batches (
          hospital_code, public_id, tenant_id, item_id,
          batch_number, expiry_date, unit_cost, currency
        ) VALUES (
          'HOSP_MAIN', 'PUB-BAT-002', 'HOSP_MAIN', $inventoryItemId,
          'BATCH-2026-B', DATE_ADD(CURDATE(), INTERVAL 365 DAY), '20.0000', 'EGP'
        )
      ''');

      // Fetch or seed existing prescription item
      final piSql = await db.execute(
        "SELECT id, prescription_id FROM mc_prescription_items WHERE medication_code = 'MED-ASP-100' LIMIT 1",
      );
      if (piSql.rows.isEmpty) {
        final pRes = await db.execute("SELECT id FROM mc_patients LIMIT 1");
        final pid = int.parse(pRes.rows.first.colByName('id')!);
        final rxRes = await db.execute('''
          INSERT INTO mc_prescriptions (hospital_code, visit_id, patient_id, doctor_id, doctor_name, status, created_at)
          VALUES ('HOSP_MAIN', 1, $pid, 1, 'Dr. Tarek', 'ACTIVE', NOW())
        ''');
        prescriptionId = rxRes.lastInsertID.toInt();
        final piRes = await db.execute('''
          INSERT INTO mc_prescription_items (hospital_code, public_id, tenant_id, prescription_id, medication_code, medication_name, quantity, status, created_at, updated_at)
          VALUES ('HOSP_MAIN', 'PUB-PI-01', 'HOSP_MAIN', $prescriptionId, 'MED-ASP-100', 'Aspirin 100mg Tablet', '30.0000', 'PENDING', NOW(), NOW())
        ''');
        prescriptionItemId = piRes.lastInsertID.toInt();
      } else {
        prescriptionItemId = int.parse(piSql.rows.first.colByName('id')!);
        prescriptionId = int.parse(piSql.rows.first.colByName('prescription_id')!);
      }
    });

    test('6.1 Lists items and verifies FIFO ordering of non-expired batches', () async {
      final itemsRes = await http.get(
        Uri.parse('$baseUrl/api/v1/inventory/items'),
        headers: authHeaders('PHM01', 'DEV-PHARM'),
      );
      expect(itemsRes.statusCode, equals(200));
      final items = jsonDecode(itemsRes.body)['data']['items'] as List;
      expect(items.any((i) => i['itemCode'] == 'MED-ASP-100'), isTrue);

      final batchesRes = await http.get(
        Uri.parse('$baseUrl/api/v1/inventory/batches?itemId=$inventoryItemId'),
        headers: authHeaders('PHM01', 'DEV-PHARM'),
      );
      expect(batchesRes.statusCode, equals(200));
      final batches = jsonDecode(batchesRes.body)['data']['items'] as List;
      expect(batches.length, equals(2));
      // First batch in list must be BATCH-2026-A (earliest expiry)
      expect(batches[0]['batchNumber'], equals('BATCH-2026-A'));
    });

    test('6.2 Dispenses item using FIFO batch and writes balanced COGS postings (FIN-004)', () async {
      final dispRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pharmacy/dispense'),
        headers: authHeaders('PHM01', 'DEV-PHARM'),
        body: jsonEncode({
          'prescriptionId': prescriptionId,
          'prescriptionItemId': prescriptionItemId,
          'inventoryItemId': inventoryItemId,
          'shiftId': activeShiftId,
          'quantity': '2.0000',
        }),
      );

      expect(dispRes.statusCode, equals(200));
      final body = jsonDecode(dispRes.body)['data'];
      expect(body['status'], equals('DISPENSED'));
      expect(body['batchId'], equals(batch1Id)); // CLN-004 FIFO: Earliest batch selected!
      expect(body['unitCost'], equals('15.0000'));
      expect(body['totalCost'], equals('30.0000')); // 2.0000 * 15.0000

      // Direct MariaDB Read-back verification
      // 1. mc_pharmacy_dispenses
      final dSql = await db.execute(
        'SELECT * FROM mc_pharmacy_dispenses WHERE prescription_item_id = :id',
        {'id': prescriptionItemId},
      );
      expect(dSql.rows.length, equals(1));
      expect(dSql.rows.first.colByName('status'), equals('DISPENSED'));

      // 2. mc_prescription_items status updated to DISPENSED
      final piSql = await db.execute('SELECT status FROM mc_prescription_items WHERE id = :id', {'id': prescriptionItemId});
      expect(piSql.rows.first.colByName('status'), equals('DISPENSED'));

      // 3. Balanced COGS Double-Entry in mc_financial_postings (FIN-004)
      final postSql = await db.execute(
        '''
        SELECT
          SUM(CASE WHEN direction = 'DEBIT' THEN amount ELSE 0 END) AS total_debit,
          SUM(CASE WHEN direction = 'CREDIT' THEN amount ELSE 0 END) AS total_credit
        FROM mc_financial_postings
        WHERE posting_type IN ('COGS_DISPENSE', 'INVENTORY_RELIEF')
        ''',
      );
      final totalDebit = Decimal.parse(postSql.rows.first.colByName('total_debit') ?? '0');
      final totalCredit = Decimal.parse(postSql.rows.first.colByName('total_credit') ?? '0');
      expect(totalDebit, equals(Decimal.parse('30.0000')));
      expect(totalCredit, equals(Decimal.parse('30.0000')));
      expect(totalDebit, equals(totalCredit)); // Trial Balance identity!
    });
  });

  group('BATCH 2 — WORKSTREAM 7: Inpatient Bed Map & Admissions (CLN-005)', () {
    late int bedId;
    late int admissionId;
    late int patientId;

    setUpAll(() async {
      // Seed Ward Bed
      final bRes = await db.execute('''
        INSERT INTO mc_ward_beds (
          hospital_code, tenant_id, public_id, department_id,
          room_id, bed_number, status, created_at
        ) VALUES (
          'HOSP_MAIN', 'HOSP_MAIN', 'PUB-BED-001', 'ICU',
          'ICU-ROOM-1', 'BED-01', 'AVAILABLE', NOW()
        )
      ''');
      bedId = bRes.lastInsertID.toInt();

      final pRes = await db.execute("SELECT id FROM mc_patients WHERE mrn = 'MRN-ENC-001'");
      patientId = int.parse(pRes.rows.first.colByName('id')!);
    });

    test('7.1 Lists available beds and admits patient, locking bed to OCCUPIED', () async {
      final bedsRes = await http.get(
        Uri.parse('$baseUrl/api/v1/beds?departmentId=ICU'),
        headers: authHeaders('SUP01', 'DEV-SUPER'),
      );
      expect(bedsRes.statusCode, equals(200));
      final beds = jsonDecode(bedsRes.body)['data']['items'] as List;
      expect(beds.any((b) => b['id'] == bedId && b['status'] == 'AVAILABLE'), isTrue);

      // Admit Patient
      final admRes = await http.post(
        Uri.parse('$baseUrl/api/v1/admissions'),
        headers: authHeaders('SUP01', 'DEV-SUPER'),
        body: jsonEncode({
          'patientId': patientId.toString(),
          'bedId': bedId.toString(),
          'departmentId': 'ICU',
          'roomId': 'ICU-ROOM-1',
          'admissionType': 'EMERGENCY',
          'diagnosisJson': jsonEncode({'admissionDx': 'Acute Myocardial Infarction'}),
        }),
      );

      expect(admRes.statusCode, equals(201));
      admissionId = jsonDecode(admRes.body)['data']['admissionId'];

      // Direct MariaDB Read-back: Bed status must be OCCUPIED
      final bSql = await db.execute('SELECT status FROM mc_ward_beds WHERE id = :id', {'id': bedId});
      expect(bSql.rows.first.colByName('status'), equals('OCCUPIED'));
    });

    test('7.2 Adversarial Test CLN-005: Attempting to admit another patient to OCCUPIED bed fails closed', () async {
      final admRes2 = await http.post(
        Uri.parse('$baseUrl/api/v1/admissions'),
        headers: authHeaders('SUP01', 'DEV-SUPER'),
        body: jsonEncode({
          'patientId': '999',
          'bedId': bedId.toString(),
          'admissionType': 'ELECTIVE',
        }),
      );
      // Fails with conflict/state error
      expect(admRes2.statusCode, equals(409));
      expect(jsonDecode(admRes2.body)['error']['message'], contains('CLN-005 Violation'));
    });

    test('7.3 Discharges patient and releases bed back to AVAILABLE', () async {
      final disRes = await http.post(
        Uri.parse('$baseUrl/api/v1/admissions/$admissionId/discharge'),
        headers: authHeaders('SUP01', 'DEV-SUPER'),
        body: jsonEncode({
          'dischargeReason': 'Condition stabilized; transferred to step-down telemetry.',
        }),
      );
      expect(disRes.statusCode, equals(200));
      expect(jsonDecode(disRes.body)['data']['status'], equals('Discharged'));

      // Direct MariaDB Read-back
      final bSql = await db.execute('SELECT status FROM mc_ward_beds WHERE id = :id', {'id': bedId});
      expect(bSql.rows.first.colByName('status'), equals('AVAILABLE'));

      final aSql = await db.execute('SELECT status FROM mc_admissions WHERE id = :id', {'id': admissionId});
      expect(aSql.rows.first.colByName('status'), equals('Discharged'));
    });
  });

  group('BATCH 2 — WORKSTREAM 8: Financial Commission Settlement & Dual Control (FIN-007 & SEC-005)', () {
    late int activeShiftId;

    setUpAll(() async {
      final sRes = await db.execute("SELECT id FROM mc_shifts WHERE shift_code = 'SHF-2026-02'");
      activeShiftId = int.parse(sRes.rows.first.colByName('id')!);
    });

    test('8.1 Settles accrued doctor commission with corrected double-entry & SEC-005 Two-Person Integrity', () async {
      final docId = staffIds['DOC01']!;

      // Check current accrued commission for Doctor 1
      final pCheck = await db.execute(
        '''
        SELECT SUM(amount) AS total
        FROM mc_financial_postings
        WHERE hospital_code = 'HOSP_MAIN'
          AND posting_type = 'COMMISSION_ACCRUAL'
          AND beneficiary_id = :doc_id
          AND status = 'POSTED'
        ''',
        {'doc_id': docId},
      );
      final accrued = Decimal.parse(pCheck.rows.first.colByName('total') ?? '0');
      expect(accrued, greaterThan(Decimal.zero));

      // 1. Direct single-actor settlement attempt WITHOUT approval FAILS CLOSED (SEC-005)
      final directFailRes = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements'),
        headers: authHeaders('CSH01', 'DEV-CASHIER'),
        body: jsonEncode({
          'doctorId': docId,
          'settleAmount': '50.0000',
          'shiftId': activeShiftId,
        }),
      );
      expect(directFailRes.statusCode, equals(403), reason: 'Direct unapproved settlement must be rejected');

      // 2. Step 1: Cashier requests settlement via /api/v1/finance/settlements/request
      final reqRes = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/request'),
        headers: authHeaders('CSH01', 'DEV-CASHIER'),
        body: jsonEncode({
          'doctorId': docId,
          'settleAmount': '50.0000',
          'shiftId': activeShiftId,
          'notes': 'Doctor commission payout request',
        }),
      );
      expect(reqRes.statusCode, equals(201), reason: 'POST /settlements/request failed: ${reqRes.body}');
      final reqBody = jsonDecode(reqRes.body)['data'];
      expect(reqBody['status'], equals('REQUESTED'));
      final settlementId = reqBody['settlementId'] as int;
      final dualReqId = reqBody['requestId'] as int;
      final setNo = reqBody['settlementNumber'] as String;

      // 3. Step 2 Adversarial Check: Cashier attempts self-approval (SEC-005)
      final selfApprove = await http.post(
        Uri.parse('$baseUrl/api/v1/dual-control/requests/$dualReqId/decide'),
        headers: authHeaders('CSH01', 'DEV-CASHIER'),
        body: jsonEncode({'approve': true}),
      );
      expect(selfApprove.statusCode, equals(403), reason: 'Self-approval must fail closed');

      // 4. Adversarial Check: Cashier attempts delivery before supervisor approval
      final prematureDeliver = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/$settlementId/deliver'),
        headers: authHeaders('CSH01', 'DEV-CASHIER'),
        body: jsonEncode({'shiftId': activeShiftId}),
      );
      expect(prematureDeliver.statusCode, equals(403), reason: 'Unapproved delivery must fail closed');

      // 5. Step 2 Legitimate Approval: Supervisor approves request
      final supApprove = await http.post(
        Uri.parse('$baseUrl/api/v1/dual-control/requests/$dualReqId/decide'),
        headers: authHeaders('SUP01', 'DEV-SUPER'),
        body: jsonEncode({'approve': true, 'decisionNotes': 'Approved commission payout'}),
      );
      expect(supApprove.statusCode, equals(200));

      // 6. Step 3: Cashier delivers/pays out approved settlement
      final delivRes = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/$settlementId/deliver'),
        headers: authHeaders('CSH01', 'DEV-CASHIER'),
        body: jsonEncode({'shiftId': activeShiftId}),
      );
      expect(delivRes.statusCode, equals(200), reason: 'Delivery failed: ${delivRes.body}');
      final delivBody = jsonDecode(delivRes.body)['data'];
      expect(delivBody['status'], equals('SETTLED'));

      // Direct MariaDB Read-back verification
      // 1. mc_financial_settlements records TWO DISTINCT ACTORS
      final sSql = await db.execute(
        "SELECT * FROM mc_financial_settlements WHERE settlement_number = :sno",
        {'sno': setNo},
      );
      expect(sSql.rows.length, equals(1));
      final sRow = sSql.rows.first;
      expect(sRow.colByName('status'), equals('SETTLED'));
      expect(sRow.colByName('requested_by'), isNotNull);
      expect(sRow.colByName('approved_by'), isNotNull);
      expect(sRow.colByName('delivered_by'), isNotNull);
      expect(sRow.colByName('requested_by'), isNot(equals(sRow.colByName('approved_by'))),
          reason: 'SEC-005 Two-Person Integrity: Requester and Approver must be distinct staff');

      // 2. FIN-007 Accrual Consumption: Accruals are marked SETTLED
      final postSettledSql = await db.execute(
        '''
        SELECT COUNT(*) as settled_count
        FROM mc_financial_postings
        WHERE settlement_id = :sid AND status = 'SETTLED'
        ''',
        {'sid': settlementId},
      );
      expect(int.parse(postSettledSql.rows.first.colByName('settled_count')!), greaterThan(0),
          reason: 'Accrual postings must be marked SETTLED');

      // 3. FIN-007 Double-Entry: Leg 1 DEBIT Liability, Leg 2 CREDIT Cash (Fixes P3 double-debit bug!)
      final legsSql = await db.execute(
        '''
        SELECT posting_type, account_bucket, direction, amount
        FROM mc_financial_postings
        WHERE settlement_id = :sid AND posting_type IN ('SETTLEMENT_LIABILITY', 'SETTLEMENT_PAYMENT')
        ORDER BY id ASC
        ''',
        {'sid': settlementId},
      );
      expect(legsSql.rows.length, equals(2));

      final liabLeg = legsSql.rows.firstWhere((r) => r.colByName('posting_type') == 'SETTLEMENT_LIABILITY');
      final payLeg = legsSql.rows.firstWhere((r) => r.colByName('posting_type') == 'SETTLEMENT_PAYMENT');

      expect(liabLeg.colByName('direction'), equals('DEBIT'));
      expect(liabLeg.colByName('account_bucket'), equals('PAYABLE_COMMISSION_DOCTOR'));

      expect(payLeg.colByName('direction'), equals('CREDIT')); // STRICTLY CREDIT!
      expect(payLeg.colByName('account_bucket'), equals('CASH_ON_HAND'));
    });

    test('8.2 Dual Control Approval Workflow & SEC-005 Two-Person Integrity Enforced', () async {
      // 1. Cashier with refundPolicy='approval' requests refund
      final vSql = await db.execute("SELECT id FROM mc_visits WHERE visit_number = 'VIS-CSH-0001'");
      final vid = int.parse(vSql.rows.first.colByName('id')!);

      final refRes = await http.post(
        Uri.parse('$baseUrl/api/v1/visits/$vid/refund'),
        headers: authHeaders('CSH01', 'DEV-CASHIER'),
        body: jsonEncode({
          'refundAmount': '50.0000',
          'reason': 'Customer requested refund for unused service component',
        }),
      );

      expect(refRes.statusCode, equals(200));
      final refBody = jsonDecode(refRes.body)['data'];
      expect(refBody['status'], equals('PENDING_APPROVAL'));
      final reqId = refBody['dualControlRequestId'] as int;

      // 2. Adversarial attack: Cashier attempts to self-approve their own request
      final selfApproveRes = await http.post(
        Uri.parse('$baseUrl/api/v1/dual-control/requests/$reqId/decide'),
        headers: authHeaders('CSH01', 'DEV-CASHIER'),
        body: jsonEncode({'approve': true}),
      );
      // Blocked!
      expect(selfApproveRes.statusCode, equals(403));

      // 3. Supervisor lists requests and approves legitimately
      final listRes = await http.get(
        Uri.parse('$baseUrl/api/v1/dual-control/requests'),
        headers: authHeaders('SUP01', 'DEV-SUPER'),
      );
      expect(listRes.statusCode, equals(200));
      final reqs = jsonDecode(listRes.body)['data']['items'] as List;
      expect(reqs.any((r) => r['id'] == reqId), isTrue);

      final approveRes = await http.post(
        Uri.parse('$baseUrl/api/v1/dual-control/requests/$reqId/decide'),
        headers: authHeaders('SUP01', 'DEV-SUPER'),
        body: jsonEncode({
          'approve': true,
          'decisionNotes': 'Verified receipt and patient identity.',
        }),
      );
      expect(approveRes.statusCode, equals(200));
      expect(jsonDecode(approveRes.body)['data']['status'], equals('APPROVED'));

      // Direct MariaDB Read-back verification
      final dcrSql = await db.execute('SELECT status, approver_staff_id FROM mc_dual_control_request WHERE id = :id', {'id': reqId});
      expect(dcrSql.rows.first.colByName('status'), equals('APPROVED'));
      expect(int.parse(dcrSql.rows.first.colByName('approver_staff_id')!), equals(staffIds['SUP01']));

      // Visit status transitioned to REFUNDED
      final visitSql = await db.execute('SELECT status FROM mc_visits WHERE id = :id', {'id': vid});
      expect(visitSql.rows.first.colByName('status'), equals('REFUNDED'));
    });
  });
}
