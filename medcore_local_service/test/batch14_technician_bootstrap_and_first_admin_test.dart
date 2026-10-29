import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:medcore_local_service/medcore_local_service.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'support/test_db_config.dart';

void main() {
  const dbName = 'medcore_technician_bootstrap_test';
  late DbClient db;
  late MigrationRunner migrationRunner;
  LocalMedCoreServer? server;
  late String baseUrl;
  late Directory securityRoot;

  const hospitalCode = 'HOSP_BOOTSTRAP_01';
  const hospitalCodeB = 'HOSP_ATTACKER_99';
  const deviceId = 'DEV-BOOTSTRAP-HOST';
  const deviceIdUntrusted = 'DEV-UNTRUSTED-DEVICE';

  final serviceRoot = Directory.current.path;
  final migrationsDir = p.join(serviceRoot, 'sql', 'migrations');

  late String commissioningSecret;
  late String techToken;
  late String sessionUuid;
  const adminTempPassword = 'InitialAdminTempPass#2026';
  const adminPermanentPassword = 'PermanentAdminSecret#2026';
  late String adminToken;

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
    securityRoot = Directory.systemTemp.createTempSync('medcore-tech-bootstrap-');
    final config = testDbConfig(databaseName: dbName, maxConnections: 10);
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

    // 3. Register Tenants & Host Device
    final govRepo = TenantGovernanceRepository(db);
    await govRepo.upsertTenant(
      hospitalCode: hospitalCode,
      name: 'Bootstrap General Hospital',
    );
    await govRepo.upsertTenant(
      hospitalCode: hospitalCodeB,
      name: 'Rogue Host Facility',
    );
    await govRepo.enrollOrUpdateDevice(
      hospitalCode: hospitalCode,
      deviceId: deviceId,
      deviceName: 'Server Workstation Host',
      platform: 'WINDOWS',
      connectionType: 'LOOPBACK',
      hwFingerprintSha256: PasswordHasher.sha256Hex('BOOTSTRAP-HW-01'),
      devicePublicKeyEd25519: 'PUBKEY-BOOTSTRAP-01',
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

  group('PHASE 1: Fresh Installation State Verification', () {
    test('1.1: Database has ZERO staff members initially', () async {
      final res = await db.execute('SELECT COUNT(*) AS c FROM mc_staff');
      expect(int.parse(res.rows.first.colByName('c')!), equals(0));
    });

    test('1.2: One-time Commissioning Secret and Hash files exist', () async {
      final secFile = File(p.join(securityRoot.path, 'technician_secret.json'));
      expect(secFile.existsSync(), isTrue, reason: 'technician_secret.json must be created on fresh start');

      final slipFile = File(p.join(securityRoot.path, 'FIRST_RUN_COMMISSIONING_SECRET.txt'));
      expect(slipFile.existsSync(), isTrue, reason: 'FIRST_RUN_COMMISSIONING_SECRET.txt must be generated for technician');

      final slipContent = slipFile.readAsStringSync();
      expect(slipContent, contains('ONE-TIME FIRST-RUN TECHNICIAN COMMISSIONING SECRET'));
      expect(slipContent, contains('Commissioning Secret  : TECH-COMM-'));

      // Extract the plain secret from the one-time slip
      final match = RegExp(r'Commissioning Secret\s+:\s+(TECH-COMM-[^\r\n\s]+)').firstMatch(slipContent);
      expect(match, isNotNull);
      commissioningSecret = match!.group(1)!;

      // Verify JSON storage contains only PBKDF2 hash, zero plaintext
      final jsonContent = secFile.readAsStringSync();
      expect(jsonContent, isNot(contains(commissioningSecret)), reason: 'Secret must NEVER be stored in plaintext');
      final decoded = jsonDecode(jsonContent) as Map<String, dynamic>;
      expect(decoded['technicianSecretHash'], startsWith('pbkdf2_sha256\$'));
    });
  });

  group('PHASE 2: Technician Authentication & First-Run Handover', () {
    test('2.1: Open technician session with one-time commissioning secret', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/session/open'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'deviceId': deviceId,
          'technicianSecret': commissioningSecret,
        }),
      );
      if (res.statusCode != 201) {
        print('2.1 FAILED: Status ${res.statusCode}, Body: ${res.body}');
      }
      expect(res.statusCode, equals(201), reason: 'Technician session must open successfully (201 Created)');
      final body = jsonDecode(res.body)['data'] as Map<String, dynamic>;
      expect(body['technicianToken'], startsWith('mct_'));
      techToken = body['technicianToken'] as String;
      sessionUuid = body['session']['sessionUuid'] as String;

      // Verify MariaDB mc_technician_sessions record
      final dbRes = await db.execute(
        'SELECT * FROM mc_technician_sessions WHERE session_uuid = :uuid',
        {'uuid': sessionUuid},
      );
      expect(dbRes.rows.length, equals(1));
      expect(dbRes.rows.first.colByName('auth_method'), equals('INSTALLATION_TECH_SECRET'));
      expect(dbRes.rows.first.colByName('is_active'), equals('1'));

      // Verify one-time slip file was consumed / deleted
      final slipFile = File(p.join(securityRoot.path, 'FIRST_RUN_COMMISSIONING_SECRET.txt'));
      expect(slipFile.existsSync(), isFalse, reason: 'One-time slip file must be deleted upon first login');
    });

    test('2.2: Initial Admin status reports hasAdmin = false', () async {
      final res = await http.get(
        Uri.parse('$baseUrl/api/v1/technician/initial-admin/status'),
        headers: techHeaders(),
      );
      expect(res.statusCode, equals(200));
      final body = jsonDecode(res.body)['data'] as Map<String, dynamic>;
      expect(body['hasAdmin'], isFalse);
      expect(body['administrators'], isEmpty);
    });

    test('2.3: Technician saves facility configuration', () async {
      final res = await http.put(
        Uri.parse('$baseUrl/api/v1/technician/config'),
        headers: techHeaders(),
        body: jsonEncode({
          'facilityName': 'Bootstrap City Hospital',
          'facilityType': 'GENERAL_HOSPITAL',
          'edition': 'PLATINUM',
          'enabledModules': ['EMR', 'CLINICAL', 'PATIENTS', 'APPOINTMENTS', 'FINANCIAL_POSTINGS', 'CLINICAL_TEMPLATES'],
        }),
      );
      expect(res.statusCode, equals(200));

      final dbCfg = await db.execute(
        'SELECT * FROM mc_facility_config WHERE hospital_code = :hosp',
        {'hosp': hospitalCode},
      );
      expect(dbCfg.rows.length, equals(1));
      expect(dbCfg.rows.first.colByName('facility_name'), equals('Bootstrap City Hospital'));
      expect(dbCfg.rows.first.colByName('updated_by_tech_session'), equals(sessionUuid));
    });

    test('2.4: Technician provisions Initial Hospital Administrator (Tab 8)', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/initial-admin'),
        headers: techHeaders(),
        body: jsonEncode({
          'staffCode': 'ADM-BOOT-001',
          'fullName': 'Dr. Sarah Connor',
          'email': 'sarah.connor@bootstrap.hospital',
          'password': adminTempPassword,
          'phone': '+15550199',
        }),
      );
      expect(res.statusCode, equals(201));
      final body = jsonDecode(res.body)['data'] as Map<String, dynamic>;
      expect(body['admin']['staffCode'], equals('ADM-BOOT-001'));
      expect(body['admin']['role'], equals('HospitalAdmin'));
      expect(body['forcePasswordChange'], isTrue);

      // Verify MariaDB mc_staff authoritative persistence
      final staffRes = await db.execute(
        "SELECT * FROM mc_staff WHERE staff_code = 'ADM-BOOT-001' AND hospital_code = :hosp",
        {'hosp': hospitalCode},
      );
      expect(staffRes.rows.length, equals(1));
      final row = staffRes.rows.first;
      expect(row.colByName('role'), equals('HospitalAdmin'));
      expect(row.colByName('is_active'), equals('1'));
      expect(row.colByName('force_password_change'), equals('1'));
      expect(row.colByName('password_hash'), startsWith('pbkdf2_sha256\$'));
      expect(row.colByName('password_hash'), isNot(contains(adminTempPassword)));

      // Verify audit log
      final auditRes = await db.execute(
        "SELECT * FROM mc_audit_logs WHERE action = 'technician.initial_admin.provisioned' AND hospital_code = :hosp",
        {'hosp': hospitalCode},
      );
      expect(auditRes.rows.length, equals(1));
    });

    test('2.5: Initial Admin status now reports hasAdmin = true', () async {
      final res = await http.get(
        Uri.parse('$baseUrl/api/v1/technician/initial-admin/status'),
        headers: techHeaders(),
      );
      expect(res.statusCode, equals(200));
      final body = jsonDecode(res.body)['data'] as Map<String, dynamic>;
      expect(body['hasAdmin'], isTrue);
      final admins = body['administrators'] as List;
      expect(admins.length, equals(1));
      expect(admins.first['staffCode'], equals('ADM-BOOT-001'));
    });

    test('2.6: Close Technician Session', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/session/close'),
        headers: techHeaders(),
      );
      expect(res.statusCode, equals(200));

      // MariaDB verification: session is deactivated
      final dbRes = await db.execute(
        'SELECT is_active, revoked_at FROM mc_technician_sessions WHERE session_uuid = :uuid',
        {'uuid': sessionUuid},
      );
      expect(dbRes.rows.first.colByName('is_active'), equals('0'));
      expect(dbRes.rows.first.colByName('revoked_at'), isNotNull);
    });
  });

  group('PHASE 3: Hospital Administrator First Login & Mandatory Password Change', () {
    test('3.1: Admin signs in with temporary password -> forcePasswordChange = true', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/login'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'deviceId': deviceId,
          'identifier': 'sarah.connor@bootstrap.hospital',
          'password': adminTempPassword,
        }),
      );
      expect(res.statusCode, equals(200));
      final body = jsonDecode(res.body)['data'] as Map<String, dynamic>;
      expect(body['token'], startsWith('mcd_'));
      adminToken = body['token'] as String;
      expect(body['user']['forcePasswordChange'], isTrue);
      expect(body['user']['role'], equals('HospitalAdmin'));
    });

    test('3.2: Admin updates password to permanent password', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/change-password'),
        headers: bearerHeaders(adminToken),
        body: jsonEncode({
          'oldPassword': adminTempPassword,
          'newPassword': adminPermanentPassword,
        }),
      );
      expect(res.statusCode, equals(200));

      // MariaDB verification: force_password_change is now 0
      final staffRes = await db.execute(
        "SELECT force_password_change, password_hash FROM mc_staff WHERE staff_code = 'ADM-BOOT-001' AND hospital_code = :hosp",
        {'hosp': hospitalCode},
      );
      final row = staffRes.rows.first;
      expect(row.colByName('force_password_change'), equals('0'));
      expect(row.colByName('password_hash'), startsWith('pbkdf2_sha256\$'));
    });

    test('3.3: Temporary password no longer works (invalidated)', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/login'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'deviceId': deviceId,
          'identifier': 'sarah.connor@bootstrap.hospital',
          'password': adminTempPassword,
        }),
      );
      expect(res.statusCode, equals(401), reason: 'Old temporary password must be rejected');
    });

    test('3.4: Login with permanent password succeeds with normal session', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/login'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'deviceId': deviceId,
          'identifier': 'sarah.connor@bootstrap.hospital',
          'password': adminPermanentPassword,
        }),
      );
      expect(res.statusCode, equals(200));
      final body = jsonDecode(res.body)['data'] as Map<String, dynamic>;
      expect(body['user']['forcePasswordChange'], isFalse);
      adminToken = body['token'] as String;
    });

    test('3.5: Administrator accesses normal hospital operations', () async {
      final res = await http.get(
        Uri.parse('$baseUrl/api/v1/patients'),
        headers: bearerHeaders(adminToken),
      );
      expect(res.statusCode, equals(200), reason: 'Admin can now operate normal system');
    });
  });

  group('SECURITY RED TEAM: Technician Authentication & Commissioning Attack Vectors', () {
    test('RT-1: Technician API without technician token returns 403', () async {
      final res = await http.get(
        Uri.parse('$baseUrl/api/v1/technician/config'),
        headers: {'content-type': 'application/json', 'x-tenant-id': hospitalCode, 'x-medcore-device-id': deviceId},
      );
      expect(res.statusCode, equals(403));
    });

    test('RT-2: Technician API with expired/closed token returns 403', () async {
      final res = await http.get(
        Uri.parse('$baseUrl/api/v1/technician/config'),
        headers: techHeaders(token: techToken), // Closed in Phase 2.6
      );
      expect(res.statusCode, equals(403));
    });

    test('RT-3: Technician API with malformed token returns 403', () async {
      final res = await http.get(
        Uri.parse('$baseUrl/api/v1/technician/config'),
        headers: techHeaders(token: 'mct_MALFORMED_GARBAGE_TOKEN_12345'),
      );
      expect(res.statusCode, equals(403));
    });

    test('RT-4: Technician API from wrong/untrusted device binding returns 403', () async {
      // Re-open session to get a valid token
      final openRes = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/session/open'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'deviceId': deviceId,
          'technicianSecret': commissioningSecret,
        }),
      );
      final activeTechToken = (jsonDecode(openRes.body)['data'] as Map)['technicianToken'] as String;

      // Attacker uses valid token with untrusted device
      final res = await http.get(
        Uri.parse('$baseUrl/api/v1/technician/config'),
        headers: techHeaders(token: activeTechToken, dev: deviceIdUntrusted),
      );
      expect(res.statusCode, equals(403), reason: 'Wrong device binding must be blocked');
    });

    test('RT-5: Initial Admin creation without technician authorization returns 403', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/initial-admin'),
        headers: bearerHeaders(adminToken), // Calling technician endpoint with staff token
        body: jsonEncode({
          'staffCode': 'ADM-ATTACK-001',
          'fullName': 'Attacker Admin',
          'email': 'attacker@rogue.hospital',
          'password': 'AttackerPass#2026',
        }),
      );
      expect(res.statusCode, equals(403), reason: 'Staff token must NEVER access technician endpoints');
    });

    test('RT-6: Guessing / wrong technician credentials returns 403', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/session/open'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'deviceId': deviceId,
          'technicianSecret': 'WrongGuessedSecret#9999',
        }),
      );
      expect(res.statusCode, equals(403));
      final body = jsonDecode(res.body)['error'] as Map<String, dynamic>;
      expect(body['code'], equals('INVALID_TECHNICIAN_CREDENTIALS'));
    });

    test('RT-7: Provisioning administrator with duplicate staffCode returns 409', () async {
      // Open valid technician session
      final openRes = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/session/open'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'deviceId': deviceId,
          'technicianSecret': commissioningSecret,
        }),
      );
      final activeTech = (jsonDecode(openRes.body)['data'] as Map)['technicianToken'] as String;

      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/initial-admin'),
        headers: techHeaders(token: activeTech),
        body: jsonEncode({
          'staffCode': 'ADM-BOOT-001', // Already exists!
          'fullName': 'Duplicate Admin',
          'email': 'duplicate@bootstrap.hospital',
          'password': 'DuplicatePass#2026',
        }),
      );
      expect(res.statusCode, equals(409), reason: 'Duplicate staff code must return 409 Conflict');
    });

    test('RT-8: Cross-tenant technician session access returns 403', () async {
      // Attacker attempts to open technician session for an unknown/unauthorized tenant
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/session/open'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': 'UNKNOWN_UNAUTHORIZED_TENANT',
          'deviceId': deviceId,
          'technicianSecret': commissioningSecret,
        }),
      );
      expect(res.statusCode, equals(403), reason: 'Unauthorized tenant must return 403');
    });
  });
}
