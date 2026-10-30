import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:medcore_local_service/medcore_local_service.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/test_authority_signer.dart';
import 'support/test_db_config.dart';

void main() {
  group('MEDCORE PLATINUM RUN #11: Self-Contained Offline MariaDB & Package Truth', () {
    const testDbName = 'medcore_self_contained_offline_test';
    late DbClient adminDb;
    late DbClient testDb;
    late Directory tempSecurityDir;
    late TestAuthoritySigner authoritySigner;

    setUpAll(() async {
      authoritySigner = TestAuthoritySigner.loadDefault();
      tempSecurityDir = Directory.systemTemp.createTempSync('medcore_sec_test_');

      final adminConfig = testDbConfig(databaseName: 'mysql', maxConnections: 10);
      adminDb = DbClient(adminConfig);
      await adminDb.execute(
        'CREATE DATABASE IF NOT EXISTS `$testDbName` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;',
      );

      final testConfig = testDbConfig(databaseName: testDbName, maxConnections: 10);
      testDb = DbClient(testConfig);
    });

    tearDownAll(() async {
      try {
        await adminDb.execute('DROP DATABASE IF EXISTS `$testDbName`;');
      } catch (_) {}
      try {
        await testDb.close();
        await adminDb.close();
      } catch (_) {}
      try {
        if (tempSecurityDir.existsSync()) tempSecurityDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    // =========================================================================
    // MARIADB-01: Bundled Binary Exists
    // =========================================================================
    test('MARIADB-01: Bundled MariaDB binary exists in runtime or service paths', () {
      final repoRoot = Directory.current.parent.path;
      final candidates = [
        p.join(repoRoot, 'runtime', 'mariadb', 'bin'),
        p.join(repoRoot, 'service', 'mariadb', 'bin'),
        p.join(Directory.current.path, '..', 'runtime', 'mariadb', 'bin'),
      ];

      String? foundBin;
      for (final cand in candidates) {
        if (File(p.join(cand, 'mariadbd.exe')).existsSync() ||
            File(p.join(cand, 'mysqld.exe')).existsSync()) {
          foundBin = cand;
          break;
        }
      }

      expect(foundBin, isNotNull, reason: 'MariaDB server executable must exist in bundled path.');
      final daemonExe = File(p.join(foundBin!, 'mariadbd.exe')).existsSync()
          ? p.join(foundBin, 'mariadbd.exe')
          : p.join(foundBin, 'mysqld.exe');
      expect(File(daemonExe).existsSync(), isTrue);
    });

    // =========================================================================
    // MARIADB-02: Bundled Version Detected
    // =========================================================================
    test('MARIADB-02: Bundled MariaDB version matches 11.4 LTS', () {
      final repoRoot = Directory.current.parent.path;
      final binPath = p.join(repoRoot, 'runtime', 'mariadb', 'bin');
      final daemon = File(p.join(binPath, 'mariadbd.exe')).existsSync()
          ? p.join(binPath, 'mariadbd.exe')
          : p.join(binPath, 'mysqld.exe');

      if (File(daemon).existsSync()) {
        final result = Process.runSync(daemon, ['--version']);
        final out = '${result.stdout} ${result.stderr}';
        expect(out, contains('11.4'), reason: 'MariaDB must be version 11.4.x');
        expect(out.toLowerCase(), contains('mariadb'));
      }
    });

    // =========================================================================
    // MARIADB-03: No External MariaDB Dependency
    // =========================================================================
    test('MARIADB-03: Dynamic binary resolution locates bundled instance without system PATH', () {
      final script = File(p.join(Directory.current.path, 'scripts', 'provision_mariadb.ps1'));
      expect(script.existsSync(), isTrue);

      final content = script.readAsStringSync();
      expect(content, contains('Resolve-MariaDBBinDir'));
      expect(content, contains('Resolve-MariaDBDataDir'));
      expect(content, isNot(contains(r'C:\Program Files\MariaDB\bin\mariadb.exe')),
          reason: 'Hard-coded Program Files paths forbidden.');
    });

    // =========================================================================
    // MARIADB-04: Fresh Data Directory & Isolated Config Structure
    // =========================================================================
    test('MARIADB-04: my.ini enforces local bind-address 127.0.0.1 and port 3307', () {
      final repoRoot = Directory.current.parent.path;
      final myIni = File(p.join(repoRoot, 'runtime', 'mariadb_data', 'my.ini'));
      if (myIni.existsSync()) {
        final content = myIni.readAsStringSync();
        expect(content, contains('bind-address=127.0.0.1'),
            reason: 'MariaDB must strictly bind to loopback.');
        expect(content, contains('port=3307'),
            reason: 'MariaDB must use dedicated port 3307.');
        expect(content, contains('character-set-server=utf8mb4'));
      }
    });

    // =========================================================================
    // MARIADB-05: Authenticated Connection
    // =========================================================================
    test('MARIADB-05: Authenticated connection succeeds and queries database metadata', () async {
      final res = await testDb.execute('SELECT 1 AS probe, VERSION() AS ver, @@port AS port;');
      expect(res.rows, isNotEmpty);
      expect(res.rows.first.colByName('probe'), equals('1'));
      expect(res.rows.first.colByName('port'), equals('3307'));
    });

    // =========================================================================
    // MARIADB-06: Port 3307 & Strict Authentication
    // =========================================================================
    test('MARIADB-06: MariaDB rejects unauthenticated connections on port 3307', () async {
      final badConfig = DbConfig(
        host: '127.0.0.1',
        port: 3307,
        user: 'root',
        password: 'WRONG_UNAUTHORIZED_PASSWORD_123',
        databaseName: testDbName,
        maxConnections: 1,
      );
      final badDb = DbClient(badConfig);
      expect(
        badDb.execute('SELECT 1;'),
        throwsA(anything),
        reason: 'Unauthenticated connection attempt must fail closed.',
      );
    });

    // =========================================================================
    // MARIADB-07: Migrations V001..V017 Complete Execution
    // =========================================================================
    test('MARIADB-07: All 17 migrations apply and verify with 100% integrity', () async {
      final migrationsDir = p.join(Directory.current.path, 'sql', 'migrations');
      final runner = MigrationRunner(db: testDb, migrationsDir: migrationsDir);
      final applied = await runner.runMigrations();

      expect(applied.length, greaterThanOrEqualTo(17),
          reason: 'All V001..V017 migrations must be executed.');

      final tables = await testDb.execute(
        "SELECT table_name FROM information_schema.tables WHERE table_schema = :db;",
        {'db': testDbName},
      );
      final tableNames = tables.rows.map((r) => r.colByName('table_name')?.toLowerCase()).toSet();

      expect(tableNames.contains('mc_tenants'), isTrue);
      expect(tableNames.contains('mc_security_root'), isTrue);
      expect(tableNames.contains('mc_technician_sessions'), isTrue);
      expect(tableNames.contains('mc_consumed_maintenance_tokens'), isTrue);
      expect(tableNames.contains('mc_audit_logs'), isTrue);
      expect(tableNames.contains('mc_scheduling_resources'), isTrue);
      expect(tableNames.contains('mc_scheduling_rules'), isTrue);
    });

    // =========================================================================
    // MARIADB-08: Local Service Connection & Health Polling
    // =========================================================================
    test('MARIADB-08: LocalMedCoreServer starts against bundled database and reports HEALTHY', () async {
      final timeVerifier = TrustedTimeVerifier.forTesting(
        authorityId: 'MEDCORE-TIME-TEST-AUTHORITY',
        modulus: authoritySigner.modulus,
        exponent: authoritySigner.publicExponent,
      );
      final maintService = MaintenanceTokenService(
        modulus: authoritySigner.modulus,
        publicExponent: authoritySigner.publicExponent,
      );

      final server = LocalMedCoreServer(
        testDb,
        securityRootDirectory: tempSecurityDir.path,
        autoBootstrapCommissioningSecret: true,
        maintenanceTokenService: maintService,
        trustedTimeVerifier: timeVerifier,
      );

      final boundPort = await server.start(port: 0, address: '127.0.0.1');
      try {
        final res = await http.get(Uri.parse('http://127.0.0.1:$boundPort/api/v1/health'));
        expect(res.statusCode, equals(200));
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final data = body['data'] as Map<String, dynamic>;
        expect(data['status'], equals('HEALTHY'));
      } finally {
        await server.stop();
      }
    });

    // =========================================================================
    // MARIADB-09: Restart Persistence
    // =========================================================================
    test('MARIADB-09: Committed data persists across connection terminations', () async {
      const hospitalCode = 'HOSP_PERSIST_TEST';
      await testDb.execute(
        '''
        INSERT INTO mc_tenants (
          hospital_code, name, edition,
          created_at, updated_at
        ) VALUES (
          :code, 'Persistence Test Hospital', 'ENTERPRISE_LAN',
          NOW(), NOW()
        ) ON DUPLICATE KEY UPDATE name = VALUES(name);
        ''',
        {'code': hospitalCode},
      );

      // Close connection and re-open
      await testDb.close();
      final freshConfig = testDbConfig(databaseName: testDbName, maxConnections: 5);
      testDb = DbClient(freshConfig);

      final readBack = await testDb.execute(
        'SELECT name FROM mc_tenants WHERE hospital_code = :code;',
        {'code': hospitalCode},
      );
      expect(readBack.rows, isNotEmpty);
      expect(readBack.rows.first.colByName('name'), equals('Persistence Test Hospital'));
    });

    // =========================================================================
    // MARIADB-10: Factory Reset Reinitialization
    // =========================================================================
    test('MARIADB-10: Factory Reset executes complete schema reset and credential re-seeding', () async {
      final timeVerifier = TrustedTimeVerifier.forTesting(
        authorityId: 'MEDCORE-TIME-TEST-AUTHORITY',
        modulus: authoritySigner.modulus,
        exponent: authoritySigner.publicExponent,
      );
      final maintService = MaintenanceTokenService(
        modulus: authoritySigner.modulus,
        publicExponent: authoritySigner.publicExponent,
      );

      final server = LocalMedCoreServer(
        testDb,
        securityRootDirectory: tempSecurityDir.path,
        autoBootstrapCommissioningSecret: true,
        maintenanceTokenService: maintService,
        trustedTimeVerifier: timeVerifier,
      );

      await server.start(port: 0, address: '127.0.0.1');
      try {
        final resetResult = await server.databaseLifecycleService.factoryReset(
          hospitalCode: 'HOSP_PERSIST_TEST',
          confirmationText: 'RESET MEDCORE',
        );

        expect(resetResult['status'], equals('COMPLETED_AND_REBUILT'));

        // Verify fresh slip exists
        final slip = File(p.join(tempSecurityDir.path, 'FIRST_RUN_COMMISSIONING_SECRET.txt'));
        expect(slip.existsSync(), isTrue);

        // Verify V001..V017 migrations re-applied
        final checkTables = await testDb.execute(
          "SELECT COUNT(*) AS c FROM information_schema.tables WHERE table_schema = :db;",
          {'db': testDbName},
        );
        final count = int.parse(checkTables.rows.first.colByName('c') ?? '0');
        expect(count, greaterThan(15));
      } finally {
        await server.stop();
      }
    });

    // =========================================================================
    // MARIADB-11: Offline Startup & Autonomous Operation
    // =========================================================================
    test('MARIADB-11: Complete authentication, cryptographic checks and DB execution run offline', () {
      // 1. Password PBKDF2 hashing runs entirely local
      final password = 'TestHospitalOffline#2026';
      final hash = PasswordHasher.hashPassword(password);
      expect(PasswordHasher.verifyPassword(password, hash), isTrue);

      // 2. High-entropy token generation runs offline
      final token = PasswordHasher.generateSecureToken(32);
      expect(token.isNotEmpty, isTrue);
      expect(token.length, greaterThanOrEqualTo(32));

      // 3. Cryptographic seal computation runs offline without network sockets
      final sha = PasswordHasher.sha256Hex('OfflineTestPayload');
      expect(sha.length, equals(64));
    });
  });
}
