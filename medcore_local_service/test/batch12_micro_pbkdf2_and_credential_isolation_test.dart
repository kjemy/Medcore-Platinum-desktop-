import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:medcore_local_service/medcore_local_service.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'support/test_db_config.dart';

void main() {
  const dbName = 'medcore_commissioning_gate_test';
  late DbClient db;
  LocalMedCoreServer? server;
  late String baseUrl;
  late Directory securityRoot;
  const hospitalCode = 'HOSP_MICRO_GATE';
  const deviceId = 'DEV-MICRO-HOST';
  const techSecret = 'MicroTechSecret!2026';

  setUpAll(() async {
    securityRoot = Directory.systemTemp.createTempSync('medcore-micro-gate-');
    final config = testDbConfig(databaseName: dbName, maxConnections: 5);
    db = DbClient(config);

    // Apply migrations if needed
    final serviceRoot = Directory.current.path;
    final migrationsDir = p.join(serviceRoot, 'sql', 'migrations');
    final runner = MigrationRunner(db: db, migrationsDir: migrationsDir);
    await runner.runMigrations();

    server = LocalMedCoreServer(
      db,
      securityRootDirectory: securityRoot.path,
      technicianSecretHashOverride: PasswordHasher.hashPassword(techSecret),
    );
    final port = await server!.start(address: '127.0.0.1', port: 0);
    baseUrl = 'http://127.0.0.1:$port';
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

  group('MICRO VERIFICATION A — PBKDF2 Implementation Truth', () {
    test('A.1: Algorithm parameters, default iteration count and salt length', () {
      expect(PasswordHasher.defaultIterations, equals(20000));
      expect(PasswordHasher.keyLength, equals(32));

      final hash = PasswordHasher.hashPassword('PermanentAdminPass#2026');
      expect(hash, startsWith('pbkdf2_sha256\$20000\$'));

      final parts = hash.split('\$');
      expect(parts.length, equals(4));
      expect(parts[0], equals('pbkdf2_sha256'));
      expect(parts[1], equals('20000'));

      final saltBytes = base64Url.decode(parts[2]);
      expect(saltBytes.length, equals(16), reason: 'Salt must be exactly 16 bytes');

      final hashBytes = base64Url.decode(parts[3]);
      expect(hashBytes.length, equals(32), reason: 'Derived key must be exactly 32 bytes (256 bits)');
    });

    test('A.2: Constant-time verification, negative passwords, and iteration count agility', () {
      const password = 'TestSecretPassword#2026';
      final hashDefault = PasswordHasher.hashPassword(password);

      expect(PasswordHasher.verifyPassword(password, hashDefault), isTrue);
      expect(PasswordHasher.verifyPassword('WrongPassword#2026', hashDefault), isFalse);

      // Verify iteration agility: verifier dynamically respects iterations in hash string
      final hash5000 = PasswordHasher.hashPassword(password, iterations: 5000);
      expect(hash5000, startsWith('pbkdf2_sha256\$5000\$'));
      expect(PasswordHasher.verifyPassword(password, hash5000), isTrue);

      final hash30000 = PasswordHasher.hashPassword(password, iterations: 30000);
      expect(hash30000, startsWith('pbkdf2_sha256\$30000\$'));
      expect(PasswordHasher.verifyPassword(password, hash30000), isTrue);
    });
  });

  group('MICRO VERIFICATION B — Test Credential Isolation & Universal Backdoor Absence', () {
    test('B.1: Baseline seeding produces zero staff rows in MariaDB', () async {
      const freshHosp = 'HOSP_ZERO_TEST_01';
      await server!.databaseLifecycleService.seedBaselineSystemDataForTesting(freshHosp);

      final countRes = await db.execute(
        'SELECT COUNT(*) AS total FROM mc_staff WHERE hospital_code = :hosp',
        {'hosp': freshHosp},
      );
      final count = int.parse(countRes.rows.first.colByName('total')!.toString());
      expect(count, equals(0), reason: 'Fresh baseline must NEVER seed staff accounts');

      // Verify zero legacy universal admin across database
      final legacyRes = await db.execute(
        'SELECT COUNT(*) AS total FROM mc_staff WHERE email = "admin@medcore.local"',
      );
      final legacyCount = int.parse(legacyRes.rows.first.colByName('total')!.toString());
      expect(legacyCount, equals(0));
    });

    test('B.2: Test credentials do not act as universal fallback passwords', () async {
      // 1. Setup tenant & device for login test
      final govRepo = TenantGovernanceRepository(db);
      await govRepo.upsertTenant(hospitalCode: hospitalCode, name: 'Micro Test Hospital');
      await govRepo.enrollOrUpdateDevice(
        hospitalCode: hospitalCode,
        deviceId: deviceId,
        deviceName: 'Test Host',
        platform: 'WINDOWS',
        connectionType: 'LOOPBACK',
        hwFingerprintSha256: PasswordHasher.sha256Hex('HW-MICRO-01'),
        devicePublicKeyEd25519: 'PUBKEY-MICRO-01',
        roleScope: 'SERVER_HOST',
        isTrustedSecureRuntime: true,
        status: 'ACTIVE',
      );

      // 2. Attempt login as non-existent user with test passwords -> all rejected 401
      final testPasswordsToProbe = [
        'TempAdminSecret#2026',
        'PermanentAdminPass#2026',
        'StaffInitialPass#2026',
        'AdminPassword#2026',
        'admin',
      ];

      for (final pwd in testPasswordsToProbe) {
        final resp = await http.post(
          Uri.parse('$baseUrl/api/v1/auth/login'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'hospitalCode': hospitalCode,
            'deviceId': deviceId,
            'email': 'admin@medcore.local',
            'password': pwd,
          }),
        );
        expect(resp.statusCode, equals(401), reason: 'Non-existent admin with $pwd must fail 401');
      }

      // 3. Create a real staff member with unique password 'StaffRealSecret#2026'
      final staffRepo = StaffIdentityRepository(db);
      await staffRepo.createStaff(
        hospitalCode: hospitalCode,
        staffCode: 'STF-MICRO-01',
        fullName: 'Micro Real Staff',
        email: 'staff.real@micro.org',
        passwordHash: PasswordHasher.hashPassword('StaffRealSecret#2026'),
        role: MedCoreRole.Employee,
      );

      // 4. Verify that probing this real staff member with test passwords fails closed (401)
      for (final pwd in testPasswordsToProbe) {
        final resp = await http.post(
          Uri.parse('$baseUrl/api/v1/auth/login'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'hospitalCode': hospitalCode,
            'deviceId': deviceId,
            'email': 'staff.real@micro.org',
            'password': pwd,
          }),
        );
        expect(resp.statusCode, equals(401), reason: 'Real staff probing with $pwd must fail 401');
      }

      // 5. Verify that only the real password succeeds
      final validResp = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/login'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'deviceId': deviceId,
          'email': 'staff.real@micro.org',
          'password': 'StaffRealSecret#2026',
        }),
      );
      expect(validResp.statusCode, equals(200));
    });
  });
}
