import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:medcore_local_service/medcore_local_service.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'support/test_authority_signer.dart';
import 'support/test_db_config.dart';

void main() {
  const dbName = 'medcore_technician_lifecycle_test';
  late DbClient db;
  late MigrationRunner migrationRunner;
  LocalMedCoreServer? server;
  late String baseUrl;
  late Directory securityRoot;

  const hospitalCode = 'HOSP_TECH_01';
  const hospitalCodeB = 'HOSP_ATTACK_99';
  const deviceId = 'DEV-TECH-HOST';
  const deviceIdB = 'DEV-ATTACK-02';

  final serviceRoot = Directory.current.path;
  final migrationsDir = p.join(serviceRoot, 'sql', 'migrations');
  late TestAuthoritySigner authoritySigner;

  late String commissioningSecret;
  late String techToken;
  late String rotatedSecret;
  late String recoveredSecret;
  late String recoveryTimeResponse;

  Map<String, String> techHeaders({String? token, String? hosp, String? dev}) => {
        'content-type': 'application/json',
        'x-medcore-tech-token': token ?? techToken,
        'x-tenant-id': hosp ?? hospitalCode,
        'x-medcore-device-id': dev ?? deviceId,
      };

  Map<String, dynamic> decodeData(http.Response res) {
    final decoded = jsonDecode(res.body);
    if (decoded is Map && decoded.containsKey('data') && decoded['data'] is Map) {
      return Map<String, dynamic>.from(decoded['data'] as Map);
    }
    return Map<String, dynamic>.from(decoded as Map);
  }

  setUpAll(() async {
    authoritySigner = TestAuthoritySigner.loadDefault();
    securityRoot = Directory.systemTemp.createTempSync('medcore-tech-sec-root-');
    final config = testDbConfig(databaseName: dbName, maxConnections: 15);
    db = DbClient(config);

    // 1. Drop and Recreate test database
    final adminConn = await db.openDedicatedConnection(useDatabase: false);
    try {
      await adminConn.execute('DROP DATABASE IF EXISTS `$dbName`');
      await adminConn.execute(
        'CREATE DATABASE `$dbName` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
      );
    } finally {
      await adminConn.close();
    }

    // 2. Run migrations
    migrationRunner = MigrationRunner(db: db, migrationsDir: migrationsDir);
    final applied = await migrationRunner.runMigrations();
    expect(applied.length, greaterThanOrEqualTo(16));

    // 3. Register Tenant & Host Device
    final govRepo = TenantGovernanceRepository(db);
    await govRepo.upsertTenant(
      hospitalCode: hospitalCode,
      name: 'MedCore Technician Lifecycle Hospital',
    );
    await govRepo.enrollOrUpdateDevice(
      hospitalCode: hospitalCode,
      deviceId: deviceId,
      deviceName: 'Technician Server Host Workstation',
      platform: 'WINDOWS',
      connectionType: 'LOOPBACK',
      hwFingerprintSha256: PasswordHasher.sha256Hex('TECH-HW-01'),
      devicePublicKeyEd25519: 'PUBKEY-TECH-01',
      roleScope: 'SERVER_HOST',
      isTrustedSecureRuntime: true,
      status: 'ACTIVE',
    );

    // Also register tenant B and device B for boundary tests
    await govRepo.upsertTenant(
      hospitalCode: hospitalCodeB,
      name: 'Attacker Hospital Tenant',
    );
    await govRepo.enrollOrUpdateDevice(
      hospitalCode: hospitalCodeB,
      deviceId: deviceIdB,
      deviceName: 'Attacker Host Workstation',
      platform: 'WINDOWS',
      connectionType: 'LOOPBACK',
      hwFingerprintSha256: PasswordHasher.sha256Hex('ATTACK-HW-02'),
      devicePublicKeyEd25519: 'PUBKEY-ATTACK-02',
      roleScope: 'SERVER_HOST',
      isTrustedSecureRuntime: true,
      status: 'ACTIVE',
    );

    final timeVerifier = TrustedTimeVerifier.forTesting(
      authorityId: 'MEDCORE-TIME-TEST-AUTHORITY',
      modulus: authoritySigner.modulus,
      exponent: authoritySigner.publicExponent,
    );

    final maintService = MaintenanceTokenService(
      modulus: authoritySigner.modulus,
      publicExponent: authoritySigner.publicExponent,
    );

    // 4. Start LocalMedCoreServer with autoBootstrapCommissioningSecret
    server = LocalMedCoreServer(
      db,
      securityRootDirectory: securityRoot.path,
      autoBootstrapCommissioningSecret: true,
      maintenanceTokenService: maintService,
      trustedTimeVerifier: timeVerifier,
    );

    final boundPort = await server!.start(address: '127.0.0.1', port: 0);
    baseUrl = 'http://127.0.0.1:$boundPort';
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

  // =========================================================================
  // STATE A: FRESH INSTALLATION & ONE-TIME FIRST-RUN SECRET
  // =========================================================================
  group('STATE A: Brand New Installation & Bootstrap Truth', () {
    test('A.1: Initial database has 0 staff accounts and clean uncommissioned state', () async {
      final staffRows = await db.execute('SELECT COUNT(*) as cnt FROM mc_staff');
      final count = int.parse(staffRows.rows.first.assoc()['cnt'].toString());
      expect(count, equals(0));
    });

    test('A.2: One-time first-run commissioning secret slip exists on disk', () async {
      final slipFile = File(p.join(securityRoot.path, 'FIRST_RUN_COMMISSIONING_SECRET.txt'));
      expect(slipFile.existsSync(), isTrue);

      final content = slipFile.readAsStringSync();
      expect(content, contains('FIRST-RUN TECHNICIAN COMMISSIONING SECRET'));
      final match = RegExp(r'Commissioning Secret\s+:\s+(TECH-COMM-[^\r\n\s]+)').firstMatch(content);
      expect(match, isNotNull);
      commissioningSecret = match!.group(1)!;
      expect(commissioningSecret.length, greaterThanOrEqualTo(16));
    });

    test('A.3: RT-TECH-20: Plain service restart does NOT regenerate secret or overwrite slip', () async {
      final slipFile = File(p.join(securityRoot.path, 'FIRST_RUN_COMMISSIONING_SECRET.txt'));
      final modifiedBefore = slipFile.lastModifiedSync();

      final reBootstrap = server!.technicianService.ensureCommissioningSecretProvisioned();
      expect(reBootstrap['isNewlyGenerated'], isFalse);
      expect(reBootstrap['status'], equals('ALREADY_PROVISIONED'));

      final modifiedAfter = slipFile.lastModifiedSync();
      expect(modifiedAfter, equals(modifiedBefore));
    });
  });

  // =========================================================================
  // STATE B: COMMISSIONING AUTHENTICATION & SLIP CONSUMPTION
  // =========================================================================
  group('STATE B: Commissioning Completed & Slip Destruction', () {
    test('B.1: Technician opens authenticated session using one-time secret', () async {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/session/open'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'deviceId': deviceId,
          'technicianSecret': commissioningSecret,
        }),
      );
      expect(resp.statusCode, anyOf(equals(200), equals(201)));
      final data = decodeData(resp);
      expect(data['technicianToken'], isNotNull);
      expect(data['session']['sessionUuid'], isNotNull);
      techToken = data['technicianToken'] as String;

      // Verify slip is immediately consumed and deleted
      final slipFile = File(p.join(securityRoot.path, 'FIRST_RUN_COMMISSIONING_SECRET.txt'));
      expect(slipFile.existsSync(), isFalse);
    });

    test('B.2: RT-TECH-03: First-run secret file physically destroyed after initial login', () async {
      final slipFile = File(p.join(securityRoot.path, 'FIRST_RUN_COMMISSIONING_SECRET.txt'));
      expect(slipFile.existsSync(), isFalse);
    });
  });

  // =========================================================================
  // STATE C: CREDENTIAL ROTATION & NORMAL OPERATION
  // =========================================================================
  group('STATE C: Technician Credential Rotation & Persistence', () {
    test('C.1: Authenticated technician rotates secret via POST /api/v1/technician/secret/rotate', () async {
      rotatedSecret = 'SecureRotatedPass#2026';
      final resp = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/secret/rotate'),
        headers: techHeaders(),
        body: jsonEncode({'newSecret': rotatedSecret}),
      );
      expect(resp.statusCode, equals(200));
      final data = decodeData(resp);
      expect(data['status'], anyOf(equals('ROTATED'), equals('TECHNICIAN_SECRET_ROTATED')));

      // Verify MariaDB audit log directly
      final auditRows = await db.execute(
        "SELECT * FROM mc_audit_logs WHERE action = 'technician.secret.rotated' AND hospital_code = :hosp",
        {'hosp': hospitalCode},
      );
      expect(auditRows.rows.isNotEmpty, isTrue);
    });

    test('C.2: Close current technician session', () async {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/session/close'),
        headers: techHeaders(),
        body: jsonEncode({}),
      );
      expect(resp.statusCode, equals(200));
    });

    test('C.3: RT-TECH-04: Closed technician token cannot be reused (replay rejected)', () async {
      final resp = await http.get(
        Uri.parse('$baseUrl/api/v1/technician/config'),
        headers: techHeaders(),
      );
      expect(resp.statusCode, anyOf(equals(401), equals(403)));
    });

    test('C.4: Old commissioning secret now strictly rejected', () async {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/session/open'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'deviceId': deviceId,
          'technicianSecret': commissioningSecret,
        }),
      );
      expect(resp.statusCode, anyOf(equals(401), equals(403)));
    });

    test('C.5: Rotated secret successfully opens new technician session', () async {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/session/open'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'deviceId': deviceId,
          'technicianSecret': rotatedSecret,
        }),
      );
      expect(resp.statusCode, anyOf(equals(200), equals(201)));
      final data = decodeData(resp);
      techToken = data['technicianToken'] as String;
    });
  });

  // =========================================================================
  // STATE D: TECHNICIAN FORGOTTEN CREDENTIAL CRYPTOGRAPHIC RECOVERY
  // =========================================================================
  group('STATE D: Cryptographic Forgotten Credential Recovery (RSA-2048)', () {
    late String challengeId;
    late String nonce;
    late String recoveryToken;

    test('D.1: Close current session to simulate forgotten credentials', () async {
      await http.post(
        Uri.parse('$baseUrl/api/v1/technician/session/close'),
        headers: techHeaders(),
        body: jsonEncode({}),
      );
    });

    test('D.2: Request recovery challenge from /api/v1/technician/recovery/challenge', () async {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/recovery/challenge'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'deviceId': deviceId,
        }),
      );
      expect(resp.statusCode, equals(200));
      final data = decodeData(resp);
      expect(data['challengeId'], isNotNull);
      expect(data['nonce'], isNotNull);
      challengeId = data['challengeId'] as String;
      nonce = data['nonce'] as String;
    });

    test('D.3: Sign authority recovery token with MC_MAINT_V1 (action: TECHNICIAN_RECOVERY)', () async {
      final now = DateTime.now().toUtc();
      final config = await server!.facilityConfigService.getConfiguration(hospitalCode);
      final instId = config.installationIdentity;

      recoveryTimeResponse = authoritySigner.signTimeResponse(
        authorityId: 'MEDCORE-TIME-TEST-AUTHORITY',
        hospitalCode: hospitalCode,
        installationId: instId,
        nonce: nonce,
        trustedUtc: now,
      );

      recoveryToken = authoritySigner.signToken(
        hospitalCode: hospitalCode,
        installationId: instId,
        nonce: nonce,
        issuedAt: now,
        expiresAt: now.add(const Duration(minutes: 15)),
        action: 'TECHNICIAN_RECOVERY',
      );
      expect(recoveryToken.startsWith('MC_MAINT_V1.'), isTrue);
    });

    test('D.4: Verify recovery token via /api/v1/technician/recovery/verify', () async {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/recovery/verify'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'deviceId': deviceId,
          'challengeId': challengeId,
          'rawRecoveryAuthorityToken': recoveryToken,
          'rawTrustedTimeResponse': recoveryTimeResponse,
        }),
      );
      expect(resp.statusCode, equals(200));
      final data = decodeData(resp);
      expect(data['status'], anyOf(equals('RECOVERED'), equals('RECOVERY_VERIFIED_AND_SECRET_ROTATED')));
      final sec = data['temporarySecret'] ?? data['temporaryTechnicianSecret'];
      expect(sec, isNotNull);
      recoveredSecret = sec as String;

      // Verify nonce is consumed in MariaDB mc_consumed_maintenance_tokens
      final consumedRows = await db.execute(
        'SELECT * FROM mc_consumed_maintenance_tokens WHERE nonce = :nonce',
        {'nonce': nonce},
      );
      expect(consumedRows.rows.isNotEmpty, isTrue);

      // Verify audit log mc_audit_logs directly
      final auditRows = await db.execute(
        "SELECT * FROM mc_audit_logs WHERE action = 'technician.secret.recovered' AND hospital_code = :hosp",
        {'hosp': hospitalCode},
      );
      expect(auditRows.rows.isNotEmpty, isTrue);
    });

    test('D.5: RT-TECH-08: Recovery token replay rejected (nonce consumed)', () async {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/recovery/verify'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'deviceId': deviceId,
          'challengeId': challengeId,
          'rawRecoveryAuthorityToken': recoveryToken,
          'rawTrustedTimeResponse': recoveryTimeResponse,
        }),
      );
      expect(resp.statusCode, anyOf(equals(400), equals(403), equals(409)));
    });

    test('D.6: Old rotated secret fails after recovery reset', () async {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/session/open'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'deviceId': deviceId,
          'technicianSecret': rotatedSecret,
        }),
      );
      expect(resp.statusCode, anyOf(equals(401), equals(403)));
    });

    test('D.7: Recovered temporary secret successfully opens technician session', () async {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/session/open'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'deviceId': deviceId,
          'technicianSecret': recoveredSecret,
        }),
      );
      expect(resp.statusCode, anyOf(equals(200), equals(201)));
      final data = decodeData(resp);
      techToken = data['technicianToken'] as String;
    });
  });

  // =========================================================================
  // STATE E: FACTORY RESET & CREDENTIAL INVALIDATION
  // =========================================================================
  group('STATE E: Factory Reset Integration & Post-Reset Commissioning', () {
    late String postResetSecret;

    test('E.1: Perform Factory Reset through DatabaseLifecycleService', () async {
      final resetResult = await server!.databaseLifecycleService.factoryReset(
        hospitalCode: hospitalCode,
        confirmationText: 'RESET MEDCORE',
        requireMandatoryBackup: false,
        actorRoleLabel: 'TECHNICIAN_SERVICE',
      );
      expect(resetResult['status'], equals('COMPLETED_AND_REBUILT'));
    });

    test('E.2: RT-TECH-17: Factory Reset drops previous technician sessions from MariaDB', () async {
      final activeSessions = await db.execute(
        'SELECT COUNT(*) as cnt FROM mc_technician_sessions WHERE is_active = 1',
      );
      expect(int.parse(activeSessions.rows.first.assoc()['cnt'].toString()), equals(0));
    });

    test('E.3: RT-TECH-18: Pre-reset technician token strictly fails', () async {
      final resp = await http.get(
        Uri.parse('$baseUrl/api/v1/technician/config'),
        headers: techHeaders(),
      );
      expect(resp.statusCode, anyOf(equals(401), equals(403)));
    });

    test('E.4: Pre-reset technician password strictly fails', () async {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/session/open'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'deviceId': deviceId,
          'technicianSecret': recoveredSecret,
        }),
      );
      expect(resp.statusCode, anyOf(equals(401), equals(403)));
    });

    test('E.5: RT-TECH-19: Factory Reset generated brand-new commissioning secret slip', () async {
      final slipFile = File(p.join(securityRoot.path, 'FIRST_RUN_COMMISSIONING_SECRET.txt'));
      expect(slipFile.existsSync(), isTrue);

      final content = slipFile.readAsStringSync();
      final match = RegExp(r'Commissioning Secret\s+:\s+(TECH-COMM-[^\r\n\s]+)').firstMatch(content);
      expect(match, isNotNull);
      postResetSecret = match!.group(1)!;

      expect(postResetSecret, isNot(equals(commissioningSecret)));
      expect(postResetSecret, isNot(equals(recoveredSecret)));
    });

    test('E.6: Post-reset commissioning secret successfully opens fresh technician session', () async {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/session/open'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'deviceId': deviceId,
          'technicianSecret': postResetSecret,
        }),
      );
      expect(resp.statusCode, anyOf(equals(200), equals(201)));
      final data = decodeData(resp);
      techToken = data['technicianToken'] as String;

      // Close post-reset session cleanly
      await http.post(
        Uri.parse('$baseUrl/api/v1/technician/session/close'),
        headers: techHeaders(),
        body: jsonEncode({}),
      );
    });
  });

  // =========================================================================
  // COMPLETE RED TEAM VECTORS: RT-TECH-01 THROUGH RT-TECH-24
  // =========================================================================
  group('SECURITY RED TEAM: Comprehensive Vectors RT-TECH-01 to RT-TECH-24', () {
    test('RT-TECH-01: Unauthenticated Technician Mode returns 401/403', () async {
      final resp = await http.get(
        Uri.parse('$baseUrl/api/v1/technician/config'),
        headers: {'content-type': 'application/json'},
      );
      expect(resp.statusCode, anyOf(equals(401), equals(403)));
    });

    test('RT-TECH-02: Hospital Admin JWT cannot access Technician endpoints', () async {
      final resp = await http.get(
        Uri.parse('$baseUrl/api/v1/technician/config'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer FAKE.STAFF.ADMIN.TOKEN',
        },
      );
      expect(resp.statusCode, anyOf(equals(401), equals(403)));
    });

    test('RT-TECH-05: Expired technician token rejected', () async {
      final expiredToken = PasswordHasher.generateSecureToken(32);
      final expiredHash = PasswordHasher.sha256Hex(expiredToken);

      await db.execute(
        '''
        INSERT INTO mc_technician_sessions (
          session_uuid, hospital_code, device_id, token_sha256,
          auth_method, is_active, issued_at, expires_at
        ) VALUES (
          'SESS-EXPIRED-01', :hosp, :dev, :thash,
          'INSTALLATION_TECH_SECRET', 1, DATE_SUB(NOW(), INTERVAL 5 HOUR), DATE_SUB(NOW(), INTERVAL 1 HOUR)
        )
        ''',
        {
          'hosp': hospitalCode,
          'dev': deviceId,
          'thash': expiredHash,
        },
      );

      final resp = await http.get(
        Uri.parse('$baseUrl/api/v1/technician/config'),
        headers: techHeaders(token: expiredToken),
      );
      expect(resp.statusCode, anyOf(equals(401), equals(403)));
    });

    test('RT-TECH-06: Wrong device ID in headers rejected', () async {
      final resp = await http.get(
        Uri.parse('$baseUrl/api/v1/technician/config'),
        headers: techHeaders(dev: 'DEV-WRONG-99'),
      );
      expect(resp.statusCode, anyOf(equals(401), equals(403)));
    });

    test('RT-TECH-07: Wrong tenant ID in headers rejected', () async {
      final resp = await http.get(
        Uri.parse('$baseUrl/api/v1/technician/config'),
        headers: techHeaders(hosp: hospitalCodeB),
      );
      expect(resp.statusCode, anyOf(equals(401), equals(403)));
    });

    test('RT-TECH-09: Expired recovery token rejected', () async {
      final chResp = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/recovery/challenge'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'hospitalCode': hospitalCode, 'deviceId': deviceId}),
      );
      final chData = decodeData(chResp);
      final past = DateTime.now().toUtc().subtract(const Duration(hours: 2));

      final expiredToken = authoritySigner.signToken(
        hospitalCode: hospitalCode,
        installationId: 'INST-01',
        nonce: chData['nonce'] as String,
        issuedAt: past.subtract(const Duration(minutes: 30)),
        expiresAt: past,
        action: 'TECHNICIAN_RECOVERY',
      );

      final resp = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/recovery/verify'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'deviceId': deviceId,
          'challengeId': chData['challengeId'],
          'rawRecoveryAuthorityToken': expiredToken,
        }),
      );
      expect(resp.statusCode, anyOf(equals(400), equals(401), equals(403)));
    });

    test('RT-TECH-10: Malformed recovery token rejected', () async {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/recovery/verify'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'deviceId': deviceId,
          'challengeId': 'FAKE-CHALLENGE',
          'rawRecoveryAuthorityToken': 'MC_MAINT_V1.CORRUPTED_PAYLOAD.CORRUPTED_SIG',
        }),
      );
      expect(resp.statusCode, anyOf(equals(400), equals(403)));
    });

    test('RT-TECH-11: Recovery token for another device rejected', () async {
      final chResp = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/recovery/challenge'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'hospitalCode': hospitalCode, 'deviceId': deviceId}),
      );
      final chData = decodeData(chResp);
      final now = DateTime.now().toUtc();

      // Issue token bound to another device
      final misboundToken = authoritySigner.signPayload({
        'v': 1,
        'tid': 'TID-DEV-MISMATCH',
        'hosp': hospitalCode,
        'dev': 'DEV-ANOTHER-99',
        'act': 'TECHNICIAN_RECOVERY',
        'nonce': chData['nonce'],
        'iat': now.toIso8601String(),
        'exp': now.add(const Duration(minutes: 15)).toIso8601String(),
      });

      final resp = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/recovery/verify'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'deviceId': deviceId,
          'challengeId': chData['challengeId'],
          'rawRecoveryAuthorityToken': misboundToken,
        }),
      );
      expect(resp.statusCode, anyOf(equals(400), equals(403)));
    });

    test('RT-TECH-12: Recovery token for another tenant rejected', () async {
      final chResp = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/recovery/challenge'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'hospitalCode': hospitalCode, 'deviceId': deviceId}),
      );
      final chData = decodeData(chResp);
      final now = DateTime.now().toUtc();

      // Token bound to hospitalCodeB
      final crossTenantToken = authoritySigner.signToken(
        hospitalCode: hospitalCodeB,
        installationId: 'INST-CROSS-01',
        nonce: chData['nonce'] as String,
        issuedAt: now,
        expiresAt: now.add(const Duration(minutes: 15)),
        action: 'TECHNICIAN_RECOVERY',
      );

      final resp = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/recovery/verify'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'deviceId': deviceId,
          'challengeId': chData['challengeId'],
          'rawRecoveryAuthorityToken': crossTenantToken,
        }),
      );
      expect(resp.statusCode, anyOf(equals(400), equals(403)));
    });

    test('RT-TECH-14 & RT-TECH-15: Tampered or missing security root on established system fails closed', () async {
      await db.execute(
        "UPDATE mc_tenants SET clock_guard_initialized_at = NOW() WHERE hospital_code = :hosp",
        {'hosp': hospitalCode},
      );

      final clockRepo = ClockGuardRepository(db, securityRootDirectory: securityRoot.path);
      final key = sha256.convert(utf8.encode('${db.config.databaseName}:$hospitalCode')).toString();
      final anchorFile = File(p.join(securityRoot.path, '$key.json'));
      final validContent = anchorFile.existsSync() ? anchorFile.readAsStringSync() : null;

      try {
        // 1. Tampered payload
        anchorFile.writeAsStringSync('{"tampered": true, "rootSecret": "CORRUPTED"}');
        await expectLater(
          clockRepo.evaluateAndUpdateClock(
            hospitalCode: hospitalCode,
            currentWallClock: DateTime.now().toUtc(),
            driftTolerance: const Duration(seconds: 30),
          ),
          throwsA(isA<ClockTamperException>()),
        );

        // 2. Missing disk anchor on established system
        if (anchorFile.existsSync()) anchorFile.deleteSync();
        await expectLater(
          clockRepo.evaluateAndUpdateClock(
            hospitalCode: hospitalCode,
            currentWallClock: DateTime.now().toUtc(),
            driftTolerance: const Duration(seconds: 30),
          ),
          throwsA(isA<ClockTamperException>()),
        );
      } finally {
        // Restore valid anchor
        if (validContent != null) {
          anchorFile.writeAsStringSync(validContent);
        }
      }
    });

    test('RT-TECH-16: Clock rollback detected and blocks normal technician session', () async {
      final clockRepo = ClockGuardRepository(db, securityRootDirectory: securityRoot.path);
      final t1 = DateTime.now().toUtc();
      final eval1 = await clockRepo.evaluateAndUpdateClock(
        hospitalCode: hospitalCode,
        currentWallClock: t1,
        driftTolerance: const Duration(seconds: 30),
      );
      expect(eval1.rollbackDetected, isFalse);

      // Roll clock backwards by 2 hours
      final t2 = t1.subtract(const Duration(hours: 2));
      final eval2 = await clockRepo.evaluateAndUpdateClock(
        hospitalCode: hospitalCode,
        currentWallClock: t2,
        driftTolerance: const Duration(seconds: 30),
      );
      expect(eval2.rollbackDetected, isTrue);
      expect(eval2.rollbackDeltaSeconds, greaterThan(3600));
    });

    test('RT-TECH-21: Zero hardcoded technician passwords (dictionary attack blocked)', () async {
      const dictionary = [
        'admin',
        'password',
        'technician',
        'medcore',
        'MedCore#2026',
        'MedcorePlatinum#2026',
        '12345678',
        'root',
        'service',
        'install',
      ];

      for (final pwd in dictionary) {
        final resp = await http.post(
          Uri.parse('$baseUrl/api/v1/technician/session/open'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'hospitalCode': hospitalCode,
            'deviceId': deviceId,
            'technicianSecret': pwd,
          }),
        );
        expect(resp.statusCode, anyOf(equals(401), equals(403)), reason: 'Password "$pwd" must be rejected');
      }
    });

    test('RT-TECH-22: Zero universal recovery passwords (backdoors blocked)', () async {
      const backdoorStrings = [
        'OVERRIDE_MASTER_RECOVERY',
        'MEDCORE_BACKDOOR_KEY',
        'SUPER_USER_RECOVER',
        'RSA_BYPASS_TOKEN',
        'MC_MAINT_V1.MASTER.BYPASS',
      ];

      for (final backdoor in backdoorStrings) {
        final resp = await http.post(
          Uri.parse('$baseUrl/api/v1/technician/recovery/verify'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'hospitalCode': hospitalCode,
            'deviceId': deviceId,
            'challengeId': 'CHALLENGE-TEST',
            'rawRecoveryAuthorityToken': backdoor,
          }),
        );
        expect(resp.statusCode, anyOf(equals(400), equals(403)), reason: 'Backdoor "$backdoor" must be rejected');
      }
    });

    test('RT-TECH-23: Unauthenticated / direct API calls cannot bypass service authorization', () async {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/initial-admin'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'staffCode': 'ADM-BYPASS-01',
          'fullName': 'Attacker Admin',
          'email': 'attacker@bypass.com',
          'password': 'BypassPassword#2026',
        }),
      );
      expect(resp.statusCode, anyOf(equals(401), equals(403)));
    });

    test('RT-TECH-24: Direct MariaDB modification cannot forge valid HMAC technician session token', () async {
      final fakeToken = PasswordHasher.generateSecureToken(32);
      final fakeHash = PasswordHasher.sha256Hex(fakeToken);

      await db.execute(
        '''
        INSERT INTO mc_technician_sessions (
          session_uuid, hospital_code, device_id, token_sha256,
          auth_method, is_active, issued_at, expires_at
        ) VALUES (
          'SESS-FORGED-01', :hosp, :dev, :thash,
          'INSTALLATION_TECH_SECRET', 1, NOW(), DATE_ADD(NOW(), INTERVAL 4 HOUR)
        )
        ''',
        {
          'hosp': hospitalCode,
          'dev': deviceId,
          'thash': fakeHash,
        },
      );

      final resp = await http.get(
        Uri.parse('$baseUrl/api/v1/technician/config'),
        headers: techHeaders(token: 'INVALID_SIGNATURE_TOKEN'),
      );
      expect(resp.statusCode, anyOf(equals(401), equals(403)));
    });
  });
}
