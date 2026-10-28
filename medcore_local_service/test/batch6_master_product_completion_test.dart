import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
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
  late Directory backupDir;

  late String runtimeTechSecret;
  late String runtimeBackupKey;

  final serviceRoot = Directory.current.path;
  final migrationsDir = p.join(serviceRoot, 'sql', 'migrations');

  late String adminToken;
  late String cashierToken;
  late String radTechToken;
  late String techSessionToken;

  late int doctorId;
  late int patientId;
  late int visitId;
  late int shiftId;

  setUpAll(() async {
    securityRoot = Directory.systemTemp.createTempSync('medcore-b6-sec-');
    backupDir = Directory.systemTemp.createTempSync('medcore-b6-bak-');
    runtimeTechSecret = 'TechSecret_${PasswordHasher.generateSecureToken(16)}';
    runtimeBackupKey = 'BackupKey_${PasswordHasher.generateSecureToken(24)}';

    final config = testDbConfig(databaseName: 'medcore_batch6_test', maxConnections: 10);
    db = DbClient(config);

    final adminConn = await db.openDedicatedConnection(useDatabase: false);
    try {
      await adminConn.execute('DROP DATABASE IF EXISTS `medcore_batch6_test`');
      await adminConn.execute(
        'CREATE DATABASE `medcore_batch6_test` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
      );
    } finally {
      await adminConn.close();
    }

    migrationRunner = MigrationRunner(db: db, migrationsDir: migrationsDir);
    final applied = await migrationRunner.runMigrations();
    expect(applied.length, greaterThanOrEqualTo(15));

    final govRepo = TenantGovernanceRepository(db);
    await govRepo.upsertTenant(
      hospitalCode: 'HOSP_TEST',
      name: 'MedCore Test Medical Center',
    );
    await govRepo.enrollOrUpdateDevice(
      hospitalCode: 'HOSP_TEST',
      deviceId: 'DEV-WORKSTATION-01',
      deviceName: 'Workstation 1',
      platform: 'WINDOWS',
      connectionType: 'LOOPBACK',
      hwFingerprintSha256: PasswordHasher.sha256Hex('HW-01-FP'),
      devicePublicKeyEd25519: 'PUBKEY-01',
      roleScope: 'SERVER_HOST',
      isTrustedSecureRuntime: true,
      status: 'ACTIVE',
    );

    // Create staff users
    final staffRepo = StaffIdentityRepository(db);
    await staffRepo.createStaff(
      hospitalCode: 'HOSP_TEST',
      staffCode: 'ADM-01',
      fullName: 'Hospital Administrator',
      email: 'admin@hosp-test.local',
      passwordHash: PasswordHasher.hashPassword('Admin123!'),
      role: MedCoreRole.HospitalAdmin,
      operationalFlags: const OperationalFlags(
        canEdit: true,
        canDelete: true,
        canCollectMoney: true,
        canMakeRefunds: true,
        refundPolicy: RefundPolicy.direct,
      ),
    );

    await staffRepo.createStaff(
      hospitalCode: 'HOSP_TEST',
      staffCode: 'CSH-01',
      fullName: 'Cashier Fatima',
      email: 'cashier@hosp-test.local',
      passwordHash: PasswordHasher.hashPassword('Cashier123!'),
      role: MedCoreRole.Cashier,
    );

    await staffRepo.createStaff(
      hospitalCode: 'HOSP_TEST',
      staffCode: 'RAD-01',
      fullName: 'Radiographer Tariq',
      email: 'rad@hosp-test.local',
      passwordHash: PasswordHasher.hashPassword('Rad123!'),
      role: MedCoreRole.Nurse,
      permissionsMode: 'custom',
      customPermissions: {'rad_Dashboard', 'rad_Tests'},
    );

    // Create a Doctor
    final doc = await staffRepo.createStaff(
      hospitalCode: 'HOSP_TEST',
      staffCode: 'DOC-01',
      fullName: 'Dr. Ziyad Consultant',
      email: 'doctor@hosp-test.local',
      passwordHash: PasswordHasher.hashPassword('Doctor123!'),
      role: MedCoreRole.Doctor,
      departmentId: 'DEPT-CLINIC',
      clinicId: 'CLINIC-01',
    );
    doctorId = doc.id;

    server = LocalMedCoreServer(
      db,
      securityRootDirectory: securityRoot.path,
      technicianSecretHashOverride: PasswordHasher.hashPassword(runtimeTechSecret),
      backupStorageDirectory: backupDir.path,
      backupEncryptionKeyOverride: runtimeBackupKey,
    );
    final port = await server!.start(address: '127.0.0.1', port: 0);
    baseUrl = 'http://127.0.0.1:$port';

    // Login Admin
    final admResp = await http.post(
      Uri.parse('$baseUrl/api/v1/auth/login'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'hospitalCode': 'HOSP_TEST',
        'identifier': 'admin@hosp-test.local',
        'password': 'Admin123!',
        'deviceId': 'DEV-WORKSTATION-01',
      }),
    );
    expect(admResp.statusCode, equals(200));
    adminToken = jsonDecode(admResp.body)['data']['token'] as String;

    // Create Patient via Admin API
    final patResp = await http.post(
      Uri.parse('$baseUrl/api/v1/patients'),
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer $adminToken',
        'x-tenant-id': 'HOSP_TEST',
        'x-medcore-device-id': 'DEV-WORKSTATION-01',
      },
      body: jsonEncode({
        'mrn': 'MRN-2026-001',
        'fullName': 'Ali Hassan Patient',
        'gender': 'male',
        'dateOfBirth': '1985-05-15',
        'phone': '+201012345678',
        'nationalId': '28505151234567',
        'address': 'Cairo, Egypt',
      }),
    );
    expect(patResp.statusCode, anyOf([200, 201]));
    patientId = jsonDecode(patResp.body)['data']['id'] as int;

    // Login Cashier
    final cshResp = await http.post(
      Uri.parse('$baseUrl/api/v1/auth/login'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'hospitalCode': 'HOSP_TEST',
        'identifier': 'cashier@hosp-test.local',
        'password': 'Cashier123!',
        'deviceId': 'DEV-WORKSTATION-01',
      }),
    );
    expect(cshResp.statusCode, equals(200));
    cashierToken = jsonDecode(cshResp.body)['data']['token'] as String;

    // Login RadTech
    final radResp = await http.post(
      Uri.parse('$baseUrl/api/v1/auth/login'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'hospitalCode': 'HOSP_TEST',
        'identifier': 'rad@hosp-test.local',
        'password': 'Rad123!',
        'deviceId': 'DEV-WORKSTATION-01',
      }),
    );
    expect(radResp.statusCode, equals(200));
    radTechToken = jsonDecode(radResp.body)['data']['token'] as String;

    // Login Technician via session/open
    final techAuthResp = await http.post(
      Uri.parse('$baseUrl/api/v1/technician/session/open'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'hospitalCode': 'HOSP_TEST',
        'deviceId': 'DEV-WORKSTATION-01',
        'technicianSecret': runtimeTechSecret,
      }),
    );
    expect(techAuthResp.statusCode, equals(201));
    techSessionToken = jsonDecode(techAuthResp.body)['data']['technicianToken'] as String;

    // Open Cashier Shift
    final shiftResp = await http.post(
      Uri.parse('$baseUrl/api/v1/shifts/open'),
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer $cashierToken',
        'x-tenant-id': 'HOSP_TEST',
        'x-medcore-device-id': 'DEV-WORKSTATION-01',
      },
      body: jsonEncode({
        'shiftCode': 'SHIFT-B6-01',
        'openingBalance': '1000.00',
      }),
    );
    expect(shiftResp.statusCode, equals(201));
    shiftId = jsonDecode(shiftResp.body)['data']['id'] as int;

    // Create an initial Paid Visit
    final visitResp = await http.post(
      Uri.parse('$baseUrl/api/v1/visits'),
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer $cashierToken',
        'x-tenant-id': 'HOSP_TEST',
        'x-medcore-device-id': 'DEV-WORKSTATION-01',
      },
      body: jsonEncode({
        'visitNumber': 'VISIT-B6-REFUND-001',
        'idempotencyKey': 'IDEMP-VISIT-B6-001',
        'patientId': patientId,
        'doctorId': doctorId,
        'shiftId': shiftId,
        'serviceCode': 'SRV-001',
        'serviceName': 'General Consultation',
        'serviceLaborGross': '300.00',
        'consumableGross': '0.00',
        'consumableFifoCost': '0.00',
        'discountAmount': '0.00',
        'insuranceCoveredAmount': '0.00',
        'paidAmount': '300.00',
        'doctorCommissionRatePercent': '10.00',
      }),
    );
    expect(visitResp.statusCode, equals(201));
    visitId = jsonDecode(visitResp.body)['data']['visitId'] as int;
  });

  tearDownAll(() async {
    await server?.stop();
    await db.close();
    if (securityRoot.existsSync()) securityRoot.deleteSync(recursive: true);
    if (backupDir.existsSync()) backupDir.deleteSync(recursive: true);
  });

  Map<String, String> staffHeaders(String token) => {
        'content-type': 'application/json',
        'authorization': 'Bearer $token',
        'x-tenant-id': 'HOSP_TEST',
        'x-medcore-device-id': 'DEV-WORKSTATION-01',
      };

  Map<String, String> techHeaders() => {
        'content-type': 'application/json',
        'x-medcore-tech-token': techSessionToken,
        'x-tenant-id': 'HOSP_TEST',
        'x-medcore-device-id': 'DEV-WORKSTATION-01',
      };

  // =========================================================================
  // TEST 1: BATCH 1 FINANCIAL REFUND REVERSAL & TRIAL BALANCE INVARIANT
  // =========================================================================
  test('Batch 1: Financial Refund Reversal symmetrically reverses ledger legs and maintains trial balance', () async {
    // 1. Post refund on visitId
    final refResp = await http.post(
      Uri.parse('$baseUrl/api/v1/visits/$visitId/refund'),
      headers: staffHeaders(adminToken),
      body: jsonEncode({
        'refundAmount': '300.00',
        'reason': 'Patient requested appointment cancellation',
        'shiftId': shiftId,
        'idempotencyKey': 'IDEMP-REFUND-B6-001',
      }),
    );
    expect(refResp.statusCode, equals(200));
    final refData = jsonDecode(refResp.body)['data'];
    expect(refData['status'], equals('EXECUTED_DIRECT'));
    expect(refData['visitId'], equals(visitId));

    // 2. Direct MariaDB Verification of Visit State
    final vRow = (await db.execute(
      'SELECT status, paid_amount, balance_amount FROM mc_visits WHERE id = :id',
      {'id': visitId},
    )).rows.first.assoc();
    expect(vRow['status'], equals('REFUNDED'));
    expect(Decimal.parse(vRow['balance_amount']!), equals(Decimal.zero));

    // 3. Direct MariaDB Verification of Shift Cash
    final sRow = (await db.execute(
      'SELECT opening_balance, cash_in, cash_out, expected_cash FROM mc_shifts WHERE id = :id',
      {'id': shiftId},
    )).rows.first.assoc();
    expect(Decimal.parse(sRow['cash_out']!), equals(Decimal.parse('300.00')));
    // expected cash was 1000 + 300 - 300 = 1000.00
    expect(Decimal.parse(sRow['expected_cash']!), equals(Decimal.parse('1000.00')));

    // 4. Physical Trial Balance Invariant: SUM(debit) == SUM(credit)
    final balRow = (await db.execute(
      '''
      SELECT SUM(CASE WHEN direction = 'DEBIT' THEN amount ELSE 0 END) AS total_debit,
             SUM(CASE WHEN direction = 'CREDIT' THEN amount ELSE 0 END) AS total_credit
      FROM mc_financial_postings
      WHERE hospital_code = 'HOSP_TEST'
      ''',
    )).rows.first.assoc();
    final totDebit = Decimal.parse(balRow['total_debit']!);
    final totCredit = Decimal.parse(balRow['total_credit']!);
    expect(totDebit, equals(totCredit), reason: 'Trial balance invariant violated: SUM(DEBIT) != SUM(CREDIT)');

    // 5. Verification of mc_financial_events reversal linkage
    final evRow = (await db.execute(
      '''
      SELECT event_type, gross_amount, reversal_of_event_id
      FROM mc_financial_events
      WHERE hospital_code = 'HOSP_TEST' AND event_type = 'VISIT_REFUND' AND source_entity_id = :id
      ''',
      {'id': visitId},
    )).rows.first.assoc();
    expect(evRow['event_type'], equals('VISIT_REFUND'));
    expect(evRow['reversal_of_event_id'], isNotNull);

    // 6. Adversarial Replay: Duplicate refund request must be rejected (409 Conflict)
    final dupRefResp = await http.post(
      Uri.parse('$baseUrl/api/v1/visits/$visitId/refund'),
      headers: staffHeaders(adminToken),
      body: jsonEncode({
        'refundAmount': '300.00',
        'reason': 'Duplicate refund attempt',
        'shiftId': shiftId,
        'idempotencyKey': 'IDEMP-REFUND-B6-DUP',
      }),
    );
    expect(dupRefResp.statusCode, equals(409));
  });

  // =========================================================================
  // TEST 2: BATCH 2 STANDALONE PATIENT_AR COLLECTION
  // =========================================================================
  test('Batch 2: Standalone PATIENT_AR Collection posts balanced double entries and prevents over-collection', () async {
    // 1. Create a visit with partial payment leaving an outstanding balance of 400.00
    final partVisitResp = await http.post(
      Uri.parse('$baseUrl/api/v1/visits'),
      headers: staffHeaders(cashierToken),
      body: jsonEncode({
        'visitNumber': 'VISIT-B6-PARTIAL-002',
        'idempotencyKey': 'IDEMP-VISIT-B6-002',
        'patientId': patientId,
        'doctorId': doctorId,
        'shiftId': shiftId,
        'serviceCode': 'SRV-002',
        'serviceName': 'Root Canal Treatment',
        'serviceLaborGross': '500.00',
        'consumableGross': '0.00',
        'consumableFifoCost': '0.00',
        'discountAmount': '0.00',
        'insuranceCoveredAmount': '0.00',
        'paidAmount': '100.00',
        'doctorCommissionRatePercent': '10.00',
      }),
    );
    expect(partVisitResp.statusCode, equals(201));

    // Verify patient balance before collection
    final patBefore = (await db.execute(
      'SELECT balance FROM mc_patients WHERE id = :id',
      {'id': patientId},
    )).rows.first.assoc();
    expect(Decimal.parse(patBefore['balance']!), equals(Decimal.parse('400.00')));

    // 2. Collect 250.00 via Standalone AR Collection
    final collResp = await http.post(
      Uri.parse('$baseUrl/api/v1/finance/ar-collections'),
      headers: staffHeaders(cashierToken),
      body: jsonEncode({
        'patientId': patientId,
        'amount': '250.00',
        'paymentMethod': 'CASH',
        'notes': 'Partial counter settlement',
        'idempotencyKey': 'IDEMP-AR-B6-001',
      }),
    );
    expect(collResp.statusCode, anyOf([200, 201]));
    final collData = jsonDecode(collResp.body)['data'];
    expect(Decimal.parse(collData['collectedAmount']!), equals(Decimal.parse('250.00')));
    expect(Decimal.parse(collData['remainingBalance']!), equals(Decimal.parse('150.00')));

    // 3. Direct MariaDB Verification of Postings & Patient Balance
    final patAfter = (await db.execute(
      'SELECT balance FROM mc_patients WHERE id = :id',
      {'id': patientId},
    )).rows.first.assoc();
    expect(Decimal.parse(patAfter['balance']!), equals(Decimal.parse('150.00')));

    // Verify balanced double-entry in mc_financial_postings
    final arEntries = (await db.execute(
      '''
      SELECT posting_type, direction, amount, account_bucket
      FROM mc_financial_postings
      WHERE hospital_code = 'HOSP_TEST' AND posting_type LIKE 'AR_COLLECTION_%'
      ORDER BY id DESC LIMIT 2
      ''',
    )).rows;
    expect(arEntries.length, equals(2));
    final debitLeg = arEntries.firstWhere((r) => r.assoc()['direction'] == 'DEBIT').assoc();
    final creditLeg = arEntries.firstWhere((r) => r.assoc()['direction'] == 'CREDIT').assoc();
    expect(debitLeg['account_bucket'], equals('CASH_ON_HAND'));
    expect(creditLeg['account_bucket'], equals('ACCOUNTS_RECEIVABLE_PATIENT'));
    expect(Decimal.parse(debitLeg['amount']!), equals(Decimal.parse('250.00')));
    expect(Decimal.parse(creditLeg['amount']!), equals(Decimal.parse('250.00')));

    // 4. Adversarial Over-Collection: Attempt to collect 200.00 when balance is only 150.00
    final overCollResp = await http.post(
      Uri.parse('$baseUrl/api/v1/finance/ar-collections'),
      headers: staffHeaders(cashierToken),
      body: jsonEncode({
        'patientId': patientId,
        'amount': '200.00',
        'paymentMethod': 'CASH',
        'notes': 'Over collection attempt',
        'idempotencyKey': 'IDEMP-AR-B6-OVER',
      }),
    );
    expect(overCollResp.statusCode, anyOf([400, 409]));
  });

  // =========================================================================
  // TEST 3: BATCH 6 RAD/LAB PERMISSION SPLIT
  // =========================================================================
  test('Batch 6: RAD/LAB Permission Split enforces granular access on /api/v1/orders', () async {
    // RadTech has 'rad_Dashboard' and 'rad_Tests', but lacks 'lab_Dashboard'
    // 1. Query RAD orders -> MUST SUCCEED (200 OK)
    final radResp = await http.get(
      Uri.parse('$baseUrl/api/v1/orders?orderType=RAD'),
      headers: staffHeaders(radTechToken),
    );
    expect(radResp.statusCode, equals(200));

    // 2. Query LAB orders with radTechToken -> MUST FAIL CLOSED (403 Forbidden)
    final labResp = await http.get(
      Uri.parse('$baseUrl/api/v1/orders?orderType=LAB'),
      headers: staffHeaders(radTechToken),
    );
    expect(labResp.statusCode, equals(403));

    // 3. HospitalAdmin has all permissions -> both RAD and LAB succeed
    final admRadResp = await http.get(
      Uri.parse('$baseUrl/api/v1/orders?orderType=RAD'),
      headers: staffHeaders(adminToken),
    );
    expect(admRadResp.statusCode, equals(200));

    final admLabResp = await http.get(
      Uri.parse('$baseUrl/api/v1/orders?orderType=LAB'),
      headers: staffHeaders(adminToken),
    );
    expect(admLabResp.statusCode, equals(200));
  });

  // =========================================================================
  // TEST 4: BATCH 5 SPECIALTY CLINICAL REST CONTROLLERS
  // =========================================================================
  test('Batch 5: Specialty Clinical Endpoints operate on MariaDB schema and enforce module entitlement', () async {
    // 1. Nursing: Create task, list, and complete
    final nurseTaskResp = await http.post(
      Uri.parse('$baseUrl/api/v1/clinical/nursing/tasks'),
      headers: staffHeaders(adminToken),
      body: jsonEncode({
        'patientId': patientId,
        'taskType': 'VITAL_SIGNS',
        'description': 'Measure blood pressure and spO2 every 4 hours',
        'scheduledTime': DateTime.now().toUtc().toIso8601String(),
        'priority': 'URGENT',
      }),
    );
    expect(nurseTaskResp.statusCode, anyOf([200, 201]));
    final taskId = jsonDecode(nurseTaskResp.body)['data']['taskId'] as int;

    final nurseListResp = await http.get(
      Uri.parse('$baseUrl/api/v1/clinical/nursing/tasks?patientId=$patientId'),
      headers: staffHeaders(adminToken),
    );
    expect(nurseListResp.statusCode, equals(200));
    final tasks = jsonDecode(nurseListResp.body)['data']['items'] as List;
    expect(tasks.any((t) => t['id'] == taskId), isTrue);

    final nurseDoneResp = await http.post(
      Uri.parse('$baseUrl/api/v1/clinical/nursing/tasks/$taskId/complete'),
      headers: staffHeaders(adminToken),
      body: jsonEncode({'completionNotes': 'BP 120/80, spO2 99%'}),
    );
    expect(nurseDoneResp.statusCode, equals(200));

    // 2. ICU: Record flowsheet and SOFA score
    final icuFlowResp = await http.post(
      Uri.parse('$baseUrl/api/v1/clinical/icu/flowsheets'),
      headers: staffHeaders(adminToken),
      body: jsonEncode({
        'patientId': patientId,
        'bedId': 'ICU-BED-01',
        'systolicBp': 120,
        'diastolicBp': 80,
        'meanArterialPressure': 93.3,
        'heartRate': 72,
        'respiratoryRate': 16,
        'temperatureC': 37.1,
        'spo2Percent': 98.5,
        'gcsScore': 15,
      }),
    );
    expect(icuFlowResp.statusCode, anyOf([200, 201]));

    final icuSofaResp = await http.post(
      Uri.parse('$baseUrl/api/v1/clinical/icu/scores'),
      headers: staffHeaders(adminToken),
      body: jsonEncode({
        'admissionId': 'ADM-B6-001',
        'patientId': patientId,
        'score': 0,
        'details': {
          'respirationScore': 0,
          'coagulationScore': 0,
          'liverScore': 0,
          'cardiovascularScore': 0,
          'cnsScore': 0,
          'renalScore': 0,
        },
      }),
    );
    expect(icuSofaResp.statusCode, anyOf([200, 201]));
    expect(jsonDecode(icuSofaResp.body)['data']['score'], equals(0));

    // 3. Surgery: Schedule surgery and update status
    final surgResp = await http.post(
      Uri.parse('$baseUrl/api/v1/clinical/surgeries'),
      headers: staffHeaders(adminToken),
      body: jsonEncode({
        'patientId': patientId,
        'operatingRoom': 'OR-1',
        'procedureName': 'Laparoscopic Appendectomy',
        'leadSurgeonStaffId': doctorId,
        'scheduledStartTime': DateTime.now().toUtc().add(const Duration(days: 1)).toIso8601String(),
        'scheduledEndTime': DateTime.now().toUtc().add(const Duration(days: 1, hours: 2)).toIso8601String(),
      }),
    );
    expect(surgResp.statusCode, anyOf([200, 201]));
    final surgeryId = jsonDecode(surgResp.body)['data']['surgeryId'] as int;

    final surgStatusResp = await http.put(
      Uri.parse('$baseUrl/api/v1/clinical/surgeries/$surgeryId/status'),
      headers: staffHeaders(adminToken),
      body: jsonEncode({
        'status': 'IN_PROGRESS',
        'notes': 'Patient prepped and draped',
      }),
    );
    expect(surgStatusResp.statusCode, equals(200));

    // 4. Dialysis: Schedule and complete
    final dialResp = await http.post(
      Uri.parse('$baseUrl/api/v1/clinical/dialysis/sessions'),
      headers: staffHeaders(adminToken),
      body: jsonEncode({
        'patientId': patientId,
        'dialysisMachineId': 'HEMO-01',
        'scheduledDate': DateTime.now().toUtc().toIso8601String().substring(0, 10),
        'prescribedHours': 4.0,
        'targetUltrafiltrationLiters': 2.5,
        'preWeightKg': 75.0,
      }),
    );
    expect(dialResp.statusCode, anyOf([200, 201]));
    final sessionId = jsonDecode(dialResp.body)['data']['sessionId'] as int;

    final dialDoneResp = await http.put(
      Uri.parse('$baseUrl/api/v1/clinical/dialysis/sessions/$sessionId/complete'),
      headers: staffHeaders(adminToken),
      body: jsonEncode({
        'actualHours': 4.0,
        'postWeightKg': 72.5,
        'fluidRemovedLiters': 2.5,
        'complicationsNotes': 'None, patient well tolerated session',
      }),
    );
    expect(dialDoneResp.statusCode, equals(200));

    // 5. Fail-Closed Module Entitlement: Disable Dialysis module in facility config and assert 403
    await db.execute(
      '''
      INSERT INTO mc_facility_config (
        hospital_code, facility_name, facility_type, edition,
        installation_identity, enabled_modules_json, patient_fields_config_json,
        branding_appearance_json, network_config_json, backup_config_json,
        remote_hybrid_config_json, created_at, updated_at
      ) VALUES (
        'HOSP_TEST', 'MedCore Test Medical Center', 'GENERAL_HOSPITAL', 'PLATINUM',
        'INSTALL-TEST-01', '{"Dialysis": false}', '{}', '{}', '{}', '{}', '{}', NOW(), NOW()
      )
      ON DUPLICATE KEY UPDATE enabled_modules_json = '{"Dialysis": false}', updated_at = NOW()
      ''',
    );
    final dialDisabledResp = await http.get(
      Uri.parse('$baseUrl/api/v1/clinical/dialysis/sessions'),
      headers: staffHeaders(adminToken),
    );
    expect(dialDisabledResp.statusCode, equals(403));
    expect(jsonDecode(dialDisabledResp.body)['error']['code'], equals('MODULE_NOT_ENTITLED'));
  });

  // =========================================================================
  // TEST 5: BATCH 17 RESTORE HARDENING (verifyBackupArchiveForRestore)
  // =========================================================================
  test('Batch 17: Restore Hardening verifies backup archive integrity before restore', () async {
    // 1. Create a simulated encrypted backup archive file
    final sampleArchive = File(p.join(backupDir.path, 'sample_backup.enc.tar'));
    sampleArchive.writeAsStringSync('SIMULATED_ENCRYPTED_BACKUP_CONTENT');
    final actualSha256 = sha256.convert(sampleArchive.readAsBytesSync()).toString();

    // 2. Verify with matching SHA-256 -> PASS
    final validResp = await http.post(
      Uri.parse('$baseUrl/api/v1/backups/verify-restore'),
      headers: techHeaders(),
      body: jsonEncode({
        'archiveFilePath': sampleArchive.path,
        'expectedSha256': actualSha256,
      }),
    );
    expect(validResp.statusCode, equals(200));
    final validData = jsonDecode(validResp.body)['data'];
    expect(validData['verified'], isTrue);
    expect(validData['actualSha256'], equals(actualSha256));

    // 3. Verify with tampered expected SHA-256 -> FAILS INTEGRITY (409 DOMAIN_STATE_CONFLICT)
    final invalidResp = await http.post(
      Uri.parse('$baseUrl/api/v1/backups/verify-restore'),
      headers: techHeaders(),
      body: jsonEncode({
        'archiveFilePath': sampleArchive.path,
        'expectedSha256': '0000000000000000000000000000000000000000000000000000000000000000',
      }),
    );
    expect(invalidResp.statusCode, equals(409));
    final err = jsonDecode(invalidResp.body)['error'];
    expect(err['code'], equals('DOMAIN_STATE_CONFLICT'));
    expect(err['message'], contains('CHECKSUM_MISMATCH'));
  });

  // =========================================================================
  // TEST 6: BATCH 18 NATIVE PRINTING FORMATTER
  // =========================================================================
  test('Batch 6/18: Native Printing formats ESC/POS and ZPL jobs with HARDWARE_VERIFICATION_PENDING marker', () async {
    // 1. ESC/POS Receipt
    final escResp = await http.post(
      Uri.parse('$baseUrl/api/v1/printing/format'),
      headers: staffHeaders(cashierToken),
      body: jsonEncode({
        'format': 'ESC_POS',
        'documentType': 'RECEIPT',
        'documentId': 'REC-B6-001',
        'facilityName': 'MedCore Center',
        'patientName': 'Ali Hassan',
        'patientMrn': 'MRN-2026-001',
        'grossAmount': '300.00',
        'netAmount': '300.00',
        'paidAmount': '300.00',
        'balanceAmount': '0.00',
        'items': [
          {'name': 'Dental Cleaning', 'amount': '300.00'}
        ],
      }),
    );
    expect(escResp.statusCode, equals(200));
    final escJob = jsonDecode(escResp.body)['data'];
    expect(escJob['format'], equals('ESC_POS'));
    expect(escJob['byteLength'], greaterThan(10));
    expect(escJob['hardwareStatus'], equals('HARDWARE_VERIFICATION_PENDING'));

    // 2. ZPL Barcode Specimen Label
    final zplResp = await http.post(
      Uri.parse('$baseUrl/api/v1/printing/format'),
      headers: staffHeaders(cashierToken),
      body: jsonEncode({
        'format': 'ZPL',
        'documentType': 'LABEL',
        'documentId': 'SPEC-B6-99',
        'labelTitle': 'Blood Chemistry',
        'patientName': 'Ali Hassan',
        'patientMrn': 'MRN-2026-001',
      }),
    );
    expect(zplResp.statusCode, equals(200));
    final zplJob = jsonDecode(zplResp.body)['data'];
    expect(zplJob['format'], equals('ZPL'));
    expect(zplJob['byteLength'], greaterThan(10));
    expect(zplJob['hardwareStatus'], equals('HARDWARE_VERIFICATION_PENDING'));
  });

  // =========================================================================
  // TEST 7: BATCH 19 DIAGNOSTIC BUNDLE WITH PII REDACTION
  // =========================================================================
  test('Batch 19: Technician Diagnostic Bundle redacts PII and includes authoritative system telemetry', () async {
    final bundleResp = await http.post(
      Uri.parse('$baseUrl/api/v1/maintenance/engineering-bundle'),
      headers: techHeaders(),
    );
    expect(bundleResp.statusCode, equals(200));
    final bundle = jsonDecode(bundleResp.body)['data'];

    expect(bundle['bundleFormat'], equals('MEDCORE_ENGINEERING_BUNDLE_V1'));
    expect(bundle['piiPrivacyFilterApplied'], isTrue);
    expect(bundle['diagnosticPayload'], isNotNull);

    // Assert that raw patient email or phone is NEVER present in the bundle string
    final bundleJson = jsonEncode(bundle);
    expect(bundleJson.contains('admin@hosp-test.local'), isFalse);
    expect(bundleJson.contains('+201012345678'), isFalse);
    expect(bundleJson.contains('28505151234567'), isFalse);
  });
}
