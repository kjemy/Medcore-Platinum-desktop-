import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:medcore_local_service/medcore_local_service.dart';
import 'package:medcore_local_service/src/security/commercial_entitlement_service.dart';
import 'package:medcore_local_service/src/security/hardware_binding_service.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/test_authority_signer.dart';
import 'support/test_db_config.dart';

void main() {
  group('MEDCORE PLATINUM RUN #14/15: Commercial Rights & Offline Licensing Acceptance', () {
    const testDbName = 'medcore_comm_rights_test';
    const hosp = 'HOSP_COMM_01';
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
      tempSecurityDir = Directory.systemTemp.createTempSync('medcore_comm_sec_');

      final adminConfig = testDbConfig(databaseName: 'mysql', maxConnections: 10);
      adminDb = DbClient(adminConfig);
      await adminDb.execute(
        'CREATE DATABASE IF NOT EXISTS `$testDbName` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;',
      );

      final testConfig = testDbConfig(databaseName: testDbName, maxConnections: 10);
      testDb = DbClient(testConfig);

      // Run all migrations including V018
      final migrationsDir = Directory('sql/migrations').existsSync()
          ? 'sql/migrations'
          : (Directory('medcore_local_service/sql/migrations').existsSync()
              ? 'medcore_local_service/sql/migrations'
              : 'sql/migrations');
      final runner = MigrationRunner(db: testDb, migrationsDir: migrationsDir);
      await runner.runMigrations();

      // Seed tenant and device in database for testing technician operations
      await testDb.execute(
        "INSERT INTO mc_tenants (hospital_code, name, status) VALUES ('$hosp', 'Commercial Hospital', 'active') "
        "ON DUPLICATE KEY UPDATE status = 'active';",
      );
      final govRepo = TenantGovernanceRepository(testDb);
      await govRepo.enrollOrUpdateDevice(
        hospitalCode: hosp,
        deviceId: 'DEV-TECH-PORTABLE',
        deviceName: 'Portable Tech Workstation',
        platform: 'WINDOWS',
        connectionType: 'LOOPBACK',
        hwFingerprintSha256: PasswordHasher.sha256Hex('TECH-DEV-01'),
        devicePublicKeyEd25519: 'PUBKEY-TECH-DEV-01',
        roleScope: 'SERVER_HOST',
        isTrustedSecureRuntime: true,
        status: 'ACTIVE',
      );

      hwService = HardwareBindingService(overrideFingerprint: 'TEST-HARDWARE-ALPHA-1234');
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
        technicianSecretHashOverride: PasswordHasher.hashPassword('TechSecret!2026'),
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
    // COMM-01: Canonical Domain Model
    // =========================================================================
    test('COMM-01: Canonical Entitlement Domain Model evaluates status deterministically', () {
      final now = DateTime.now().toUtc();
      final entValid = CommercialEntitlement(
        licenseId: 'LIC-001',
        hospitalCode: hosp,
        installationId: 'INST-001',
        hardwareFingerprintSha256: 'HW-001',
        edition: 'PLATINUM',
        issuedAtUtc: now.subtract(const Duration(days: 1)),
        notBeforeUtc: now.subtract(const Duration(days: 1)),
        expiresAtUtc: now.add(const Duration(days: 365)),
        maintenanceExpiresAtUtc: now.add(const Duration(days: 365)),
        enabledModules: {'Patients': true, 'Surgery': true},
        status: EntitlementStatus.valid,
      );

      expect(entValid.isMutationAllowed, isTrue);
      expect(entValid.isReadOnlyAllowed, isTrue);
      expect(entValid.isModuleEntitled('Patients'), isTrue);
      expect(entValid.isModuleEntitled('Billing'), isFalse);

      final entExpired = CommercialEntitlement(
        licenseId: 'LIC-002',
        hospitalCode: hosp,
        installationId: 'INST-001',
        hardwareFingerprintSha256: 'HW-001',
        edition: 'PLATINUM',
        issuedAtUtc: now.subtract(const Duration(days: 400)),
        notBeforeUtc: now.subtract(const Duration(days: 400)),
        expiresAtUtc: now.subtract(const Duration(days: 35)),
        maintenanceExpiresAtUtc: now.subtract(const Duration(days: 35)),
        enabledModules: {'Patients': true},
        status: EntitlementStatus.expiredReadOnly,
      );

      expect(entExpired.isMutationAllowed, isFalse);
      expect(entExpired.isReadOnlyAllowed, isTrue);
    });

    // =========================================================================
    // COMM-02: Cryptographically Signed Offline License (.mclic)
    // =========================================================================
    test('COMM-02: Signed license verification validates genuine signature and rejects tampering', () {
      final now = DateTime.now().toUtc();
      final payload = {
        'v': 1,
        'lid': 'LIC-TEST-2026-001',
        'hosp': hosp,
        'inst': 'INST-ALPHA',
        'hw': 'TEST-HARDWARE-ALPHA-1234',
        'ed': 'PLATINUM',
        'iat': now.subtract(const Duration(days: 1)).toIso8601String(),
        'nbf': now.subtract(const Duration(days: 1)).toIso8601String(),
        'exp': now.add(const Duration(days: 365)).toIso8601String(),
        'maint_exp': now.add(const Duration(days: 365)).toIso8601String(),
        'max_dev': 50,
        'max_doc': 100,
        'mods': {'Patients': true, 'Surgery': true, 'Finance': true},
      };

      final validTokenStr = authoritySigner.signLicenseLease(payload);
      final parsed = SignedLicenseToken.parse(validTokenStr);
      expect(
        parsed.verifySignature(modulus: authoritySigner.modulus, publicExponent: authoritySigner.publicExponent),
        isTrue,
      );

      // Tampered payload
      final tamperedPayload = Map<String, dynamic>.from(payload);
      tamperedPayload['exp'] = '2099-12-31T23:59:59.000Z';
      final tamperedB64 = base64UrlEncode(utf8.encode(jsonEncode(tamperedPayload))).replaceAll('=', '');
      final forgedTokenStr = 'MEDCORE_LIC_V1.$tamperedB64.${validTokenStr.split('.').last}';
      final parsedForged = SignedLicenseToken.parse(forgedTokenStr);
      expect(
        parsedForged.verifySignature(modulus: authoritySigner.modulus, publicExponent: authoritySigner.publicExponent),
        isFalse,
      );
    });

    // =========================================================================
    // COMM-03: Hardware / Installation Binding (Gate 3)
    // =========================================================================
    test('COMM-03: Hardware binding enforces installation to authorized physical machine', () async {
      final now = DateTime.now().toUtc();
      final payloadAlpha = {
        'v': 1,
        'lid': 'LIC-HW-001',
        'hosp': hosp,
        'inst': 'INST-001',
        'hw': 'TEST-HARDWARE-ALPHA-1234',
        'ed': 'PLATINUM',
        'iat': now.toIso8601String(),
        'nbf': now.toIso8601String(),
        'exp': now.add(const Duration(days: 180)).toIso8601String(),
        'maint_exp': now.add(const Duration(days: 180)).toIso8601String(),
        'mods': {'Patients': true},
      };

      // Import on matching hardware
      final tokenAlpha = authoritySigner.signLicenseLease(payloadAlpha);
      final entAlpha = await commService.importSignedLicense(tokenAlpha, hospitalCode: hosp);
      expect(entAlpha.status, equals(EntitlementStatus.valid));
      expect(entAlpha.isMutationAllowed, isTrue);

      // Evaluate on mismatching cloned hardware
      final mismatchHwService = HardwareBindingService(overrideFingerprint: 'CLONED-PIRATED-HARDWARE-9999');
      final commServiceCloned = CommercialEntitlementService(
        db: testDb,
        securityRootDirectory: tempSecurityDir.path,
        hardwareService: mismatchHwService,
        authorityModulusOverride: authoritySigner.modulus,
        authorityExponentOverride: authoritySigner.publicExponent,
      );

      final entCloned = await commServiceCloned.getActiveEntitlement(hosp);
      expect(entCloned.status, equals(EntitlementStatus.tamperLocked));
      expect(entCloned.isMutationAllowed, isFalse);
      expect(entCloned.rejectionReason, contains('HARDWARE_BINDING_VIOLATION'));
    });

    // =========================================================================
    // COMM-04: Dynamic Database Credentials (Gate 4)
    // =========================================================================
    test('COMM-04: Dynamic MariaDB credentials file exists and old default password fails', () {
      final credFile = File(p.join(Directory.current.path, 'runtime', 'security', 'db_credentials.json'));
      expect(credFile.existsSync(), isTrue, reason: 'Dynamic credentials file must exist.');
      final json = jsonDecode(credFile.readAsStringSync()) as Map<String, dynamic>;
      expect(json['user'], equals('root'));
      expect(json['password'], isNotNull);
      expect(json['password'], isNot(equals('MedCoreLocalDb#2026')), reason: 'Old hardcoded password must be eliminated.');
      expect((json['password'] as String).length, greaterThanOrEqualTo(24));
    });

    // =========================================================================
    // COMM-05: Database Entitlement Integrity & HMAC Sealing (Gate 5)
    // =========================================================================
    test('COMM-05: Authoritative license state in MariaDB contains HMAC seal', () async {
      final rows = await testDb.execute(
        'SELECT license_id, hmac_seal, status FROM mc_license_state WHERE hospital_code = :hosp LIMIT 1',
        {'hosp': hosp},
      );
      expect(rows.rows.isNotEmpty, isTrue);
      final row = rows.rows.first.assoc();
      expect(row['license_id'], equals('LIC-HW-001'));
      expect(row['hmac_seal'], isNotNull);
      expect(row['hmac_seal'].toString().length, equals(64));
    });

    // =========================================================================
    // COMM-06: Server-Side Entitlement Middleware & EXPIRED_READ_ONLY Enforcement
    // =========================================================================
    test('COMM-06: Expired license allows GET reads but strictly blocks POST mutations with 403', () async {
      // 1. First, import an expired license
      final past = DateTime.now().toUtc().subtract(const Duration(days: 10));
      final payloadExpired = {
        'v': 1,
        'lid': 'LIC-EXPIRED-999',
        'hosp': hosp,
        'inst': 'INST-001',
        'hw': 'TEST-HARDWARE-ALPHA-1234',
        'ed': 'PLATINUM',
        'iat': past.subtract(const Duration(days: 365)).toIso8601String(),
        'nbf': past.subtract(const Duration(days: 365)).toIso8601String(),
        'exp': past.toIso8601String(), // Expired 10 days ago
        'maint_exp': past.toIso8601String(),
        'mods': {'Patients': true},
      };

      final expiredToken = authoritySigner.signLicenseLease(payloadExpired);
      await commService.importSignedLicense(expiredToken, hospitalCode: hosp);

      // Verify active entitlement status is EXPIRED_READ_ONLY
      final ent = await commService.getActiveEntitlement(hosp);
      expect(ent.status, equals(EntitlementStatus.expiredReadOnly));
      expect(ent.isMutationAllowed, isFalse);

      // 2. GET /api/v1/health -> Allowed (Public)
      final healthRes = await http.get(Uri.parse('http://127.0.0.1:$serverPort/api/v1/health'));
      expect(healthRes.statusCode, equals(200));

      // 3. GET /api/v1/product/bootstrap -> Allowed (Read-only patient safety invariant)
      final cfgRes = await http.get(Uri.parse('http://127.0.0.1:$serverPort/api/v1/product/bootstrap?hospitalCode=$hosp'));
      expect(cfgRes.statusCode, equals(200));

      // 4. POST /api/v1/staff -> Blocked fail-closed with 403 SUBSCRIPTION_EXPIRED
      final mutateRes = await http.post(
        Uri.parse('http://127.0.0.1:$serverPort/api/v1/staff'),
        headers: {
          'content-type': 'application/json',
          'x-tenant-id': hosp,
        },
        body: jsonEncode({'staffCode': 'DR-NEW', 'fullName': 'Dr New', 'role': 'Doctor'}),
      );
      expect(mutateRes.statusCode, equals(403));
      final errBody = jsonDecode(mutateRes.body);
      expect(errBody['error']['code'], equals('SUBSCRIPTION_EXPIRED'));
      expect(errBody['error']['status'], equals('EXPIRED_READ_ONLY'));
    });

    // =========================================================================
    // COMM-07: Timezone Invariance (Gate 7)
    // =========================================================================
    test('COMM-07: Strict UTC parsing prevents local machine timezone from altering expiration', () {
      final rec = FacilityConfigurationRecord(
        hospitalCode: hosp,
        facilityName: 'Test Hosp',
        facilityType: 'GENERAL_HOSPITAL',
        branchCode: 'MAIN',
        installationIdentity: 'INST-01',
        edition: 'PLATINUM',
        subscriptionExpiresUtc: '2026-10-30 10:00:00', // Naive MariaDB string in the past
        enabledModules: const {},
        patientFields: const {},
        branding: const BrandingAppearanceConfig(
          appDisplayName: 'App',
          facilityDisplayName: 'Hosp',
          editionLabel: 'Platinum',
        ),
        networkConfig: const {},
        backupConfig: const {},
        remoteHybridConfig: const {},
        configVersion: 1,
        isPersistedInConfigTable: true,
      );

      // Regardless of whether host is UTC+14 or UTC-12, naive string must parse strictly as UTC
      expect(rec.isSubscriptionExpired, isTrue);
    });

    // =========================================================================
    // COMM-08: Clean Host Process Reboot (Gates 7, 16)
    // =========================================================================
    test('COMM-08: Clean process restart with forward advancing time does not throw false tamper', () async {
      const hospReboot = 'HOSP_COMM_REBOOT';
      final clockRepo1 = ClockGuardRepository(testDb, securityRootDirectory: tempSecurityDir.path);
      final t1 = DateTime.utc(2026, 10, 30, 10, 0, 0);
      final res1 = await clockRepo1.evaluateAndUpdateClock(hospitalCode: hospReboot, currentWallClock: t1);
      expect(res1.record.processBootId, isNotEmpty);

      // New independent repository instance simulating service restart after overnight shutdown
      final clockRepo2 = ClockGuardRepository(testDb, securityRootDirectory: tempSecurityDir.path);

      // Next morning: host clock has advanced 14 hours forward (t2 > t1)
      final t2 = DateTime.utc(2026, 10, 31, 0, 0, 0);
      final res2 = await clockRepo2.evaluateAndUpdateClock(hospitalCode: hospReboot, currentWallClock: t2);
      expect(res2.rollbackDetected, isFalse);
      expect(res2.record.maxObservedUtc, equals(t2));
    });

    // =========================================================================
    // COMM-09: Reinstallation & Factory Reset Invariants (Gate 9)
    // =========================================================================
    test('COMM-09: Fresh baseline seeding initializes a finite 30-day evaluation, never perpetual NULL', () async {
      const freshHosp = 'HOSP_FRESH_SITE_B';
      await server.databaseLifecycleService.seedBaselineSystemDataForTesting(freshHosp);

      final row = (await testDb.execute(
        'SELECT subscription_expires_utc, edition FROM mc_facility_config WHERE hospital_code = :hosp LIMIT 1',
        {'hosp': freshHosp},
      )).rows.first.assoc();

      expect(row['subscription_expires_utc'], isNotNull, reason: 'Perpetual NULL expiration must be eradicated.');
      expect(row['edition'], equals('PLATINUM'));
    });

    // =========================================================================
    // COMM-10: Field Technician License Import API Flow (Gates 2, 10)
    // =========================================================================
    test('COMM-10: Authenticated technician imports signed license via HTTP API', () async {
      // 1. Open authenticated technician session via technician secret
      final now = DateTime.now().toUtc();
      final openResp = await http.post(
        Uri.parse('http://127.0.0.1:$serverPort/api/v1/technician/session/open'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hosp,
          'deviceId': 'DEV-TECH-PORTABLE',
          'technicianSecret': 'TechSecret!2026',
        }),
      );
      expect(openResp.statusCode, equals(201), reason: 'openSession response: ${openResp.body}');
      final techSessionToken = jsonDecode(openResp.body)['data']['technicianToken'] as String;

      // 2. Create valid license
      final validPayload = {
        'v': 1,
        'lid': 'LIC-ANNUAL-ENTERPRISE-2027',
        'hosp': hosp,
        'inst': 'INST-001',
        'hw': 'TEST-HARDWARE-ALPHA-1234',
        'ed': 'PLATINUM',
        'iat': now.toIso8601String(),
        'nbf': now.toIso8601String(),
        'exp': now.add(const Duration(days: 365)).toIso8601String(),
        'maint_exp': now.add(const Duration(days: 365)).toIso8601String(),
        'mods': {'Patients': true, 'Surgery': true, 'Finance': true},
      };
      final token = authoritySigner.signLicenseLease(validPayload);

      // 3. POST /api/v1/technician/license/import
      final importRes = await http.post(
        Uri.parse('http://127.0.0.1:$serverPort/api/v1/technician/license/import'),
        headers: {
          'content-type': 'application/json',
          'x-medcore-tech-token': techSessionToken,
          'x-tenant-id': hosp,
          'x-medcore-device-id': 'DEV-TECH-PORTABLE',
        },
        body: jsonEncode({'licenseToken': token}),
      );

      expect(importRes.statusCode, equals(200));
      final importBody = jsonDecode(importRes.body);
      expect(importBody['ok'], isTrue);
      expect(importBody['data']['status'], equals('IMPORTED'));
      expect(importBody['data']['entitlement']['licenseId'], equals('LIC-ANNUAL-ENTERPRISE-2027'));
      expect(importBody['data']['entitlement']['status'], equals('VALID'));

      // 4. Verify license is now active and allows mutations
      final activeEnt = await commService.getActiveEntitlement(hosp);
      expect(activeEnt.isMutationAllowed, isTrue);
      expect(activeEnt.licenseId, equals('LIC-ANNUAL-ENTERPRISE-2027'));
    });
  });
}
