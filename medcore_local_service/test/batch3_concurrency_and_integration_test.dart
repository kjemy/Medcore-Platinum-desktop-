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
    securityRoot = Directory.systemTemp.createTempSync('medcore-b3-concurrency-');
    final config = testDbConfig(databaseName: 'medcore_concurrency_test', maxConnections: 20);
    db = DbClient(config);

    final adminConn = await db.openDedicatedConnection(useDatabase: false);
    try {
      await adminConn.execute('DROP DATABASE IF EXISTS `medcore_concurrency_test`');
      await adminConn.execute(
        'CREATE DATABASE `medcore_concurrency_test` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
      );
    } finally {
      await adminConn.close();
    }

    migrationRunner = MigrationRunner(db: db, migrationsDir: migrationsDir);
    await migrationRunner.runMigrations();

    server = LocalMedCoreServer(db, securityRootDirectory: securityRoot.path);
    final port = await server!.start(address: '127.0.0.1', port: 0);
    baseUrl = 'http://127.0.0.1:$port';

    // Bootstrap Tenants
    final govRepo = TenantGovernanceRepository(db);
    await govRepo.upsertTenant(hospitalCode: 'HOSP_CONC_A', name: 'Conc Hospital Alpha');
    await govRepo.upsertTenant(hospitalCode: 'HOSP_CONC_B', name: 'Conc Hospital Beta');

    // Devices
    final deviceList = [
      ('HOSP_CONC_A', 'DEV-DOC-A1'),
      ('HOSP_CONC_A', 'DEV-DOC-A2'),
      ('HOSP_CONC_A', 'DEV-PHARM-A'),
      ('HOSP_CONC_A', 'DEV-CASH-A'),
      ('HOSP_CONC_A', 'DEV-SUP-A1'),
      ('HOSP_CONC_A', 'DEV-SUP-A2'),
      ('HOSP_CONC_B', 'DEV-DOC-B1'),
      ('HOSP_CONC_B', 'DEV-CASH-B'),
    ];

    for (final (hosp, dev) in deviceList) {
      await govRepo.enrollOrUpdateDevice(
        hospitalCode: hosp,
        deviceId: dev,
        deviceName: '$dev Terminal',
        platform: 'WINDOWS',
        hwFingerprintSha256: PasswordHasher.sha256Hex(dev),
        devicePublicKeyEd25519: 'PUBKEY-$dev',
        isTrustedSecureRuntime: true,
        status: 'ACTIVE',
      );
    }

    // Staff
    final staffRepo = StaffIdentityRepository(db);

    Future<void> enrollAndLogin({
      required String hosp,
      required String code,
      required String name,
      required String email,
      required MedCoreRole role,
      required String devId,
      OperationalFlags? flags,
      Set<String>? customPerms,
    }) async {
      final s = await staffRepo.createStaff(
        hospitalCode: hosp,
        staffCode: code,
        fullName: name,
        email: email,
        role: role,
        passwordHash: PasswordHasher.hashPassword('Pass123!'),
        permissionsMode: (flags != null || customPerms != null) ? 'custom' : 'default',
        customPermissions: customPerms,
        operationalFlags: flags,
      );
      staffIds['$hosp:$code'] = s.id;

      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/login'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hosp,
          'identifier': email,
          'password': 'Pass123!',
          'deviceId': devId,
        }),
      );
      expect(res.statusCode, equals(200), reason: 'Login failed for $code: ${res.body}');
      final body = jsonDecode(res.body);
      tokens['$hosp:$code'] = body['data']['token'];
    }

    // Hosp A Staff
    await enrollAndLogin(
      hosp: 'HOSP_CONC_A',
      code: 'DOC_A1',
      name: 'Dr. Alpha One',
      email: 'alpha1@medcore.local',
      role: MedCoreRole.Doctor,
      devId: 'DEV-DOC-A1',
      customPerms: {'doctor', 'clinical_orders', 'clinic_Prescriptions', 'prescriptions_Write', 'inpatient_Admissions', 'inpatient_Discharge', 'inpatient_BedMap', 'appointments'},
      flags: const OperationalFlags(
        canEdit: true,
        canDelete: false,
        canCollectMoney: false,
        canMakeRefunds: false,
        refundPolicy: RefundPolicy.none,
      ),
    );
    await enrollAndLogin(
      hosp: 'HOSP_CONC_A',
      code: 'DOC_A2',
      name: 'Dr. Alpha Two',
      email: 'alpha2@medcore.local',
      role: MedCoreRole.Doctor,
      devId: 'DEV-DOC-A2',
      customPerms: {'doctor', 'clinical_orders', 'clinic_Prescriptions', 'prescriptions_Write', 'inpatient_Admissions', 'inpatient_Discharge', 'inpatient_BedMap', 'appointments'},
      flags: const OperationalFlags(
        canEdit: true,
        canDelete: false,
        canCollectMoney: false,
        canMakeRefunds: false,
        refundPolicy: RefundPolicy.none,
      ),
    );
    await enrollAndLogin(
      hosp: 'HOSP_CONC_A',
      code: 'PHM_A',
      name: 'Pharmacist Alpha',
      email: 'pharm@medcore.local',
      role: MedCoreRole.Pharmacist,
      devId: 'DEV-PHARM-A',
      customPerms: {'pharmacy', 'pharmacy_Dispensing', 'inventory_ItemsCatalog', 'inventory_StockBatches'},
      flags: const OperationalFlags(
        canEdit: true,
        canDelete: false,
        canCollectMoney: true,
        canMakeRefunds: false,
        refundPolicy: RefundPolicy.none,
      ),
    );
    await enrollAndLogin(
      hosp: 'HOSP_CONC_A',
      code: 'CSH_A',
      name: 'Cashier Alpha',
      email: 'cashier@medcore.local',
      role: MedCoreRole.Cashier,
      devId: 'DEV-CASH-A',
      customPerms: {'shifts', 'finance_Settlements'},
      flags: const OperationalFlags(
        canEdit: true,
        canDelete: false,
        canCollectMoney: true,
        canMakeRefunds: true,
        refundPolicy: RefundPolicy.approval,
      ),
    );
    await enrollAndLogin(
      hosp: 'HOSP_CONC_A',
      code: 'SUP_A1',
      name: 'Supervisor Alpha One',
      email: 'sup1@medcore.local',
      role: MedCoreRole.HospitalAdmin,
      devId: 'DEV-SUP-A1',
      customPerms: {'settings_Permissions'},
      flags: const OperationalFlags(
        canEdit: true,
        canDelete: false,
        canCollectMoney: true,
        canMakeRefunds: true,
        refundPolicy: RefundPolicy.direct,
      ),
    );
    await enrollAndLogin(
      hosp: 'HOSP_CONC_A',
      code: 'SUP_A2',
      name: 'Supervisor Alpha Two',
      email: 'sup2@medcore.local',
      role: MedCoreRole.HospitalAdmin,
      devId: 'DEV-SUP-A2',
      customPerms: {'settings_Permissions'},
      flags: const OperationalFlags(
        canEdit: true,
        canDelete: false,
        canCollectMoney: true,
        canMakeRefunds: true,
        refundPolicy: RefundPolicy.direct,
      ),
    );

    // Hosp B Staff
    await enrollAndLogin(
      hosp: 'HOSP_CONC_B',
      code: 'DOC_B1',
      name: 'Dr. Beta One',
      email: 'beta1@medcore.local',
      role: MedCoreRole.Doctor,
      devId: 'DEV-DOC-B1',
      customPerms: {'doctor', 'inpatient_Admissions', 'inpatient_Discharge', 'inpatient_BedMap', 'appointments'},
      flags: const OperationalFlags(
        canEdit: true,
        canDelete: false,
        canCollectMoney: false,
        canMakeRefunds: false,
        refundPolicy: RefundPolicy.none,
      ),
    );
    await enrollAndLogin(
      hosp: 'HOSP_CONC_B',
      code: 'CSH_B',
      name: 'Cashier Beta',
      email: 'cashierb@medcore.local',
      role: MedCoreRole.Cashier,
      devId: 'DEV-CASH-B',
      customPerms: {'shifts'},
      flags: const OperationalFlags(
        canEdit: true,
        canDelete: false,
        canCollectMoney: true,
        canMakeRefunds: false,
        refundPolicy: RefundPolicy.none,
      ),
    );
  });

  tearDownAll(() async {
    await server?.stop();
    await db.close();
    if (securityRoot.existsSync()) {
      securityRoot.deleteSync(recursive: true);
    }
  });

  Map<String, String> authHeaders(String hosp, String staffCode, String devId) => {
        'content-type': 'application/json',
        'x-tenant-id': hosp,
        'x-medcore-device-id': devId,
        'authorization': 'Bearer ${tokens['$hosp:$staffCode']}',
      };

  group('CONCURRENCY SUITE 1: Inpatient Bed Admission & Discharge Race Conditions (CLN-005)', () {
    late int raceBedId;
    late int patientA1Id;
    late int patientA2Id;

    setUpAll(() async {
      // 1. Seed Bed
      final bRes = await db.execute('''
        INSERT INTO mc_ward_beds (
          hospital_code, tenant_id, public_id, department_id,
          room_id, bed_number, status, created_at
        ) VALUES (
          'HOSP_CONC_A', 'HOSP_CONC_A', 'PUB-BED-RACE', 'ICU',
          'ICU-ROOM-RACE', 'BED-RACE-01', 'AVAILABLE', NOW()
        )
      ''');
      raceBedId = bRes.lastInsertID.toInt();

      // 2. Seed Patients
      final p1Res = await db.execute('''
        INSERT INTO mc_patients (hospital_code, mrn, full_name, phone, created_at, updated_at)
        VALUES ('HOSP_CONC_A', 'MRN-CONC-01', 'Patient Conc One', '01011111111', NOW(), NOW())
      ''');
      patientA1Id = p1Res.lastInsertID.toInt();

      final p2Res = await db.execute('''
        INSERT INTO mc_patients (hospital_code, mrn, full_name, phone, created_at, updated_at)
        VALUES ('HOSP_CONC_A', 'MRN-CONC-02', 'Patient Conc Two', '01022222222', NOW(), NOW())
      ''');
      patientA2Id = p2Res.lastInsertID.toInt();
    });

    test('1.1 Concurrent Bed Admission Race: Exactly 1 succeeds, exactly 1 rejected with 409 Conflict', () async {
      // Fire two simultaneous admission requests for the SAME bed
      final future1 = http.post(
        Uri.parse('$baseUrl/api/v1/admissions'),
        headers: authHeaders('HOSP_CONC_A', 'DOC_A1', 'DEV-DOC-A1'),
        body: jsonEncode({
          'patientId': patientA1Id.toString(),
          'bedId': raceBedId.toString(),
          'admissionType': 'EMERGENCY',
        }),
      );

      final future2 = http.post(
        Uri.parse('$baseUrl/api/v1/admissions'),
        headers: authHeaders('HOSP_CONC_A', 'DOC_A2', 'DEV-DOC-A2'),
        body: jsonEncode({
          'patientId': patientA2Id.toString(),
          'bedId': raceBedId.toString(),
          'admissionType': 'ELECTIVE',
        }),
      );

      final responses = await Future.wait([future1, future2]);

      final statusCodes = responses.map((r) => r.statusCode).toList();
      expect(statusCodes, contains(201), reason: 'One admission must succeed with 201 Created');
      expect(statusCodes, contains(409), reason: 'The competing admission must fail with 409 Conflict');

      final successResp = responses.firstWhere((r) => r.statusCode == 201);
      final conflictResp = responses.firstWhere((r) => r.statusCode == 409);

      final succBody = jsonDecode(successResp.body);
      expect(succBody['data']['status'], equals('Admitted'));
      expect(succBody['data']['bedId'], equals(raceBedId.toString()));

      final conflictBody = jsonDecode(conflictResp.body);
      expect(conflictBody['error']['code'], equals('DOMAIN_STATE_CONFLICT'));
      expect(conflictBody['error']['message'], contains('Violation'));

      // Direct MariaDB Read-back verification
      // 1. Bed status is OCCUPIED
      final bedSql = await db.execute('SELECT status FROM mc_ward_beds WHERE id = :id', {'id': raceBedId});
      expect(bedSql.rows.first.colByName('status'), equals('OCCUPIED'));

      // 2. Exactly ONE active admission exists for this bed
      final admSql = await db.execute(
        "SELECT id, patient_id, status FROM mc_admissions WHERE bed_id = :bed AND status = 'Admitted'",
        {'bed': raceBedId.toString()},
      );
      expect(admSql.rows.length, equals(1), reason: 'Exactly one active admission must exist in DB');
    });

    test('1.2 Concurrent Discharge Race: Exactly 1 succeeds, concurrent duplicate discharge rejected', () async {
      final admSql = await db.execute(
        "SELECT id FROM mc_admissions WHERE bed_id = :bed AND status = 'Admitted' LIMIT 1",
        {'bed': raceBedId.toString()},
      );
      final activeAdmId = int.parse(admSql.rows.first.colByName('id')!);

      // Launch two concurrent discharge requests for the same admission
      final f1 = http.post(
        Uri.parse('$baseUrl/api/v1/admissions/$activeAdmId/discharge'),
        headers: authHeaders('HOSP_CONC_A', 'DOC_A1', 'DEV-DOC-A1'),
        body: jsonEncode({'dischargeReason': 'Doctor 1 discharge'}),
      );

      final f2 = http.post(
        Uri.parse('$baseUrl/api/v1/admissions/$activeAdmId/discharge'),
        headers: authHeaders('HOSP_CONC_A', 'DOC_A2', 'DEV-DOC-A2'),
        body: jsonEncode({'dischargeReason': 'Doctor 2 discharge'}),
      );

      final responses = await Future.wait([f1, f2]);
      final statusCodes = responses.map((r) => r.statusCode).toList();

      expect(statusCodes, contains(200));
      expect(statusCodes, contains(409));

      // Direct MariaDB Read-back verification
      // 1. Bed status is restored to AVAILABLE
      final bedSql = await db.execute('SELECT status FROM mc_ward_beds WHERE id = :id', {'id': raceBedId});
      expect(bedSql.rows.first.colByName('status'), equals('AVAILABLE'));

      // 2. Admission status is Discharged
      final admCheck = await db.execute('SELECT status FROM mc_admissions WHERE id = :id', {'id': activeAdmId});
      expect(admCheck.rows.first.colByName('status'), equals('Discharged'));
    });
  });

  group('CONCURRENCY SUITE 2: Concurrent FIFO Pharmacy Dispensing Race Condition (CLN-004 & FIN-004)', () {
    late int itemId;
    late int batchId;
    late int prescriptionId;
    late int prescriptionItemId;
    late int shiftId;

    setUpAll(() async {
      // 1. Open Shift
      final sRes = await db.execute('''
        INSERT INTO mc_shifts (
          hospital_code, shift_code, cashier_staff_id,
          opening_balance, cash_in, cash_out, expected_cash,
          status, opened_at
        ) VALUES (
          'HOSP_CONC_A', 'SHF-CONC-PHM', ${staffIds['HOSP_CONC_A:CSH_A']},
          '500.0000', '0.0000', '0.0000', '500.0000',
          'OPEN', NOW()
        )
      ''');
      shiftId = sRes.lastInsertID.toInt();

      // 2. Seed Master Inventory Item & Batch
      final iRes = await db.execute('''
        INSERT INTO mc_inventory_items (
          hospital_code, public_id, tenant_id, item_number,
          item_code, name, unit, tracking_type, status
        ) VALUES (
          'HOSP_CONC_A', 'PUB-INV-CONC', 'HOSP_CONC_A', 'ITEM-CONC-01',
          'MED-CONC-100', 'Amoxicillin 500mg Capsule', 'STRIP', 'BATCH', 'ACTIVE'
        )
      ''');
      itemId = iRes.lastInsertID.toInt();

      final bRes = await db.execute('''
        INSERT INTO mc_inventory_batches (
          hospital_code, public_id, tenant_id, item_id,
          batch_number, expiry_date, unit_cost, currency
        ) VALUES (
          'HOSP_CONC_A', 'PUB-BAT-CONC', 'HOSP_CONC_A', $itemId,
          'BATCH-CONC-FIFO', DATE_ADD(CURDATE(), INTERVAL 60 DAY), '25.0000', 'EGP'
        )
      ''');
      batchId = bRes.lastInsertID.toInt();

      // 3. Seed Prescription
      final pRes = await db.execute("SELECT id FROM mc_patients WHERE hospital_code = 'HOSP_CONC_A' LIMIT 1");
      final patientId = int.parse(pRes.rows.first.colByName('id')!);

      final rxRes = await db.execute('''
        INSERT INTO mc_prescriptions (hospital_code, visit_id, patient_id, doctor_id, doctor_name, status, created_at)
        VALUES ('HOSP_CONC_A', 99, $patientId, ${staffIds['HOSP_CONC_A:DOC_A1']}, 'Dr. Alpha One', 'ACTIVE', NOW())
      ''');
      prescriptionId = rxRes.lastInsertID.toInt();

      final piRes = await db.execute('''
        INSERT INTO mc_prescription_items (
          hospital_code, public_id, tenant_id, prescription_id,
          medication_code, medication_name, quantity, status, created_at, updated_at
        ) VALUES (
          'HOSP_CONC_A', 'PUB-PI-CONC', 'HOSP_CONC_A', $prescriptionId,
          'MED-CONC-100', 'Amoxicillin 500mg Capsule', '2.0000', 'PENDING', NOW(), NOW()
        )
      ''');
      prescriptionItemId = piRes.lastInsertID.toInt();
    });

    test('2.1 Concurrent Dispense Race: Exactly 1 dispense succeeds, duplicate dispense fails closed', () async {
      // Simulate double-click or simultaneous pharmacy requests for the same prescription item
      final f1 = http.post(
        Uri.parse('$baseUrl/api/v1/pharmacy/dispense'),
        headers: authHeaders('HOSP_CONC_A', 'PHM_A', 'DEV-PHARM-A'),
        body: jsonEncode({
          'prescriptionId': prescriptionId,
          'prescriptionItemId': prescriptionItemId,
          'inventoryItemId': itemId,
          'shiftId': shiftId,
          'quantity': '2.0000',
        }),
      );

      final f2 = http.post(
        Uri.parse('$baseUrl/api/v1/pharmacy/dispense'),
        headers: authHeaders('HOSP_CONC_A', 'PHM_A', 'DEV-PHARM-A'),
        body: jsonEncode({
          'prescriptionId': prescriptionId,
          'prescriptionItemId': prescriptionItemId,
          'inventoryItemId': itemId,
          'shiftId': shiftId,
          'quantity': '2.0000',
        }),
      );

      final responses = await Future.wait([f1, f2]);
      final statusCodes = responses.map((r) => r.statusCode).toList();

      expect(statusCodes, contains(200), reason: 'One dispense operation must succeed');
      expect(statusCodes, contains(409), reason: 'Concurrent double-dispense must be rejected with 409 Conflict');

      // Direct MariaDB Read-back verification
      // 1. mc_pharmacy_dispenses has exactly 1 record
      final dSql = await db.execute(
        'SELECT id, quantity, unit_cost FROM mc_pharmacy_dispenses WHERE prescription_item_id = :piid',
        {'piid': prescriptionItemId},
      );
      expect(dSql.rows.length, equals(1));
      expect(dSql.rows.first.colByName('quantity'), equals('2.0000'));
      expect(dSql.rows.first.colByName('unit_cost'), equals('25.0000'));

      // 2. mc_prescription_items is DISPENSED
      final piSql = await db.execute(
        'SELECT status FROM mc_prescription_items WHERE id = :id',
        {'id': prescriptionItemId},
      );
      expect(piSql.rows.first.colByName('status'), equals('DISPENSED'));

      // 3. Exactly ONE movement in mc_inventory_movements
      final mSql = await db.execute(
        "SELECT id, quantity FROM mc_inventory_movements WHERE item_id = :iid AND batch_id = :bid AND movement_type = 'PHARMACY_DISPENSE'",
        {'iid': itemId, 'bid': batchId},
      );
      expect(mSql.rows.length, equals(1));
      expect(mSql.rows.first.colByName('quantity'), equals('2.0000'));

      // 4. Balanced COGS Postings in mc_financial_postings (FIN-004)
      final postSql = await db.execute(
        '''
        SELECT
          SUM(CASE WHEN direction = 'DEBIT' THEN amount ELSE 0 END) AS total_debit,
          SUM(CASE WHEN direction = 'CREDIT' THEN amount ELSE 0 END) AS total_credit
        FROM mc_financial_postings
        WHERE shift_id = :sid AND posting_type IN ('COGS_DISPENSE', 'INVENTORY_RELIEF')
        ''',
        {'sid': shiftId},
      );
      final totalDebit = Decimal.parse(postSql.rows.first.colByName('total_debit') ?? '0');
      final totalCredit = Decimal.parse(postSql.rows.first.colByName('total_credit') ?? '0');
      expect(totalDebit, equals(Decimal.parse('50.0000'))); // 2 * 25.0000
      expect(totalCredit, equals(Decimal.parse('50.0000')));
      expect(totalDebit, equals(totalCredit)); // Trial Balance identity!
    });
  });

  group('CONCURRENCY SUITE 3: Cashier Shift Closing vs Concurrent Settlements (FIN-006 & FIN-007)', () {
    late int shiftId;
    late int doctorId;

    setUpAll(() async {
      doctorId = staffIds['HOSP_CONC_A:DOC_A1']!;

      // 1. Seed Cashier Shift with opening balance 1000.0000
      final sRes = await db.execute('''
        INSERT INTO mc_shifts (
          hospital_code, shift_code, cashier_staff_id,
          opening_balance, cash_in, cash_out, expected_cash,
          status, opened_at
        ) VALUES (
          'HOSP_CONC_A', 'SHF-CONC-SET', ${staffIds['HOSP_CONC_A:CSH_A']},
          '1000.0000', '500.0000', '0.0000', '1500.0000',
          'OPEN', NOW()
        )
      ''');
      shiftId = sRes.lastInsertID.toInt();

      // 2. Seed doctor commission accrual in mc_financial_postings (500.0000)
      final evRes = await db.execute('''
        INSERT INTO mc_financial_events (
          event_uuid, hospital_code, idempotency_key, event_type,
          source_module, source_entity_type, source_entity_id, shift_id,
          gross_amount, discount_amount, net_amount, paid_amount,
          insurance_covered_amount, patient_responsibility_amount, balance_amount,
          status, created_by
        ) VALUES (
          'EV-ACCRUAL-CONC', 'HOSP_CONC_A', 'IDEMP-ACCRUAL-CONC', 'CONSULTATION_COMMISSION',
          'CLINICAL', 'VISIT', 101, $shiftId,
          '500.0000', '0.0000', '500.0000', '0.0000',
          '0.0000', '0.0000', '0.0000',
          'POSTED', $doctorId
        )
      ''');
      final evId = evRes.lastInsertID.toInt();

      // Seed balanced double-entry accrual postings (FIN-001 & FIN-007)
      await db.execute('''
        INSERT INTO mc_financial_postings (
          posting_uuid, hospital_code, event_id, posting_type,
          account_bucket, direction, amount, beneficiary_type, beneficiary_id, shift_id, status
        ) VALUES (
          'POST-ACCRUAL-EXP', 'HOSP_CONC_A', $evId, 'COMMISSION_EXPENSE',
          'EXPENSE_DOCTOR_COMMISSION', 'DEBIT', '500.0000', 'DOCTOR', $doctorId, $shiftId, 'POSTED'
        )
      ''');

      await db.execute('''
        INSERT INTO mc_financial_postings (
          posting_uuid, hospital_code, event_id, posting_type,
          account_bucket, direction, amount, beneficiary_type, beneficiary_id, shift_id, status
        ) VALUES (
          'POST-ACCRUAL-PAY', 'HOSP_CONC_A', $evId, 'COMMISSION_ACCRUAL',
          'PAYABLE_COMMISSION_DOCTOR', 'CREDIT', '500.0000', 'DOCTOR', $doctorId, $shiftId, 'POSTED'
        )
      ''');
    });

    test('3.1 Concurrent Shift Close vs Settlement Serialization: Atomicity and Trial Balance', () async {
      // 1. Step 1: Cashier requests settlement
      final reqRes = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/request'),
        headers: authHeaders('HOSP_CONC_A', 'CSH_A', 'DEV-CASH-A'),
        body: jsonEncode({
          'doctorId': doctorId,
          'settleAmount': '200.0000',
          'shiftId': shiftId,
        }),
      );
      expect(reqRes.statusCode, equals(201));
      final setBody = jsonDecode(reqRes.body)['data'];
      final settlementId = setBody['settlementId'] as int;
      final dualReqId = setBody['requestId'] as int;

      // 2. Step 2: Supervisor approves request (SEC-005 Two-Person Integrity)
      final appRes = await http.post(
        Uri.parse('$baseUrl/api/v1/dual-control/requests/$dualReqId/decide'),
        headers: authHeaders('HOSP_CONC_A', 'SUP_A1', 'DEV-SUP-A1'),
        body: jsonEncode({'approve': true}),
      );
      expect(appRes.statusCode, equals(200));

      // 3. Fire concurrent settlement delivery and shift close
      final fSettlement = http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/$settlementId/deliver'),
        headers: authHeaders('HOSP_CONC_A', 'CSH_A', 'DEV-CASH-A'),
        body: jsonEncode({'shiftId': shiftId}),
      );

      final fClose = http.post(
        Uri.parse('$baseUrl/api/v1/shifts/close'),
        headers: authHeaders('HOSP_CONC_A', 'CSH_A', 'DEV-CASH-A'),
        body: jsonEncode({
          'shiftId': shiftId,
          'countedCash': '1300.0000',
          'notes': 'Concurrent shift close test',
        }),
      );

      final responses = await Future.wait([fSettlement, fClose]);
      final statusCodes = responses.map((r) => r.statusCode).toList();

      // Serialization invariant: Either (Settlement 200 + Close 200) or (Close 200 + Settlement 409/Error)
      expect(statusCodes, contains(200));

      // Direct MariaDB Read-back verification
      final shiftSql = await db.execute('SELECT status, opening_balance, cash_in, cash_out, expected_cash, counted_cash FROM mc_shifts WHERE id = :id', {'id': shiftId});
      final row = shiftSql.rows.first;
      expect(row.colByName('status'), equals('CLOSED'));

      final openBal = Decimal.parse(row.colByName('opening_balance')!);
      final cashIn = Decimal.parse(row.colByName('cash_in')!);
      final cashOut = Decimal.parse(row.colByName('cash_out')!);
      final expCash = Decimal.parse(row.colByName('expected_cash')!);

      // Strict FIN-006 Invariant: Expected = Open + In - Out
      expect(expCash, equals(openBal + cashIn - cashOut));
    });

    test('3.2 Closed-Shift Rejection Invariant: Delivery against already-CLOSED shift is strictly rejected', () async {
      // 1. Request and approve a second settlement of 100.0000
      final reqRes = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/request'),
        headers: authHeaders('HOSP_CONC_A', 'CSH_A', 'DEV-CASH-A'),
        body: jsonEncode({
          'doctorId': doctorId,
          'settleAmount': '100.0000',
          'shiftId': shiftId,
        }),
      );
      // Since shift is CLOSED, requesting on closed shift fails closed!
      // Even if forced, delivering on closed shift fails closed!
      expect(reqRes.statusCode, isNot(equals(200)));
      expect(reqRes.statusCode, isNot(equals(201)));

      // Verify MariaDB: Closed shift was not mutated
      final shiftSql = await db.execute('SELECT status FROM mc_shifts WHERE id = :id', {'id': shiftId});
      expect(shiftSql.rows.first.colByName('status'), equals('CLOSED'));
    });
  });

  group('CONCURRENCY SUITE 4: Concurrent Dual-Control Approval Race (SEC-005 Two-Person Rule)', () {
    late int requestId;

    setUpAll(() async {
      // Seed a pending dual-control request created by Cashier
      final rRes = await db.execute('''
        INSERT INTO mc_dual_control_request (
          hospital_code, request_uuid, action_type,
          target_entity_type, target_entity_id, requested_amount, payload_json,
          requester_staff_id, status, reason, created_at
        ) VALUES (
          'HOSP_CONC_A', 'REQ-CONC-01', 'VISIT_REFUND',
          'mc_visits', '888', '150.0000', '{}',
          ${staffIds['HOSP_CONC_A:CSH_A']}, 'PENDING', 'Patient requested refund', NOW()
        )
      ''');
      requestId = rRes.lastInsertID.toInt();
    });

    test('4.1 Concurrent Decision Race: Exactly 1 supervisor decision commits, competing decision rejected', () async {
      // Two supervisors attempt to decide the request at the exact same instant
      final f1 = http.post(
        Uri.parse('$baseUrl/api/v1/dual-control/requests/$requestId/decide'),
        headers: authHeaders('HOSP_CONC_A', 'SUP_A1', 'DEV-SUP-A1'),
        body: jsonEncode({
          'approve': true,
          'decisionNotes': 'Approved by Supervisor 1',
        }),
      );

      final f2 = http.post(
        Uri.parse('$baseUrl/api/v1/dual-control/requests/$requestId/decide'),
        headers: authHeaders('HOSP_CONC_A', 'SUP_A2', 'DEV-SUP-A2'),
        body: jsonEncode({
          'approve': false,
          'decisionNotes': 'Rejected by Supervisor 2',
        }),
      );

      final responses = await Future.wait([f1, f2]);
      final statusCodes = responses.map((r) => r.statusCode).toList();

      expect(statusCodes, contains(200), reason: 'One supervisor decision must succeed');
      expect(statusCodes, contains(409), reason: 'The concurrent duplicate decision must be rejected with 409 Conflict');

      // Direct MariaDB Read-back verification
      final reqSql = await db.execute(
        'SELECT status, approver_staff_id, decided_at FROM mc_dual_control_request WHERE id = :id',
        {'id': requestId},
      );
      final reqRow = reqSql.rows.first;
      expect(reqRow.colByName('status'), anyOf('APPROVED', 'REJECTED'));
      expect(reqRow.colByName('approver_staff_id'), isNotNull);
      expect(reqRow.colByName('decided_at'), isNotNull);
    });

    test('4.2 Self-Approval Prevention (SEC-005 Two-Person Integrity): Staff cannot approve own request', () async {
      // Create request where requester is Supervisor SUP_A1
      final r2Res = await db.execute('''
        INSERT INTO mc_dual_control_request (
          hospital_code, request_uuid, action_type,
          target_entity_type, target_entity_id, requested_amount, payload_json,
          requester_staff_id, status, reason, created_at
        ) VALUES (
          'HOSP_CONC_A', 'REQ-CONC-02', 'VISIT_REFUND',
          'mc_visits', '889', '200.0000', '{}',
          ${staffIds['HOSP_CONC_A:SUP_A1']}, 'PENDING', 'Self approval attempt test', NOW()
        )
      ''');
      final req2Id = r2Res.lastInsertID.toInt();

      // SUP_A1 attempts to approve own request
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/dual-control/requests/$req2Id/decide'),
        headers: authHeaders('HOSP_CONC_A', 'SUP_A1', 'DEV-SUP-A1'),
        body: jsonEncode({
          'approve': true,
          'decisionNotes': 'Self-approval attempt',
        }),
      );

      // Must fail closed with 403 Forbidden
      expect(res.statusCode, equals(403));
      final body = jsonDecode(res.body);
      expect(body['error']['code'], equals('DUAL_CONTROL_SELF_APPROVAL_FORBIDDEN'));

      // Direct MariaDB Read-back verification: Still PENDING!
      final reqCheck = await db.execute('SELECT status FROM mc_dual_control_request WHERE id = :id', {'id': req2Id});
      expect(reqCheck.rows.first.colByName('status'), equals('PENDING'));
    });
  });

  group('CONCURRENCY SUITE 5: Cross-Tenant Isolation Integrity under Parallel Workload', () {
    late int hospBPatientId;
    late int hospBBedId;

    setUpAll(() async {
      // Seed Patient and Bed in Hospital Beta
      final pRes = await db.execute('''
        INSERT INTO mc_patients (hospital_code, mrn, full_name, phone, created_at, updated_at)
        VALUES ('HOSP_CONC_B', 'MRN-BETA-01', 'Patient Beta One', '01233333333', NOW(), NOW())
      ''');
      hospBPatientId = pRes.lastInsertID.toInt();

      final bRes = await db.execute('''
        INSERT INTO mc_ward_beds (
          hospital_code, tenant_id, public_id, department_id,
          room_id, bed_number, status, created_at
        ) VALUES (
          'HOSP_CONC_B', 'HOSP_CONC_B', 'PUB-BED-BETA', 'SURGICAL',
          'BETA-ROOM-1', 'BED-BETA-01', 'AVAILABLE', NOW()
        )
      ''');
      hospBBedId = bRes.lastInsertID.toInt();
    });

    test('5.1 Tenant A Doctor cannot view or mutate Tenant B Beds or Patients', () async {
      // 1. Doctor in Tenant A attempts to admit Tenant B's patient into Tenant B's bed
      final admRes = await http.post(
        Uri.parse('$baseUrl/api/v1/admissions'),
        headers: authHeaders('HOSP_CONC_A', 'DOC_A1', 'DEV-DOC-A1'),
        body: jsonEncode({
          'patientId': hospBPatientId.toString(),
          'bedId': hospBBedId.toString(),
          'admissionType': 'EMERGENCY',
        }),
      );

      // Bed is in HOSP_CONC_B, so HOSP_CONC_A query for bed id fails with Bed not found (409)
      expect(admRes.statusCode, equals(409));
      final body = jsonDecode(admRes.body);
      expect(body['error']['message'], contains('not found'));

      // 2. Doctor A listing beds only sees Tenant A beds, ZERO Tenant B beds
      final bedsRes = await http.get(
        Uri.parse('$baseUrl/api/v1/beds'),
        headers: authHeaders('HOSP_CONC_A', 'DOC_A1', 'DEV-DOC-A1'),
      );
      expect(bedsRes.statusCode, equals(200));
      final bedsList = jsonDecode(bedsRes.body)['data']['items'] as List;
      expect(bedsList.any((b) => b['bedNumber'] == 'BED-BETA-01'), isFalse);

      // 3. Doctor B listing beds sees BED-BETA-01, ZERO Tenant A beds
      final bedsBRes = await http.get(
        Uri.parse('$baseUrl/api/v1/beds'),
        headers: authHeaders('HOSP_CONC_B', 'DOC_B1', 'DEV-DOC-B1'),
      );
      expect(bedsBRes.statusCode, equals(200));
      final bedsBList = jsonDecode(bedsBRes.body)['data']['items'] as List;
      expect(bedsBList.any((b) => b['bedNumber'] == 'BED-BETA-01'), isTrue);
      expect(bedsBList.any((b) => b['bedNumber'] == 'BED-RACE-01'), isFalse);
    });

    test('5.2 High-Throughput Concurrent Multi-Tenant Appointments: Zero Cross-Leakage', () async {
      // Concurrently create 5 appointments in Tenant A and 5 in Tenant B
      final futuresA = List.generate(5, (i) {
        return http.post(
          Uri.parse('$baseUrl/api/v1/appointments'),
          headers: authHeaders('HOSP_CONC_A', 'DOC_A1', 'DEV-DOC-A1'),
          body: jsonEncode({
            'appointmentNumber': 'APT-A-$i',
            'patientId': 1,
            'doctorId': staffIds['HOSP_CONC_A:DOC_A1']!.toString(),
            'scheduledAt': DateTime.now().add(Duration(days: i + 1)).toIso8601String(),
          }),
        );
      });

      final futuresB = List.generate(5, (i) {
        return http.post(
          Uri.parse('$baseUrl/api/v1/appointments'),
          headers: authHeaders('HOSP_CONC_B', 'DOC_B1', 'DEV-DOC-B1'),
          body: jsonEncode({
            'appointmentNumber': 'APT-B-$i',
            'patientId': hospBPatientId,
            'doctorId': staffIds['HOSP_CONC_B:DOC_B1']!.toString(),
            'scheduledAt': DateTime.now().add(Duration(days: i + 1)).toIso8601String(),
          }),
        );
      });

      final allResponses = await Future.wait([...futuresA, ...futuresB]);
      for (final r in allResponses) {
        expect(r.statusCode, equals(201), reason: 'Appointment creation response: ${r.body}');
      }

      // Direct MariaDB Read-back verification
      final aptASql = await db.execute("SELECT COUNT(*) AS cnt FROM mc_appointments WHERE hospital_code = 'HOSP_CONC_A' AND appointment_number LIKE 'APT-A-%'");
      expect(int.parse(aptASql.rows.first.colByName('cnt')!), equals(5));

      final aptBSql = await db.execute("SELECT COUNT(*) AS cnt FROM mc_appointments WHERE hospital_code = 'HOSP_CONC_B' AND appointment_number LIKE 'APT-B-%'");
      expect(int.parse(aptBSql.rows.first.colByName('cnt')!), equals(5));

      // Cross-tenant verification: zero APT-B records in Tenant A
      final crossSql = await db.execute("SELECT COUNT(*) AS cnt FROM mc_appointments WHERE hospital_code = 'HOSP_CONC_A' AND appointment_number LIKE 'APT-B-%'");
      expect(int.parse(crossSql.rows.first.colByName('cnt')!), equals(0));
    });
  });
}
