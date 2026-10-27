import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;
import 'package:medcore_local_service/medcore_local_service.dart';
import 'package:test/test.dart';
import 'support/test_db_config.dart';

void main() {
  const dbName = 'medcore_redteam_settlement_test';
  late DbClient db;
  late LocalMedCoreServer server;
  late int serverPort;
  late String baseUrl;
  late Directory securityRoot;

  final tokens = <String, String>{};
  final staffIds = <String, int>{};

  Map<String, String> authHeaders(String userKey, String deviceId) {
    final parts = userKey.split(':');
    final hosp = parts[0];
    return {
      'authorization': 'Bearer ${tokens[userKey]}',
      'x-tenant-id': hosp,
      'x-medcore-device-id': deviceId,
      'content-type': 'application/json',
    };
  }

  late TenantGovernanceRepository govRepo;
  late StaffIdentityRepository staffRepo;

  Future<void> enrollAndLogin({
    required String hosp,
    required String code,
    required String name,
    required String email,
    required MedCoreRole role,
    required String devId,
    required Set<String> customPerms,
    required OperationalFlags flags,
  }) async {
    await govRepo.enrollOrUpdateDevice(
      hospitalCode: hosp,
      deviceId: devId,
      deviceName: '$devId Terminal',
      platform: 'WINDOWS',
      hwFingerprintSha256: PasswordHasher.sha256Hex(devId),
      devicePublicKeyEd25519: 'PUBKEY-$devId',
      isTrustedSecureRuntime: true,
      status: 'ACTIVE',
    );

    final s = await staffRepo.createStaff(
      hospitalCode: hosp,
      staffCode: code,
      fullName: name,
      email: email,
      role: role,
      passwordHash: PasswordHasher.hashPassword('Pass123!'),
      permissionsMode: 'custom',
      customPermissions: customPerms,
      operationalFlags: flags,
    );
    staffIds['$hosp:$code'] = s.id;

    final loginRes = await http.post(
      Uri.parse('$baseUrl/api/v1/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'hospitalCode': hosp,
        'identifier': email,
        'password': 'Pass123!',
        'deviceId': devId,
      }),
    );
    expect(loginRes.statusCode, equals(200), reason: 'Login failed: ${loginRes.body}');
    final token = jsonDecode(loginRes.body)['data']['token'] as String;
    tokens['$hosp:$code'] = token;
  }

  setUpAll(() async {
    final rootDb = DbClient(testDbConfig(databaseName: 'mysql'));
    await rootDb.execute('DROP DATABASE IF EXISTS $dbName');
    await rootDb.execute('CREATE DATABASE $dbName CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci');
    await rootDb.close();

    db = DbClient(testDbConfig(databaseName: dbName));

    final runner = MigrationRunner(db: db, migrationsDir: 'sql/migrations');
    await runner.runMigrations();

    govRepo = TenantGovernanceRepository(db);
    staffRepo = StaffIdentityRepository(db);

    securityRoot = Directory.systemTemp.createTempSync('medcore-redteam-settlement-');
    server = LocalMedCoreServer(db, securityRootDirectory: securityRoot.path);
    serverPort = await server.start(address: '127.0.0.1', port: 0);
    baseUrl = 'http://127.0.0.1:$serverPort';

    // Seed Tenants
    await govRepo.upsertTenant(hospitalCode: 'HOSP_RED_A', name: 'Red Team Hospital Alpha');
    await govRepo.upsertTenant(hospitalCode: 'HOSP_RED_B', name: 'Red Team Hospital Beta');

    // Seed Staff in HOSP_RED_A
    await enrollAndLogin(
      hosp: 'HOSP_RED_A',
      code: 'CSH01',
      name: 'Cashier One',
      email: 'csh01@medcore.red',
      role: MedCoreRole.Cashier,
      devId: 'DEV-RED-CSH01',
      customPerms: {'shifts', 'finance_Settlements'},
      flags: const OperationalFlags(canEdit: true, canDelete: false, canCollectMoney: true, canMakeRefunds: true, refundPolicy: RefundPolicy.approval),
    );

    await enrollAndLogin(
      hosp: 'HOSP_RED_A',
      code: 'SUP01',
      name: 'Supervisor One',
      email: 'sup01@medcore.red',
      role: MedCoreRole.HospitalAdmin,
      devId: 'DEV-RED-SUP01',
      customPerms: {'settings_Permissions'},
      flags: const OperationalFlags(canEdit: true, canDelete: false, canCollectMoney: true, canMakeRefunds: true, refundPolicy: RefundPolicy.direct),
    );

    await enrollAndLogin(
      hosp: 'HOSP_RED_A',
      code: 'REC01',
      name: 'Receptionist One',
      email: 'rec01@medcore.red',
      role: MedCoreRole.Receptionist,
      devId: 'DEV-RED-REC01',
      customPerms: {'patients', 'appointments'},
      flags: const OperationalFlags(canEdit: true, canDelete: false, canCollectMoney: false, canMakeRefunds: false, refundPolicy: RefundPolicy.none),
    );

    await enrollAndLogin(
      hosp: 'HOSP_RED_A',
      code: 'DOC01',
      name: 'Dr. Red Surgeon',
      email: 'doc01@medcore.red',
      role: MedCoreRole.Doctor,
      devId: 'DEV-RED-DOC01',
      customPerms: {'clinical'},
      flags: const OperationalFlags(canEdit: true, canDelete: false, canCollectMoney: false, canMakeRefunds: false, refundPolicy: RefundPolicy.none),
    );

    // Seed Staff in HOSP_RED_B (Cross-Tenant isolation tests)
    await enrollAndLogin(
      hosp: 'HOSP_RED_B',
      code: 'CSH_B',
      name: 'Cashier Beta',
      email: 'csh_b@medcore.red',
      role: MedCoreRole.Cashier,
      devId: 'DEV-RED-CSH-B',
      customPerms: {'shifts', 'finance_Settlements'},
      flags: const OperationalFlags(canEdit: true, canDelete: false, canCollectMoney: true, canMakeRefunds: true, refundPolicy: RefundPolicy.approval),
    );

    await enrollAndLogin(
      hosp: 'HOSP_RED_B',
      code: 'SUP_B',
      name: 'Supervisor Beta',
      email: 'sup_b@medcore.red',
      role: MedCoreRole.HospitalAdmin,
      devId: 'DEV-RED-SUP-B',
      customPerms: {'settings_Permissions'},
      flags: const OperationalFlags(canEdit: true, canDelete: false, canCollectMoney: true, canMakeRefunds: true, refundPolicy: RefundPolicy.direct),
    );
  });

  tearDownAll(() async {
    await server.stop();
    await db.close();
    if (securityRoot.existsSync()) {
      securityRoot.deleteSync(recursive: true);
    }
  });

  group('DEDICATED SETTLEMENT RED TEAM ADVERSARIAL SUITE (30 ATTACK VECTORS)', () {
    late int shiftId;
    late int docId;

    setUp(() async {
      docId = staffIds['HOSP_RED_A:DOC01']!;

      final rand = Random().nextInt(9999999);
      final shiftCode = 'SHF-RED-${DateTime.now().microsecondsSinceEpoch}-$rand';
      final sRes = await db.execute('''
        INSERT INTO mc_shifts (
          hospital_code, shift_code, cashier_staff_id,
          opening_balance, cash_in, cash_out, expected_cash,
          status, opened_at
        ) VALUES (
          'HOSP_RED_A', '$shiftCode', ${staffIds['HOSP_RED_A:CSH01']},
          '1000.0000', '0.0000', '0.0000', '1000.0000',
          'OPEN', NOW()
        )
      ''');
      shiftId = sRes.lastInsertID.toInt();

      // Seed balanced accrual: 200.0000
      final evUuid = 'EV-RED-${DateTime.now().microsecondsSinceEpoch}-$rand';
      final idemp = 'IDEMP-RED-$rand';
      final evRes = await db.execute('''
        INSERT INTO mc_financial_events (
          event_uuid, hospital_code, idempotency_key, event_type,
          source_module, source_entity_type, source_entity_id, shift_id,
          gross_amount, discount_amount, net_amount, paid_amount,
          insurance_covered_amount, patient_responsibility_amount, balance_amount,
          status, created_by
        ) VALUES (
          '$evUuid', 'HOSP_RED_A', '$idemp', 'CONSULTATION_COMMISSION',
          'CLINICAL', 'VISIT', 999, $shiftId,
          '200.0000', '0.0000', '200.0000', '0.0000',
          '0.0000', '0.0000', '0.0000',
          'POSTED', $docId
        )
      ''');
      final evId = evRes.lastInsertID.toInt();

      final pExpUuid = 'POST-RED-EXP-$rand';
      await db.execute('''
        INSERT INTO mc_financial_postings (
          posting_uuid, hospital_code, event_id, posting_type,
          account_bucket, direction, amount, beneficiary_type, beneficiary_id, shift_id, status
        ) VALUES (
          '$pExpUuid', 'HOSP_RED_A', $evId, 'COMMISSION_EXPENSE',
          'EXPENSE_DOCTOR_COMMISSION', 'DEBIT', '200.0000', 'DOCTOR', $docId, $shiftId, 'POSTED'
        )
      ''');

      final pPayUuid = 'POST-RED-PAY-$rand';
      await db.execute('''
        INSERT INTO mc_financial_postings (
          posting_uuid, hospital_code, event_id, posting_type,
          account_bucket, direction, amount, beneficiary_type, beneficiary_id, shift_id, status
        ) VALUES (
          '$pPayUuid', 'HOSP_RED_A', $evId, 'COMMISSION_ACCRUAL',
          'PAYABLE_COMMISSION_DOCTOR', 'CREDIT', '200.0000', 'DOCTOR', $docId, $shiftId, 'POSTED'
        )
      ''');
    });

    test('Vector 1 & 24: Direct Single-Step Settlement Bypass Attempt Fails Closed (SEC-005)', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements'),
        headers: authHeaders('HOSP_RED_A:CSH01', 'DEV-RED-CSH01'),
        body: jsonEncode({
          'doctorId': docId,
          'settleAmount': '100.0000',
          'shiftId': shiftId,
        }),
      );
      expect(res.statusCode, equals(403), reason: 'Direct settlement without dual-control approval must fail closed');
      expect(jsonDecode(res.body)['error']['code'], equals('DUAL_CONTROL_APPROVAL_REQUIRED'));
    });

    test('Vector 1: Cashier Self-Approval Prevention (SEC-005 Two-Person Integrity)', () async {
      // 1. Request settlement
      final reqRes = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/request'),
        headers: authHeaders('HOSP_RED_A:CSH01', 'DEV-RED-CSH01'),
        body: jsonEncode({'doctorId': docId, 'settleAmount': '100.0000', 'shiftId': shiftId}),
      );
      expect(reqRes.statusCode, equals(201));
      final dualReqId = jsonDecode(reqRes.body)['data']['requestId'];

      // 2. Cashier attempts self-approval
      final appRes = await http.post(
        Uri.parse('$baseUrl/api/v1/dual-control/requests/$dualReqId/decide'),
        headers: authHeaders('HOSP_RED_A:CSH01', 'DEV-RED-CSH01'),
        body: jsonEncode({'approve': true}),
      );
      expect(appRes.statusCode, equals(403));
      expect(
        ['DUAL_CONTROL_SELF_APPROVAL_FORBIDDEN', 'PERMISSION_DENIED'],
        contains(jsonDecode(appRes.body)['error']['code']),
      );
    });

    test('Vector 2: Forged Approver ID Injection Ignored by Server-Side Derivation', () async {
      final reqRes = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/request'),
        headers: authHeaders('HOSP_RED_A:CSH01', 'DEV-RED-CSH01'),
        body: jsonEncode({'doctorId': docId, 'settleAmount': '50.0000', 'shiftId': shiftId}),
      );
      final dualReqId = jsonDecode(reqRes.body)['data']['requestId'];

      // Supervisor approves with forged approverStaffId in body
      final appRes = await http.post(
        Uri.parse('$baseUrl/api/v1/dual-control/requests/$dualReqId/decide'),
        headers: authHeaders('HOSP_RED_A:SUP01', 'DEV-RED-SUP01'),
        body: jsonEncode({'approve': true, 'approverStaffId': 99999}),
      );
      expect(appRes.statusCode, equals(200));

      // MariaDB check: server derived approver from auth session, not body
      final checkSql = await db.execute('SELECT approver_staff_id FROM mc_dual_control_request WHERE id = :id', {'id': dualReqId});
      expect(int.parse(checkSql.rows.first.colByName('approver_staff_id')!), equals(staffIds['HOSP_RED_A:SUP01']));
    });

    test('Vector 3 & 23: Unauthorized Role Attempting Approval or Settlement Fails Closed', () async {
      final reqRes = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/request'),
        headers: authHeaders('HOSP_RED_A:CSH01', 'DEV-RED-CSH01'),
        body: jsonEncode({'doctorId': docId, 'settleAmount': '50.0000', 'shiftId': shiftId}),
      );
      final dualReqId = jsonDecode(reqRes.body)['data']['requestId'];

      // Receptionist attempts approval
      final appRes = await http.post(
        Uri.parse('$baseUrl/api/v1/dual-control/requests/$dualReqId/decide'),
        headers: authHeaders('HOSP_RED_A:REC01', 'DEV-RED-REC01'),
        body: jsonEncode({'approve': true}),
      );
      expect(appRes.statusCode, equals(403));

      // Receptionist attempts settlement request
      final setRes = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/request'),
        headers: authHeaders('HOSP_RED_A:REC01', 'DEV-RED-REC01'),
        body: jsonEncode({'doctorId': docId, 'settleAmount': '50.0000', 'shiftId': shiftId}),
      );
      expect(setRes.statusCode, equals(403));
    });

    test('Vector 6 & 29: Settlement Request or Delivery against CLOSED Shift Fails Closed', () async {
      // Close shift first
      await http.post(
        Uri.parse('$baseUrl/api/v1/shifts/close'),
        headers: authHeaders('HOSP_RED_A:CSH01', 'DEV-RED-CSH01'),
        body: jsonEncode({'shiftId': shiftId, 'countedCash': '1000.0000'}),
      );

      // Attempt to request settlement on closed shift
      final reqRes = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/request'),
        headers: authHeaders('HOSP_RED_A:CSH01', 'DEV-RED-CSH01'),
        body: jsonEncode({'doctorId': docId, 'settleAmount': '50.0000', 'shiftId': shiftId}),
      );
      expect(reqRes.statusCode, isNot(equals(200)));
      expect(reqRes.statusCode, isNot(equals(201)));
    });

    test('Vector 9 & 13: Cross-Tenant Settlement and Approval Isolation Integrity', () async {
      // 1. Tenant A cashier attempts to request settlement for Tenant B doctor
      final crossReq = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/request'),
        headers: authHeaders('HOSP_RED_A:CSH01', 'DEV-RED-CSH01'),
        body: jsonEncode({'doctorId': staffIds['HOSP_RED_B:CSH_B'], 'settleAmount': '50.0000', 'shiftId': shiftId}),
      );
      expect(crossReq.statusCode, isNot(equals(201)));

      // 2. Tenant A requests valid settlement
      final validReq = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/request'),
        headers: authHeaders('HOSP_RED_A:CSH01', 'DEV-RED-CSH01'),
        body: jsonEncode({'doctorId': docId, 'settleAmount': '50.0000', 'shiftId': shiftId}),
      );
      final dualReqId = jsonDecode(validReq.body)['data']['requestId'];

      // 3. Tenant B supervisor attempts to approve Tenant A request
      final crossApp = await http.post(
        Uri.parse('$baseUrl/api/v1/dual-control/requests/$dualReqId/decide'),
        headers: authHeaders('HOSP_RED_B:SUP_B', 'DEV-RED-SUP-B'),
        body: jsonEncode({'approve': true}),
      );
      expect(crossApp.statusCode, isNot(equals(200)));
    });

    test('Vector 10 & 27: Manipulated Settlement Amount (Zero, Negative, or Excessive) Fails Closed', () async {
      // Zero amount
      final zeroRes = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/request'),
        headers: authHeaders('HOSP_RED_A:CSH01', 'DEV-RED-CSH01'),
        body: jsonEncode({'doctorId': docId, 'settleAmount': '0.0000', 'shiftId': shiftId}),
      );
      expect(zeroRes.statusCode, isNot(equals(201)));

      // Negative amount
      final negRes = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/request'),
        headers: authHeaders('HOSP_RED_A:CSH01', 'DEV-RED-CSH01'),
        body: jsonEncode({'doctorId': docId, 'settleAmount': '-50.0000', 'shiftId': shiftId}),
      );
      expect(negRes.statusCode, isNot(equals(201)));

      // Excessive amount (accrued is 200, asking 99999)
      final excRes = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/request'),
        headers: authHeaders('HOSP_RED_A:CSH01', 'DEV-RED-CSH01'),
        body: jsonEncode({'doctorId': docId, 'settleAmount': '99999.0000', 'shiftId': shiftId}),
      );
      expect(excRes.statusCode, isNot(equals(201)));
    });

    test('Vector 14: Premature Delivery Attempt on Unapproved Settlement Fails Closed', () async {
      final reqRes = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/request'),
        headers: authHeaders('HOSP_RED_A:CSH01', 'DEV-RED-CSH01'),
        body: jsonEncode({'doctorId': docId, 'settleAmount': '50.0000', 'shiftId': shiftId}),
      );
      final settlementId = jsonDecode(reqRes.body)['data']['settlementId'];

      final delivRes = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/$settlementId/deliver'),
        headers: authHeaders('HOSP_RED_A:CSH01', 'DEV-RED-CSH01'),
        body: jsonEncode({'shiftId': shiftId}),
      );
      expect(delivRes.statusCode, equals(403));
      expect(jsonDecode(delivRes.body)['error']['code'], equals('DUAL_CONTROL_APPROVAL_REQUIRED'));
    });

    test('Vector 16 & 17: Duplicate Approval and Duplicate Delivery Rejections', () async {
      final reqRes = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/request'),
        headers: authHeaders('HOSP_RED_A:CSH01', 'DEV-RED-CSH01'),
        body: jsonEncode({'doctorId': docId, 'settleAmount': '50.0000', 'shiftId': shiftId}),
      );
      final reqData = jsonDecode(reqRes.body)['data'];
      final settlementId = reqData['settlementId'];
      final dualReqId = reqData['requestId'];

      // First approval
      final app1 = await http.post(
        Uri.parse('$baseUrl/api/v1/dual-control/requests/$dualReqId/decide'),
        headers: authHeaders('HOSP_RED_A:SUP01', 'DEV-RED-SUP01'),
        body: jsonEncode({'approve': true}),
      );
      expect(app1.statusCode, equals(200));

      // Duplicate approval -> fails closed
      final app2 = await http.post(
        Uri.parse('$baseUrl/api/v1/dual-control/requests/$dualReqId/decide'),
        headers: authHeaders('HOSP_RED_A:SUP01', 'DEV-RED-SUP01'),
        body: jsonEncode({'approve': true}),
      );
      expect(app2.statusCode, isNot(equals(200)));

      // First delivery
      final deliv1 = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/$settlementId/deliver'),
        headers: authHeaders('HOSP_RED_A:CSH01', 'DEV-RED-CSH01'),
        body: jsonEncode({'shiftId': shiftId}),
      );
      expect(deliv1.statusCode, equals(200));

      // Duplicate delivery -> fails closed
      final deliv2 = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/$settlementId/deliver'),
        headers: authHeaders('HOSP_RED_A:CSH01', 'DEV-RED-CSH01'),
        body: jsonEncode({'shiftId': shiftId}),
      );
      expect(deliv2.statusCode, isNot(equals(200)));
    });

    test('Vector 28 & 30: Accrual Replay Prevention: Consumed Accruals Cannot Be Resettled', () async {
      // Find total available posted accruals for docId
      final pCheck = await db.execute(
        "SELECT SUM(amount) AS total FROM mc_financial_postings WHERE hospital_code = 'HOSP_RED_A' AND posting_type = 'COMMISSION_ACCRUAL' AND beneficiary_id = :docId AND status = 'POSTED'",
        {'docId': docId},
      );
      final totalAccruedStr = pCheck.rows.first.colByName('total') ?? '200.0000';
      final totalAccrued = Decimal.parse(totalAccruedStr);
      expect(totalAccrued > Decimal.zero, isTrue);

      // Settle entire available accrued balance
      final req1 = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/request'),
        headers: authHeaders('HOSP_RED_A:CSH01', 'DEV-RED-CSH01'),
        body: jsonEncode({'doctorId': docId, 'settleAmount': totalAccrued.toStringAsFixed(4), 'shiftId': shiftId}),
      );
      expect(req1.statusCode, equals(201));
      final sData1 = jsonDecode(req1.body)['data'];

      await http.post(
        Uri.parse('$baseUrl/api/v1/dual-control/requests/${sData1['requestId']}/decide'),
        headers: authHeaders('HOSP_RED_A:SUP01', 'DEV-RED-SUP01'),
        body: jsonEncode({'approve': true}),
      );

      final deliv1 = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/${sData1['settlementId']}/deliver'),
        headers: authHeaders('HOSP_RED_A:CSH01', 'DEV-RED-CSH01'),
        body: jsonEncode({'shiftId': shiftId}),
      );
      expect(deliv1.statusCode, equals(200));

      // Attempt second settlement request for same doctor -> Accruals are now 100% SETTLED, must fail closed!
      final req2 = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/request'),
        headers: authHeaders('HOSP_RED_A:CSH01', 'DEV-RED-CSH01'),
        body: jsonEncode({'doctorId': docId, 'settleAmount': '50.0000', 'shiftId': shiftId}),
      );
      expect(req2.statusCode, isNot(equals(201)), reason: 'Consumed accruals must not be available for resettlement');
    });

    test('Vector 21 & 22: Stale or Tampered Bearer Tokens Rejected with 401', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/request'),
        headers: {
          'Authorization': 'Bearer FORGED_STALE_TOKEN_9999',
          'X-Device-Id': 'DEV-RED-CSH01',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'doctorId': docId, 'settleAmount': '10.0000', 'shiftId': shiftId}),
      );
      expect(res.statusCode, equals(401));
    });

    test('Vector 4, 5, 7, 8: Concurrent Duplicate Settlement Delivery Serialization Proof', () async {
      final req = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/request'),
        headers: authHeaders('HOSP_RED_A:CSH01', 'DEV-RED-CSH01'),
        body: jsonEncode({'doctorId': docId, 'settleAmount': '50.0000', 'shiftId': shiftId}),
      );
      final sData = jsonDecode(req.body)['data'];
      final setId = sData['settlementId'];

      await http.post(
        Uri.parse('$baseUrl/api/v1/dual-control/requests/${sData['requestId']}/decide'),
        headers: authHeaders('HOSP_RED_A:SUP01', 'DEV-RED-SUP01'),
        body: jsonEncode({'approve': true}),
      );

      // Concurrent delivery of the exact same settlement
      final d1 = http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/$setId/deliver'),
        headers: authHeaders('HOSP_RED_A:CSH01', 'DEV-RED-CSH01'),
        body: jsonEncode({'shiftId': shiftId}),
      );
      final d2 = http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/$setId/deliver'),
        headers: authHeaders('HOSP_RED_A:CSH01', 'DEV-RED-CSH01'),
        body: jsonEncode({'shiftId': shiftId}),
      );

      final responses = await Future.wait([d1, d2]);
      final codes = responses.map((r) => r.statusCode).toList();

      expect(codes, contains(200));
      expect(codes.where((c) => c == 200).length, equals(1), reason: 'Exactly one delivery may commit; duplicate must be rejected');
    });

    test('F-FIN-01 Focused Invariant: Partial Accrual Consumption Preserves Remainder in MariaDB and Enables Subsequent Settlement', () async {
      // 1. Create a dedicated doctor for this isolated test to prevent interference
      final docF = await staffRepo.createStaff(
        hospitalCode: 'HOSP_RED_A',
        staffCode: 'DOC_FFIN01_${DateTime.now().millisecondsSinceEpoch}',
        fullName: 'Dr. Partial Consumption',
        email: 'doc_ffin01_${DateTime.now().millisecondsSinceEpoch}@medcore.red',
        role: MedCoreRole.Doctor,
        passwordHash: PasswordHasher.hashPassword('Pass123!'),
        permissionsMode: 'default',
        customPermissions: {},
        operationalFlags: const OperationalFlags(canEdit: true, canDelete: false, canCollectMoney: false, canMakeRefunds: false, refundPolicy: RefundPolicy.none),
      );

      // 2. Seed exactly one 200.0000 accrual
      final evRes = await db.execute('''
        INSERT INTO mc_financial_events (
          event_uuid, hospital_code, idempotency_key, event_type,
          source_module, source_entity_type, source_entity_id, shift_id,
          gross_amount, discount_amount, net_amount, paid_amount,
          insurance_covered_amount, patient_responsibility_amount, balance_amount,
          status, created_by
        ) VALUES (
          'EV-FFIN-${DateTime.now().microsecondsSinceEpoch}', 'HOSP_RED_A', 'IDEMP-FFIN-${DateTime.now().microsecondsSinceEpoch}', 'CONSULTATION_COMMISSION',
          'CLINICAL', 'VISIT', 555, $shiftId,
          '200.0000', '0.0000', '200.0000', '0.0000',
          '0.0000', '0.0000', '0.0000',
          'POSTED', ${docF.id}
        )
      ''');
      final evId = evRes.lastInsertID.toInt();

      await db.execute('''
        INSERT INTO mc_financial_postings (
          posting_uuid, hospital_code, event_id, posting_type,
          account_bucket, direction, amount, beneficiary_type, beneficiary_id, shift_id, status
        ) VALUES (
          'POST-FFIN-EXP-${DateTime.now().microsecondsSinceEpoch}', 'HOSP_RED_A', $evId, 'COMMISSION_EXPENSE',
          'EXPENSE_DOCTOR_COMMISSION', 'DEBIT', '200.0000', 'DOCTOR', ${docF.id}, $shiftId, 'POSTED'
        )
      ''');

      final aRes = await db.execute('''
        INSERT INTO mc_financial_postings (
          posting_uuid, hospital_code, event_id, posting_type,
          account_bucket, direction, amount, beneficiary_type, beneficiary_id, shift_id, status
        ) VALUES (
          'POST-FFIN-ACCRUAL-${DateTime.now().microsecondsSinceEpoch}', 'HOSP_RED_A', $evId, 'COMMISSION_ACCRUAL',
          'PAYABLE_COMMISSION_DOCTOR', 'CREDIT', '200.0000', 'DOCTOR', ${docF.id}, $shiftId, 'POSTED'
        )
      ''');
      final originalAccrualId = aRes.lastInsertID.toInt();

      // 3. Settle 50.0000 via HTTP
      final req1 = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/request'),
        headers: authHeaders('HOSP_RED_A:CSH01', 'DEV-RED-CSH01'),
        body: jsonEncode({'doctorId': docF.id, 'settleAmount': '50.0000', 'shiftId': shiftId}),
      );
      expect(req1.statusCode, equals(201));
      final s1Data = jsonDecode(req1.body)['data'];
      final set1Id = s1Data['settlementId'];

      final app1 = await http.post(
        Uri.parse('$baseUrl/api/v1/dual-control/requests/${s1Data['requestId']}/decide'),
        headers: authHeaders('HOSP_RED_A:SUP01', 'DEV-RED-SUP01'),
        body: jsonEncode({'approve': true}),
      );
      expect(app1.statusCode, equals(200));

      final del1 = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/$set1Id/deliver'),
        headers: authHeaders('HOSP_RED_A:CSH01', 'DEV-RED-CSH01'),
        body: jsonEncode({'shiftId': shiftId}),
      );
      expect(del1.statusCode, equals(200));

      // 4. Physical MariaDB Assertions after 50.0000 settlement
      final consumedRow = await db.execute('SELECT amount, status, settlement_id FROM mc_financial_postings WHERE id = :id', {'id': originalAccrualId});
      expect(consumedRow.rows.first.colByName('status'), equals('SETTLED'));
      expect(consumedRow.rows.first.colByName('settlement_id'), equals(set1Id.toString()));
      expect(Decimal.parse(consumedRow.rows.first.colByName('amount')!), equals(Decimal.parse('50.0000')), reason: 'Original row must be updated to consumed portion 50.0000');

      final remainderCheck = await db.execute('''
        SELECT id, amount, status, settlement_id 
        FROM mc_financial_postings 
        WHERE hospital_code = 'HOSP_RED_A' 
          AND beneficiary_id = :docId 
          AND posting_type = 'COMMISSION_ACCRUAL' 
          AND status = 'POSTED'
      ''', {'docId': docF.id});
      expect(remainderCheck.rows.length, equals(1), reason: 'Remainder posting row must exist in MariaDB');
      expect(Decimal.parse(remainderCheck.rows.first.colByName('amount')!), equals(Decimal.parse('150.0000')), reason: 'Remainder amount must be exactly 150.0000');
      expect(remainderCheck.rows.first.colByName('settlement_id'), isNull, reason: 'Remainder must not be linked to prior settlement');

      // 5. Critical Second Transaction: Settle remaining 150.0000 via HTTP
      final req2 = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/request'),
        headers: authHeaders('HOSP_RED_A:CSH01', 'DEV-RED-CSH01'),
        body: jsonEncode({'doctorId': docF.id, 'settleAmount': '150.0000', 'shiftId': shiftId}),
      );
      expect(req2.statusCode, equals(201), reason: 'Second settlement for remaining 150.0000 must succeed');
      final s2Data = jsonDecode(req2.body)['data'];
      final set2Id = s2Data['settlementId'];

      final app2 = await http.post(
        Uri.parse('$baseUrl/api/v1/dual-control/requests/${s2Data['requestId']}/decide'),
        headers: authHeaders('HOSP_RED_A:SUP01', 'DEV-RED-SUP01'),
        body: jsonEncode({'approve': true}),
      );
      expect(app2.statusCode, equals(200));

      final del2 = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/$set2Id/deliver'),
        headers: authHeaders('HOSP_RED_A:CSH01', 'DEV-RED-CSH01'),
        body: jsonEncode({'shiftId': shiftId}),
      );
      expect(del2.statusCode, equals(200));

      // 6. Assert MariaDB has 0 unconsumed accruals for docF
      final unconsumedCheck = await db.execute('''
        SELECT COUNT(*) as cnt 
        FROM mc_financial_postings 
        WHERE hospital_code = 'HOSP_RED_A' 
          AND beneficiary_id = :docId 
          AND posting_type = 'COMMISSION_ACCRUAL' 
          AND status = 'POSTED'
      ''', {'docId': docF.id});
      expect(int.parse(unconsumedCheck.rows.first.colByName('cnt')!), equals(0));

      // 7. Transaction 3: Settle when 0 remaining -> Fails Closed
      final req3 = await http.post(
        Uri.parse('$baseUrl/api/v1/finance/settlements/request'),
        headers: authHeaders('HOSP_RED_A:CSH01', 'DEV-RED-CSH01'),
        body: jsonEncode({'doctorId': docF.id, 'settleAmount': '1.0000', 'shiftId': shiftId}),
      );
      expect(req3.statusCode, isNot(equals(201)), reason: 'Zero balance remaining must fail closed');
    });
  });
}
