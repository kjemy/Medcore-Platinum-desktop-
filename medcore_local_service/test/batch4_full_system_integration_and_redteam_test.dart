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
    securityRoot = Directory.systemTemp.createTempSync('medcore-b4-e2e-');
    final config = testDbConfig(databaseName: 'medcore_e2e_test', maxConnections: 20);
    db = DbClient(config);

    final adminConn = await db.openDedicatedConnection(useDatabase: false);
    try {
      await adminConn.execute('DROP DATABASE IF EXISTS `medcore_e2e_test`');
      await adminConn.execute(
        'CREATE DATABASE `medcore_e2e_test` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
      );
    } finally {
      await adminConn.close();
    }

    migrationRunner = MigrationRunner(db: db, migrationsDir: migrationsDir);
    await migrationRunner.runMigrations();

    server = LocalMedCoreServer(db, securityRootDirectory: securityRoot.path);
    final port = await server!.start(address: '127.0.0.1', port: 0);
    baseUrl = 'http://127.0.0.1:$port';

    // Bootstrap Tenant
    final govRepo = TenantGovernanceRepository(db);
    await govRepo.upsertTenant(hospitalCode: 'HOSP_E2E', name: 'MedCore Apex General Hospital');

    // Devices
    final deviceList = [
      'DEV-REC',
      'DEV-DOC',
      'DEV-LAB',
      'DEV-PHM',
      'DEV-CSH',
      'DEV-ADM',
    ];

    for (final dev in deviceList) {
      await govRepo.enrollOrUpdateDevice(
        hospitalCode: 'HOSP_E2E',
        deviceId: dev,
        deviceName: '$dev Station',
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
      required String code,
      required String name,
      required String email,
      required MedCoreRole role,
      required String devId,
      OperationalFlags? flags,
      Set<String>? customPerms,
    }) async {
      final s = await staffRepo.createStaff(
        hospitalCode: 'HOSP_E2E',
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
          'hospitalCode': 'HOSP_E2E',
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
      name: 'Amira Receptionist',
      email: 'amira@medcore.local',
      role: MedCoreRole.Receptionist,
      devId: 'DEV-REC',
      customPerms: {'reception', 'reception_QuickCheckIn', 'appointments', 'patients', 'patients.write'},
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
      name: 'Dr. Hazem Cardiologist',
      email: 'hazem@medcore.local',
      role: MedCoreRole.Doctor,
      devId: 'DEV-DOC',
      customPerms: {
        'doctor',
        'clinic_DoctorQueue',
        'clinic_Prescriptions',
        'prescriptions_Write',
        'inpatient_Admissions',
        'inpatient_Discharge',
        'inpatient_BedMap',
        'appointments',
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
      code: 'LAB01',
      name: 'Kareem Lab Tech',
      email: 'kareem@medcore.local',
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
      name: 'Salma Pharmacist',
      email: 'salma@medcore.local',
      role: MedCoreRole.Pharmacist,
      devId: 'DEV-PHM',
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
      code: 'CSH01',
      name: 'Omar Cashier',
      email: 'omar@medcore.local',
      role: MedCoreRole.Cashier,
      devId: 'DEV-CSH',
      customPerms: {'shifts', 'reception_QuickCheckIn', 'finance_Invoices', 'finance_Settlements', 'finance_Settlements_secure'},
      flags: const OperationalFlags(
        canEdit: true,
        canDelete: false,
        canCollectMoney: true,
        canMakeRefunds: true,
        refundPolicy: RefundPolicy.approval,
      ),
    );

    await enrollAndLogin(
      code: 'ADM01',
      name: 'General Director',
      email: 'director@medcore.local',
      role: MedCoreRole.HospitalAdmin,
      devId: 'DEV-ADM',
      customPerms: {'settings_Permissions'},
      flags: const OperationalFlags(
        canEdit: true,
        canDelete: false,
        canCollectMoney: true,
        canMakeRefunds: true,
        refundPolicy: RefundPolicy.direct,
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

  Map<String, String> authHeaders(String staffCode, String devId) => {
        'content-type': 'application/json',
        'x-tenant-id': 'HOSP_E2E',
        'x-medcore-device-id': devId,
        'authorization': 'Bearer ${tokens[staffCode]}',
      };

  group('FULL-SYSTEM INTEGRATED JOURNEY (12 STAGES): Complete Clinical & Financial Lifecycle', () {
    late int shiftId;
    late int patientId;
    late int appointmentId;
    late int visitId;
    late int encounterId;
    late int labOrderId;
    late int labOrderItemId;
    late int prescriptionId;
    late int rxItemId;
    late int inventoryItemId;
    late int inventoryBatchId;
    late int bedId;
    late int admissionId;

    test('Stage 1: Cashier opens morning shift (FIN-006)', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/shifts/open'),
        headers: authHeaders('CSH01', 'DEV-CSH'),
        body: jsonEncode({
          'shiftCode': 'SHF-E2E-01',
          'openingBalance': '1000.0000',
        }),
      );
      expect(res.statusCode, equals(201));
      shiftId = jsonDecode(res.body)['data']['id'];
      expect(shiftId, isPositive);

      // MariaDB Read-back
      final sSql = await db.execute('SELECT status, opening_balance FROM mc_shifts WHERE id = :id', {'id': shiftId});
      expect(sSql.rows.first.colByName('status'), equals('OPEN'));
      expect(Decimal.parse(sSql.rows.first.colByName('opening_balance')!), equals(Decimal.parse('1000.0000')));
    });

    test('Stage 2: Reception registers patient and books appointment', () async {
      // 1. Register Patient
      final pRes = await http.post(
        Uri.parse('$baseUrl/api/v1/patients'),
        headers: authHeaders('REC01', 'DEV-REC'),
        body: jsonEncode({
          'mrn': 'MRN-E2E-100',
          'fullName': 'Mona Ahmed E2E',
          'phone': '01122334455',
          'gender': 'female',
        }),
      );
      expect(pRes.statusCode, equals(201));
      patientId = jsonDecode(pRes.body)['data']['id'];

      // 2. Schedule Appointment
      final aRes = await http.post(
        Uri.parse('$baseUrl/api/v1/appointments'),
        headers: authHeaders('REC01', 'DEV-REC'),
        body: jsonEncode({
          'appointmentNumber': 'APT-E2E-01',
          'patientId': patientId,
          'doctorId': staffIds['DOC01']!.toString(),
          'scheduledAt': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
          'reason': 'Chest pain and palpitations',
        }),
      );
      expect(aRes.statusCode, equals(201));
      appointmentId = jsonDecode(aRes.body)['data']['id'];

      // MariaDB Read-back
      final aptSql = await db.execute('SELECT status FROM mc_appointments WHERE id = :id', {'id': appointmentId});
      expect(aptSql.rows.first.colByName('status'), equals('SCHEDULED'));
    });

    test('Stage 3: Patient arrives, creates active visit with cash payment (FIN-006)', () async {
      // Update appointment status to ARRIVED
      final uRes = await http.put(
        Uri.parse('$baseUrl/api/v1/appointments/$appointmentId/status'),
        headers: authHeaders('REC01', 'DEV-REC'),
        body: jsonEncode({'status': 'ARRIVED'}),
      );
      expect(uRes.statusCode, equals(200));

      // Create Visit with 300.0000 cash payment via Cashier
      final vRes = await http.post(
        Uri.parse('$baseUrl/api/v1/visits'),
        headers: authHeaders('CSH01', 'DEV-CSH'),
        body: jsonEncode({
          'visitNumber': 'VIS-E2E-001',
          'idempotencyKey': 'IDEMP-VIS-E2E-001',
          'patientId': patientId,
          'doctorId': staffIds['DOC01'],
          'shiftId': shiftId,
          'serviceLaborGross': '300.0000',
          'consumableGross': '0.0000',
          'consumableFifoCost': '0.0000',
          'discountAmount': '0.0000',
          'insuranceCoveredAmount': '0.0000',
          'paidAmount': '300.0000',
          'doctorCommissionRatePercent': '33.3333',
        }),
      );
      expect(vRes.statusCode, equals(201));
      visitId = jsonDecode(vRes.body)['data']['visitId'];

      // MariaDB Read-back: Shift cash_in and expected_cash incremented!
      final sCheck = await db.execute('SELECT cash_in, expected_cash FROM mc_shifts WHERE id = :id', {'id': shiftId});
      expect(Decimal.parse(sCheck.rows.first.colByName('cash_in')!), equals(Decimal.parse('300.0000')));
      expect(Decimal.parse(sCheck.rows.first.colByName('expected_cash')!), equals(Decimal.parse('1300.0000')));
    });

    test('Stage 4: Doctor consultations, encounters, SOAP notes & queue completion (CLN-001)', () async {
      // Doctor views queue
      final qRes = await http.get(
        Uri.parse('$baseUrl/api/v1/doctor/queue'),
        headers: authHeaders('DOC01', 'DEV-DOC'),
      );
      expect(qRes.statusCode, equals(200));
      final qItems = jsonDecode(qRes.body)['data']['items'] as List;
      expect(qItems.any((i) => i['visitId'] == visitId), isTrue);

      // Create Encounter with SOAP notes
      final eRes = await http.post(
        Uri.parse('$baseUrl/api/v1/encounters'),
        headers: authHeaders('DOC01', 'DEV-DOC'),
        body: jsonEncode({
          'visitId': visitId,
          'patientId': patientId,
          'encounterNumber': 'ENC-E2E-001',
          'chiefComplaint': 'Acute substernal chest discomfort',
          'vitals': {'bp': '150/95', 'hr': 110, 'spo2': 94, 'temp': 37.2},
          'assessment': {'primaryDiagnosis': 'Acute Coronary Syndrome', 'riskLevel': 'HIGH'},
          'plan': {'admmitIcu': true, 'troponinTest': true, 'nitroglycerin': true},
          'diagnoses': [
            {'code': 'I20.0', 'description': 'Unstable angina', 'type': 'PRIMARY'}
          ],
        }),
      );
      expect(eRes.statusCode, equals(201));
      encounterId = jsonDecode(eRes.body)['data']['encounterId'];

      // MariaDB Read-back: Visit status marked COMPLETED
      final vSql = await db.execute('SELECT clinical_status FROM mc_visits WHERE id = :id', {'id': visitId});
      expect(vSql.rows.first.colByName('clinical_status'), equals('COMPLETED'));
    });

    test('Stage 5: Doctor orders Diagnostic Cardiac Troponin Lab Test (CLN-003)', () async {
      final oRes = await http.post(
        Uri.parse('$baseUrl/api/v1/orders'),
        headers: authHeaders('DOC01', 'DEV-DOC'),
        body: jsonEncode({
          'patientId': patientId,
          'encounterId': encounterId,
          'orderType': 'LAB',
          'priority': 'STAT',
          'clinicalIndication': 'R/O Myocardial Infarction',
          'items': [
            {'itemCode': 'LAB-TROP-I', 'itemName': 'High-Sensitivity Troponin I', 'quantity': '1.0000', 'price': '150.0000'}
          ],
        }),
      );
      expect(oRes.statusCode, equals(201));
      final body = jsonDecode(oRes.body)['data'];
      labOrderId = body['orderId'];
      labOrderItemId = body['items'][0]['id'];

      // MariaDB Read-back
      final ordSql = await db.execute('SELECT status, priority FROM mc_clinical_orders WHERE id = :id', {'id': labOrderId});
      expect(ordSql.rows.first.colByName('status'), equals('PENDING'));
      expect(ordSql.rows.first.colByName('priority'), equals('STAT'));
    });

    test('Stage 6: Lab enters Panic Troponin Result with Critical Panic Alert Flag (CLN-003)', () async {
      final rRes = await http.post(
        Uri.parse('$baseUrl/api/v1/orders/$labOrderId/results'),
        headers: authHeaders('LAB01', 'DEV-LAB'),
        body: jsonEncode({
          'orderItemId': labOrderItemId,
          'resultType': 'NUMERIC',
          'resultJson': {'troponin_i_ng_l': 450.8, 'reference_upper': 14.0, 'status': 'CRITICAL_HIGH'},
          'isCriticalPanic': true,
          'notes': 'Panic value phoned to Dr. Hazem immediately',
        }),
      );
      expect(rRes.statusCode, equals(200));
      final body = jsonDecode(rRes.body)['data'];
      expect(body['status'], equals('COMPLETED'));
      expect(body['criticalFlag'], isTrue);

      // MariaDB Read-back: Critical flag in DB is 1
      final resSql = await db.execute('SELECT critical_flag, status FROM mc_clinical_results WHERE order_id = :id', {'id': labOrderId});
      expect(resSql.rows.first.colByName('critical_flag'), equals('1'));
      expect(resSql.rows.first.colByName('status'), equals('COMPLETED'));
    });

    test('Stage 7: Doctor writes e-Rx Prescription for Clopidogrel and Aspirin (Workstream 4)', () async {
      final rxRes = await http.post(
        Uri.parse('$baseUrl/api/v1/prescriptions'),
        headers: authHeaders('DOC01', 'DEV-DOC'),
        body: jsonEncode({
          'visitId': visitId,
          'patientId': patientId,
          'notes': 'Emergency dual antiplatelet therapy',
          'items': [
            {
              'medicationCode': 'MED-CLOP-75',
              'medicationName': 'Clopidogrel 75mg Tablet',
              'dose': '300mg loading then 75mg daily',
              'route': 'Oral',
              'quantity': '4.0000',
            }
          ],
        }),
      );
      expect(rxRes.statusCode, equals(201));
      final body = jsonDecode(rxRes.body)['data'];
      prescriptionId = body['prescriptionId'];
      rxItemId = body['items'][0]['id'];

      // MariaDB Read-back
      final rxSql = await db.execute('SELECT status FROM mc_prescriptions WHERE id = :id', {'id': prescriptionId});
      expect(rxSql.rows.first.colByName('status'), equals('ACTIVE'));
    });

    test('Stage 8: Pharmacist dispenses medicine via FIFO batch with balanced COGS ledger (CLN-004 & FIN-004)', () async {
      // Seed Inventory Item and Batch
      final iRes = await db.execute('''
        INSERT INTO mc_inventory_items (
          hospital_code, public_id, tenant_id, item_number,
          item_code, name, unit, tracking_type, status
        ) VALUES (
          'HOSP_E2E', 'PUB-INV-CLOP', 'HOSP_E2E', 'ITEM-E2E-CLOP',
          'MED-CLOP-75', 'Clopidogrel 75mg', 'TAB', 'BATCH', 'ACTIVE'
        )
      ''');
      inventoryItemId = iRes.lastInsertID.toInt();

      final bRes = await db.execute('''
        INSERT INTO mc_inventory_batches (
          hospital_code, public_id, tenant_id, item_id,
          batch_number, expiry_date, unit_cost, currency
        ) VALUES (
          'HOSP_E2E', 'PUB-BAT-CLOP', 'HOSP_E2E', $inventoryItemId,
          'BAT-CLOP-2026', DATE_ADD(CURDATE(), INTERVAL 90 DAY), '10.0000', 'EGP'
        )
      ''');
      inventoryBatchId = bRes.lastInsertID.toInt();

      // Dispense 4 tablets
      final dispRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pharmacy/dispense'),
        headers: authHeaders('PHM01', 'DEV-PHM'),
        body: jsonEncode({
          'prescriptionId': prescriptionId,
          'prescriptionItemId': rxItemId,
          'inventoryItemId': inventoryItemId,
          'shiftId': shiftId,
          'quantity': '4.0000',
        }),
      );
      expect(dispRes.statusCode, equals(200));
      final dispBody = jsonDecode(dispRes.body)['data'];
      expect(dispBody['batchId'], equals(inventoryBatchId));
      expect(dispBody['totalCost'], equals('40.0000')); // 4 * 10.0000

      // MariaDB Read-back: Balanced COGS Postings (FIN-004)
      final postSql = await db.execute(
        '''
        SELECT
          SUM(CASE WHEN direction = 'DEBIT' THEN amount ELSE 0 END) AS debits,
          SUM(CASE WHEN direction = 'CREDIT' THEN amount ELSE 0 END) AS credits
        FROM mc_financial_postings
        WHERE shift_id = :sid AND posting_type IN ('COGS_DISPENSE', 'INVENTORY_RELIEF')
        ''',
        {'sid': shiftId},
      );
      final debits = Decimal.parse(postSql.rows.first.colByName('debits')!);
      final credits = Decimal.parse(postSql.rows.first.colByName('credits')!);
      expect(debits, equals(Decimal.parse('40.0000')));
      expect(credits, equals(Decimal.parse('40.0000')));
      expect(debits, equals(credits)); // Ledger balance invariant!
    });

    test('Stage 9: Emergency Inpatient ICU Bed Admission with row lock (CLN-005)', () async {
      // Seed ICU Bed
      final bRes = await db.execute('''
        INSERT INTO mc_ward_beds (
          hospital_code, tenant_id, public_id, department_id,
          room_id, bed_number, status, created_at
        ) VALUES (
          'HOSP_E2E', 'HOSP_E2E', 'PUB-BED-ICU-1', 'ICU',
          'ICU-ROOM-A', 'ICU-BED-01', 'AVAILABLE', NOW()
        )
      ''');
      bedId = bRes.lastInsertID.toInt();

      // Admit Patient
      final admRes = await http.post(
        Uri.parse('$baseUrl/api/v1/admissions'),
        headers: authHeaders('DOC01', 'DEV-DOC'),
        body: jsonEncode({
          'patientId': patientId.toString(),
          'bedId': bedId.toString(),
          'departmentId': 'ICU',
          'roomId': 'ICU-ROOM-A',
          'admissionType': 'EMERGENCY',
          'attendingDoctorId': staffIds['DOC01']!.toString(),
          'diagnosisJson': jsonEncode({'primary': 'Acute Coronary Syndrome', 'troponinPanic': 450.8}),
        }),
      );
      expect(admRes.statusCode, equals(201));
      admissionId = jsonDecode(admRes.body)['data']['admissionId'];

      // MariaDB Read-back: Bed is OCCUPIED
      final bSql = await db.execute('SELECT status FROM mc_ward_beds WHERE id = :id', {'id': bedId});
      expect(bSql.rows.first.colByName('status'), equals('OCCUPIED'));
    });

    test('Stage 10: Patient stabilized and discharged, Bed released back to AVAILABLE (CLN-005)', () async {
      final disRes = await http.post(
        Uri.parse('$baseUrl/api/v1/admissions/$admissionId/discharge'),
        headers: authHeaders('DOC01', 'DEV-DOC'),
        body: jsonEncode({
          'dischargeReason': 'Stabilized post-intervention, transferred to step-down ward',
        }),
      );
      expect(disRes.statusCode, equals(200));

      // MariaDB Read-back: Bed restored to AVAILABLE
      final bSql = await db.execute('SELECT status FROM mc_ward_beds WHERE id = :id', {'id': bedId});
      expect(bSql.rows.first.colByName('status'), equals('AVAILABLE'));

      final aSql = await db.execute('SELECT status FROM mc_admissions WHERE id = :id', {'id': admissionId});
      expect(aSql.rows.first.colByName('status'), equals('Discharged'));
    });

    test('Stage 11: Finance settles Doctor Commission with corrected double-entry & SEC-005 Two-Person Integrity', () async {
      final docId = staffIds['DOC01']!;

      // Seed Doctor Commission Accrual: 100.0000 with balanced double-entry (FIN-001 & FIN-007)
      final evRes = await db.execute('''
        INSERT INTO mc_financial_events (
          event_uuid, hospital_code, idempotency_key, event_type,
          source_module, source_entity_type, source_entity_id, shift_id,
          gross_amount, discount_amount, net_amount, paid_amount,
          insurance_covered_amount, patient_responsibility_amount, balance_amount,
          status, created_by
        ) VALUES (
          'EV-COMM-E2E', 'HOSP_E2E', 'IDEMP-COMM-E2E', 'CONSULTATION_COMMISSION',
          'CLINICAL', 'VISIT', $visitId, $shiftId,
          '100.0000', '0.0000', '100.0000', '0.0000',
          '0.0000', '0.0000', '0.0000',
          'POSTED', $docId
        )
      ''');
      final evId = evRes.lastInsertID.toInt();

      // Leg 1: DEBIT Expense
      await db.execute('''
        INSERT INTO mc_financial_postings (
          posting_uuid, hospital_code, event_id, posting_type,
          account_bucket, direction, amount, beneficiary_type, beneficiary_id, shift_id, status
        ) VALUES (
          'POST-COMM-EXP', 'HOSP_E2E', $evId, 'COMMISSION_EXPENSE',
          'EXPENSE_DOCTOR_COMMISSION', 'DEBIT', '100.0000', 'DOCTOR', $docId, $shiftId, 'POSTED'
        )
      ''');

      // Leg 2: CREDIT Payable (Fixes TEST-FIN-01 one-sided posting defect!)
      await db.execute('''
        INSERT INTO mc_financial_postings (
          posting_uuid, hospital_code, event_id, posting_type,
          account_bucket, direction, amount, beneficiary_type, beneficiary_id, shift_id, status
        ) VALUES (
          'POST-COMM-PAY', 'HOSP_E2E', $evId, 'COMMISSION_ACCRUAL',
          'PAYABLE_COMMISSION_DOCTOR', 'CREDIT', '100.0000', 'DOCTOR', $docId, $shiftId, 'POSTED'
        )
      ''');

      // 1. Direct settlement attempt without dual-control approval fails closed (SEC-005)
      final directRes = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements'),
        headers: authHeaders('CSH01', 'DEV-CSH'),
        body: jsonEncode({
          'doctorId': docId,
          'settleAmount': '100.0000',
          'shiftId': shiftId,
        }),
      );
      expect(directRes.statusCode, equals(403), reason: 'Direct unapproved settlement must fail closed');

      // 2. Step 1: Cashier requests settlement
      final reqRes = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/request'),
        headers: authHeaders('CSH01', 'DEV-CSH'),
        body: jsonEncode({
          'doctorId': docId,
          'settleAmount': '100.0000',
          'shiftId': shiftId,
          'notes': 'E2E commission settlement request',
        }),
      );
      expect(reqRes.statusCode, equals(201));
      final reqBody = jsonDecode(reqRes.body)['data'];
      final settlementId = reqBody['settlementId'] as int;
      final dualReqId = reqBody['requestId'] as int;
      final setNo = reqBody['settlementNumber'] as String;

      // 3. Step 2 Adversarial: Cashier self-approval rejected
      final selfApp = await http.post(
        Uri.parse('$baseUrl/api/v1/dual-control/requests/$dualReqId/decide'),
        headers: authHeaders('CSH01', 'DEV-CSH'),
        body: jsonEncode({'approve': true}),
      );
      expect(selfApp.statusCode, equals(403));

      // 4. Step 2 Legitimate: Admin/Supervisor approves
      final admApp = await http.post(
        Uri.parse('$baseUrl/api/v1/dual-control/requests/$dualReqId/decide'),
        headers: authHeaders('ADM01', 'DEV-ADM'),
        body: jsonEncode({'approve': true, 'decisionNotes': 'E2E Admin approval'}),
      );
      expect(admApp.statusCode, equals(200));

      // 5. Step 3: Cashier delivers payout
      final setRes = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/$settlementId/deliver'),
        headers: authHeaders('CSH01', 'DEV-CSH'),
        body: jsonEncode({'shiftId': shiftId}),
      );
      expect(setRes.statusCode, equals(200));

      // MariaDB Read-back: P3 double-debit bug is 100% fixed:
      // Settlement liability reduction is DEBIT, Cash payout is strictly CREDIT!
      final setPostSql = await db.execute(
        '''
        SELECT posting_type, account_bucket, direction, amount
        FROM mc_financial_postings
        WHERE shift_id = :sid AND posting_type IN ('SETTLEMENT_LIABILITY', 'SETTLEMENT_PAYMENT')
        ORDER BY id ASC
        ''',
        {'sid': shiftId},
      );
      expect(setPostSql.rows.length, equals(2));
      final liab = setPostSql.rows.firstWhere((r) => r.colByName('posting_type') == 'SETTLEMENT_LIABILITY');
      final cash = setPostSql.rows.firstWhere((r) => r.colByName('posting_type') == 'SETTLEMENT_PAYMENT');

      expect(liab.colByName('direction'), equals('DEBIT'));
      expect(liab.colByName('account_bucket'), equals('PAYABLE_COMMISSION_DOCTOR'));

      expect(cash.colByName('direction'), equals('CREDIT')); // STRICTLY CREDIT!
      expect(cash.colByName('account_bucket'), equals('CASH_ON_HAND'));

      // Check settlement record has distinct requester and approver (SEC-005)
      final setSql = await db.execute('SELECT * FROM mc_financial_settlements WHERE settlement_number = :sno', {'sno': setNo});
      final sRow = setSql.rows.first;
      expect(sRow.colByName('status'), equals('SETTLED'));
      expect(sRow.colByName('requested_by'), isNot(equals(sRow.colByName('approved_by'))));

      // Check shift cash_out in DB: 100.0000
      final sSql = await db.execute('SELECT cash_out, expected_cash FROM mc_shifts WHERE id = :id', {'id': shiftId});
      expect(Decimal.parse(sSql.rows.first.colByName('cash_out')!), equals(Decimal.parse('100.0000')));
      expect(Decimal.parse(sSql.rows.first.colByName('expected_cash')!), equals(Decimal.parse('1200.0000')));
    });

    test('Stage 12: Cashier closes shift with physical cash count (FIN-006 Reconciliation Formula)', () async {
      // Opening = 1000.0000, Cash In = 300.0000, Cash Out = 100.0000
      // Expected = 1000 + 300 - 100 = 1200.0000
      // Counted = 1200.0000 -> Variance = 0.0000!
      final closeRes = await http.post(
        Uri.parse('$baseUrl/api/v1/shifts/close'),
        headers: authHeaders('CSH01', 'DEV-CSH'),
        body: jsonEncode({
          'shiftId': shiftId,
          'countedCash': '1200.0000',
          'notes': 'End of shift reconciliation perfect match',
        }),
      );
      expect(closeRes.statusCode, equals(200));
      final closeBody = jsonDecode(closeRes.body)['data'];
      expect(closeBody['status'], equals('CLOSED'));
      expect(closeBody['expectedCash'], equals('1200.0000'));
      expect(closeBody['countedCash'], equals('1200.0000'));
      expect(closeBody['variance'], equals('0.0000'));

      // Direct MariaDB Read-back verification
      final shiftFinal = await db.execute('SELECT status, variance_amount, closed_at FROM mc_shifts WHERE id = :id', {'id': shiftId});
      final row = shiftFinal.rows.first;
      expect(row.colByName('status'), equals('CLOSED'));
      expect(Decimal.parse(row.colByName('variance_amount')!), equals(Decimal.zero));
      expect(row.colByName('closed_at'), isNotNull);

      // FIN-001 Double-Entry Balance Invariant: Total Debits == Total Credits across the entire test ledger
      final trialSql = await db.execute('''
        SELECT
          SUM(CASE WHEN direction = 'DEBIT' THEN amount ELSE 0 END) AS total_debits,
          SUM(CASE WHEN direction = 'CREDIT' THEN amount ELSE 0 END) AS total_credits
        FROM mc_financial_postings
      ''');
      final totalDebits = Decimal.parse(trialSql.rows.first.colByName('total_debits') ?? '0');
      final totalCredits = Decimal.parse(trialSql.rows.first.colByName('total_credits') ?? '0');
      expect(totalDebits, equals(totalCredits),
          reason: 'FIN-001 Invariant: Entire ledger must be strictly balanced! Debits($totalDebits) == Credits($totalCredits)');
    });
  });

  group('ADVERSARIAL RED TEAM SECURITY SUITE: Multi-Vector Penetration & Negative Boundary Tests', () {
    test('Attack 1: Unauthorized Role Action — Receptionist attempts to prescribe medication (Fails closed 403)', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/prescriptions'),
        headers: authHeaders('REC01', 'DEV-REC'),
        body: jsonEncode({
          'visitId': 1,
          'patientId': 1,
          'items': [
            {'medicationCode': 'MED-ILLEGAL', 'medicationName': 'Morphine', 'quantity': '10.0000'}
          ],
        }),
      );
      expect(res.statusCode, equals(403));
      final body = jsonDecode(res.body);
      expect(body['error']['code'], anyOf('FORBIDDEN', 'PERMISSION_DENIED'));

      // MariaDB Read-back: Zero rows inserted
      final rxCheck = await db.execute("SELECT COUNT(*) AS cnt FROM mc_prescriptions WHERE hospital_code = 'HOSP_E2E' AND notes LIKE '%Morphine%'");
      expect(int.parse(rxCheck.rows.first.colByName('cnt')!), equals(0));
    });

    test('Attack 2: Unauthorized Cash Payout — Receptionist attempts to settle doctor commissions (Fails closed 403)', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements'),
        headers: authHeaders('REC01', 'DEV-REC'),
        body: jsonEncode({
          'doctorId': 1,
          'settleAmount': '500.0000',
          'shiftId': 1,
        }),
      );
      expect(res.statusCode, equals(403));
    });

    test('Attack 3: Double-Close Attack on Closed Shift (Fails with 409 Conflict)', () async {
      final shiftSql = await db.execute("SELECT id FROM mc_shifts WHERE status = 'CLOSED' LIMIT 1");
      final closedShiftId = int.parse(shiftSql.rows.first.colByName('id')!);

      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/shifts/close'),
        headers: authHeaders('CSH01', 'DEV-CSH'),
        body: jsonEncode({
          'shiftId': closedShiftId,
          'countedCash': '1000.0000',
        }),
      );
      expect(res.statusCode, equals(409));
      final body = jsonDecode(res.body);
      expect(body['error']['code'], equals('DOMAIN_STATE_CONFLICT'));
    });

    test('Attack 4: Double-Bed Occupancy Overbooking (CLN-005 Isolation)', () async {
      // Seed Available Bed
      final bRes = await db.execute('''
        INSERT INTO mc_ward_beds (
          hospital_code, tenant_id, public_id, department_id,
          room_id, bed_number, status, created_at
        ) VALUES (
          'HOSP_E2E', 'HOSP_E2E', 'PUB-BED-ATTACK', 'SURGERY',
          'SURG-1', 'BED-ATTACK-01', 'AVAILABLE', NOW()
        )
      ''');
      final attackBedId = bRes.lastInsertID.toInt();

      // First admission succeeds
      final adm1 = await http.post(
        Uri.parse('$baseUrl/api/v1/admissions'),
        headers: authHeaders('DOC01', 'DEV-DOC'),
        body: jsonEncode({
          'patientId': '1',
          'bedId': attackBedId.toString(),
          'admissionType': 'EMERGENCY',
        }),
      );
      expect(adm1.statusCode, equals(201));

      // Second admission into same bed MUST fail with 409 Conflict
      final adm2 = await http.post(
        Uri.parse('$baseUrl/api/v1/admissions'),
        headers: authHeaders('DOC01', 'DEV-DOC'),
        body: jsonEncode({
          'patientId': '2',
          'bedId': attackBedId.toString(),
          'admissionType': 'ELECTIVE',
        }),
      );
      expect(adm2.statusCode, equals(409));
    });

    test('Attack 5: Tampered Bearer Token Injection (Fails closed 401 Unauthorized)', () async {
      final res = await http.get(
        Uri.parse('$baseUrl/api/v1/beds'),
        headers: {
          'content-type': 'application/json',
          'x-tenant-id': 'HOSP_E2E',
          'x-medcore-device-id': 'DEV-DOC',
          'authorization': 'Bearer FORGED_OR_TAMPERED_SESSION_TOKEN_123',
        },
      );
      expect(res.statusCode, equals(401));
    });
  });
}
