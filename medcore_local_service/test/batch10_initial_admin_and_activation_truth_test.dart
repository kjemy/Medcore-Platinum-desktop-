import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:medcore_local_service/medcore_local_service.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'support/test_db_config.dart';

void main() {
  late DbClient db;
  late MigrationRunner migrationRunner;
  LocalMedCoreServer? server;
  late String baseUrl;
  late Directory securityRoot;
  late String techSecretHash;
  late String techToken;

  const hospitalCode = 'HOSP_BATCH9';
  const deviceId = 'DEV-MAIN-HOST';
  final serviceRoot = Directory.current.path;
  final migrationsDir = p.join(serviceRoot, 'sql', 'migrations');

  setUpAll(() async {
    securityRoot = Directory.systemTemp.createTempSync('medcore-b9-root-');
    final config = testDbConfig(databaseName: 'medcore_test_batch9', maxConnections: 10);
    db = DbClient(config);

    final adminConn = await db.openDedicatedConnection(useDatabase: false);
    try {
      await adminConn.execute('DROP DATABASE IF EXISTS `medcore_test_batch9`');
      await adminConn.execute(
        'CREATE DATABASE `medcore_test_batch9` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
      );
    } finally {
      await adminConn.close();
    }

    migrationRunner = MigrationRunner(db: db, migrationsDir: migrationsDir);
    await migrationRunner.runMigrations();

    // Setup technician secret
    const rawSecret = 'CertifiedTechnicianSecret#2026';
    techSecretHash = PasswordHasher.hashPassword(rawSecret);

    server = LocalMedCoreServer(
      db,
      securityRootDirectory: securityRoot.path,
      technicianSecretHashOverride: techSecretHash,
    );
    final port = await server!.start(address: '127.0.0.1', port: 0);
    baseUrl = 'http://127.0.0.1:$port';

    // Seed tenant, device, and facility config (without staff!)
    final conn = await db.openDedicatedConnection(useDatabase: true);
    try {
      await conn.execute('''
        INSERT INTO mc_tenants (hospital_code, name, status)
        VALUES ('$hospitalCode', 'Batch 9 Reference Hospital', 'active')
      ''');

      final govRepo = TenantGovernanceRepository(db);
      await govRepo.enrollOrUpdateDevice(
        hospitalCode: hospitalCode,
        deviceId: deviceId,
        deviceName: 'Host Workstation',
        platform: 'WINDOWS',
        hwFingerprintSha256: PasswordHasher.sha256Hex('HW-B9-HOST'),
        devicePublicKeyEd25519: 'pk_host_b9',
        roleScope: 'SERVER_HOST',
        isTrustedSecureRuntime: true,
        status: 'ACTIVE',
      );

      final facilityService = FacilityConfigService(db);
      await facilityService.saveConfigurationFromTechnician(
        hospitalCode: hospitalCode,
        technicianSessionUuid: 'SES-INIT-BOOTSTRAP',
        payload: {
          'facilityName': 'Batch 9 Reference Medical Center',
          'facilityType': 'GENERAL_HOSPITAL',
          'branchCode': 'MAIN',
          'edition': 'PLATINUM',
          'subscriptionStartsUtc': '2026-01-01T00:00:00Z',
          'subscriptionExpiresUtc': '2027-12-31T23:59:59Z',
          'applyEditionModulePreset': true,
        },
        deviceId: deviceId,
      );
    } finally {
      await conn.close();
    }

    // Open technician session to obtain valid X-MedCore-Tech-Token
    final openResp = await http.post(
      Uri.parse('$baseUrl/api/v1/technician/session/open'),
      headers: {
        'content-type': 'application/json',
        'x-tenant-id': hospitalCode,
        'x-medcore-device-id': deviceId,
      },
      body: jsonEncode({
        'hospitalCode': hospitalCode,
        'deviceId': deviceId,
        'technicianSecret': rawSecret,
      }),
    );
    expect(openResp.statusCode, equals(201));
    final openBody = jsonDecode(openResp.body)['data'] as Map<String, dynamic>;
    techToken = openBody['technicianToken'] as String;
    expect(techToken, isNotEmpty);
  });

  tearDownAll(() async {
    if (server != null) {
      await server!.stop();
    }
    await db.close();
    try {
      securityRoot.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('BATCH 9 — Initial Administrator Provisioning & Handover Truth', () {
    test('1. Initial admin status reports hasAdmin = false before provisioning', () async {
      final resp = await http.get(
        Uri.parse('$baseUrl/api/v1/technician/initial-admin/status'),
        headers: {
          'x-tenant-id': hospitalCode,
          'x-medcore-device-id': deviceId,
          'x-medcore-tech-token': techToken,
        },
      );
      expect(resp.statusCode, equals(200));
      final data = jsonDecode(resp.body)['data'] as Map<String, dynamic>;
      expect(data['hasAdmin'], isFalse);
      expect(data['totalStaffCount'], equals(0));
      expect(data['administrators'], isEmpty);
    });

    test('2. Unauthorized request without technician token is strictly rejected (401 or 403)', () async {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/initial-admin'),
        headers: {
          'content-type': 'application/json',
          'x-tenant-id': hospitalCode,
          'x-medcore-device-id': deviceId,
          // Missing x-medcore-tech-token
        },
        body: jsonEncode({
          'staffCode': 'ADM-999',
          'fullName': 'Attacker Admin',
          'email': 'attacker@medcore.local',
        }),
      );
      expect(resp.statusCode, anyOf(401, 403));
    });

    late String generatedTemporaryPassword;

    test('3. Technician provisions initial Hospital Administrator with forced password change', () async {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/initial-admin'),
        headers: {
          'content-type': 'application/json',
          'x-tenant-id': hospitalCode,
          'x-medcore-device-id': deviceId,
          'x-medcore-tech-token': techToken,
        },
        body: jsonEncode({
          'staffCode': 'ADM-001',
          'fullName': 'Dr. Sarah Connor / Hospital Director',
          'email': 'director@batch9hospital.org',
          'phone': '+1 555-0100',
          'nationalId': 'NAT-998877',
        }),
      );
      expect(resp.statusCode, equals(201));
      final data = jsonDecode(resp.body)['data'] as Map<String, dynamic>;
      expect(data['status'], equals('SUCCESS'));
      expect(data['forcePasswordChange'], isTrue);
      expect(data['facilityCode'], equals(hospitalCode));

      generatedTemporaryPassword = data['handoverTemporaryPassword'] as String;
      expect(generatedTemporaryPassword, isNotEmpty);
      expect(generatedTemporaryPassword.length, greaterThanOrEqualTo(8));

      final admin = data['admin'] as Map<String, dynamic>;
      expect(admin['staffCode'], equals('ADM-001'));
      expect(admin['fullName'], equals('Dr. Sarah Connor / Hospital Director'));
      expect(admin['email'], equals('director@batch9hospital.org'));
      expect(admin['role'], equals('HospitalAdmin'));
      expect(admin['isActive'], isTrue);
      expect(admin['forcePasswordChange'], isTrue);

      // Verify physical MariaDB state reification
      final readConn = await db.openDedicatedConnection(useDatabase: true);
      try {
        final rows = await readConn.execute(
          'SELECT staff_code, role, force_password_change, is_active FROM mc_staff WHERE hospital_code = :hosp AND staff_code = :code',
          {'hosp': hospitalCode, 'code': 'ADM-001'},
        );
        expect(rows.rows.length, equals(1));
        final row = rows.rows.first;
        expect(row.colByName('staff_code'), equals('ADM-001'));
        expect(row.colByName('role'), equals('HospitalAdmin'));
        expect(row.colByName('force_password_change')?.toString(), equals('1'));
        expect(row.colByName('is_active')?.toString(), equals('1'));

        // Verify audit log reification
        final auditRows = await readConn.execute(
          'SELECT action, actor_role, entity_type, entity_id FROM mc_audit_logs WHERE hospital_code = :hosp AND action = :act',
          {'hosp': hospitalCode, 'act': 'technician.initial_admin.provisioned'},
        );
        expect(auditRows.rows.isNotEmpty, isTrue);
        expect(auditRows.rows.first.colByName('actor_role'), equals('TECHNICIAN_SERVICE'));
        expect(auditRows.rows.first.colByName('entity_id'), equals('ADM-001'));
      } finally {
        await readConn.close();
      }
    });

    test('4. Status endpoint now reports hasAdmin = true with the provisioned administrator', () async {
      final resp = await http.get(
        Uri.parse('$baseUrl/api/v1/technician/initial-admin/status'),
        headers: {
          'x-tenant-id': hospitalCode,
          'x-medcore-device-id': deviceId,
          'x-medcore-tech-token': techToken,
        },
      );
      expect(resp.statusCode, equals(200));
      final data = jsonDecode(resp.body)['data'] as Map<String, dynamic>;
      expect(data['hasAdmin'], isTrue);
      expect(data['totalStaffCount'], equals(1));
      final admins = data['administrators'] as List;
      expect(admins.length, equals(1));
      expect(admins[0]['staffCode'], equals('ADM-001'));
      expect(admins[0]['role'], equals('HospitalAdmin'));
      expect(admins[0]['forcePasswordChange'], isTrue);
    });

    test('5. Duplicate staffCode or email is rejected with 409 Conflict', () async {
      final duplicateCodeResp = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/initial-admin'),
        headers: {
          'content-type': 'application/json',
          'x-tenant-id': hospitalCode,
          'x-medcore-device-id': deviceId,
          'x-medcore-tech-token': techToken,
        },
        body: jsonEncode({
          'staffCode': 'ADM-001',
          'fullName': 'Duplicate Person',
          'email': 'another@batch9hospital.org',
        }),
      );
      expect(duplicateCodeResp.statusCode, equals(409));
      final dupCodeData = jsonDecode(duplicateCodeResp.body);
      expect(dupCodeData['error']['code'], equals('DUPLICATE_STAFF_CODE'));

      final duplicateEmailResp = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/initial-admin'),
        headers: {
          'content-type': 'application/json',
          'x-tenant-id': hospitalCode,
          'x-medcore-device-id': deviceId,
          'x-medcore-tech-token': techToken,
        },
        body: jsonEncode({
          'staffCode': 'ADM-002',
          'fullName': 'Duplicate Email Person',
          'email': 'director@batch9hospital.org',
        }),
      );
      expect(duplicateEmailResp.statusCode, equals(409));
      final dupEmailData = jsonDecode(duplicateEmailResp.body);
      expect(dupEmailData['error']['code'], equals('DUPLICATE_EMAIL'));
    });

    late String staffBearerToken;

    test('6. Initial Administrator logs in with temporary password; forcePasswordChange is signaled', () async {
      final loginResp = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/login'),
        headers: {
          'content-type': 'application/json',
          'x-tenant-id': hospitalCode,
          'x-medcore-device-id': deviceId,
        },
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'identifier': 'ADM-001',
          'password': generatedTemporaryPassword,
          'deviceId': deviceId,
        }),
      );
      expect(loginResp.statusCode, equals(200));
      final loginData = jsonDecode(loginResp.body)['data'] as Map<String, dynamic>;
      staffBearerToken = loginData['token'] as String;
      expect(staffBearerToken, isNotEmpty);

      final user = loginData['user'] as Map<String, dynamic>;
      expect(user['staffCode'], equals('ADM-001'));
      expect(user['role'], equals('HospitalAdmin'));
      expect(user['forcePasswordChange'], isTrue);
    });

    test('7. Password change enforcement: wrong old password (401) and weak new password (400) rejected', () async {
      // Wrong old password
      final wrongOldResp = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/change-password'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $staffBearerToken',
          'x-tenant-id': hospitalCode,
          'x-medcore-device-id': deviceId,
        },
        body: jsonEncode({
          'oldPassword': 'WrongOldPassword123!',
          'newPassword': 'NewSecurePassword#2026',
        }),
      );
      expect(wrongOldResp.statusCode, equals(401));

      // Weak new password (< 8 chars)
      final weakNewResp = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/change-password'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $staffBearerToken',
          'x-tenant-id': hospitalCode,
          'x-medcore-device-id': deviceId,
        },
        body: jsonEncode({
          'oldPassword': generatedTemporaryPassword,
          'newPassword': 'short',
        }),
      );
      expect(weakNewResp.statusCode, equals(400));
    });

    const newPermanentPassword = 'PermanentSecureDirectorPassword#2026';

    test('8. Administrator completes forced password change: old password cleared, forcePasswordChange = false', () async {
      final changeResp = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/change-password'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $staffBearerToken',
          'x-tenant-id': hospitalCode,
          'x-medcore-device-id': deviceId,
        },
        body: jsonEncode({
          'oldPassword': generatedTemporaryPassword,
          'newPassword': newPermanentPassword,
        }),
      );
      expect(changeResp.statusCode, equals(200));
      final changeData = jsonDecode(changeResp.body)['data'];
      expect(changeData['status'], equals('PASSWORD_CHANGED_SUCCESS'));

      // Check physical MariaDB state reification
      final readConn = await db.openDedicatedConnection(useDatabase: true);
      try {
        final rows = await readConn.execute(
          'SELECT force_password_change FROM mc_staff WHERE hospital_code = :hosp AND staff_code = :code',
          {'hosp': hospitalCode, 'code': 'ADM-001'},
        );
        expect(rows.rows.first.colByName('force_password_change')?.toString(), equals('0'));
      } finally {
        await readConn.close();
      }

      // Old temporary password is now rejected
      final oldLoginResp = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/login'),
        headers: {
          'content-type': 'application/json',
          'x-tenant-id': hospitalCode,
          'x-medcore-device-id': deviceId,
        },
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'identifier': 'ADM-001',
          'password': generatedTemporaryPassword,
          'deviceId': deviceId,
        }),
      );
      expect(oldLoginResp.statusCode, equals(401));

      // New permanent password succeeds with forcePasswordChange = false
      final newLoginResp = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/login'),
        headers: {
          'content-type': 'application/json',
          'x-tenant-id': hospitalCode,
          'x-medcore-device-id': deviceId,
        },
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'identifier': 'ADM-001',
          'password': newPermanentPassword,
          'deviceId': deviceId,
        }),
      );
      expect(newLoginResp.statusCode, equals(200));
      final newLoginData = jsonDecode(newLoginResp.body)['data'] as Map<String, dynamic>;
      final user = newLoginData['user'] as Map<String, dynamic>;
      expect(user['forcePasswordChange'], isFalse);
    });

    test('9. Activation & Subscription Truth: Past expiration blocks operational access (403 SUBSCRIPTION_EXPIRED)', () async {
      // 1. Set subscription to expired date
      final conn = await db.openDedicatedConnection(useDatabase: true);
      try {
        await conn.execute(
          'UPDATE mc_facility_config SET subscription_expires_utc = "2025-01-01 00:00:00" WHERE hospital_code = :hosp',
          {'hosp': hospitalCode},
        );
      } finally {
        await conn.close();
      }

      // 2. Staff login with new password
      final loginResp = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/login'),
        headers: {
          'content-type': 'application/json',
          'x-tenant-id': hospitalCode,
          'x-medcore-device-id': deviceId,
        },
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'identifier': 'ADM-001',
          'password': newPermanentPassword,
          'deviceId': deviceId,
        }),
      );
      expect(loginResp.statusCode, equals(200));
      final newStaffToken = jsonDecode(loginResp.body)['data']['token'] as String;

      // 3. Operational module request is blocked with SUBSCRIPTION_EXPIRED
      final expiredResp = await http.get(
        Uri.parse('$baseUrl/api/v1/patients'),
        headers: {
          'authorization': 'Bearer $newStaffToken',
          'x-tenant-id': hospitalCode,
          'x-medcore-device-id': deviceId,
        },
      );
      expect(expiredResp.statusCode, equals(403));
      final expiredData = jsonDecode(expiredResp.body);
      expect(expiredData['error']['code'], equals('SUBSCRIPTION_EXPIRED'));

      // 4. Technician session is NEVER blocked by expired subscription
      final techCfgResp = await http.get(
        Uri.parse('$baseUrl/api/v1/technician/config'),
        headers: {
          'x-medcore-tech-token': techToken,
          'x-tenant-id': hospitalCode,
          'x-medcore-device-id': deviceId,
        },
      );
      expect(techCfgResp.statusCode, equals(200));

      // 5. Restore subscription to active future date
      final connRestore = await db.openDedicatedConnection(useDatabase: true);
      try {
        await connRestore.execute(
          'UPDATE mc_facility_config SET subscription_expires_utc = "2028-12-31 23:59:59" WHERE hospital_code = :hosp',
          {'hosp': hospitalCode},
        );
      } finally {
        await connRestore.close();
      }

      // 6. Operational request now succeeds
      final restoredResp = await http.get(
        Uri.parse('$baseUrl/api/v1/patients'),
        headers: {
          'authorization': 'Bearer $newStaffToken',
          'x-tenant-id': hospitalCode,
          'x-medcore-device-id': deviceId,
        },
      );
      expect(restoredResp.statusCode, equals(200));
    });

    test('10. Baseline Seeding Truth: Factory baseline contains zero hardcoded staff accounts or universal passwords', () async {
      const freshHosp = 'HOSP_ZERO_CREDENTIAL';
      final conn = await db.openDedicatedConnection(useDatabase: true);
      try {
        await server!.databaseLifecycleService.seedBaselineSystemDataForTesting(freshHosp);

        final staffRows = await conn.execute(
          'SELECT count(*) as cnt FROM mc_staff WHERE hospital_code = :hosp',
          {'hosp': freshHosp},
        );
        final count = int.parse(staffRows.rows.first.colByName('cnt').toString());
        expect(count, equals(0));

        // Verify zero occurrences of legacy universal admin email across all tenants
        final legacyRows = await conn.execute(
          'SELECT count(*) as cnt FROM mc_staff WHERE email = "admin@medcore.local"',
        );
        final legacyCount = int.parse(legacyRows.rows.first.colByName('cnt').toString());
        expect(legacyCount, equals(0));
      } finally {
        await conn.close();
      }
    });
  });
}
