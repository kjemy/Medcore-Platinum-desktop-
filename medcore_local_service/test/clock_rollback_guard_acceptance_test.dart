import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:medcore_local_service/medcore_local_service.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'support/test_authority_signer.dart';
import 'support/test_db_config.dart';

void main() {
  late DbClient db;
  late MigrationRunner migrationRunner;
  late TransactionManager txManager;
  LocalMedCoreServer? server;
  late String baseUrl;
  late TestAuthoritySigner authoritySigner;
  late TestAuthoritySigner timeAuthoritySigner;
  late TrustedTimeVerifier timeVerifier;
  late Directory securityRoot;
  late String installationId;

  ClockGuardRepository clockRepoFor(SqlExecutor executor) => ClockGuardRepository(
        executor,
        maintenanceTokenService: MaintenanceTokenService(
          modulus: authoritySigner.modulus,
          publicExponent: authoritySigner.publicExponent,
        ),
        trustedTimeVerifier: timeVerifier,
        securityRootDirectory: securityRoot.path,
      );

  TrustedTimeEvidence trustedEvidence(String hospital, String installation, DateTime time) {
    final challenge = timeVerifier.createChallenge(hospitalCode: hospital, installationId: installation);
    final response = timeAuthoritySigner.signTimeResponse(
      authorityId: timeVerifier.authorityId,
      hospitalCode: hospital,
      installationId: installation,
      nonce: challenge.nonce,
      trustedUtc: time,
    );
    return timeVerifier.verifyResponse(challenge: challenge, rawResponse: response);
  }

  // Controllable wall clock for deterministic time manipulation
  DateTime simulatedTime = DateTime.utc(2026, 10, 27, 10, 0, 0);
  DateTime getClock() => simulatedTime;

  final serviceRoot = Directory.current.path;
  final migrationsDir = p.join(serviceRoot, 'sql', 'migrations');

  const testDbName = 'medcore_clock_test';
  final dbConfig = testDbConfig(databaseName: testDbName, maxConnections: 10);

  setUpAll(() async {
    // Load Test Authority Signer (lives strictly outside production distribution)
    authoritySigner = TestAuthoritySigner.loadDefault();
    timeAuthoritySigner = TestAuthoritySigner.fromPrivateKeyFile(
      p.join(serviceRoot, 'test', 'fixtures', 'time_test_authority.json'),
    );
    timeVerifier = TrustedTimeVerifier.forTesting(
      authorityId: 'MEDCORE-TIME-TEST-AUTHORITY',
      modulus: timeAuthoritySigner.modulus,
      exponent: timeAuthoritySigner.publicExponent,
    );
    installationId = ClockGuardKeyManager.fromFile().installationId;
    securityRoot = Directory.systemTemp.createTempSync('medcore-clock-root-');

    db = DbClient(dbConfig);

    // Recreate isolated test database to protect operational databases
    final adminConn = await db.openDedicatedConnection(useDatabase: false);
    try {
      await adminConn.execute('DROP DATABASE IF EXISTS `$testDbName`');
      await adminConn.execute(
        'CREATE DATABASE `$testDbName` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
      );
    } finally {
      await adminConn.close();
    }

    // Apply all V001..V011 migrations
    migrationRunner = MigrationRunner(db: db, migrationsDir: migrationsDir);
    await migrationRunner.runMigrations();

    txManager = TransactionManager(db);

    // Bootstrap test tenant A
    final govRepo = TenantGovernanceRepository(db);
    await govRepo.upsertTenant(
      hospitalCode: 'HOSP_CLOCK_A',
      name: 'Clock Guard Test Hospital A',
    );

    await govRepo.enrollOrUpdateDevice(
      hospitalCode: 'HOSP_CLOCK_A',
      deviceId: 'DEV-CLOCK-01',
      deviceName: 'Secure Counter Terminal A',
      platform: 'WINDOWS',
      hwFingerprintSha256: PasswordHasher.sha256Hex('CLOCK-TEST-HW-01'),
      devicePublicKeyEd25519: 'PUBKEY-CLOCK-01',
      isTrustedSecureRuntime: true,
      status: 'ACTIVE',
    );

    final staffRepo = StaffIdentityRepository(db);
    await staffRepo.createStaff(
      hospitalCode: 'HOSP_CLOCK_A',
      staffCode: 'STF-CLK-01',
      fullName: 'Youssef Security Officer',
      email: 'youssef@clock-a.local',
      passwordHash: PasswordHasher.hashPassword('ClockPass#2026'),
      role: MedCoreRole.HospitalAdmin,
    );

    // Bootstrap test tenant B (for multi-tenant isolation verification)
    await govRepo.upsertTenant(
      hospitalCode: 'HOSP_CLOCK_B',
      name: 'Clock Guard Test Hospital B',
    );

    await govRepo.enrollOrUpdateDevice(
      hospitalCode: 'HOSP_CLOCK_B',
      deviceId: 'DEV-CLOCK-B1',
      deviceName: 'Secure Counter Terminal B',
      platform: 'WINDOWS',
      hwFingerprintSha256: PasswordHasher.sha256Hex('CLOCK-TEST-HW-B1'),
      devicePublicKeyEd25519: 'PUBKEY-CLOCK-B1',
      isTrustedSecureRuntime: true,
      status: 'ACTIVE',
    );

    await staffRepo.createStaff(
      hospitalCode: 'HOSP_CLOCK_B',
      staffCode: 'STF-CLK-B1',
      fullName: 'Layla Security Officer B',
      email: 'layla@clock-b.local',
      passwordHash: PasswordHasher.hashPassword('ClockPass#2026'),
      role: MedCoreRole.HospitalAdmin,
    );

    // Start server with controllable clock
    server = LocalMedCoreServer(db, clock: getClock, securityRootDirectory: securityRoot.path);
    final port = await server!.start();
    baseUrl = 'http://127.0.0.1:$port';
  });

  tearDownAll(() async {
    await server?.stop();
    await db.close();
    if (securityRoot.existsSync()) securityRoot.deleteSync(recursive: true);
  });

  group('P1 REMEDIATION: Server-Side Monotonic Clock Rollback Guard & Keyed HMAC Integrity', () {
    String? revokedTokenS3;

    test('1. Baseline initialization: mc_clock_guard is populated and sealed with keyed HMAC on login', () async {
      simulatedTime = DateTime.utc(2026, 10, 27, 10, 0, 0);

      final loginResp = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/login'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': 'HOSP_CLOCK_A',
          'identifier': 'youssef@clock-a.local',
          'password': 'ClockPass#2026',
          'deviceId': 'DEV-CLOCK-01',
        }),
      );
      expect(loginResp.statusCode, equals(200));

      final clockRepo = clockRepoFor(db);
      final record = await clockRepo.getClockGuard('HOSP_CLOCK_A');
      expect(record, isNotNull);
      expect(record!.hospitalCode, equals('HOSP_CLOCK_A'));
      expect(record.maxObservedUtc.isAtSameMomentAs(simulatedTime), isTrue);
      expect(record.rollbackDetected, isFalse);
      expect(record.rollbackDeltaSeconds, isNull);
      expect(record.processBootId, isNotNull, reason: 'Persisted process boundary must be present in MariaDB.');
      expect(clockRepo.verifyHmacSeal(record), isTrue, reason: 'Keyed HMAC seal must match row content');
    });

    test('2. Normal forward time advancement updates max_observed_utc and recomputes valid keyed HMAC seal', () async {
      simulatedTime = DateTime.utc(2026, 10, 27, 10, 10, 0);

      final clockRepo = clockRepoFor(db);
      final eval = await txManager.runInTransaction((tx) async {
        return await clockRepoFor(tx).evaluateAndUpdateClock(
          hospitalCode: 'HOSP_CLOCK_A',
          currentWallClock: getClock(),
        );
      });

      expect(eval.effectiveTime, equals(simulatedTime));
      expect(eval.rollbackDetected, isFalse);

      final record = (await clockRepo.getClockGuard('HOSP_CLOCK_A'))!;
      expect(record.maxObservedUtc.isAtSameMomentAs(simulatedTime), isTrue);
      expect(clockRepo.verifyHmacSeal(record), isTrue);
    });

    test('3. Multi-Tenant Clock Isolation: Tenant A future jump does NOT leak to or affect Tenant B', () async {
      // Advance Tenant A clock 12 hours into the future
      final tenantAFutureTime = DateTime.utc(2026, 10, 27, 22, 0, 0);
      await txManager.runInTransaction((tx) async {
        await clockRepoFor(tx).evaluateAndUpdateClock(
          hospitalCode: 'HOSP_CLOCK_A',
          currentWallClock: tenantAFutureTime,
        );
      });

      // Tenant B evaluates at its current normal time (10:15:00)
      final tenantBTime = DateTime.utc(2026, 10, 27, 10, 15, 0);
      final evalB = await txManager.runInTransaction((tx) async {
        return await clockRepoFor(tx).evaluateAndUpdateClock(
          hospitalCode: 'HOSP_CLOCK_B',
          currentWallClock: tenantBTime,
        );
      });

      // ISOLATION PROOF: Tenant B must NOT be contaminated by Tenant A's 22:00:00 clock
      expect(evalB.effectiveTime, equals(tenantBTime));
      expect(evalB.rollbackDetected, isFalse);
      expect(evalB.record.maxObservedUtc, equals(tenantBTime));

      // Direct MariaDB Read-back verification
      final resB = await db.execute(
        'SELECT max_observed_utc, rollback_detected FROM mc_clock_guard WHERE hospital_code = :hosp',
        {'hosp': 'HOSP_CLOCK_B'},
      );
      expect(resB.rows.isNotEmpty, isTrue);
      expect(resB.rows.first.colByName('max_observed_utc'), contains('2026-10-27 10:15:00'));
      expect(resB.rows.first.colByName('rollback_detected'), equals('0'));

      // Restore Tenant A for remainder of test suite
      final keyMgr = ClockGuardKeyManager.fromFile();
      final restoreTime = DateTime.utc(2026, 10, 27, 10, 10, 0);
      final sealA = keyMgr.computeKeyedSeal(
        hospitalCode: 'HOSP_CLOCK_A',
        maxObservedUtc: restoreTime,
        lastBootMonotonicMs: 0,
        processBootId: ClockGuardRepository.currentProcessBootId,
        rollbackDetected: false,
      );
      await db.execute(
        '''
        UPDATE mc_clock_guard
        SET max_observed_utc = '2026-10-27 10:10:00.000',
            last_boot_monotonic_ms = 0,
            rollback_detected = 0,
            rollback_delta_seconds = NULL,
            hmac_seal = :seal
        WHERE hospital_code = 'HOSP_CLOCK_A'
        ''',
        {'seal': sealA},
      );
    });

    test('4. Adversarial State Deletion: Out-of-band deletion of mc_clock_guard fails closed on established tenant', () async {
      // First ensure HOSP_CLOCK_A has established records in mc_auth_sessions
      final sessions = await db.execute(
        'SELECT COUNT(*) as c FROM mc_auth_sessions WHERE hospital_code = :hosp',
        {'hosp': 'HOSP_CLOCK_A'},
      );
      final sCount = int.parse(sessions.rows.first.colByName('c') ?? '0');
      expect(sCount > 0, isTrue, reason: 'HOSP_CLOCK_A must have established session history');

      // Attacker deletes the mc_clock_guard row directly from MariaDB
      await db.execute("DELETE FROM mc_clock_guard WHERE hospital_code = 'HOSP_CLOCK_A'");

      // Verify row is physically gone
      final readBack = await db.execute(
        "SELECT id FROM mc_clock_guard WHERE hospital_code = 'HOSP_CLOCK_A'",
      );
      expect(readBack.rows.isEmpty, isTrue);

      // Attempting to evaluate clock must FAIL CLOSED with ClockTamperException
      expect(
        () async => await txManager.runInTransaction((tx) async {
          return await clockRepoFor(tx).evaluateAndUpdateClock(
            hospitalCode: 'HOSP_CLOCK_A',
            currentWallClock: DateTime.utc(2026, 10, 27, 10, 15, 0),
          );
        }),
        throwsA(isA<ClockTamperException>().having(
          (e) => e.message,
          'message',
          contains('security root exists but mc_clock_guard is missing'),
        )),
      );

      // HTTP session verification must also reject with HTTP 403 CLOCK_TAMPER_DETECTED
      final httpResp = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/login'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': 'HOSP_CLOCK_A',
          'identifier': 'youssef@clock-a.local',
          'password': 'ClockPass#2026',
          'deviceId': 'DEV-CLOCK-01',
        }),
      );
      expect(httpResp.statusCode, equals(403));
      expect(jsonDecode(httpResp.body)['error']['code'], equals('CLOCK_TAMPER_DETECTED'));

      // Re-insert valid record for HOSP_CLOCK_A for subsequent tests
      final keyMgr = ClockGuardKeyManager.fromFile();
      final restoreTime = DateTime.utc(2026, 10, 27, 10, 10, 0);
      final validSeal = keyMgr.computeKeyedSeal(
        hospitalCode: 'HOSP_CLOCK_A',
        maxObservedUtc: restoreTime,
        lastBootMonotonicMs: 0,
        processBootId: ClockGuardRepository.currentProcessBootId,
        rollbackDetected: false,
      );
      await db.execute(
        '''
        INSERT INTO mc_clock_guard (
          hospital_code, max_observed_utc, last_boot_monotonic_ms, process_boot_id,
          rollback_detected, rollback_delta_seconds, hmac_seal
        ) VALUES (
          'HOSP_CLOCK_A', '2026-10-27 10:10:00.000', 0, :boot_id,
          0, NULL, :seal
        )
        ''',
        {'seal': validSeal, 'boot_id': ClockGuardRepository.currentProcessBootId},
      );
    });

    test('5. Keyed HMAC Field Tampering Matrix: Tampering with ANY security field is rejected by fail-closed HMAC', () async {
      final keyMgr = ClockGuardKeyManager.fromFile();
      final baseTime = DateTime.utc(2026, 10, 27, 10, 10, 0);

      Future<void> restoreRow() async {
        final seal = keyMgr.computeKeyedSeal(
          hospitalCode: 'HOSP_CLOCK_A',
          maxObservedUtc: baseTime,
          lastBootMonotonicMs: 0,
          processBootId: ClockGuardRepository.currentProcessBootId,
          rollbackDetected: false,
        );
        await db.execute(
          '''
          UPDATE mc_clock_guard
          SET max_observed_utc = '2026-10-27 10:10:00.000',
              last_boot_monotonic_ms = 0,
              rollback_detected = 0,
              rollback_delta_seconds = NULL,
              locked_at_utc = NULL,
              unlocked_by_maintenance_token_id = NULL,
              hmac_seal = :seal
          WHERE hospital_code = 'HOSP_CLOCK_A'
          ''',
          {'seal': seal},
        );
      }

      final clockRepo = clockRepoFor(db);

      // 5.1 Tamper max_observed_utc
      await db.execute(
        "UPDATE mc_clock_guard SET max_observed_utc = '2026-10-27 09:00:00.000' WHERE hospital_code = 'HOSP_CLOCK_A'",
      );
      final rec1 = (await clockRepo.getClockGuard('HOSP_CLOCK_A'))!;
      expect(clockRepo.verifyHmacSeal(rec1), isFalse);

      // 5.2 Tamper rollback_delta_seconds
      await restoreRow();
      await db.execute(
        "UPDATE mc_clock_guard SET rollback_delta_seconds = 777 WHERE hospital_code = 'HOSP_CLOCK_A'",
      );
      final rec2 = (await clockRepo.getClockGuard('HOSP_CLOCK_A'))!;
      expect(clockRepo.verifyHmacSeal(rec2), isFalse);

      // 5.3 Tamper locked_at_utc
      await restoreRow();
      await db.execute(
        "UPDATE mc_clock_guard SET locked_at_utc = '2026-10-27 10:00:00' WHERE hospital_code = 'HOSP_CLOCK_A'",
      );
      final rec3 = (await clockRepo.getClockGuard('HOSP_CLOCK_A'))!;
      expect(clockRepo.verifyHmacSeal(rec3), isFalse);

      // 5.4 Tamper unlocked_by_maintenance_token_id
      await restoreRow();
      await db.execute(
        "UPDATE mc_clock_guard SET unlocked_by_maintenance_token_id = 'FORGED-TOKEN' WHERE hospital_code = 'HOSP_CLOCK_A'",
      );
      final rec4 = (await clockRepo.getClockGuard('HOSP_CLOCK_A'))!;
      expect(clockRepo.verifyHmacSeal(rec4), isFalse);

      // 5.5 Tamper last_boot_monotonic_ms
      await restoreRow();
      await db.execute(
        "UPDATE mc_clock_guard SET last_boot_monotonic_ms = 999999 WHERE hospital_code = 'HOSP_CLOCK_A'",
      );
      final rec5 = (await clockRepo.getClockGuard('HOSP_CLOCK_A'))!;
      expect(clockRepo.verifyHmacSeal(rec5), isFalse);

      // 5.6 Unkeyed SHA-256 seal is rejected
      await restoreRow();
      final unkeyedSha = PasswordHasher.sha256Hex('HOSP_CLOCK_A|2026-10-27 10:10:00.000|0|0');
      await db.execute(
        "UPDATE mc_clock_guard SET hmac_seal = :seal WHERE hospital_code = 'HOSP_CLOCK_A'",
        {'seal': unkeyedSha},
      );
      final rec6 = (await clockRepo.getClockGuard('HOSP_CLOCK_A'))!;
      expect(clockRepo.verifyHmacSeal(rec6), isFalse);

      await restoreRow();
    });

    test('6. Secret Scanning Invariant: Assert zero private authority keys exist inside Desktop tree', () async {
      final project4Dir = Directory(p.normalize(p.join(serviceRoot, '..')));
      final files = project4Dir.listSync(recursive: true, followLinks: false);

      for (final entity in files) {
        if (entity is File) {
          if (p.normalize(entity.path).contains(p.join('test', 'fixtures'))) continue;
          final relPath = p.relative(entity.path, from: project4Dir.path);
          // Skip scratch directories outside project 4 or temporary git files
          if (relPath.startsWith('.git') || relPath.startsWith('.dart_tool')) continue;

          // Check filename
          expect(
            relPath.toLowerCase().contains('authority_priv'),
            isFalse,
            reason: 'Private authority key file must NOT exist in Desktop product tree: $relPath',
          );

          // Check small text files for private key markers
          if (entity.lengthSync() < 100000 &&
              (relPath.endsWith('.json') || relPath.endsWith('.pem') || relPath.endsWith('.key'))) {
            // clock_guard.key is the symmetric installation secret (allowed)
            if (relPath.endsWith('clock_guard.key')) continue;

            final content = entity.readAsStringSync();
            expect(
              content.contains('BEGIN RSA PRIVATE KEY') || content.contains('"d":'),
              isFalse,
              reason: 'Private RSA key component found inside $relPath!',
            );
          }
        }
      }
    });

    test('7. Mandatory Installation Binding: Token missing, empty, or mismatched installation ID is rejected', () async {
      final clockRepo = clockRepoFor(db);
      final now = DateTime.utc(2026, 10, 27, 12, 0, 0);

      // 7.1 Empty installationId parameter rejected
      expect(
        () async => await clockRepo.unlockWithMaintenanceToken(
          hospitalCode: 'HOSP_CLOCK_A',
          rawMaintenanceToken: 'dummy',
          currentWallClock: now,
          expectedInstallationId: '   ',
        ),
        throwsA(isA<ArgumentError>()),
      );

      // 7.2 Token with empty installationId claim rejected
      final tokenEmptyInst = authoritySigner.signToken(
        hospitalCode: 'HOSP_CLOCK_A',
        installationId: '',
        nonce: 'NONCE-EMPTY-INST-01',
        issuedAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
      );
      expect(
        () async => await clockRepo.unlockWithMaintenanceToken(
          hospitalCode: 'HOSP_CLOCK_A',
          rawMaintenanceToken: tokenEmptyInst,
          currentWallClock: now,
          expectedInstallationId: installationId,
        ),
        throwsA(isA<MaintenanceTokenException>().having((e) => e.code, 'code', 'EMPTY_INSTALLATION_CLAIM')),
      );

      // 7.3 Token with mismatched installationId claim rejected
      final tokenWrongInst = authoritySigner.signToken(
        hospitalCode: 'HOSP_CLOCK_A',
        installationId: 'INST-OTHER-DEVICE',
        nonce: 'NONCE-WRONG-INST-01',
        issuedAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
      );
      expect(
        () async => await clockRepo.unlockWithMaintenanceToken(
          hospitalCode: 'HOSP_CLOCK_A',
          rawMaintenanceToken: tokenWrongInst,
          currentWallClock: now,
          expectedInstallationId: installationId,
        ),
        throwsA(isA<MaintenanceTokenException>().having((e) => e.code, 'code', 'INSTALLATION_MISMATCH')),
      );
    });

    test('8. Trusted Security Time Authority: Rolled-back wall clock CANNOT resurrect expired maintenance token', () async {
      final clockRepo = clockRepoFor(db);

      // Set high-water mark to 12:00:00
      simulatedTime = DateTime.utc(2026, 10, 27, 12, 0, 0);
      await txManager.runInTransaction((tx) async {
        await clockRepoFor(tx).evaluateAndUpdateClock(
          hospitalCode: 'HOSP_CLOCK_A',
          currentWallClock: simulatedTime,
        );
      });

      // Token expired at 11:30:00 (before high-water mark of 12:00:00)
      final tokenExpiredPast = authoritySigner.signToken(
        hospitalCode: 'HOSP_CLOCK_A',
        installationId: installationId,
        nonce: 'NONCE-TRUSTED-TIME-01',
        issuedAt: DateTime.utc(2026, 10, 27, 10, 30, 0),
        expiresAt: DateTime.utc(2026, 10, 27, 11, 30, 0),
      );

      // Attacker rolls host wall clock back to 11:00:00 to pretend token is not yet expired
      final rolledBackWallClock = DateTime.utc(2026, 10, 27, 11, 0, 0);

      // Trusted Security Time Invariant:
      // Expiration MUST be evaluated against high-water mark (12:00:00), NOT caller's rolled back wall clock (11:00:00)!
      expect(
        () async => await clockRepo.unlockWithMaintenanceToken(
          hospitalCode: 'HOSP_CLOCK_A',
          rawMaintenanceToken: tokenExpiredPast,
          currentWallClock: rolledBackWallClock,
          expectedInstallationId: installationId,
          trustedTimeEvidence: trustedEvidence('HOSP_CLOCK_A', installationId, DateTime.utc(2026, 10, 27, 12, 30)),
        ),
        throwsA(isA<MaintenanceTokenException>().having((e) => e.code, 'code', 'TOKEN_EXPIRED')),
      );
    });

    test('9. Strict Fail-Closed Expiration: exp <= now rule enforces that exp == now fails closed', () async {
      final clockRepo = clockRepoFor(db);
      final exactTime = DateTime.utc(2026, 10, 27, 12, 0, 0);

      final tokenBoundary = authoritySigner.signToken(
        hospitalCode: 'HOSP_CLOCK_A',
        installationId: installationId,
        nonce: 'NONCE-BOUNDARY-EXP-01',
        issuedAt: exactTime.subtract(const Duration(minutes: 30)),
        expiresAt: exactTime, // Exactly at boundary
      );

      // Evaluation at exact expiration moment must FAIL CLOSED
      expect(
        () async => await clockRepo.unlockWithMaintenanceToken(
          hospitalCode: 'HOSP_CLOCK_A',
          rawMaintenanceToken: tokenBoundary,
          currentWallClock: exactTime,
          expectedInstallationId: installationId,
          trustedTimeEvidence: trustedEvidence('HOSP_CLOCK_A', installationId, exactTime),
        ),
        throwsA(isA<MaintenanceTokenException>().having((e) => e.code, 'code', 'TOKEN_EXPIRED')),
      );
    });

    test('10. Millisecond Drift Precision: Drift of 5001ms with 5s tolerance immediately flags rollback (no truncation)', () async {
      // Set high-water mark to T0
      final t0 = DateTime.utc(2026, 10, 27, 12, 0, 0);
      await txManager.runInTransaction((tx) async {
        await clockRepoFor(tx).evaluateAndUpdateClock(
          hospitalCode: 'HOSP_CLOCK_A',
          currentWallClock: t0,
        );
      });

      // Host clock is behind by 5001 milliseconds (5.001 seconds)
      final tMinus5001Ms = t0.subtract(const Duration(milliseconds: 5001));

      final eval = await txManager.runInTransaction((tx) async {
        return await clockRepoFor(tx).evaluateAndUpdateClock(
          hospitalCode: 'HOSP_CLOCK_A',
          currentWallClock: tMinus5001Ms,
          driftTolerance: const Duration(seconds: 5),
        );
      });

      // Invariant: Must detect rollback immediately without integer-second truncation!
      expect(eval.rollbackDetected, isTrue);
      expect(eval.rollbackDeltaSeconds, equals(6)); // ceil(5001/1000) = 6s
    });

    test('11. Real OS Process-Level Restart: Physical persistence verified across independent OS process boundaries', () async {
      final workerScript = p.join(serviceRoot, 'test', 'support', 'clock_worker.dart');

      // Bootstrap tenant for worker test
      final govRepo = TenantGovernanceRepository(db);
      await govRepo.upsertTenant(
        hospitalCode: 'HOSP_PROC_01',
        name: 'Process Test Hospital',
      );

      // Process 1: Real OS Process execution to advance clock
      final proc1 = await Process.run(
        Platform.executable,
        [workerScript, 'evaluate', 'HOSP_PROC_01', '2026-10-27T13:00:00.000Z', securityRoot.path],
        workingDirectory: serviceRoot,
      );
      expect(proc1.exitCode, equals(0), reason: 'Process 1 error: ${proc1.stderr}');
      final output1 = jsonDecode(proc1.stdout.toString().trim());
      expect(output1['status'], equals('OK'));
      expect(output1['effectiveTime'], contains('2026-10-27T13:00:00.000Z'));

      // Process 1 is dead. MariaDB persisted state.
      // Process 2: Real OS Process execution reading and verifying high-water mark and HMAC seal
      final proc2 = await Process.run(
        Platform.executable,
        [workerScript, 'read', 'HOSP_PROC_01', '2026-10-27T13:00:00.000Z', securityRoot.path],
        workingDirectory: serviceRoot,
      );
      expect(proc2.exitCode, equals(0), reason: 'Process 2 error: ${proc2.stderr}');
      final output2 = jsonDecode(proc2.stdout.toString().trim());
      expect(output2['status'], equals('OK'));
      expect(output2['maxObservedUtc'], contains('2026-10-27T13:00:00.000Z'));
      expect(output2['validSeal'], isTrue, reason: 'Keyed HMAC seal must survive across OS process termination');

      // A third, independently launched process must fail closed on normal clock evaluation.
      final proc3 = await Process.run(
        Platform.executable,
        [workerScript, 'evaluate', 'HOSP_PROC_01', '2026-10-27T10:00:00.000Z', securityRoot.path],
        workingDirectory: serviceRoot,
      );
      expect(proc3.exitCode, isNot(0));
      expect(proc3.stderr.toString(), contains('UNTRUSTED_DOWNTIME_CLOCK'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('12. Concurrency Proof: Simultaneous replay of identical token nonce under real concurrent load', () async {
      final clockRepo = clockRepoFor(db);
      final now = DateTime.utc(2026, 10, 27, 13, 30, 0);

      // First induce a rollback state so unlock is needed
      await txManager.runInTransaction((tx) async {
        await clockRepoFor(tx).evaluateAndUpdateClock(
          hospitalCode: 'HOSP_CLOCK_A',
          currentWallClock: DateTime.utc(2026, 10, 27, 14, 0, 0),
        );
      });

      final concurrentNonce = 'NONCE-CONCURRENT-${DateTime.now().microsecondsSinceEpoch}';
      final concurrentToken = authoritySigner.signToken(
        hospitalCode: 'HOSP_CLOCK_A',
        installationId: installationId,
        nonce: concurrentNonce,
        issuedAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
      );

      // Fire 10 concurrent requests simultaneously with the same token
      final results = await Future.wait(
        List.generate(10, (_) async {
          try {
            await clockRepo.unlockWithMaintenanceToken(
              hospitalCode: 'HOSP_CLOCK_A',
              rawMaintenanceToken: concurrentToken,
              currentWallClock: now,
              expectedInstallationId: installationId,
              trustedTimeEvidence: trustedEvidence('HOSP_CLOCK_A', installationId, now),
            );
            return 'SUCCESS';
          } on MaintenanceTokenException catch (e) {
            return e.code;
          } catch (e) {
            return e.toString();
          }
        }),
      );

      final successCount = results.where((r) => r == 'SUCCESS').length;
      final replayCount = results.where((r) => r == 'NONCE_ALREADY_USED').length;

      // CONCURRENCY PROOF: Exactly 1 must succeed; exactly 9 must be rejected with NONCE_ALREADY_USED
      expect(successCount, equals(1), reason: 'Exactly one concurrent request may consume the nonce');
      expect(replayCount, equals(9), reason: 'All 9 concurrent replays must fail with NONCE_ALREADY_USED');

      // Authoritative MariaDB read-back
      final dbCheck = await db.execute(
        'SELECT COUNT(*) as c FROM mc_consumed_maintenance_tokens WHERE hospital_code = :hosp AND nonce = :nonce',
        {'hosp': 'HOSP_CLOCK_A', 'nonce': concurrentNonce},
      );
      final consumedCount = int.parse(dbCheck.rows.first.colByName('c') ?? '0');
      expect(consumedCount, equals(1), reason: 'Physical MariaDB table must contain exactly 1 row for consumed nonce');
    });

    test('13. Claim Tampering Matrix: Tampering with ANY token claim invalidates RSA-2048 PKCS#1 signature', () async {
      final now = DateTime.utc(2026, 10, 27, 14, 0, 0);
      final validToken = authoritySigner.signToken(
        hospitalCode: 'HOSP_CLOCK_A',
        installationId: installationId,
        nonce: 'NONCE-TAMPER-MATRIX-01',
        issuedAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
      );

      final parts = validToken.split('.');
      expect(parts.length, equals(3));
      final payloadMap = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map<String, dynamic>;

      String tamperClaim(String key, dynamic val) {
        final tamperedMap = Map<String, dynamic>.from(payloadMap);
        tamperedMap[key] = val;
        final newJson = jsonEncode(tamperedMap);
        final newB64 = base64UrlEncode(utf8.encode(newJson)).replaceAll('=', '');
        return '${parts[0]}.$newB64.${parts[2]}';
      }

      final tokenSvc = MaintenanceTokenService(
        modulus: authoritySigner.modulus,
        publicExponent: authoritySigner.publicExponent,
      );

      // 13.1 Tamper hospital
      expect(
        () => tokenSvc.verifyAndParseToken(
          rawToken: tamperClaim('hosp', 'HOSP_TAMPERED'),
          expectedHospitalCode: 'HOSP_TAMPERED',
          effectiveTime: now,
          expectedInstallationId: installationId,
        ),
        throwsA(isA<MaintenanceTokenException>().having((e) => e.code, 'code', 'INVALID_SIGNATURE')),
      );

      // 13.2 Tamper installationId
      expect(
        () => tokenSvc.verifyAndParseToken(
          rawToken: tamperClaim('inst', 'INST-TAMPERED'),
          expectedHospitalCode: 'HOSP_CLOCK_A',
          effectiveTime: now,
          expectedInstallationId: 'INST-TAMPERED',
        ),
        throwsA(isA<MaintenanceTokenException>().having((e) => e.code, 'code', 'INVALID_SIGNATURE')),
      );

      // 13.3 Tamper action
      expect(
        () => tokenSvc.verifyAndParseToken(
          rawToken: tamperClaim('act', 'ADMIN_TAKEOVER'),
          expectedHospitalCode: 'HOSP_CLOCK_A',
          effectiveTime: now,
          expectedInstallationId: installationId,
        ),
        throwsA(isA<MaintenanceTokenException>().having((e) => e.code, 'code', 'INVALID_SIGNATURE')),
      );

      // 13.4 Tamper exp
      expect(
        () => tokenSvc.verifyAndParseToken(
          rawToken: tamperClaim('exp', '2030-01-01T00:00:00.000Z'),
          expectedHospitalCode: 'HOSP_CLOCK_A',
          effectiveTime: now,
          expectedInstallationId: installationId,
        ),
        throwsA(isA<MaintenanceTokenException>().having((e) => e.code, 'code', 'INVALID_SIGNATURE')),
      );

      // 13.5 Tamper nonce
      expect(
        () => tokenSvc.verifyAndParseToken(
          rawToken: tamperClaim('nonce', 'FORGED-NONCE-999'),
          expectedHospitalCode: 'HOSP_CLOCK_A',
          effectiveTime: now,
          expectedInstallationId: installationId,
        ),
        throwsA(isA<MaintenanceTokenException>().having((e) => e.code, 'code', 'INVALID_SIGNATURE')),
      );
    });

    test('14. Session Expiration Invariant: Wall clock rollback CANNOT revive expired session', () async {
      simulatedTime = DateTime.utc(2026, 10, 27, 15, 0, 0);

      final staffRepo = StaffIdentityRepository(db);
      final staff = (await staffRepo.findByEmailOrCode('HOSP_CLOCK_A', 'youssef@clock-a.local'))!;

      final sessionRepo = AuthSessionRepository(db);
      final rawToken = 'mcd_${PasswordHasher.generateSecureToken(32)}';
      final tokenSha256 = PasswordHasher.sha256Hex(rawToken);

      await sessionRepo.createSession(
        sessionUuid: 'SES-TEST-TTL-5S',
        tokenSha256: tokenSha256,
        hospitalCode: 'HOSP_CLOCK_A',
        staffId: staff.identity.id,
        deviceId: 'DEV-CLOCK-01',
        roleSnapshot: 'HospitalAdmin',
        ttl: const Duration(seconds: 5),
        nowUtc: simulatedTime,
      );

      // Verify active at T0
      final activeCheck = await sessionRepo.findByTokenSha256(tokenSha256);
      expect(activeCheck!.isActive, isTrue);

      // Advance clock past TTL
      simulatedTime = DateTime.utc(2026, 10, 27, 15, 0, 10);
      final expiredResp = await http.get(
        Uri.parse('$baseUrl/api/v1/auth/me'),
        headers: {
          'authorization': 'Bearer $rawToken',
          'x-tenant-id': 'HOSP_CLOCK_A',
          'x-medcore-device-id': 'DEV-CLOCK-01',
        },
      );
      expect(expiredResp.statusCode, equals(401));
      expect(jsonDecode(expiredResp.body)['error']['code'], equals('SESSION_EXPIRED'));

      // MariaDB Read-back: session physically marked inactive
      final dbSession = await sessionRepo.findByTokenSha256(tokenSha256);
      expect(dbSession!.isActive, isFalse);

      // Attacker rewinds host wall clock
      simulatedTime = DateTime.utc(2026, 10, 27, 14, 59, 40);
      final tamperedResp = await http.get(
        Uri.parse('$baseUrl/api/v1/auth/me'),
        headers: {
          'authorization': 'Bearer $rawToken',
          'x-tenant-id': 'HOSP_CLOCK_A',
          'x-medcore-device-id': 'DEV-CLOCK-01',
        },
      );

      expect(tamperedResp.statusCode, isIn([401, 403]));
      final errorCode = jsonDecode(tamperedResp.body)['error']['code'];
      expect(errorCode, isIn(['INVALID_SESSION', 'SESSION_EXPIRED', 'CLOCK_ROLLBACK_DETECTED']));
    });

    test('15. Maintenance Reset Invariant: Resetting clock backwards revokes all active sessions to prevent revival', () async {
      simulatedTime = DateTime.utc(2026, 10, 27, 16, 0, 0);

      final staffRepo = StaffIdentityRepository(db);
      final staff = (await staffRepo.findByEmailOrCode('HOSP_CLOCK_A', 'youssef@clock-a.local'))!;

      final sessionRepo = AuthSessionRepository(db);
      final tokenS3 = 'mcd_${PasswordHasher.generateSecureToken(32)}';
      revokedTokenS3 = tokenS3;
      final tokenSha256S3 = PasswordHasher.sha256Hex(tokenS3);

      await sessionRepo.createSession(
        sessionUuid: 'SES-MAINT-REVOKE-01',
        tokenSha256: tokenSha256S3,
        hospitalCode: 'HOSP_CLOCK_A',
        staffId: staff.identity.id,
        deviceId: 'DEV-CLOCK-01',
        roleSnapshot: 'HospitalAdmin',
        ttl: const Duration(hours: 1),
        nowUtc: simulatedTime,
      );

      // Verify S3 active
      final beforeCheck = await sessionRepo.findByTokenSha256(tokenSha256S3);
      expect(beforeCheck!.isActive, isTrue);

      // Artificially advance clock to 18:00:00 (simulating forward clock jump defect)
      simulatedTime = DateTime.utc(2026, 10, 27, 18, 0, 0);
      await txManager.runInTransaction((tx) async {
        await clockRepoFor(tx).evaluateAndUpdateClock(
          hospitalCode: 'HOSP_CLOCK_A',
          currentWallClock: simulatedTime,
        );
      });

      // True time is 16:10:00. Technician applies authorized recovery token to reset clock backwards
      simulatedTime = DateTime.utc(2026, 10, 27, 16, 10, 0);
      final resetToken = authoritySigner.signToken(
        hospitalCode: 'HOSP_CLOCK_A',
        installationId: installationId,
        nonce: 'NONCE-BACKWARD-RESET-01',
        issuedAt: DateTime.utc(2026, 10, 27, 16, 0, 0),
        expiresAt: DateTime.utc(2026, 10, 27, 19, 0, 0),
      );

      final clockRepo = clockRepoFor(db);
      await clockRepo.unlockWithMaintenanceToken(
        hospitalCode: 'HOSP_CLOCK_A',
        rawMaintenanceToken: resetToken,
        currentWallClock: simulatedTime,
        expectedInstallationId: installationId,
        trustedTimeEvidence: trustedEvidence('HOSP_CLOCK_A', installationId, simulatedTime),
      );

      // INVARIANT: S3 must have been revoked by the backward reset
      final afterCheck = await sessionRepo.findByTokenSha256(tokenSha256S3);
      expect(afterCheck!.isActive, isFalse, reason: 'Active sessions MUST be revoked on backward clock reset');

      // Attempting to use S3 must fail with 401 INVALID_SESSION
      final resp = await http.get(
        Uri.parse('$baseUrl/api/v1/auth/me'),
        headers: {
          'authorization': 'Bearer $revokedTokenS3',
          'x-tenant-id': 'HOSP_CLOCK_A',
          'x-medcore-device-id': 'DEV-CLOCK-01',
        },
      );
      expect(resp.statusCode, equals(401));
      expect(jsonDecode(resp.body)['error']['code'], equals('INVALID_SESSION'));
    });

    test('16. Normal operations resume cleanly after authorized maintenance unlock', () async {
      simulatedTime = DateTime.utc(2026, 10, 27, 16, 15, 0);

      final loginResp = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/login'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': 'HOSP_CLOCK_A',
          'identifier': 'youssef@clock-a.local',
          'password': 'ClockPass#2026',
          'deviceId': 'DEV-CLOCK-01',
        }),
      );
      expect(loginResp.statusCode, equals(200));

      final newToken = jsonDecode(loginResp.body)['data']['token'] as String;

      final meResp = await http.get(
        Uri.parse('$baseUrl/api/v1/auth/me'),
        headers: {
          'authorization': 'Bearer $newToken',
          'x-tenant-id': 'HOSP_CLOCK_A',
          'x-medcore-device-id': 'DEV-CLOCK-01',
        },
      );
      expect(meResp.statusCode, equals(200));
      expect(jsonDecode(meResp.body)['data']['user']['email'], equals('youssef@clock-a.local'));

      final clockRepo = clockRepoFor(db);
      final guard = (await clockRepo.getClockGuard('HOSP_CLOCK_A'))!;
      expect(guard.rollbackDetected, isFalse);
      expect(clockRepo.verifyHmacSeal(guard), isTrue);
    });

    test('17. Formal Schema Migration V011 Verification: mc_consumed_maintenance_tokens and tenant uniqueness exist', () async {
      // Direct Schema Reification check
      final tableCheck = await db.execute(
        "SELECT TABLE_NAME, ENGINE FROM information_schema.TABLES WHERE TABLE_SCHEMA = :db AND TABLE_NAME = 'mc_consumed_maintenance_tokens'",
        {'db': testDbName},
      );
      expect(tableCheck.rows.isNotEmpty, isTrue);
      expect(tableCheck.rows.first.colByName('ENGINE'), equals('InnoDB'));

      // Check unique index on mc_consumed_maintenance_tokens (hospital_code, nonce)
      final indexCheck = await db.execute(
        "SHOW INDEX FROM mc_consumed_maintenance_tokens WHERE Key_name = 'uq_maint_token_nonce'",
      );
      expect(indexCheck.rows.isNotEmpty, isTrue);

      // Check unique index on mc_clock_guard (hospital_code)
      final guardIndexCheck = await db.execute(
        "SHOW INDEX FROM mc_clock_guard WHERE Key_name = 'uq_mc_clock_guard_hosp'",
      );
      expect(guardIndexCheck.rows.isNotEmpty, isTrue);
    });

    test('18. Adversarial Test F-01: Expired Maintenance Token Resurrection After Downtime Rollback Is Strictly Rejected', () async {
      final clockRepo = clockRepoFor(db);
      const hosp = 'HOSP_F01_ADV';
      final inst = installationId;

      // 1. Establish tenant with high-water H = 10:00:00 UTC
      final govRepo = TenantGovernanceRepository(db);
      await govRepo.upsertTenant(hospitalCode: hosp, name: 'F01 Test Hospital');
      final hTime = DateTime.utc(2026, 10, 27, 10, 0, 0);
      await txManager.runInTransaction((tx) async {
        await clockRepoFor(tx).evaluateAndUpdateClock(
          hospitalCode: hosp,
          currentWallClock: hTime,
          eventUuid: 'BOOT-PROCESS-1',
        );
      });

      // Verify high-water H in MariaDB
      final initialGuard = (await clockRepo.getClockGuard(hosp))!;
      expect(initialGuard.maxObservedUtc, equals(hTime));

      // 2. Token expires at E = 11:00:00 UTC (issued at 10:05:00)
      final tokenNonce = 'NONCE-F01-EXPIRED-${DateTime.now().millisecondsSinceEpoch}';
      final expiredToken = authoritySigner.signToken(
        hospitalCode: hosp,
        installationId: inst,
        nonce: tokenNonce,
        issuedAt: DateTime.utc(2026, 10, 27, 10, 5, 0),
        expiresAt: DateTime.utc(2026, 10, 27, 11, 0, 0),
      );

      // 3. Process stops (simulating shutdown)
      // 4. Real physical time advances beyond E (e.g. 12:30:00 UTC, token is physically expired in reality)
      // 5. Machine restarts with CMOS wall clock between H and E (e.g. 10:50:00 UTC)
      final bootedWallClock = DateTime.utc(2026, 10, 27, 10, 50, 0);

      // 6. Token submitted through real recovery path across downtime restart:
      // Without verified time authority (offline downtime), it must FAIL CLOSED with UNTRUSTED_DOWNTIME_CLOCK
      expect(
        () async => await clockRepo.unlockWithMaintenanceToken(
          hospitalCode: hosp,
          rawMaintenanceToken: expiredToken,
          currentWallClock: bootedWallClock,
          expectedInstallationId: inst,
        ),
        throwsA(isA<MaintenanceTokenException>().having(
          (e) => e.code,
          'code',
          'UNTRUSTED_DOWNTIME_CLOCK',
        )),
      );

      // With a trusted time authority reporting real physical time (12:30:00 UTC), it must reject as TOKEN_EXPIRED
      final realPhysicalTime = DateTime.utc(2026, 10, 27, 12, 30, 0);
      expect(
        () async => await clockRepo.unlockWithMaintenanceToken(
          hospitalCode: hosp,
          rawMaintenanceToken: expiredToken,
          currentWallClock: realPhysicalTime,
          expectedInstallationId: inst,
          trustedTimeEvidence: trustedEvidence(hosp, inst, realPhysicalTime),
        ),
        throwsA(isA<MaintenanceTokenException>().having(
          (e) => e.code,
          'code',
          'TOKEN_EXPIRED',
        )),
      );

      // Physical MariaDB Read-Back Verification:
      // Assert nonce was NEVER consumed in MariaDB
      final consumedCheck = await db.execute(
        'SELECT COUNT(*) as c FROM mc_consumed_maintenance_tokens WHERE hospital_code = :h AND nonce = :n',
        {'h': hosp, 'n': tokenNonce},
      );
      expect(int.parse(consumedCheck.rows.first.colByName('c') ?? '0'), equals(0));

      // Assert clock guard remained untouched at H (10:00:00 UTC)
      final readBackGuard = (await clockRepo.getClockGuard(hosp))!;
      expect(readBackGuard.maxObservedUtc, equals(hTime));
      expect(readBackGuard.unlockedByMaintenanceTokenId, isNull);
    });

    test('19. Adversarial Test F-02: Clock-Guard Row Deletion on Zero-Session / Zero-Login Tenant Fails Closed via Immutable Anchor', () async {
      const hosp = 'HOSP_F02_ADV';
      final govRepo = TenantGovernanceRepository(db);

      // 1. Establish tenant clock
      await govRepo.upsertTenant(hospitalCode: hosp, name: 'F02 Zero Session Hospital');
      final baseTime = DateTime.utc(2026, 10, 27, 12, 0, 0);
      await txManager.runInTransaction((tx) async {
        await clockRepoFor(tx).evaluateAndUpdateClock(
          hospitalCode: hosp,
          currentWallClock: baseTime,
        );
      });

      // Verify clock_guard_initialized_at is permanently set in mc_tenants
      final tenantCheck = await db.execute(
        'SELECT clock_guard_initialized_at FROM mc_tenants WHERE hospital_code = :h',
        {'h': hosp},
      );
      expect(tenantCheck.rows.first.colByName('clock_guard_initialized_at'), isNotNull);

      // 2. Ensure zero sessions exist
      final sessionCheck = await db.execute(
        'SELECT COUNT(*) as c FROM mc_auth_sessions WHERE hospital_code = :h',
        {'h': hosp},
      );
      expect(int.parse(sessionCheck.rows.first.colByName('c') ?? '0'), equals(0));

      // 3. Ensure zero staff login history exists (or staff with last_login_at = NULL)
      await db.execute('''
        INSERT INTO mc_staff (
          hospital_code, staff_code, full_name, email, password_hash, role, is_active, last_login_at, created_at, updated_at
        ) VALUES (
          :h, 'STF-F02-ZERO', 'Dr. Zero Sessions', 'zero@f02.local', 'HASH123', 'Doctor', 1, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        )
      ''', {'h': hosp});

      // 4. Adversarially delete mc_clock_guard row directly from MariaDB
      await db.execute('DELETE FROM mc_clock_guard WHERE hospital_code = :h', {'h': hosp});
      await db.execute('DELETE FROM mc_security_root WHERE hospital_code = :h', {'h': hosp});
      await db.execute('UPDATE mc_tenants SET clock_guard_initialized_at = NULL WHERE hospital_code = :h', {'h': hosp});
      final protectedAnchor = await db.execute(
        'SELECT clock_guard_initialized_at FROM mc_tenants WHERE hospital_code = :h',
        {'h': hosp},
      );
      expect(protectedAnchor.rows.first.colByName('clock_guard_initialized_at'), isNotNull,
          reason: 'V013 database trigger must prevent resetting the V012 initialization anchor.');
      final guardCheck = await db.execute('SELECT COUNT(*) as c FROM mc_clock_guard WHERE hospital_code = :h', {'h': hosp});
      expect(int.parse(guardCheck.rows.first.colByName('c') ?? '0'), equals(0));

      // 5. Restart process / fresh evaluation submitting a rolled back time (e.g. 2020-01-01)
      final rolledBackClock = DateTime.utc(2020, 1, 1, 0, 0, 0);

      // 6. Expected: MUST FAIL CLOSED with ClockTamperException (cannot recreate baseline)
      expect(
        () async => await txManager.runInTransaction((tx) async {
          return await clockRepoFor(tx).evaluateAndUpdateClock(
            hospitalCode: hosp,
            currentWallClock: rolledBackClock,
          );
        }),
        throwsA(isA<ClockTamperException>().having(
          (e) => e.message,
          'message',
          contains('Security root'),
        )),
      );

      // MariaDB Read-Back: Assert NO new row was created in mc_clock_guard at 2020-01-01
      final finalGuardCheck = await db.execute('SELECT COUNT(*) as c FROM mc_clock_guard WHERE hospital_code = :h', {'h': hosp});
      expect(int.parse(finalGuardCheck.rows.first.colByName('c') ?? '0'), equals(0));
    });

    test('20. Adversarial Test F-03: Process Lifecycle Restart Boundary Enforces Fail-Closed Security Time Without Pseudo-Monotonic Claims', () async {
      const hosp = 'HOSP_F03_ADV';
      final govRepo = TenantGovernanceRepository(db);
      await govRepo.upsertTenant(hospitalCode: hosp, name: 'F03 Monotonic Architecture Hospital');

      // 1. Same-process monotonic progression:
      final t1 = DateTime.utc(2026, 10, 27, 10, 0, 0);
      final res1 = await txManager.runInTransaction((tx) async {
        return await clockRepoFor(tx).evaluateAndUpdateClock(
          hospitalCode: hosp,
          currentWallClock: t1,
        );
      });
      expect(res1.record.rollbackDetected, isFalse);
      expect(res1.record.lastBootMonotonicMs, isNonNegative);

      // 2. Process lifecycle boundary & wall rollback:
      // If host clock rolls backwards within same process beyond tolerance (e.g. 1 hour back)
      final rolledBackTime = DateTime.utc(2026, 10, 27, 9, 0, 0);
      final res2 = await txManager.runInTransaction((tx) async {
        return await clockRepoFor(tx).evaluateAndUpdateClock(
          hospitalCode: hosp,
          currentWallClock: rolledBackTime,
        );
      });
      expect(res2.rollbackDetected, isTrue);
      expect(res2.effectiveTime, equals(t1)); // Effective security time held at high-water mark

      // 3. Process restart boundary:
      // A fresh process instance starts with a new boot UUID.
      // The system explicitly rejects cross-boot monotonic claims and requires verified time across downtime.
      final clockRepo = clockRepoFor(db);
      final tokenNonce = 'NONCE-F03-TEST-${DateTime.now().millisecondsSinceEpoch}';
      final testToken = authoritySigner.signToken(
        hospitalCode: hosp,
        installationId: installationId,
        nonce: tokenNonce,
        issuedAt: t1,
        expiresAt: t1.add(const Duration(hours: 1)),
      );

      // Across unverified downtime restart, recovery FAILS CLOSED
      expect(
        () async => await clockRepo.unlockWithMaintenanceToken(
          hospitalCode: hosp,
          rawMaintenanceToken: testToken,
          currentWallClock: rolledBackTime,
          expectedInstallationId: installationId,
        ),
        throwsA(isA<MaintenanceTokenException>().having(
          (e) => e.code,
          'code',
          'UNTRUSTED_DOWNTIME_CLOCK',
        )),
      );
    });

    test('21. Adversarial Test F-04: Full ACID Transaction Atomicity and Rollback Proof During Maintenance Recovery Failure', () async {
      const hosp = 'HOSP_F04_ADV';
      final govRepo = TenantGovernanceRepository(db);
      await govRepo.upsertTenant(hospitalCode: hosp, name: 'F04 Transaction Hospital');

      // Establish locked clock state
      final tLock = DateTime.utc(2026, 10, 27, 10, 0, 0);
      await txManager.runInTransaction((tx) async {
        await clockRepoFor(tx).evaluateAndUpdateClock(
          hospitalCode: hosp,
          currentWallClock: tLock,
        );
        // Force rollback lock
        await clockRepoFor(tx).evaluateAndUpdateClock(
          hospitalCode: hosp,
          currentWallClock: tLock.subtract(const Duration(hours: 1)),
        );
      });

      final guardBefore = (await clockRepoFor(db).getClockGuard(hosp))!;
      expect(guardBefore.rollbackDetected, isTrue);

      // Mint valid token
      final tokenNonce = 'NONCE-F04-ATOMIC-${DateTime.now().millisecondsSinceEpoch}';
      final validToken = authoritySigner.signToken(
        hospitalCode: hosp,
        installationId: installationId,
        nonce: tokenNonce,
        issuedAt: tLock,
        expiresAt: tLock.add(const Duration(hours: 2)),
      );

      // Simulate transactional failure injection:
      // Inside a transaction, simulate failure after nonce insertion before commit
      try {
        await txManager.runInTransaction((tx) async {
          // Step 1: Insert nonce into mc_consumed_maintenance_tokens
          await tx.execute('''
            INSERT INTO mc_consumed_maintenance_tokens (
              hospital_code, installation_id, nonce, action, consumed_at_utc
            ) VALUES (
              :hosp, 'INST-DESKTOP-01', :nonce, 'UNLOCK_CLOCK_ROLLBACK', CURRENT_TIMESTAMP(3)
            )
          ''', {'hosp': hosp, 'nonce': tokenNonce});

          // Step 2: Inject simulated process/database crash before clock update
          throw StateError('SIMULATED_FAILURE_AFTER_NONCE_INSERTION');
        });
      } catch (e) {
        expect(e, isA<StateError>());
      }

      // PHYSICAL MARIADB PROOF: Entire transaction rolled back!
      // 1. Nonce was NOT consumed in MariaDB:
      final nonceRes = await db.execute(
        'SELECT COUNT(*) as c FROM mc_consumed_maintenance_tokens WHERE hospital_code = :h AND nonce = :nonce',
        {'h': hosp, 'nonce': tokenNonce},
      );
      expect(int.parse(nonceRes.rows.first.colByName('c') ?? '0'), equals(0));

      // 2. Clock guard is STILL in its original locked state:
      final guardAfterCrash = (await clockRepoFor(db).getClockGuard(hosp))!;
      expect(guardAfterCrash.rollbackDetected, isTrue);
      expect(guardAfterCrash.unlockedByMaintenanceTokenId, isNull);

      // 3. RETRY WITH THE SAME MAINTENANCE TOKEN:
      // Because the transaction rolled back completely, the token remains 100% usable!
      final recoveredRecord = await clockRepoFor(db).unlockWithMaintenanceToken(
        hospitalCode: hosp,
        rawMaintenanceToken: validToken,
        currentWallClock: tLock.add(const Duration(minutes: 10)),
        expectedInstallationId: installationId,
        trustedTimeEvidence: trustedEvidence(hosp, installationId, tLock.add(const Duration(minutes: 10))),
      );

      // Verification after successful retry:
      expect(recoveredRecord.rollbackDetected, isFalse);
      expect(recoveredRecord.unlockedByMaintenanceTokenId, equals(tokenNonce));

      // Nonce is now committed:
      final nonceCommitted = await db.execute(
        'SELECT COUNT(*) as c FROM mc_consumed_maintenance_tokens WHERE hospital_code = :h AND nonce = :nonce',
        {'h': hosp, 'nonce': tokenNonce},
      );
      expect(int.parse(nonceCommitted.rows.first.colByName('c') ?? '0'), equals(1));

      // Audit log was committed in the same ACID transaction:
      final auditRes = await db.execute(
        "SELECT * FROM mc_audit_logs WHERE hospital_code = :h AND correlation_id = :nonce AND action = 'MAINTENANCE_CLOCK_RECOVERY_APPLIED'",
        {'h': hosp, 'nonce': tokenNonce},
      );
      expect(auditRes.rows.isNotEmpty, isTrue);
    });

    test('22. Recovery failpoints after nonce, session, clock and audit rollback every write and permit retry', () async {
      final staff = (await StaffIdentityRepository(db).findByEmailOrCode('HOSP_CLOCK_A', 'youssef@clock-a.local'))!;
      final failpoints = <String, String>{
        'nonce': '''CREATE TRIGGER trg_test_fail_nonce AFTER INSERT ON mc_consumed_maintenance_tokens FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'INJECT_AFTER_NONCE' ''',
        'session': '''CREATE TRIGGER trg_test_fail_session AFTER UPDATE ON mc_auth_sessions FOR EACH ROW BEGIN IF OLD.hospital_code LIKE 'HOSP_ATOMIC_%' AND OLD.is_active = 1 AND NEW.is_active = 0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'INJECT_AFTER_SESSION_REVOKE'; END IF; END''',
        'clock': '''CREATE TRIGGER trg_test_fail_clock AFTER UPDATE ON mc_clock_guard FOR EACH ROW BEGIN IF OLD.hospital_code LIKE 'HOSP_ATOMIC_%' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'INJECT_AFTER_CLOCK_UPDATE'; END IF; END''',
        'audit': '''CREATE TRIGGER trg_test_fail_audit AFTER INSERT ON mc_audit_logs FOR EACH ROW BEGIN IF NEW.action = 'MAINTENANCE_CLOCK_RECOVERY_APPLIED' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'INJECT_AFTER_AUDIT_INSERT'; END IF; END''',
      };

      var index = 0;
      for (final entry in failpoints.entries) {
        index++;
        final hospital = 'HOSP_ATOMIC_$index';
        final nonce = 'NONCE-ATOMIC-$index-${DateTime.now().microsecondsSinceEpoch}';
        final tLock = DateTime.utc(2026, 10, 27, 17, index, 0);
        final tRecovery = tLock.subtract(const Duration(minutes: 1));
        await TenantGovernanceRepository(db).upsertTenant(hospitalCode: hospital, name: 'Atomic failpoint $index');
        await txManager.runInTransaction((tx) async {
          await clockRepoFor(tx).evaluateAndUpdateClock(hospitalCode: hospital, currentWallClock: tLock);
          await clockRepoFor(tx).evaluateAndUpdateClock(
            hospitalCode: hospital,
            currentWallClock: tLock.subtract(const Duration(hours: 1)),
          );
        });
        final sessionUuid = 'SES-ATOMIC-$index';
        final sessionToken = 'ATOMIC-TOKEN-$index-${DateTime.now().microsecondsSinceEpoch}';
        await AuthSessionRepository(db).createSession(
          sessionUuid: sessionUuid,
          tokenSha256: PasswordHasher.sha256Hex(sessionToken),
          hospitalCode: hospital,
          staffId: staff.identity.id,
          deviceId: 'DEV-CLOCK-01',
          roleSnapshot: 'HospitalAdmin',
          nowUtc: tLock,
        );
        final token = authoritySigner.signToken(
          hospitalCode: hospital,
          installationId: installationId,
          nonce: nonce,
          issuedAt: tRecovery.subtract(const Duration(minutes: 1)),
          expiresAt: tRecovery.add(const Duration(hours: 1)),
        );
        final evidence = trustedEvidence(hospital, installationId, tRecovery);

        await db.execute(entry.value);
        try {
          await expectLater(
            clockRepoFor(db).unlockWithMaintenanceToken(
              hospitalCode: hospital,
              rawMaintenanceToken: token,
              expectedInstallationId: installationId,
              trustedTimeEvidence: evidence,
            ),
            throwsA(anything),
          );
        } finally {
          await db.execute('DROP TRIGGER IF EXISTS trg_test_fail_${entry.key}');
        }

        final nonceAfterFailure = await db.execute(
          'SELECT COUNT(*) AS c FROM mc_consumed_maintenance_tokens WHERE hospital_code = :h AND nonce = :n',
          {'h': hospital, 'n': nonce},
        );
        expect(int.parse(nonceAfterFailure.rows.first.colByName('c') ?? '0'), 0, reason: '${entry.key}: nonce must roll back');
        final guardAfterFailure = (await clockRepoFor(db).getClockGuard(hospital))!;
        expect(guardAfterFailure.maxObservedUtc, tLock, reason: '${entry.key}: clock state must roll back');
        expect(guardAfterFailure.rollbackDetected, isTrue, reason: '${entry.key}: lock state must roll back');
        final sessionAfterFailure = (await AuthSessionRepository(db).findByTokenSha256(PasswordHasher.sha256Hex(sessionToken)))!;
        expect(sessionAfterFailure.isActive, isTrue, reason: '${entry.key}: session changes must roll back');
        final auditAfterFailure = await db.execute(
          "SELECT COUNT(*) AS c FROM mc_audit_logs WHERE hospital_code = :h AND correlation_id = :n AND action = 'MAINTENANCE_CLOCK_RECOVERY_APPLIED'",
          {'h': hospital, 'n': nonce},
        );
        expect(int.parse(auditAfterFailure.rows.first.colByName('c') ?? '0'), 0, reason: '${entry.key}: audit must roll back');

        final recovered = await clockRepoFor(db).unlockWithMaintenanceToken(
          hospitalCode: hospital,
          rawMaintenanceToken: token,
          expectedInstallationId: installationId,
          trustedTimeEvidence: evidence,
        );
        expect(recovered.rollbackDetected, isFalse);
        final nonceAfterRetry = await db.execute(
          'SELECT COUNT(*) AS c FROM mc_consumed_maintenance_tokens WHERE hospital_code = :h AND nonce = :n',
          {'h': hospital, 'n': nonce},
        );
        expect(int.parse(nonceAfterRetry.rows.first.colByName('c') ?? '0'), 1);
        final sessionAfterRetry = (await AuthSessionRepository(db).findByTokenSha256(PasswordHasher.sha256Hex(sessionToken)))!;
        expect(sessionAfterRetry.isActive, isFalse);
      }
    });

    test('23. Forged authority evidence, production key separation, malformed claims and autocommit fallback are rejected', () async {
      final productionTimeVerifier = TrustedTimeVerifier.production();
      final productionChallenge = productionTimeVerifier.createChallenge(
        hospitalCode: 'HOSP_CLOCK_A',
        installationId: installationId,
      );
      final testSignedAsProduction = timeAuthoritySigner.signTimeResponse(
        authorityId: productionTimeVerifier.authorityId,
        hospitalCode: 'HOSP_CLOCK_A',
        installationId: installationId,
        nonce: productionChallenge.nonce,
        trustedUtc: DateTime.utc(2026, 10, 27, 18, 0),
      );
      expect(
        () => productionTimeVerifier.verifyResponse(challenge: productionChallenge, rawResponse: testSignedAsProduction),
        throwsA(isA<TrustedTimeEvidenceException>().having((e) => e.code, 'code', 'INVALID_TIME_SIGNATURE')),
      );

      final forgedChallenge = timeVerifier.createChallenge(hospitalCode: 'HOSP_CLOCK_A', installationId: installationId);
      final goodResponse = timeAuthoritySigner.signTimeResponse(
        authorityId: timeVerifier.authorityId,
        hospitalCode: 'HOSP_CLOCK_A',
        installationId: installationId,
        nonce: forgedChallenge.nonce,
        trustedUtc: DateTime.utc(2026, 10, 27, 18, 0),
      );
      final alteredResponse = '${goodResponse.substring(0, goodResponse.length - 1)}${goodResponse.endsWith('A') ? 'B' : 'A'}';
      expect(
        () => timeVerifier.verifyResponse(challenge: forgedChallenge, rawResponse: alteredResponse),
        throwsA(isA<TrustedTimeEvidenceException>()),
      );

      final testToken = authoritySigner.signToken(
        hospitalCode: 'HOSP_CLOCK_A',
        installationId: installationId,
        nonce: 'NONCE-TEST-KEY-PRODUCTION-REJECT',
        issuedAt: DateTime.utc(2026, 10, 27, 18, 0),
        expiresAt: DateTime.utc(2026, 10, 27, 19, 0),
      );
      final productionTokenVerifier = MaintenanceTokenService();
      expect(productionTokenVerifier.modulus, isNot(authoritySigner.modulus));
      expect(
        () => productionTokenVerifier.verifyAndParseToken(
          rawToken: testToken,
          expectedHospitalCode: 'HOSP_CLOCK_A',
          expectedInstallationId: installationId,
        ),
        throwsA(isA<MaintenanceTokenException>().having((e) => e.code, 'code', 'INVALID_SIGNATURE')),
      );

      final testTokenVerifier = MaintenanceTokenService(
        modulus: authoritySigner.modulus,
        publicExponent: authoritySigner.publicExponent,
      );
      final missingExp = authoritySigner.signPayload({
        'v': 1,
        'tid': 'MISSING-EXP',
        'hosp': 'HOSP_CLOCK_A',
        'inst': installationId,
        'act': 'UNLOCK_CLOCK_ROLLBACK',
        'nonce': 'N-MISSING-EXP',
        'iat': '2026-10-27T18:00:00Z',
      });
      expect(
        () => testTokenVerifier.verifyAndParseToken(
          rawToken: missingExp,
          expectedHospitalCode: 'HOSP_CLOCK_A',
          expectedInstallationId: installationId,
        ),
        throwsA(isA<MaintenanceTokenException>().having((e) => e.code, 'code', 'INVALID_EXP')),
      );
      final malformedIat = authoritySigner.signPayload({
        'v': 1,
        'tid': 'MALFORMED-IAT',
        'hosp': 'HOSP_CLOCK_A',
        'inst': installationId,
        'act': 'UNLOCK_CLOCK_ROLLBACK',
        'nonce': 'N-MALFORMED-IAT',
        'iat': 'not-a-time',
        'exp': '2026-10-27T19:00:00Z',
      });
      expect(
        () => testTokenVerifier.verifyAndParseToken(
          rawToken: malformedIat,
          expectedHospitalCode: 'HOSP_CLOCK_A',
          expectedInstallationId: installationId,
        ),
        throwsA(isA<MaintenanceTokenException>().having((e) => e.code, 'code', 'INVALID_IAT')),
      );

      final connection = await db.openDedicatedConnection();
      try {
        final nonTransactionalRepo = ClockGuardRepository(DbConnectionWrapper(connection));
        expect(
          () => nonTransactionalRepo.unlockWithMaintenanceToken(
            hospitalCode: 'HOSP_CLOCK_A',
            rawMaintenanceToken: testToken,
            expectedInstallationId: installationId,
            trustedTimeEvidence: trustedEvidence('HOSP_CLOCK_A', installationId, DateTime.utc(2026, 10, 27, 18, 0)),
          ),
          throwsA(isA<StateError>()),
        );
      } finally {
        await connection.close();
      }
      final nonceAfterRejectedExecutor = await db.execute(
        'SELECT COUNT(*) AS c FROM mc_consumed_maintenance_tokens WHERE hospital_code = :h AND nonce = :n',
        {'h': 'HOSP_CLOCK_A', 'n': 'NONCE-TEST-KEY-PRODUCTION-REJECT'},
      );
      expect(int.parse(nonceAfterRejectedExecutor.rows.first.colByName('c') ?? '0'), 0);
    });

    test('24. Formal Schema Migration V012 Verification: mc_tenants.clock_guard_initialized_at reified in MariaDB', () async {
      // Check column exists in information_schema
      final colCheck = await db.execute('''
        SELECT COLUMN_NAME, DATA_TYPE
        FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = :db AND TABLE_NAME = 'mc_tenants' AND COLUMN_NAME = 'clock_guard_initialized_at'
      ''', {'db': testDbName});

      expect(colCheck.rows.isNotEmpty, isTrue);
      expect(colCheck.rows.first.colByName('DATA_TYPE'), equals('datetime'));

      // Check mc_schema_migrations records V012
      final migCheck = await db.execute(
        "SELECT version, description FROM mc_schema_migrations WHERE version = 'V012'",
      );
      expect(migCheck.rows.isNotEmpty, isTrue);

      final rootTable = await db.execute(
        "SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA = :db AND TABLE_NAME = 'mc_security_root'",
        {'db': testDbName},
      );
      expect(rootTable.rows.isNotEmpty, isTrue);
      final processColumn = await db.execute(
        "SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = :db AND TABLE_NAME = 'mc_clock_guard' AND COLUMN_NAME = 'process_boot_id'",
        {'db': testDbName},
      );
      expect(processColumn.rows.isNotEmpty, isTrue);
      final anchorTrigger = await db.execute(
        "SELECT TRIGGER_NAME FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = :db AND TRIGGER_NAME = 'trg_mc_tenants_clock_anchor_immutable'",
        {'db': testDbName},
      );
      expect(anchorTrigger.rows.isNotEmpty, isTrue);
      final migration14 = await db.execute("SELECT version FROM mc_schema_migrations WHERE version = 'V014'");
      expect(migration14.rows.isNotEmpty, isTrue);
    });
  });
}
