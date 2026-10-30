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
  late TransactionManager txManager;
  LocalMedCoreServer? server;
  late String baseUrl;
  late Directory securityRoot;

  final serviceRoot = Directory.current.path;
  final migrationsDir = p.join(serviceRoot, 'sql', 'migrations');

  setUpAll(() async {
    securityRoot = Directory.systemTemp.createTempSync('medcore-extpay-root-');
    final config = testDbConfig(databaseName: 'medcore_test_extpay', maxConnections: 10);
    db = DbClient(config);

    final adminConn = await db.openDedicatedConnection(useDatabase: false);
    try {
      await adminConn.execute('DROP DATABASE IF EXISTS `medcore_test_extpay`');
      await adminConn.execute(
        'CREATE DATABASE `medcore_test_extpay` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
      );
    } finally {
      await adminConn.close();
    }

    migrationRunner = MigrationRunner(db: db, migrationsDir: migrationsDir);
    await migrationRunner.runMigrations();

    txManager = TransactionManager(db);

    server = LocalMedCoreServer(
      db,
      securityRootDirectory: securityRoot.path,
    );
    final port = await server!.start(address: '127.0.0.1', port: 0);
    baseUrl = 'http://127.0.0.1:$port';

    // Seed test tenants, devices, staff, patient, visit, and shift
    final conn = await db.openDedicatedConnection(useDatabase: true);
    try {
      await conn.execute('''
        INSERT INTO mc_tenants (hospital_code, name, status)
        VALUES ('HOSP_PAY', 'Payables Test Hospital', 'active')
      ''');
      await conn.execute('''
        INSERT IGNORE INTO mc_facility_config (
          hospital_code, facility_name, facility_type, branch_code, installation_identity,
          edition, subscription_starts_utc, subscription_expires_utc,
          enabled_modules_json, patient_fields_config_json, branding_appearance_json,
          network_config_json, backup_config_json, remote_hybrid_config_json,
          config_version, created_at, updated_at
        ) VALUES (
          'HOSP_PAY', 'Payables Test Hospital', 'GENERAL_HOSPITAL', 'MAIN', 'INST-HOSP-PAY',
          'PLATINUM', NOW(), DATE_ADD(NOW(), INTERVAL 30 DAY),
          '{}', '{}', '{}', '{}', '{}', '{}',
          1, NOW(), NOW()
        );
      ''');

      final govRepo = TenantGovernanceRepository(db);
      await govRepo.enrollOrUpdateDevice(
        hospitalCode: 'HOSP_PAY',
        deviceId: 'DEV-PAY-1',
        deviceName: 'Billing Terminal',
        platform: 'WINDOWS',
        hwFingerprintSha256: PasswordHasher.sha256Hex('DEV-PAY-1-HW'),
        devicePublicKeyEd25519: 'pk_pay',
        roleScope: 'WORKSTATION',
        isTrustedSecureRuntime: true,
        status: 'ACTIVE',
      );

      final hash = PasswordHasher.hashPassword('AccountantPass123!');
      await conn.execute('''
        INSERT INTO mc_staff (
          hospital_code, staff_code, full_name, email, password_hash, role,
          permissions_mode, can_edit, can_delete, can_collect_money, is_active
        ) VALUES (
          'HOSP_PAY', 'ACC-01', 'Lead Accountant', 'acc@hosppay.local', '$hash',
          'HospitalAdmin', 'default', 1, 1, 1, 1
        )
      ''');

      await conn.execute('''
        INSERT INTO mc_patients (hospital_code, mrn, full_name, phone, gender, created_at)
        VALUES ('HOSP_PAY', 'MRN-P01', 'Ali Hassan', '+201122334455', 'male', CURRENT_TIMESTAMP)
      ''');

      await conn.execute('''
        INSERT INTO mc_shifts (hospital_code, shift_code, cashier_staff_id, device_id, opening_balance, expected_cash, status)
        VALUES ('HOSP_PAY', 'SHF-PAY-01', 1, 'DEV-PAY-1', 1000.0000, 1000.0000, 'OPEN')
      ''');

      await conn.execute('''
        INSERT INTO mc_visits (
          hospital_code, visit_number, idempotency_key, patient_id, shift_id,
          gross_amount, net_amount, paid_amount, balance_amount, status
        ) VALUES (
          'HOSP_PAY', 'VIS-PAY-01', 'IDEMP-VIS-01', 1, 1,
          500.0000, 500.0000, 500.0000, 0.0000, 'SETTLED'
        )
      ''');

      await conn.execute('''
        INSERT INTO mc_financial_events (
          hospital_code, event_uuid, idempotency_key, event_type,
          source_module, source_entity_type, source_entity_id, shift_id,
          gross_amount, net_amount, paid_amount, balance_amount, status
        ) VALUES (
          'HOSP_PAY', 'EVT-PAY-01', 'IDEMP-EVT-01', 'VISIT_SETTLEMENT',
          'RECEPTION', 'mc_visits', 1, 1,
          500.0000, 500.0000, 500.0000, 0.0000, 'POSTED'
        )
      ''');

      // Initial visit postings: DEBIT CASH 500, CREDIT REVENUE 500
      await conn.execute('''
        INSERT INTO mc_financial_postings (
          posting_uuid, hospital_code, event_id, posting_type, account_bucket,
          direction, amount, shift_id, status
        ) VALUES (
          'PST-INIT-1', 'HOSP_PAY', 1, 'CASH_SETTLEMENT', 'CASH_DRAWER',
          'DEBIT', 500.0000, 1, 'POSTED'
        ), (
          'PST-INIT-2', 'HOSP_PAY', 1, 'REVENUE_ACCRUAL', 'HOSPITAL_REVENUE',
          'CREDIT', 500.0000, 1, 'POSTED'
        )
      ''');
    } finally {
      await conn.close();
    }
  });

  tearDownAll(() async {
    await server?.stop();
    await db.close();
    if (securityRoot.existsSync()) {
      securityRoot.deleteSync(recursive: true);
    }
  });

  Future<String> login() async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/auth/login'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'hospitalCode': 'HOSP_PAY',
        'identifier': 'ACC-01',
        'password': 'AccountantPass123!',
        'deviceId': 'DEV-PAY-1',
      }),
    );
    expect(res.statusCode, equals(200));
    return jsonDecode(res.body)['data']['token'] as String;
  }

  test('1. Allocate External Laboratory Payable creates balanced double-entry postings', () async {
    final token = await login();

    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/finance/external-payables'),
      headers: {
        'authorization': 'Bearer $token',
        'x-tenant-id': 'HOSP_PAY',
        'x-medcore-device-id': 'DEV-PAY-1',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'sourceVisitId': 1,
        'sourceEventId': 1,
        'partyType': 'LAB',
        'partyCode': 'ALPHA_LABS',
        'partyName': 'Alpha Medical Laboratories',
        'grossAmount': '200.0000',
        'allocatedAmount': '150.0000',
        'shiftId': 1,
        'notes': 'Outsourced Thyroid Panel',
      }),
    );
    expect(res.statusCode, equals(201));
    final data = jsonDecode(res.body)['data'];
    expect(data['partyCode'], equals('ALPHA_LABS'));
    expect(Decimal.parse(data['allocatedAmount'].toString()), equals(Decimal.parse('150.0000')));
    expect(data['status'], equals('PENDING'));

    // Verify trial balance: SUM(DEBIT) == SUM(CREDIT)
    final trialRes = await db.execute(
      '''
      SELECT direction, SUM(amount) as total
      FROM mc_financial_postings
      WHERE hospital_code = 'HOSP_PAY'
      GROUP BY direction
      ''',
    );
    var debits = Decimal.zero;
    var credits = Decimal.zero;
    for (final r in trialRes.rows) {
      final dir = r.colByName('direction');
      final tot = Decimal.parse(r.colByName('total')!);
      if (dir == 'DEBIT') debits = tot;
      if (dir == 'CREDIT') credits = tot;
    }
    expect(debits, equals(credits), reason: 'Double-entry equality violated');
    expect(debits, equals(Decimal.parse('650.0000'))); // 500 initial + 150 split
  });

  test('2. Settle External Payable disburses funds and clears liability cleanly', () async {
    final token = await login();

    // Settle 100 out of 150
    final settleRes = await http.post(
      Uri.parse('$baseUrl/api/v1/finance/external-payables/1/settle'),
      headers: {
        'authorization': 'Bearer $token',
        'x-tenant-id': 'HOSP_PAY',
        'x-medcore-device-id': 'DEV-PAY-1',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'settleAmount': '100.0000',
        'paymentMethod': 'CASH',
        'idempotencyKey': 'IDEMP-SETTLE-01',
      }),
    );
    expect(settleRes.statusCode, equals(200));
    final data = jsonDecode(settleRes.body)['data'];
    expect(Decimal.parse(data['paidAmount'].toString()), equals(Decimal.parse('100.0000')));
    expect(Decimal.parse(data['balanceAmount'].toString()), equals(Decimal.parse('50.0000')));
    expect(data['status'], equals('PARTIAL'));

    // Complete remaining settlement
    final settleRes2 = await http.post(
      Uri.parse('$baseUrl/api/v1/finance/external-payables/1/settle'),
      headers: {
        'authorization': 'Bearer $token',
        'x-tenant-id': 'HOSP_PAY',
        'x-medcore-device-id': 'DEV-PAY-1',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'settleAmount': '50.0000',
        'paymentMethod': 'CASH',
        'idempotencyKey': 'IDEMP-SETTLE-02',
      }),
    );
    expect(settleRes2.statusCode, equals(200));
    expect(jsonDecode(settleRes2.body)['data']['status'], equals('SETTLED'));
    expect(Decimal.parse(jsonDecode(settleRes2.body)['data']['balanceAmount'].toString()), equals(Decimal.zero));

    // Over-settlement rejected fail-closed
    final overSettle = await http.post(
      Uri.parse('$baseUrl/api/v1/finance/external-payables/1/settle'),
      headers: {
        'authorization': 'Bearer $token',
        'x-tenant-id': 'HOSP_PAY',
        'x-medcore-device-id': 'DEV-PAY-1',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'settleAmount': '10.0000',
        'paymentMethod': 'CASH',
      }),
    );
    expect(overSettle.statusCode, greaterThanOrEqualTo(400), reason: 'Cannot settle settled payable');
  });

  test('3. LAN PKI: Issue Device Certificate and verify against database truth', () async {
    final token = await login();

    // 1. Issue certificate
    final issueRes = await http.post(
      Uri.parse('$baseUrl/api/v1/network/certificates/issue'),
      headers: {
        'authorization': 'Bearer $token',
        'x-tenant-id': 'HOSP_PAY',
        'x-medcore-device-id': 'DEV-PAY-1',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'deviceId': 'DEV-PAY-1',
        'commonName': 'Billing Terminal 1 Cert',
      }),
    );
    expect(issueRes.statusCode, equals(201));
    final certData = jsonDecode(issueRes.body)['data'];
    final fp = certData['fingerprintSha256'] as String;
    final certUuid = certData['certUuid'] as String;
    expect(fp.length, equals(64));

    // 2. Direct PKI verification
    final pki = LanPkiService(txManager);
    final isValid = await pki.verifyCertificate(
      hospitalCode: 'HOSP_PAY',
      fingerprintSha256: fp,
    );
    expect(isValid, isTrue);

    // 3. Revoke certificate
    final revokeRes = await http.post(
      Uri.parse('$baseUrl/api/v1/network/certificates/$certUuid/revoke'),
      headers: {
        'authorization': 'Bearer $token',
        'x-tenant-id': 'HOSP_PAY',
        'x-medcore-device-id': 'DEV-PAY-1',
        'content-type': 'application/json',
      },
      body: jsonEncode({'reason': 'SCHEDULED_KEY_ROTATION'}),
    );
    expect(revokeRes.statusCode, equals(200));

    // 4. Verification after revocation MUST return false
    final isValidAfter = await pki.verifyCertificate(
      hospitalCode: 'HOSP_PAY',
      fingerprintSha256: fp,
    );
    expect(isValidAfter, isFalse, reason: 'Revoked certificate must fail verification');
  });
}
