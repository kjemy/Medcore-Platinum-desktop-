import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:medcore_local_service/medcore_local_service.dart';
import 'package:medcore_local_service/src/product/facility_config_service.dart';
import 'package:medcore_local_service/src/security/commercial_entitlement_service.dart';
import 'package:medcore_local_service/src/security/hardware_binding_service.dart';
import 'package:test/test.dart';

import 'support/test_authority_signer.dart';
import 'support/test_db_config.dart';

void main() {
  group('GATE-15 & GATE-16: Commercial Bypass Red Team (35 Attack Vectors) & Clinical Safety', () {
    const testDbName = 'medcore_redteam_35_test';
    const hosp = 'HOSP_REDTEAM_35';
    const validHwFingerprint = 'rt35-hardware-sha256-genuine-999';
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
      tempSecurityDir = Directory.systemTemp.createTempSync('medcore_rt35_sec_');

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

      // Seed tenant
      await testDb.execute(
        "INSERT INTO mc_tenants (hospital_code, name, status) VALUES ('$hosp', 'RedTeam General Hospital', 'active') "
        "ON DUPLICATE KEY UPDATE status = 'active';",
      );

      hwService = HardwareBindingService(overrideFingerprint: validHwFingerprint);

      server = LocalMedCoreServer(
        testDb,
        securityRootDirectory: tempSecurityDir.path,
        technicianSecretHashOverride: PasswordHasher.hashPassword('TechRedTeamSecret!2026'),
        hardwareBindingService: hwService,
        maintenanceTokenService: MaintenanceTokenService(
          modulus: authoritySigner.modulus,
          publicExponent: authoritySigner.publicExponent,
        ),
      );
      commService = server.commercialEntitlementService;
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

    Map<String, dynamic> createBasePayload({
      String? licenseId,
      String? hospitalCode,
      String? hwFingerprint,
      DateTime? exp,
      DateTime? maintExp,
    }) {
      final now = DateTime.now().toUtc();
      return {
        'v': 1,
        'lid': licenseId ?? 'LIC-RT35-CANONICAL-001',
        'hosp': hospitalCode ?? hosp,
        'inst': 'INST-RT35-001',
        'hw': hwFingerprint ?? validHwFingerprint,
        'ed': 'PLATINUM',
        'iat': now.toIso8601String(),
        'nbf': now.toIso8601String(),
        'exp': (exp ?? now.add(const Duration(days: 365))).toIso8601String(),
        'maint_exp': (maintExp ?? now.add(const Duration(days: 365))).toIso8601String(),
        'mods': {'Patients': true, 'Surgery': true, 'ICU': true},
      };
    }

    // =========================================================================
    // CATEGORY 1: CRYPTOGRAPHIC LICENSE TOKEN TAMPERING (VECTORS 01 - 15)
    // =========================================================================
    group('Category 1: Cryptographic Token Tampering (Vectors 01-15)', () {
      test('Vector 01: Tampering header version rejected', () {
        final token = authoritySigner.signLicenseLease(createBasePayload());
        final parts = token.split('.');
        final modifiedHeader = base64Url.encode(utf8.encode(jsonEncode({'alg': 'RS256', 'typ': 'MEDCORE-LIC', 'v': 99})));
        final tamperedToken = '$modifiedHeader.${parts[1]}.${parts[2]}';
        expect(() => SignedLicenseToken.parse(tamperedToken), throwsA(isA<Exception>()));
      });

      test('Vector 02: Tampering license_id in payload rejected by RSA signature', () {
        final token = authoritySigner.signLicenseLease(createBasePayload(licenseId: 'ORIGINAL-ID'));
        final parsed = SignedLicenseToken.parse(token);
        final tamperedPayload = Map<String, dynamic>.from(parsed.payload);
        tamperedPayload['lid'] = 'FORGED-ID';
        final tamperedPayloadB64 = base64Url.encode(utf8.encode(jsonEncode(tamperedPayload)));
        final tamperedToken = SignedLicenseToken.parse('${parsed.rawToken.split('.')[0]}.$tamperedPayloadB64.${parsed.rawToken.split('.')[2]}');
        expect(tamperedToken.verifySignature(modulus: authoritySigner.modulus, publicExponent: authoritySigner.publicExponent), isFalse);
      });

      test('Vector 03: Tampering hospital code in payload rejected by RSA signature', () {
        final token = authoritySigner.signLicenseLease(createBasePayload(hospitalCode: hosp));
        final parsed = SignedLicenseToken.parse(token);
        final tamperedPayload = Map<String, dynamic>.from(parsed.payload);
        tamperedPayload['hosp'] = 'ROGUE_HOSP_99';
        final tamperedPayloadB64 = base64Url.encode(utf8.encode(jsonEncode(tamperedPayload)));
        final tamperedToken = SignedLicenseToken.parse('${parsed.rawToken.split('.')[0]}.$tamperedPayloadB64.${parsed.rawToken.split('.')[2]}');
        expect(tamperedToken.verifySignature(modulus: authoritySigner.modulus, publicExponent: authoritySigner.publicExponent), isFalse);
      });

      test('Vector 04: Tampering installation ID in payload rejected by RSA signature', () {
        final token = authoritySigner.signLicenseLease(createBasePayload());
        final parsed = SignedLicenseToken.parse(token);
        final tamperedPayload = Map<String, dynamic>.from(parsed.payload);
        tamperedPayload['inst'] = 'INST-ROGUE-999';
        final tamperedPayloadB64 = base64Url.encode(utf8.encode(jsonEncode(tamperedPayload)));
        final tamperedToken = SignedLicenseToken.parse('${parsed.rawToken.split('.')[0]}.$tamperedPayloadB64.${parsed.rawToken.split('.')[2]}');
        expect(tamperedToken.verifySignature(modulus: authoritySigner.modulus, publicExponent: authoritySigner.publicExponent), isFalse);
      });

      test('Vector 05: Tampering hardware fingerprint in payload rejected by RSA signature', () {
        final token = authoritySigner.signLicenseLease(createBasePayload());
        final parsed = SignedLicenseToken.parse(token);
        final tamperedPayload = Map<String, dynamic>.from(parsed.payload);
        tamperedPayload['hw'] = 'hw-tampered-fingerprint';
        final tamperedPayloadB64 = base64Url.encode(utf8.encode(jsonEncode(tamperedPayload)));
        final tamperedToken = SignedLicenseToken.parse('${parsed.rawToken.split('.')[0]}.$tamperedPayloadB64.${parsed.rawToken.split('.')[2]}');
        expect(tamperedToken.verifySignature(modulus: authoritySigner.modulus, publicExponent: authoritySigner.publicExponent), isFalse);
      });

      test('Vector 06: Tampering edition from STANDARD to PLATINUM rejected', () {
        final base = createBasePayload();
        base['ed'] = 'STANDARD';
        final token = authoritySigner.signLicenseLease(base);
        final parsed = SignedLicenseToken.parse(token);
        final tamperedPayload = Map<String, dynamic>.from(parsed.payload);
        tamperedPayload['ed'] = 'PLATINUM';
        final tamperedPayloadB64 = base64Url.encode(utf8.encode(jsonEncode(tamperedPayload)));
        final tamperedToken = SignedLicenseToken.parse('${parsed.rawToken.split('.')[0]}.$tamperedPayloadB64.${parsed.rawToken.split('.')[2]}');
        expect(tamperedToken.verifySignature(modulus: authoritySigner.modulus, publicExponent: authoritySigner.publicExponent), isFalse);
      });

      test('Vector 07: Extending subscription expiration date rejected', () {
        final token = authoritySigner.signLicenseLease(createBasePayload());
        final parsed = SignedLicenseToken.parse(token);
        final tamperedPayload = Map<String, dynamic>.from(parsed.payload);
        tamperedPayload['exp'] = '2099-12-31T23:59:59.000Z';
        final tamperedPayloadB64 = base64Url.encode(utf8.encode(jsonEncode(tamperedPayload)));
        final tamperedToken = SignedLicenseToken.parse('${parsed.rawToken.split('.')[0]}.$tamperedPayloadB64.${parsed.rawToken.split('.')[2]}');
        expect(tamperedToken.verifySignature(modulus: authoritySigner.modulus, publicExponent: authoritySigner.publicExponent), isFalse);
      });

      test('Vector 08: Extending maintenance expiration date rejected', () {
        final token = authoritySigner.signLicenseLease(createBasePayload());
        final parsed = SignedLicenseToken.parse(token);
        final tamperedPayload = Map<String, dynamic>.from(parsed.payload);
        tamperedPayload['maint_exp'] = '2099-12-31T23:59:59.000Z';
        final tamperedPayloadB64 = base64Url.encode(utf8.encode(jsonEncode(tamperedPayload)));
        final tamperedToken = SignedLicenseToken.parse('${parsed.rawToken.split('.')[0]}.$tamperedPayloadB64.${parsed.rawToken.split('.')[2]}');
        expect(tamperedToken.verifySignature(modulus: authoritySigner.modulus, publicExponent: authoritySigner.publicExponent), isFalse);
      });

      test('Vector 09: Injecting unpurchased modules rejected', () {
        final token = authoritySigner.signLicenseLease(createBasePayload());
        final parsed = SignedLicenseToken.parse(token);
        final tamperedPayload = Map<String, dynamic>.from(parsed.payload);
        tamperedPayload['mods'] = {'Patients': true, 'Surgery': true, 'Cardiology': true, 'AI_Enterprise': true};
        final tamperedPayloadB64 = base64Url.encode(utf8.encode(jsonEncode(tamperedPayload)));
        final tamperedToken = SignedLicenseToken.parse('${parsed.rawToken.split('.')[0]}.$tamperedPayloadB64.${parsed.rawToken.split('.')[2]}');
        expect(tamperedToken.verifySignature(modulus: authoritySigner.modulus, publicExponent: authoritySigner.publicExponent), isFalse);
      });

      test('Vector 10: Inverting single bit in base64url payload rejected', () {
        final token = authoritySigner.signLicenseLease(createBasePayload());
        final parts = token.split('.');
        final p = parts[1];
        final flippedChar = p[5] == 'A' ? 'B' : 'A';
        final corruptedPayload = p.substring(0, 5) + flippedChar + p.substring(6);
        final tamperedToken = '${parts[0]}.$corruptedPayload.${parts[2]}';
        try {
          final parsed = SignedLicenseToken.parse(tamperedToken);
          expect(parsed.verifySignature(modulus: authoritySigner.modulus, publicExponent: authoritySigner.publicExponent), isFalse);
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });

      test('Vector 11: Inverting single bit in RSA signature rejected', () {
        final token = authoritySigner.signLicenseLease(createBasePayload());
        final parts = token.split('.');
        final sig = parts[2];
        final flippedChar = sig[10] == 'X' ? 'Y' : 'X';
        final corruptedSig = sig.substring(0, 10) + flippedChar + sig.substring(11);
        final tamperedToken = '${parts[0]}.${parts[1]}.$corruptedSig';
        final parsed = SignedLicenseToken.parse(tamperedToken);
        expect(parsed.verifySignature(modulus: authoritySigner.modulus, publicExponent: authoritySigner.publicExponent), isFalse);
      });

      test('Vector 12: Truncating RSA signature bytes rejected', () {
        final token = authoritySigner.signLicenseLease(createBasePayload());
        final parts = token.split('.');
        final truncatedSig = parts[2].substring(0, parts[2].length ~/ 2);
        final tamperedToken = '${parts[0]}.${parts[1]}.$truncatedSig';
        try {
          final parsed = SignedLicenseToken.parse(tamperedToken);
          expect(parsed.verifySignature(modulus: authoritySigner.modulus, publicExponent: authoritySigner.publicExponent), isFalse);
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });

      test('Vector 13: Appending trailing bytes to signature rejected', () {
        final token = authoritySigner.signLicenseLease(createBasePayload());
        final parts = token.split('.');
        final extendedSig = parts[2] + base64Url.encode(utf8.encode('EXTRA_GARBAGE_BYTES'));
        final tamperedToken = '${parts[0]}.${parts[1]}.$extendedSig';
        try {
          final parsed = SignedLicenseToken.parse(tamperedToken);
          expect(parsed.verifySignature(modulus: authoritySigner.modulus, publicExponent: authoritySigner.publicExponent), isFalse);
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });

      test('Vector 14: Verification against rogue/attacker RSA modulus rejected', () {
        final token = authoritySigner.signLicenseLease(createBasePayload());
        final parsed = SignedLicenseToken.parse(token);
        final rogueModulus = BigInt.parse('112233445566778899AABBCCDDEEFF0011223344', radix: 16);
        expect(parsed.verifySignature(modulus: rogueModulus, publicExponent: authoritySigner.publicExponent), isFalse);
      });

      test('Vector 15: Malformed token structures (missing parts / empty string) rejected', () {
        expect(() => SignedLicenseToken.parse(''), throwsA(isA<Exception>()));
        expect(() => SignedLicenseToken.parse('ONLY_ONE_PART'), throwsA(isA<Exception>()));
        expect(() => SignedLicenseToken.parse('PART1.PART2'), throwsA(isA<Exception>()));
        expect(() => SignedLicenseToken.parse('P1.P2.P3.P4'), throwsA(isA<Exception>()));
      });
    });

    // =========================================================================
    // CATEGORY 2: DATABASE OUT-OF-BAND STATE TAMPERING (VECTORS 16 - 22)
    // =========================================================================
    group('Category 2: Database Out-of-Band State Tampering (Vectors 16-22)', () {
      test('Vector 16: Direct SQL update of mc_license_state.status = VALID overwritten by disk truth', () async {
        final licFile = File('${tempSecurityDir.path}/license.mclic');
        if (licFile.existsSync()) licFile.deleteSync();

        await testDb.execute(
          "INSERT INTO mc_license_state (hospital_code, license_id, edition, entitled_modules_json, max_devices, max_doctors, ai_entitled, issued_at_utc, expires_at_utc, offline_grace_until_utc, last_online_refresh_utc, lease_payload_json, ed25519_signature, status) "
          "VALUES ('$hosp', 'FORGED-DB-ID', 'PLATINUM', '{}', 50, 50, 1, NOW(), DATE_ADD(NOW(), INTERVAL 365 DAY), DATE_ADD(NOW(), INTERVAL 365 DAY), NOW(), 'RAW_FORGED', 'SIG', 'VALID') "
          "ON DUPLICATE KEY UPDATE status = 'VALID', lease_payload_json = 'RAW_FORGED';",
        );

        final ent = await commService.getActiveEntitlement(hosp);
        expect(ent.status, equals(EntitlementStatus.unlicensed));
      });

      test('Vector 17: Direct SQL update of mc_license_state.expires_at_utc overwritten by signed disk truth', () async {
        final token = authoritySigner.signLicenseLease(createBasePayload());
        await commService.importSignedLicense(token, hospitalCode: hosp);

        await testDb.execute(
          "UPDATE mc_license_state SET expires_at_utc = '2099-01-01 00:00:00' WHERE hospital_code = '$hosp'",
        );

        final ent = await commService.getActiveEntitlement(hosp);
        expect(ent.status, equals(EntitlementStatus.valid));
        expect(ent.expiresAtUtc.year, isNot(equals(2099)));
      });

      test('Vector 18: Direct SQL update of hmac_seal causes fail-closed reconciliation', () async {
        await testDb.execute(
          "UPDATE mc_license_state SET hmac_seal = '00000000000000000000000000000000' WHERE hospital_code = '$hosp'",
        );
        final ent = await commService.getActiveEntitlement(hosp);
        expect(ent.status, equals(EntitlementStatus.valid));
      });

      test('Vector 19: Direct SQL update mc_facility_config.subscription_expires_utc = NULL rejected', () async {
        await testDb.execute(
          "UPDATE mc_facility_config SET subscription_expires_utc = NULL WHERE hospital_code = '$hosp'",
        );
        final facService = FacilityConfigService(testDb);
        final config = await facService.getConfiguration(hosp);
        expect(config.subscriptionExpiresUtc, isNotNull);
      });

      test('Vector 20: Direct SQL update mc_facility_config.edition = ENTERPRISE_UNLIMITED on unlicensed host fails closed', () async {
        final licFile = File('${tempSecurityDir.path}/license.mclic');
        if (licFile.existsSync()) licFile.deleteSync();
        await testDb.execute("DELETE FROM mc_license_state WHERE hospital_code = '$hosp'");

        await testDb.execute(
          "UPDATE mc_facility_config SET edition = 'ENTERPRISE_UNLIMITED', subscription_expires_utc = '2099-01-01 00:00:00' WHERE hospital_code = '$hosp'",
        );
        final ent = await commService.getActiveEntitlement(hosp);
        expect(ent.isMutationAllowed, isFalse);
        expect(ent.status, equals(EntitlementStatus.unlicensed));
      });

      test('Vector 21: Direct DELETE of mc_license_state row fails closed to disk token', () async {
        final token = authoritySigner.signLicenseLease(createBasePayload());
        await commService.importSignedLicense(token, hospitalCode: hosp);

        await testDb.execute("DELETE FROM mc_license_state WHERE hospital_code = '$hosp'");
        final ent = await commService.getActiveEntitlement(hosp);
        expect(ent.status, equals(EntitlementStatus.valid));
      });

      test('Vector 22: Direct SQL manipulation of mc_clock_guard detected as tampering', () async {
        final clockRepo = ClockGuardRepository(testDb, securityRootDirectory: tempSecurityDir.path);
        final now = DateTime.now().toUtc();
        await clockRepo.evaluateAndUpdateClock(hospitalCode: hosp, currentWallClock: now);

        await testDb.execute(
          "UPDATE mc_clock_guard SET max_observed_utc = DATE_ADD(NOW(), INTERVAL 10 DAY) WHERE hospital_code = '$hosp'",
        );

        // Direct SQL modification corrupts HMAC or triggers rollback detection
        try {
          final rollback = await clockRepo.evaluateAndUpdateClock(hospitalCode: hosp, currentWallClock: now);
          expect(rollback.rollbackDetected, isTrue);
        } on ClockTamperException catch (e) {
          expect(e.message, contains('HMAC verification failed'));
        }
      });
    });

    // =========================================================================
    // CATEGORY 3: CLOCK AND TEMPORAL MANIPULATION (VECTORS 23 - 28)
    // =========================================================================
    group('Category 3: Clock and Temporal Manipulation (Vectors 23-28)', () {
      test('Vector 23: OS wall clock rewind by 1 hour detected as tampering', () async {
        final clockRepo = ClockGuardRepository(testDb, securityRootDirectory: tempSecurityDir.path);
        final base = DateTime.now().toUtc();
        await clockRepo.evaluateAndUpdateClock(hospitalCode: 'HOSP_CLK_01', currentWallClock: base);

        final rewound = base.subtract(const Duration(hours: 1));
        final res = await clockRepo.evaluateAndUpdateClock(hospitalCode: 'HOSP_CLK_01', currentWallClock: rewound);
        expect(res.rollbackDetected, isTrue);
      });

      test('Vector 24: OS wall clock rewind by 30 days detected as tampering', () async {
        final clockRepo = ClockGuardRepository(testDb, securityRootDirectory: tempSecurityDir.path);
        final base = DateTime.now().toUtc();
        await clockRepo.evaluateAndUpdateClock(hospitalCode: 'HOSP_CLK_02', currentWallClock: base);

        final rewound = base.subtract(const Duration(days: 30));
        final res = await clockRepo.evaluateAndUpdateClock(hospitalCode: 'HOSP_CLK_02', currentWallClock: rewound);
        expect(res.rollbackDetected, isTrue);
      });

      test('Vector 25: Forward time progression evaluated without false tamper alert', () async {
        final clockRepo = ClockGuardRepository(testDb, securityRootDirectory: tempSecurityDir.path);
        final base = DateTime.now().toUtc();
        await clockRepo.evaluateAndUpdateClock(hospitalCode: 'HOSP_CLK_03', currentWallClock: base);

        final forward = base.add(const Duration(hours: 2));
        final res = await clockRepo.evaluateAndUpdateClock(hospitalCode: 'HOSP_CLK_03', currentWallClock: forward);
        expect(res.rollbackDetected, isFalse);
      });

      test('Vector 26: Hardware binding mismatch triggers TAMPER_LOCKED', () async {
        final validToken = authoritySigner.signLicenseLease(createBasePayload(
          hwFingerprint: validHwFingerprint,
        ));
        await commService.importSignedLicense(validToken, hospitalCode: hosp);

        // Cloned machine with different hardware fingerprint accessing the license
        final foreignHwService = HardwareBindingService(overrideFingerprint: 'rogue-pirate-machine-hw-sha256-000');
        final foreignCommService = CommercialEntitlementService(
          db: testDb,
          securityRootDirectory: tempSecurityDir.path,
          hardwareService: foreignHwService,
          authorityModulusOverride: authoritySigner.modulus,
          authorityExponentOverride: authoritySigner.publicExponent,
        );

        final ent = await foreignCommService.getActiveEntitlement(hosp);
        expect(ent.status, equals(EntitlementStatus.tamperLocked));
        expect(ent.isMutationAllowed, isFalse);
      });

      test('Vector 27: Missing hardware fingerprint in license rejected as untrusted', () {
        final payload = createBasePayload();
        payload.remove('hw');
        final token = authoritySigner.signLicenseLease(payload);
        final parsed = SignedLicenseToken.parse(token);
        expect(hwService.verifyHardwareBinding(expectedFingerprint: parsed.payload['hw']?.toString() ?? '', actualFingerprint: validHwFingerprint), isFalse);
      });

      test('Vector 28: Expired license transitions to EXPIRED_READ_ONLY with zero grace period evasion', () async {
        final expiredToken = authoritySigner.signLicenseLease(createBasePayload(
          exp: DateTime.now().toUtc().subtract(const Duration(days: 20)),
        ));
        await commService.importSignedLicense(expiredToken, hospitalCode: hosp);

        final ent = await commService.getActiveEntitlement(hosp);
        expect(ent.status, equals(EntitlementStatus.expiredReadOnly));
        expect(ent.isMutationAllowed, isFalse);
      });
    });

    // =========================================================================
    // CATEGORY 4: ENDPOINT MUTATION BYPASS & CLINICAL SAFETY (VECTORS 29 - 35)
    // =========================================================================
    group('Category 4: Endpoint Mutation Bypass & Clinical Safety (Vectors 29-35)', () {
      test('Vector 29: Unauthenticated technician import strictly rejected with 401', () async {
        final token = authoritySigner.signLicenseLease(createBasePayload());
        final res = await http.post(
          Uri.parse('http://127.0.0.1:$serverPort/api/v1/technician/license/import'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'licenseToken': token}),
        );
        expect(res.statusCode, equals(401));
      });

      test('Vector 30: Forged technician token strictly rejected with 401 or 403', () async {
        final token = authoritySigner.signLicenseLease(createBasePayload());
        final res = await http.post(
          Uri.parse('http://127.0.0.1:$serverPort/api/v1/technician/license/import'),
          headers: {
            'content-type': 'application/json',
            'x-medcore-tech-token': 'FORGED_SESSION_TOKEN_XYZ',
            'x-tenant-id': hosp,
            'x-medcore-device-id': 'DEV-INDEP-TEST',
          },
          body: jsonEncode({'licenseToken': token}),
        );
        expect(res.statusCode, anyOf([equals(401), equals(403)]));
      });

      test('Vector 31: POST mutation rejected with HTTP 403 under EXPIRED_READ_ONLY', () async {
        final expiredToken = authoritySigner.signLicenseLease(createBasePayload(
          exp: DateTime.now().toUtc().subtract(const Duration(days: 20)),
        ));
        await commService.importSignedLicense(expiredToken, hospitalCode: hosp);

        final res = await http.post(
          Uri.parse('http://127.0.0.1:$serverPort/api/v1/staff'),
          headers: {
            'content-type': 'application/json',
            'x-tenant-id': hosp,
          },
          body: jsonEncode({'staffCode': 'DR-TEST-01', 'fullName': 'Dr Adversary'}),
        );
        expect(res.statusCode, equals(403));
        final body = jsonDecode(res.body);
        expect(body['ok'], isFalse);
        expect(body['error']['code'], equals('SUBSCRIPTION_EXPIRED'));
      });

      test('Vector 32: POST mutation rejected with HTTP 403 under TAMPER_LOCKED', () async {
        final foreignToken = authoritySigner.signLicenseLease(createBasePayload(
          hwFingerprint: 'wrong-machine-hw-sha256',
        ));
        File('${tempSecurityDir.path}/license.mclic').writeAsStringSync(foreignToken);

        final res = await http.post(
          Uri.parse('http://127.0.0.1:$serverPort/api/v1/staff'),
          headers: {
            'content-type': 'application/json',
            'x-tenant-id': hosp,
          },
          body: jsonEncode({'staffCode': 'DR-TEST-02', 'fullName': 'Dr Tamper'}),
        );
        expect(res.statusCode, equals(403));
        final body = jsonDecode(res.body);
        expect(body['ok'], isFalse);
        expect(body['error']['code'], equals('SUBSCRIPTION_EXPIRED'));
        expect(body['error']['status'], equals('TAMPER_LOCKED'));
      });

      test('Vector 33: POST mutation rejected with HTTP 403 under UNLICENSED', () async {
        final licFile = File('${tempSecurityDir.path}/license.mclic');
        if (licFile.existsSync()) licFile.deleteSync();
        await testDb.execute("DELETE FROM mc_license_state WHERE hospital_code = '$hosp'");

        final res = await http.post(
          Uri.parse('http://127.0.0.1:$serverPort/api/v1/staff'),
          headers: {
            'content-type': 'application/json',
            'x-tenant-id': hosp,
          },
          body: jsonEncode({'staffCode': 'DR-TEST-03', 'fullName': 'Dr Unlicensed'}),
        );
        expect(res.statusCode, equals(403));
        final body = jsonDecode(res.body);
        expect(body['ok'], isFalse);
        expect(body['error']['code'], equals('SUBSCRIPTION_EXPIRED'));
        expect(body['error']['status'], equals('UNLICENSED'));
      });

      test('Vector 34: Clinical Read permitted with HTTP 200 under EXPIRED_READ_ONLY (Patient Safety)', () async {
        final expiredToken = authoritySigner.signLicenseLease(createBasePayload(
          exp: DateTime.now().toUtc().subtract(const Duration(days: 20)),
        ));
        await commService.importSignedLicense(expiredToken, hospitalCode: hosp);

        final res = await http.get(
          Uri.parse('http://127.0.0.1:$serverPort/api/v1/product/bootstrap?hospitalCode=$hosp'),
          headers: {'x-tenant-id': hosp},
        );
        expect(res.statusCode, equals(200));
        final body = jsonDecode(res.body);
        expect(body['ok'], isTrue);
        expect(body['data']['isSubscriptionExpired'], isTrue);
      });

      test('Vector 35: Clinical Read permitted with HTTP 200 under TAMPER_LOCKED (Patient Safety)', () async {
        final foreignToken = authoritySigner.signLicenseLease(createBasePayload(
          hwFingerprint: 'tampered-machine-hw-sha256',
        ));
        File('${tempSecurityDir.path}/license.mclic').writeAsStringSync(foreignToken);

        final res = await http.get(
          Uri.parse('http://127.0.0.1:$serverPort/api/v1/product/bootstrap?hospitalCode=$hosp'),
          headers: {'x-tenant-id': hosp},
        );
        expect(res.statusCode, equals(200));
        final body = jsonDecode(res.body);
        expect(body['ok'], isTrue);
      });
    });
  });
}
