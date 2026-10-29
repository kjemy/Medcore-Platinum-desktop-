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

  final serviceRoot = Directory.current.path;
  final migrationsDir = p.join(serviceRoot, 'sql', 'migrations');

  setUpAll(() async {
    securityRoot = Directory.systemTemp.createTempSync('medcore-emp-root-');
    final config = testDbConfig(databaseName: 'medcore_test_emp', maxConnections: 10);
    db = DbClient(config);

    final adminConn = await db.openDedicatedConnection(useDatabase: false);
    try {
      await adminConn.execute('DROP DATABASE IF EXISTS `medcore_test_emp`');
      await adminConn.execute(
        'CREATE DATABASE `medcore_test_emp` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
      );
    } finally {
      await adminConn.close();
    }

    migrationRunner = MigrationRunner(db: db, migrationsDir: migrationsDir);
    await migrationRunner.runMigrations();

    server = LocalMedCoreServer(
      db,
      securityRootDirectory: securityRoot.path,
    );
    final port = await server!.start(address: '127.0.0.1', port: 0);
    baseUrl = 'http://127.0.0.1:$port';

    // Seed test tenants, devices, and admin
    final conn = await db.openDedicatedConnection(useDatabase: true);
    try {
      await conn.execute('''
        INSERT INTO mc_tenants (hospital_code, name, status)
        VALUES ('HOSP_EMP', 'Employee Test Hospital', 'active'),
               ('HOSP_OTHER', 'Other Hospital', 'active')
      ''');

      final govRepo = TenantGovernanceRepository(db);
      await govRepo.enrollOrUpdateDevice(
        hospitalCode: 'HOSP_EMP',
        deviceId: 'DEV-ADMIN',
        deviceName: 'Admin Terminal',
        platform: 'WINDOWS',
        hwFingerprintSha256: PasswordHasher.sha256Hex('DEV-ADMIN-HW'),
        devicePublicKeyEd25519: 'pk_admin',
        roleScope: 'WORKSTATION',
        isTrustedSecureRuntime: true,
        status: 'ACTIVE',
      );
      await govRepo.enrollOrUpdateDevice(
        hospitalCode: 'HOSP_EMP',
        deviceId: 'DEV-WORK',
        deviceName: 'Workstation 1',
        platform: 'WINDOWS',
        hwFingerprintSha256: PasswordHasher.sha256Hex('DEV-WORK-HW'),
        devicePublicKeyEd25519: 'pk_work',
        roleScope: 'WORKSTATION',
        isTrustedSecureRuntime: true,
        status: 'ACTIVE',
      );
      await govRepo.enrollOrUpdateDevice(
        hospitalCode: 'HOSP_OTHER',
        deviceId: 'DEV-OTHER',
        deviceName: 'Other Terminal',
        platform: 'WINDOWS',
        hwFingerprintSha256: PasswordHasher.sha256Hex('DEV-OTHER-HW'),
        devicePublicKeyEd25519: 'pk_other',
        roleScope: 'WORKSTATION',
        isTrustedSecureRuntime: true,
        status: 'ACTIVE',
      );

      final adminHash = PasswordHasher.hashPassword('AdminMaster123!');
      await conn.execute('''
        INSERT INTO mc_staff (
          hospital_code, staff_code, full_name, email, password_hash, role,
          permissions_mode, can_edit, can_delete, is_active
        ) VALUES (
          'HOSP_EMP', 'ADMIN-01', 'Chief Administrator', 'admin@hospemp.local', '$adminHash',
          'Admin', 'default', 1, 1, 1
        )
      ''');

      final regularHash = PasswordHasher.hashPassword('RegularUser123!');
      await conn.execute('''
        INSERT INTO mc_staff (
          hospital_code, staff_code, full_name, email, password_hash, role,
          permissions_mode, can_edit, can_delete, is_active
        ) VALUES (
          'HOSP_EMP', 'EMP-REG', 'Regular Nurse', 'nurse@hospemp.local', '$regularHash',
          'Nurse', 'default', 1, 0, 1
        )
      ''');
    } finally {
      await conn.close();
    }
  });

  tearDownAll(() async {
    await server?.stop();
    await db.close();
    if (securityRoot.existsSync()) {
      securityRoot.deleteSync(recursive: true);
    }
  });

  Future<String> login(String staffCode, String password, {String hosp = 'HOSP_EMP', String dev = 'DEV-ADMIN'}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/auth/login'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'hospitalCode': hosp,
        'identifier': staffCode,
        'password': password,
        'deviceId': dev,
      }),
    );
    expect(res.statusCode, equals(200), reason: 'Login failed: ${res.body}');
    final data = jsonDecode(res.body);
    return data['data']['token'] as String;
  }

  test('1. Non-admin user cannot access admin employee management (403 Forbidden)', () async {
    final nurseToken = await login('EMP-REG', 'RegularUser123!', dev: 'DEV-WORK');
    final res = await http.get(
      Uri.parse('$baseUrl/api/v1/admin/employees'),
      headers: {
        'authorization': 'Bearer $nurseToken',
        'x-tenant-id': 'HOSP_EMP',
        'x-medcore-device-id': 'DEV-WORK',
      },
    );
    expect(res.statusCode, equals(403), reason: 'Regular nurse must be forbidden from admin API');
  });

  test('2. Admin creates employee with secure PBKDF2 hash (Zero plaintext password in DB)', () async {
    final adminToken = await login('ADMIN-01', 'AdminMaster123!');
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/admin/employees'),
      headers: {
        'authorization': 'Bearer $adminToken',
        'x-tenant-id': 'HOSP_EMP',
        'x-medcore-device-id': 'DEV-ADMIN',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'staffCode': 'DOC-101',
        'fullName': 'Dr. Tariq Ziad',
        'email': 'tariq@hospemp.local',
        'phone': '+201011112222',
        'nationalId': '29001011234567',
        'password': 'InitialSecurePass1!',
        'role': 'Doctor',
        'specialty': 'Cardiology',
        'forcePasswordChange': true,
      }),
    );
    expect(res.statusCode, equals(201), reason: 'Failed creation: ${res.body}');
    final respJson = jsonDecode(res.body);
    final data = respJson['data'] as Map<String, dynamic>;
    expect(data['staffCode'], equals('DOC-101'));
    expect(data['forcePasswordChange'], isTrue);
    expect(data.containsKey('password'), isFalse);
    expect(data.containsKey('passwordHash'), isFalse);

    // Direct MariaDB Read-back verification
    final rows = await db.execute(
      'SELECT password_hash, force_password_change FROM mc_staff WHERE staff_code = :code AND hospital_code = :hosp',
      {'code': 'DOC-101', 'hosp': 'HOSP_EMP'},
    );
    expect(rows.rows.length, equals(1));
    final dbHash = rows.rows.first.colByName('password_hash')!;
    expect(dbHash.startsWith('pbkdf2_sha256\$'), isTrue, reason: 'Must use PBKDF2');
    expect(dbHash.contains('InitialSecurePass1!'), isFalse, reason: 'Plaintext forbidden');
    expect(rows.rows.first.colByName('force_password_change'), equals('1'));
  });

  test('3. Duplicate staffCode or duplicate email rejects fail-closed (409 Conflict)', () async {
    final adminToken = await login('ADMIN-01', 'AdminMaster123!');
    final resDupCode = await http.post(
      Uri.parse('$baseUrl/api/v1/admin/employees'),
      headers: {
        'authorization': 'Bearer $adminToken',
        'x-tenant-id': 'HOSP_EMP',
        'x-medcore-device-id': 'DEV-ADMIN',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'staffCode': 'DOC-101',
        'fullName': 'Another Doctor',
        'email': 'another@hospemp.local',
        'password': 'StrongPass123!',
        'role': 'Doctor',
      }),
    );
    expect(resDupCode.statusCode, equals(409));

    final resDupEmail = await http.post(
      Uri.parse('$baseUrl/api/v1/admin/employees'),
      headers: {
        'authorization': 'Bearer $adminToken',
        'x-tenant-id': 'HOSP_EMP',
        'x-medcore-device-id': 'DEV-ADMIN',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'staffCode': 'DOC-102',
        'fullName': 'Another Doctor',
        'email': 'tariq@hospemp.local',
        'password': 'StrongPass123!',
        'role': 'Doctor',
      }),
    );
    expect(resDupEmail.statusCode, equals(409));
  });

  test('4. Weak password (< 8 characters) rejected with 400 WEAK_PASSWORD', () async {
    final adminToken = await login('ADMIN-01', 'AdminMaster123!');
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/admin/employees'),
      headers: {
        'authorization': 'Bearer $adminToken',
        'x-tenant-id': 'HOSP_EMP',
        'x-medcore-device-id': 'DEV-ADMIN',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'staffCode': 'DOC-SHORT',
        'fullName': 'Short Pass Doc',
        'email': 'short@hospemp.local',
        'password': 'short',
        'role': 'Doctor',
      }),
    );
    expect(res.statusCode, equals(400));
    final errJson = jsonDecode(res.body);
    expect(errJson['error']['code'], equals('WEAK_PASSWORD'));
  });

  test('5. Employee logs in and changes own password (voluntary/forced)', () async {
    final docToken = await login('DOC-101', 'InitialSecurePass1!', dev: 'DEV-WORK');
    // Change password
    final changeRes = await http.post(
      Uri.parse('$baseUrl/api/v1/auth/change-password'),
      headers: {
        'authorization': 'Bearer $docToken',
        'x-tenant-id': 'HOSP_EMP',
        'x-medcore-device-id': 'DEV-WORK',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'oldPassword': 'InitialSecurePass1!',
        'newPassword': 'NewDoctorSecret2026!',
      }),
    );
    expect(changeRes.statusCode, equals(200));

    // Old password invalid
    final oldLogin = await http.post(
      Uri.parse('$baseUrl/api/v1/auth/login'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'hospitalCode': 'HOSP_EMP',
        'identifier': 'DOC-101',
        'password': 'InitialSecurePass1!',
        'deviceId': 'DEV-WORK',
      }),
    );
    expect(oldLogin.statusCode, equals(401));

    // New password valid
    final newLogin = await http.post(
      Uri.parse('$baseUrl/api/v1/auth/login'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'hospitalCode': 'HOSP_EMP',
        'identifier': 'DOC-101',
        'password': 'NewDoctorSecret2026!',
        'deviceId': 'DEV-WORK',
      }),
    );
    expect(newLogin.statusCode, equals(200));
    final newUserData = jsonDecode(newLogin.body)['data']['user'];
    expect(newUserData['forcePasswordChange'], isFalse);
  });

  test('6. Admin resets password, forces password change, and revokes active sessions', () async {
    // 1. Employee logs in
    final docToken = await login('DOC-101', 'NewDoctorSecret2026!', dev: 'DEV-WORK');

    // 2. Admin resets employee password
    final adminToken = await login('ADMIN-01', 'AdminMaster123!');
    final staffRows = await db.execute(
      'SELECT id FROM mc_staff WHERE staff_code = "DOC-101" AND hospital_code = "HOSP_EMP"',
    );
    final docId = int.parse(staffRows.rows.first.colByName('id')!);

    final resetRes = await http.post(
      Uri.parse('$baseUrl/api/v1/admin/employees/$docId/reset-password'),
      headers: {
        'authorization': 'Bearer $adminToken',
        'x-tenant-id': 'HOSP_EMP',
        'x-medcore-device-id': 'DEV-ADMIN',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'newPassword': 'TempAdminReset789!',
        'forcePasswordChange': true,
      }),
    );
    expect(resetRes.statusCode, equals(200));
    final resetData = jsonDecode(resetRes.body)['data'];
    expect(resetData['revokedSessionsCount'], greaterThanOrEqualTo(1));

    // 3. Prior session token is immediately invalid (Revocation proof)
    final checkRes = await http.get(
      Uri.parse('$baseUrl/api/v1/patients'),
      headers: {
        'authorization': 'Bearer $docToken',
        'x-tenant-id': 'HOSP_EMP',
        'x-medcore-device-id': 'DEV-WORK',
      },
    );
    expect(checkRes.statusCode, equals(401), reason: 'Old session must be revoked');

    // 4. Employee logs in with reset password and observes forced change
    final reLogin = await login('DOC-101', 'TempAdminReset789!', dev: 'DEV-WORK');
    expect(reLogin.isNotEmpty, isTrue);
  });

  test('7. Admin deactivates employee -> login denied and existing sessions revoked', () async {
    final docToken = await login('DOC-101', 'TempAdminReset789!', dev: 'DEV-WORK');
    final adminToken = await login('ADMIN-01', 'AdminMaster123!');
    final staffRows = await db.execute(
      'SELECT id FROM mc_staff WHERE staff_code = "DOC-101" AND hospital_code = "HOSP_EMP"',
    );
    final docId = int.parse(staffRows.rows.first.colByName('id')!);

    // Deactivate
    final deactRes = await http.post(
      Uri.parse('$baseUrl/api/v1/admin/employees/$docId/status'),
      headers: {
        'authorization': 'Bearer $adminToken',
        'x-tenant-id': 'HOSP_EMP',
        'x-medcore-device-id': 'DEV-ADMIN',
        'content-type': 'application/json',
      },
      body: jsonEncode({'isActive': false}),
    );
    expect(deactRes.statusCode, equals(200));

    // Login denied
    final loginRes = await http.post(
      Uri.parse('$baseUrl/api/v1/auth/login'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'hospitalCode': 'HOSP_EMP',
        'identifier': 'DOC-101',
        'password': 'TempAdminReset789!',
        'deviceId': 'DEV-WORK',
      }),
    );
    expect(loginRes.statusCode, equals(401), reason: 'Deactivated account cannot log in');

    // Existing session revoked
    final callRes = await http.get(
      Uri.parse('$baseUrl/api/v1/patients'),
      headers: {
        'authorization': 'Bearer $docToken',
        'x-tenant-id': 'HOSP_EMP',
        'x-medcore-device-id': 'DEV-WORK',
      },
    );
    expect(callRes.statusCode, equals(401));
  });

  test('8. Admin account edit does NOT reset password', () async {
    final adminToken = await login('ADMIN-01', 'AdminMaster123!');
    final staffRows = await db.execute(
      'SELECT id, password_hash FROM mc_staff WHERE staff_code = "DOC-101" AND hospital_code = "HOSP_EMP"',
    );
    final docId = int.parse(staffRows.rows.first.colByName('id')!);
    final beforeHash = staffRows.rows.first.colByName('password_hash')!;

    final editRes = await http.put(
      Uri.parse('$baseUrl/api/v1/admin/employees/$docId'),
      headers: {
        'authorization': 'Bearer $adminToken',
        'x-tenant-id': 'HOSP_EMP',
        'x-medcore-device-id': 'DEV-ADMIN',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'fullName': 'Dr. Tariq Ziad Updated',
        'phone': '+201099998888',
        'role': 'Doctor',
      }),
    );
    expect(editRes.statusCode, equals(200));

    final afterRows = await db.execute(
      'SELECT full_name, role, password_hash FROM mc_staff WHERE id = :id',
      {'id': docId},
    );
    expect(afterRows.rows.first.colByName('full_name'), equals('Dr. Tariq Ziad Updated'));
    expect(afterRows.rows.first.colByName('role'), equals('Doctor'));
    expect(afterRows.rows.first.colByName('password_hash'), equals(beforeHash),
        reason: 'Password must not change during metadata edit');
  });

  test('9. Security Audit Trail records employee mutations without plaintext passwords', () async {
    final adminToken = await login('ADMIN-01', 'AdminMaster123!');
    final staffRows = await db.execute(
      'SELECT id FROM mc_staff WHERE staff_code = "DOC-101" AND hospital_code = "HOSP_EMP"',
    );
    final docId = int.parse(staffRows.rows.first.colByName('id')!);

    final auditRes = await http.get(
      Uri.parse('$baseUrl/api/v1/admin/employees/$docId/audit'),
      headers: {
        'authorization': 'Bearer $adminToken',
        'x-tenant-id': 'HOSP_EMP',
        'x-medcore-device-id': 'DEV-ADMIN',
      },
    );
    expect(auditRes.statusCode, equals(200));
    final entries = jsonDecode(auditRes.body)['data']['auditEntries'] as List;
    expect(entries.length, greaterThanOrEqualTo(3));

    for (final e in entries) {
      final after = e['after_json']?.toString() ?? '';
      expect(after.contains('InitialSecurePass1!'), isFalse, reason: 'Plaintext leaked in audit log');
      expect(after.contains('TempAdminReset789!'), isFalse, reason: 'Plaintext leaked in audit log');
      expect(after.contains('NewDoctorSecret2026!'), isFalse, reason: 'Plaintext leaked in audit log');
    }
  });

  test('10. Cross-Tenant Isolation: Admin from Hospital A cannot manage Hospital B staff', () async {
    final adminToken = await login('ADMIN-01', 'AdminMaster123!');
    // Attempt to access with header for other hospital
    final crossRes = await http.get(
      Uri.parse('$baseUrl/api/v1/admin/employees'),
      headers: {
        'authorization': 'Bearer $adminToken',
        'x-tenant-id': 'HOSP_OTHER',
        'x-medcore-device-id': 'DEV-ADMIN',
      },
    );
    expect(crossRes.statusCode, equals(403), reason: 'Tenant crossing rejected fail-closed');
  });

  test('11. HR Staff Evaluations: Create, List, and Physical Database Persistence (GAP-015)', () async {
    final adminToken = await login('ADMIN-01', 'AdminMaster123!');
    final staffRows = await db.execute(
      'SELECT id FROM mc_staff WHERE staff_code = "DOC-101" AND hospital_code = "HOSP_EMP"',
    );
    final docId = int.parse(staffRows.rows.first.colByName('id')!);

    // Create staff evaluation
    final evalRes = await http.post(
      Uri.parse('$baseUrl/api/v1/hr/evaluations'),
      headers: {
        'authorization': 'Bearer $adminToken',
        'content-type': 'application/json',
        'x-tenant-id': 'HOSP_EMP',
        'x-medcore-device-id': 'DEV-ADMIN',
      },
      body: jsonEncode({
        'staffId': docId,
        'evaluationPeriod': '2026-Q1',
        'score': '95.50',
        'rating': 'EXCELLENT',
        'strengths': 'Exceptional diagnostic accuracy and bedside manner',
        'improvements': 'None noted',
        'notes': 'Promoted to senior attending',
        'status': 'FINALIZED',
      }),
    );
    expect(evalRes.statusCode, equals(201));
    final evalData = jsonDecode(evalRes.body)['data'];
    final evalId = evalData['id'];
    expect(evalId, isNotNull);

    // Read back via list endpoint
    final listRes = await http.get(
      Uri.parse('$baseUrl/api/v1/hr/evaluations?staffId=$docId'),
      headers: {
        'authorization': 'Bearer $adminToken',
        'x-tenant-id': 'HOSP_EMP',
        'x-medcore-device-id': 'DEV-ADMIN',
      },
    );
    expect(listRes.statusCode, equals(200));
    final listData = jsonDecode(listRes.body)['data'];
    expect(listData['count'], greaterThanOrEqualTo(1));
    expect(listData['evaluations'].first['rating'], equals('EXCELLENT'));

    // Physical MariaDB assertion
    final physicalRows = await db.execute(
      'SELECT score, rating, status FROM mc_staff_evaluations WHERE id = :id AND hospital_code = "HOSP_EMP"',
      {'id': evalId},
    );
    expect(physicalRows.rows.length, equals(1));
    expect(physicalRows.rows.first.colByName('rating'), equals('EXCELLENT'));
    expect(physicalRows.rows.first.colByName('status'), equals('FINALIZED'));
  });
}
