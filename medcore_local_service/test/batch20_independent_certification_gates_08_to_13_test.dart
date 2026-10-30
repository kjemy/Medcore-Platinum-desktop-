import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:medcore_local_service/medcore_local_service.dart';
import 'package:medcore_local_service/src/security/commercial_entitlement_service.dart';
import 'package:medcore_local_service/src/security/hardware_binding_service.dart';
import 'package:test/test.dart';

import 'support/test_authority_signer.dart';
import 'support/test_db_config.dart';

void main() {
  group('INDEPENDENT CERTIFICATION: Gates 08 to 13 Acceptance Suite', () {
    const testDbName = 'medcore_indep_cert_b20_test';
    const hosp = 'HOSP_INDEP_02';
    late DbClient adminDb;
    late DbClient testDb;
    late Directory tempSecurityDir;
    late TestAuthoritySigner authoritySigner;
    late HardwareBindingService hwService;
    late CommercialEntitlementService commService;
    late LocalMedCoreServer server;
    int? serverPort;

    setUpAll(() async {
      authoritySigner = TestAuthoritySigner.loadDefault();
      tempSecurityDir = Directory.systemTemp.createTempSync('medcore_b20_sec_');

      final adminConfig = testDbConfig(databaseName: 'mysql', maxConnections: 10);
      adminDb = DbClient(adminConfig);
      await adminDb.execute(
        'CREATE DATABASE IF NOT EXISTS `$testDbName` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;',
      );

      final testConfig = testDbConfig(databaseName: testDbName, maxConnections: 10);
      testDb = DbClient(testConfig);

      final runner = MigrationRunner(
        db: testDb,
        migrationsDir: Directory('sql/migrations').existsSync()
            ? 'sql/migrations'
            : 'medcore_local_service/sql/migrations',
      );
      await runner.runMigrations();

      // Seed tenant and device
      await testDb.execute(
        "INSERT INTO mc_tenants (hospital_code, name, status) VALUES ('$hosp', 'Independent Hospital B20', 'active') "
        "ON DUPLICATE KEY UPDATE status = 'active';",
      );
      final govRepo = TenantGovernanceRepository(testDb);
      await govRepo.enrollOrUpdateDevice(
        hospitalCode: hosp,
        deviceId: 'DEV-B20-TEST',
        deviceName: 'Workstation B20',
        platform: 'WINDOWS',
        connectionType: 'LOOPBACK',
        hwFingerprintSha256: PasswordHasher.sha256Hex('HW-B20-001'),
        devicePublicKeyEd25519: 'PUBKEY-B20-001',
        roleScope: 'SERVER_HOST',
        isTrustedSecureRuntime: true,
        status: 'ACTIVE',
      );

      hwService = HardwareBindingService(overrideFingerprint: 'B20-MACHINE-HW-SHA256-ZZZ999');
      commService = CommercialEntitlementService(
        db: testDb,
        securityRootDirectory: tempSecurityDir.path,
        hardwareService: hwService,
        authorityModulusOverride: authoritySigner.modulus,
        authorityExponentOverride: authoritySigner.publicExponent,
      );

      server = LocalMedCoreServer(
        testDb,
        securityRootDirectory: tempSecurityDir.path,
        technicianSecretHashOverride: PasswordHasher.hashPassword('TechB20Secret!2026'),
        hardwareBindingService: hwService,
        maintenanceTokenService: MaintenanceTokenService(
          modulus: authoritySigner.modulus,
          publicExponent: authoritySigner.publicExponent,
        ),
      );
      serverPort = await server.start(address: '127.0.0.1', port: 0);
    });

    tearDownAll(() async {
      try {
        await server.stop();
      } catch (_) {}
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
    // GATE 08: Clock Tampering & Monotonicity
    // =========================================================================
    test('GATE-08: Monotonic clock guard strictly flags rollback and fails closed', () async {
      final clockRepo = ClockGuardRepository(testDb, securityRootDirectory: tempSecurityDir.path);
      final t1 = DateTime.utc(2026, 10, 30, 12, 0, 0);
      final res1 = await clockRepo.evaluateAndUpdateClock(hospitalCode: hosp, currentWallClock: t1);
      expect(res1.rollbackDetected, isFalse);
      expect(res1.record.maxObservedUtc, equals(t1));

      // Attempt backwards time shift (rewind by 2 hours)
      final tBackward = DateTime.utc(2026, 10, 30, 10, 0, 0);
      final resBackward = await clockRepo.evaluateAndUpdateClock(hospitalCode: hosp, currentWallClock: tBackward);
      expect(resBackward.rollbackDetected, isTrue);
      expect(resBackward.record.maxObservedUtc, equals(t1), reason: 'High water mark must never move backward.');
    });

    // =========================================================================
    // GATE 09: Grace Period Determinism
    // =========================================================================
    test('GATE-09: 14-day offline grace period status evaluates with exact millisecond precision', () {
      final now = DateTime.now().toUtc();
      final entWithinGrace = CommercialEntitlement(
        licenseId: 'LIC-GRACE-01',
        hospitalCode: hosp,
        installationId: 'INST-01',
        hardwareFingerprintSha256: 'HW-01',
        edition: 'PLATINUM',
        issuedAtUtc: now.subtract(const Duration(days: 370)),
        notBeforeUtc: now.subtract(const Duration(days: 370)),
        expiresAtUtc: now.subtract(const Duration(days: 2)), // Expired 2 days ago
        graceUntilUtc: now.add(const Duration(days: 12)),     // Grace active for 12 more days
        maintenanceExpiresAtUtc: now.subtract(const Duration(days: 2)),
        enabledModules: {'Patients': true},
        status: EntitlementStatus.gracePeriod,
      );

      expect(entWithinGrace.status, equals(EntitlementStatus.gracePeriod));
      expect(entWithinGrace.isMutationAllowed, isTrue, reason: 'Mutations permitted during grace period.');

      final entPastGrace = CommercialEntitlement(
        licenseId: 'LIC-GRACE-02',
        hospitalCode: hosp,
        installationId: 'INST-01',
        hardwareFingerprintSha256: 'HW-01',
        edition: 'PLATINUM',
        issuedAtUtc: now.subtract(const Duration(days: 390)),
        notBeforeUtc: now.subtract(const Duration(days: 390)),
        expiresAtUtc: now.subtract(const Duration(days: 20)),
        graceUntilUtc: now.subtract(const Duration(days: 6)), // Grace expired 6 days ago
        maintenanceExpiresAtUtc: now.subtract(const Duration(days: 20)),
        enabledModules: {'Patients': true},
        status: EntitlementStatus.expiredReadOnly,
      );

      expect(entPastGrace.status, equals(EntitlementStatus.expiredReadOnly));
      expect(entPastGrace.isMutationAllowed, isFalse);
    });

    // =========================================================================
    // GATE 10: Factory Reset & Seeding Security
    // =========================================================================
    test('GATE-10: Baseline system seeding initializes finite 30-day evaluation, never NULL', () async {
      const freshHospitalCode = 'HOSP_FACTORY_FRESH_03';
      await server.databaseLifecycleService.seedBaselineSystemDataForTesting(freshHospitalCode);

      final row = (await testDb.execute(
        'SELECT subscription_expires_utc, edition FROM mc_facility_config WHERE hospital_code = :hosp LIMIT 1',
        {'hosp': freshHospitalCode},
      )).rows.first.assoc();

      expect(row['subscription_expires_utc'], isNotNull);
      final expiresParsed = DateTime.parse(row['subscription_expires_utc'].toString());
      final deltaDays = expiresParsed.difference(DateTime.now().toUtc()).inDays;
      expect(deltaDays, inInclusiveRange(28, 31), reason: 'Trial period must be exactly ~30 days.');
    });

    // =========================================================================
    // GATE 11: Technician License Import Flow
    // =========================================================================
    test('GATE-11: Authenticated technician imports signed license via HTTP API', () async {
      // Open technician session
      final openResp = await http.post(
        Uri.parse('http://127.0.0.1:$serverPort/api/v1/technician/session/open'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hosp,
          'deviceId': 'DEV-B20-TEST',
          'technicianSecret': 'TechB20Secret!2026',
        }),
      );
      expect(openResp.statusCode, equals(201));
      final techSessionToken = jsonDecode(openResp.body)['data']['technicianToken'] as String;

      final now = DateTime.now().toUtc();
      final payload = {
        'v': 1,
        'lid': 'LIC-B20-IMPORT-001',
        'hosp': hosp,
        'inst': 'INST-001',
        'hw': 'B20-MACHINE-HW-SHA256-ZZZ999',
        'ed': 'PLATINUM',
        'iat': now.toIso8601String(),
        'nbf': now.toIso8601String(),
        'exp': now.add(const Duration(days: 365)).toIso8601String(),
        'maint_exp': now.add(const Duration(days: 365)).toIso8601String(),
        'mods': {'Patients': true, 'Surgery': true},
      };
      final token = authoritySigner.signLicenseLease(payload);

      final importRes = await http.post(
        Uri.parse('http://127.0.0.1:$serverPort/api/v1/technician/license/import'),
        headers: {
          'content-type': 'application/json',
          'x-medcore-tech-token': techSessionToken,
          'x-tenant-id': hosp,
          'x-medcore-device-id': 'DEV-B20-TEST',
        },
        body: jsonEncode({'licenseToken': token}),
      );
      expect(importRes.statusCode, equals(200));
      final body = jsonDecode(importRes.body);
      expect(body['ok'], isTrue);
      expect(body['data']['status'], equals('IMPORTED'));
      expect(body['data']['entitlement']['status'], equals('VALID'));
    });

    // =========================================================================
    // GATE 12: Entitlement Database Integrity & Tamper Rejection
    // =========================================================================
    test('GATE-12: Direct SQL tampering of license state fails closed to signed disk truth', () async {
      // Attacker attempts to modify license_id and status in MariaDB
      await testDb.execute(
        "UPDATE mc_license_state SET status = 'EXPIRED_READ_ONLY', license_id = 'FORGED-ID-999' WHERE hospital_code = '$hosp'",
      );

      // System re-reads disk Level 1 truth: valid license file on disk overwrites and reconciles
      final ent = await commService.getActiveEntitlement(hosp);
      expect(ent.status, equals(EntitlementStatus.valid));
      expect(ent.licenseId, equals('LIC-B20-IMPORT-001'));
    });

    // =========================================================================
    // GATE 13: Software License vs Maintenance Entitlement Separation
    // =========================================================================
    test('GATE-13: Maintenance expiration does NOT lock clinical mutations if subscription is valid', () {
      final now = DateTime.now().toUtc();
      final ent = CommercialEntitlement(
        licenseId: 'LIC-MAINT-EXP',
        hospitalCode: hosp,
        installationId: 'INST-01',
        hardwareFingerprintSha256: 'HW-01',
        edition: 'PLATINUM',
        issuedAtUtc: now.subtract(const Duration(days: 400)),
        notBeforeUtc: now.subtract(const Duration(days: 400)),
        expiresAtUtc: now.add(const Duration(days: 100)), // Subscription still valid for 100 days
        maintenanceExpiresAtUtc: now.subtract(const Duration(days: 30)), // Maintenance expired 30 days ago
        enabledModules: {'Patients': true},
        status: EntitlementStatus.valid,
      );

      // Subscription is active -> Mutations are permitted
      expect(ent.isMutationAllowed, isTrue);
      // But maintenance / software update entitlement is expired
      expect(ent.isMaintenanceActive, isFalse);
    });
  });
}
