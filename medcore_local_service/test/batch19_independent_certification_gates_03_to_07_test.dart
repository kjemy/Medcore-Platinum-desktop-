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
  group('INDEPENDENT CERTIFICATION: Gates 03 to 07 Acceptance Suite', () {
    const testDbName = 'medcore_indep_cert_test';
    const hosp = 'HOSP_INDEP_01';
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
      tempSecurityDir = Directory.systemTemp.createTempSync('medcore_indep_sec_');

      final adminConfig = testDbConfig(databaseName: 'mysql', maxConnections: 10);
      adminDb = DbClient(adminConfig);
      await adminDb.execute(
        'CREATE DATABASE IF NOT EXISTS `$testDbName` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;',
      );

      final testConfig = testDbConfig(databaseName: testDbName, maxConnections: 10);
      testDb = DbClient(testConfig);

      // Run migrations
      final runner = MigrationRunner(
        db: testDb,
        migrationsDir: Directory('sql/migrations').existsSync()
            ? 'sql/migrations'
            : 'medcore_local_service/sql/migrations',
      );
      await runner.runMigrations();

      // Seed tenant and device
      await testDb.execute(
        "INSERT INTO mc_tenants (hospital_code, name, status) VALUES ('$hosp', 'Independent Hospital', 'active') "
        "ON DUPLICATE KEY UPDATE status = 'active';",
      );
      final govRepo = TenantGovernanceRepository(testDb);
      await govRepo.enrollOrUpdateDevice(
        hospitalCode: hosp,
        deviceId: 'DEV-INDEP-TEST',
        deviceName: 'Certification Workstation',
        platform: 'WINDOWS',
        connectionType: 'LOOPBACK',
        hwFingerprintSha256: PasswordHasher.sha256Hex('HW-INDEP-001'),
        devicePublicKeyEd25519: 'PUBKEY-INDEP-001',
        roleScope: 'SERVER_HOST',
        isTrustedSecureRuntime: true,
        status: 'ACTIVE',
      );

      hwService = HardwareBindingService(overrideFingerprint: 'CERT-MACHINE-HW-SHA256-AAA111');
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
        technicianSecretHashOverride: PasswordHasher.hashPassword('TechCertSecret!2026'),
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
    // GATE 03: Complete State Machine & Forbidden State Transitions
    // =========================================================================
    test('GATE-03: Entitlement state transitions fail-closed against unauthorized reactivation', () async {
      final now = DateTime.now().toUtc();

      // 1. Fresh state is UNLICENSED
      final entFresh = await commService.getActiveEntitlement(hosp);
      expect(entFresh.status, equals(EntitlementStatus.unlicensed));
      expect(entFresh.isMutationAllowed, isFalse);

      // 2. Import valid active license -> VALID
      final validPayload = {
        'v': 1,
        'lid': 'LIC-ACTIVE-001',
        'hosp': hosp,
        'inst': 'INST-001',
        'hw': 'CERT-MACHINE-HW-SHA256-AAA111',
        'ed': 'PLATINUM',
        'iat': now.subtract(const Duration(days: 1)).toIso8601String(),
        'nbf': now.subtract(const Duration(days: 1)).toIso8601String(),
        'exp': now.add(const Duration(days: 30)).toIso8601String(),
        'maint_exp': now.add(const Duration(days: 30)).toIso8601String(),
        'mods': {'Patients': true, 'Surgery': true},
      };
      final tokenValid = authoritySigner.signLicenseLease(validPayload);
      final entActive = await commService.importSignedLicense(tokenValid, hospitalCode: hosp);
      expect(entActive.status, equals(EntitlementStatus.valid));
      expect(entActive.isMutationAllowed, isTrue);

      // 3. Import expired license -> EXPIRED_READ_ONLY
      final expiredPayload = Map<String, dynamic>.from(validPayload)
        ..['lid'] = 'LIC-EXP-002'
        ..['exp'] = now.subtract(const Duration(days: 5)).toIso8601String();
      final tokenExpired = authoritySigner.signLicenseLease(expiredPayload);
      final entExpired = await commService.importSignedLicense(tokenExpired, hospitalCode: hosp);
      expect(entExpired.status, equals(EntitlementStatus.expiredReadOnly));
      expect(entExpired.isMutationAllowed, isFalse);
      expect(entExpired.isReadOnlyAllowed, isTrue);

      // 4. RED TEAM ATTACK: Attempt unauthorized transition EXPIRED -> ACTIVE via raw SQL update
      await testDb.execute(
        "UPDATE mc_facility_config SET entitlement_status = 'VALID', subscription_expires_utc = '2099-12-31 23:59:59' WHERE hospital_code = '$hosp'",
      );
      // Re-query: Level 1 authoritative license on disk overrides and forces status back to EXPIRED_READ_ONLY
      final entRestored = await commService.getActiveEntitlement(hosp);
      expect(entRestored.status, equals(EntitlementStatus.expiredReadOnly));
      expect(entRestored.isMutationAllowed, isFalse);
    });

    // =========================================================================
    // GATE 04: 10 Adversarial Cryptographic License Mutations
    // =========================================================================
    test('GATE-04: Adversarial License Mutation Matrix rejects all 10 tampering vectors', () {
      final now = DateTime.now().toUtc();
      final basePayload = {
        'v': 1,
        'lid': 'LIC-BASE-001',
        'hosp': hosp,
        'inst': 'INST-001',
        'hw': 'CERT-MACHINE-HW-SHA256-AAA111',
        'ed': 'PLATINUM',
        'iat': now.subtract(const Duration(days: 1)).toIso8601String(),
        'nbf': now.subtract(const Duration(days: 1)).toIso8601String(),
        'exp': now.add(const Duration(days: 90)).toIso8601String(),
        'maint_exp': now.add(const Duration(days: 90)).toIso8601String(),
        'mods': {'Patients': true},
      };

      final validTokenStr = authoritySigner.signLicenseLease(basePayload);
      final validToken = SignedLicenseToken.parse(validTokenStr);
      expect(
        validToken.verifySignature(modulus: authoritySigner.modulus, publicExponent: authoritySigner.publicExponent),
        isTrue,
      );

      final parts = validTokenStr.split('.');
      final sigB64 = parts[2];

      void assertTamperedFails(String tamperedPayloadB64, String testName) {
        final forgedStr = 'MEDCORE_LIC_V1.$tamperedPayloadB64.$sigB64';
        bool valid = false;
        try {
          final parsed = SignedLicenseToken.parse(forgedStr);
          valid = parsed.verifySignature(
            modulus: authoritySigner.modulus,
            publicExponent: authoritySigner.publicExponent,
          );
        } catch (_) {
          // Parse rejection is a valid fail-closed rejection
          valid = false;
        }
        expect(valid, isFalse, reason: 'Tampering vector failed to reject: $testName');
      }

      String encodePayload(Map<String, dynamic> map) =>
          base64UrlEncode(utf8.encode(jsonEncode(map))).replaceAll('=', '');

      // 1. Change facility
      assertTamperedFails(encodePayload(Map.from(basePayload)..['hosp'] = 'HOSP_PIRATE_02'), 'Change facility');
      // 2. Change installation
      assertTamperedFails(encodePayload(Map.from(basePayload)..['inst'] = 'INST_CLONED_99'), 'Change installation');
      // 3. Change hardware
      assertTamperedFails(encodePayload(Map.from(basePayload)..['hw'] = 'HW_FORGED_MACHINE_888'), 'Change hardware');
      // 4. Change expiration
      assertTamperedFails(encodePayload(Map.from(basePayload)..['exp'] = '2099-12-31T23:59:59.000Z'), 'Change expiration');
      // 5. Change maintenance expiry
      assertTamperedFails(encodePayload(Map.from(basePayload)..['maint_exp'] = '2099-12-31T23:59:59.000Z'), 'Change maintenance');
      // 6. Modify payload bytes (flip a bit)
      final rawB64 = parts[1];
      final flipped = '${rawB64.substring(0, 10)}${rawB64[10] == 'A' ? 'B' : 'A'}${rawB64.substring(11)}';
      assertTamperedFails(flipped, 'Bit flip in payload');
      // 7. Corrupt signature
      final corruptSig = '${sigB64.substring(0, 10)}XXXX${sigB64.substring(14)}';
      final parsedCorruptSig = SignedLicenseToken.parse('MEDCORE_LIC_V1.${parts[1]}.$corruptSig');
      expect(
        parsedCorruptSig.verifySignature(
          modulus: authoritySigner.modulus,
          publicExponent: authoritySigner.publicExponent,
        ),
        isFalse,
      );
      // 8. Truncate signature
      final truncatedSig = sigB64.substring(0, 50);
      bool truncValid = false;
      try {
        truncValid = SignedLicenseToken.parse('MEDCORE_LIC_V1.${parts[1]}.$truncatedSig')
            .verifySignature(modulus: authoritySigner.modulus, publicExponent: authoritySigner.publicExponent);
      } catch (_) {
        truncValid = false;
      }
      expect(truncValid, isFalse);

      // 9. Append bytes to signature
      final appendedSig = '${sigB64}AAAA';
      bool appValid = false;
      try {
        appValid = SignedLicenseToken.parse('MEDCORE_LIC_V1.${parts[1]}.$appendedSig')
            .verifySignature(modulus: authoritySigner.modulus, publicExponent: authoritySigner.publicExponent);
      } catch (_) {
        appValid = false;
      }
      expect(appValid, isFalse);
      // 10. Replay token with wrong public key modulus
      final wrongModulus = authoritySigner.modulus + BigInt.from(2);
      expect(
        validToken.verifySignature(modulus: wrongModulus, publicExponent: authoritySigner.publicExponent),
        isFalse,
      );
    });

    // =========================================================================
    // GATE 05: Hardware Binding Derivation & Adversarial Machine Mismatch
    // =========================================================================
    test('GATE-05: Hardware binding derivation enforces physical workstation identity', () async {
      final hwReal = await hwService.getHardwareFingerprint();
      expect(hwReal.toUpperCase(), equals('CERT-MACHINE-HW-SHA256-AAA111'));

      // Test composite hashing logic with varying component values
      final fp1 = HardwareBindingService.calculateCompositeFingerprint(
        smbiosUuid: 'UUID-1234',
        motherboardSerial: 'MB-5678',
        diskSerial: 'DISK-9999',
      );
      final fp2 = HardwareBindingService.calculateCompositeFingerprint(
        smbiosUuid: 'UUID-1234',
        motherboardSerial: 'MB-5678',
        diskSerial: 'DISK-DIFFERENT',
      );
      expect(fp1, isNot(equals(fp2)), reason: 'Changed disk must produce different hardware fingerprint.');

      // Empty / missing component fallback must produce deterministic SHA-256
      final fpFallback = HardwareBindingService.calculateCompositeFingerprint(
        smbiosUuid: null,
        motherboardSerial: null,
        diskSerial: null,
      );
      expect(fpFallback.length, equals(64));
    });

    // =========================================================================
    // GATE 06: Database Copying & Cloning Attack
    // =========================================================================
    test('GATE-06: Copying database to another physical machine results in HARDWARE_BINDING_VIOLATION', () async {
      final now = DateTime.now().toUtc();
      // Provision valid license on machine A
      final validPayload = {
        'v': 1,
        'lid': 'LIC-HW-BOUND-001',
        'hosp': hosp,
        'inst': 'INST-001',
        'hw': 'CERT-MACHINE-HW-SHA256-AAA111',
        'ed': 'PLATINUM',
        'iat': now.toIso8601String(),
        'nbf': now.toIso8601String(),
        'exp': now.add(const Duration(days: 180)).toIso8601String(),
        'maint_exp': now.add(const Duration(days: 180)).toIso8601String(),
        'mods': {'Patients': true},
      };
      final token = authoritySigner.signLicenseLease(validPayload);
      await commService.importSignedLicense(token, hospitalCode: hosp);

      // Simulate running on Machine B with stolen/cloned database
      final clonedHwService = HardwareBindingService(overrideFingerprint: 'PIRATED-MACHINE-HW-BBB222');
      final clonedCommService = CommercialEntitlementService(
        db: testDb,
        securityRootDirectory: tempSecurityDir.path,
        hardwareService: clonedHwService,
        authorityModulusOverride: authoritySigner.modulus,
        authorityExponentOverride: authoritySigner.publicExponent,
      );

      final clonedEnt = await clonedCommService.getActiveEntitlement(hosp);
      expect(clonedEnt.status, equals(EntitlementStatus.tamperLocked));
      expect(clonedEnt.isMutationAllowed, isFalse);
      expect(clonedEnt.rejectionReason, contains('HARDWARE_BINDING_VIOLATION'));
    });

    // =========================================================================
    // GATE 07: Expiration, Read-Only Safety & Mutation Blockade
    // =========================================================================
    test('GATE-07: Expired state permits clinical reading but rejects mutations with 403', () async {
      final past = DateTime.now().toUtc().subtract(const Duration(days: 30));
      final expiredPayload = {
        'v': 1,
        'lid': 'LIC-EXPIRED-READ-ONLY',
        'hosp': hosp,
        'inst': 'INST-001',
        'hw': 'CERT-MACHINE-HW-SHA256-AAA111',
        'ed': 'PLATINUM',
        'iat': past.subtract(const Duration(days: 365)).toIso8601String(),
        'nbf': past.subtract(const Duration(days: 365)).toIso8601String(),
        'exp': past.toIso8601String(),
        'maint_exp': past.toIso8601String(),
        'mods': {'Patients': true},
      };
      final tokenExpired = authoritySigner.signLicenseLease(expiredPayload);
      await commService.importSignedLicense(tokenExpired, hospitalCode: hosp);

      // Verify active entitlement is EXPIRED_READ_ONLY
      final ent = await commService.getActiveEntitlement(hosp);
      expect(ent.status, equals(EntitlementStatus.expiredReadOnly));
      expect(ent.isMutationAllowed, isFalse);
      expect(ent.isReadOnlyAllowed, isTrue);

      // 1. GET /api/v1/health -> Allowed (Public)
      final healthRes = await http.get(Uri.parse('http://127.0.0.1:$serverPort/api/v1/health'));
      expect(healthRes.statusCode, equals(200));

      // 2. GET /api/v1/product/bootstrap -> Allowed (Clinical and facility reading)
      final getRes = await http.get(Uri.parse('http://127.0.0.1:$serverPort/api/v1/product/bootstrap?hospitalCode=$hosp'));
      expect(getRes.statusCode, equals(200));

      // 3. POST /api/v1/staff -> Blocked with 403 SUBSCRIPTION_EXPIRED
      final postRes = await http.post(
        Uri.parse('http://127.0.0.1:$serverPort/api/v1/staff'),
        headers: {
          'content-type': 'application/json',
          'x-tenant-id': hosp,
        },
        body: jsonEncode({'staffCode': 'DR-MUTATION-ATTEMPT', 'fullName': 'Dr Hacker'}),
      );
      expect(postRes.statusCode, equals(403));
      final errBody = jsonDecode(postRes.body);
      expect(errBody['ok'], isFalse);
      expect(errBody['error']['code'], equals('SUBSCRIPTION_EXPIRED'));
      expect(errBody['error']['status'], equals('EXPIRED_READ_ONLY'));
    });
  });
}
