import 'dart:convert';
import 'dart:io';
import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;
import 'package:medcore_local_service/medcore_local_service.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'support/test_db_config.dart';

void main() {
  late DbClient db;
  late MigrationRunner migrationRunner;
  late TransactionManager txManager;
  LocalMedCoreServer? server;
  late String baseUrl;
  late Directory securityRoot;

  final serviceRoot = Directory.current.path;
  final migrationsDir = p.join(serviceRoot, 'sql', 'migrations');

  setUpAll(() async {
    securityRoot = Directory.systemTemp.createTempSync('medcore-gate-root-');
    final config = testDbConfig(databaseName: 'medcore_test', maxConnections: 10);
    db = DbClient(config);

    // Drop and recreate clean test database to guarantee deterministic Gate 1 & Gate 2 testing
    final adminConn = await db.openDedicatedConnection(useDatabase: false);
    try {
      await adminConn.execute('DROP DATABASE IF EXISTS `medcore_test`');
      await adminConn.execute(
        'CREATE DATABASE `medcore_test` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
      );
    } finally {
      await adminConn.close();
    }

    migrationRunner = MigrationRunner(db: db, migrationsDir: migrationsDir);
    txManager = TransactionManager(db);
    server = LocalMedCoreServer(db, securityRootDirectory: securityRoot.path);
  });

  tearDownAll(() async {
    await server?.stop();
    await db.close();
    if (securityRoot.existsSync()) securityRoot.deleteSync(recursive: true);
  });

  group('GATE 1 — Database Schema, Migrations, Indexes, Repositories & Transactions', () {
    test('TASK 1.1 & 1.2: Applies V001..V014 migrations, verifies InnoDB utf8mb4 tables & idempotency', () async {
      final applied = await migrationRunner.runMigrations();
      expect(applied.length, equals(14));

      // Verify idempotent re-run
      final secondRun = await migrationRunner.runMigrations();
      expect(secondRun.length, equals(14));

      // Verify all tables in INFORMATION_SCHEMA.TABLES
      final tables = await migrationRunner.inspectTables();
      expect(tables.length, greaterThanOrEqualTo(86));

      for (final t in tables) {
        final name = t['table_name']!;
        expect(name, equals(name.toLowerCase()), reason: 'Table $name must be lowercase snake_case');
        expect(t['engine']?.toUpperCase(), equals('INNODB'), reason: 'Table $name must use InnoDB');
        expect(t['collation']?.toLowerCase(), contains('utf8mb4'), reason: 'Table $name must use utf8mb4');
      }

      // Verify DECIMAL(14,4) on authoritative financial columns
      final decRes = await db.execute(
        '''
        SELECT TABLE_NAME, COLUMN_NAME, COLUMN_TYPE
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = 'medcore_test'
          AND TABLE_NAME IN ('mc_visits', 'mc_visit_items', 'mc_visit_item_cost_lines', 'mc_financial_events', 'mc_financial_postings', 'mc_shifts')
          AND COLUMN_NAME IN ('gross_amount', 'net_amount', 'paid_amount', 'amount', 'opening_balance', 'unit_cost_fifo')
        ''',
      );
      expect(decRes.rows.isNotEmpty, isTrue);
      for (final r in decRes.rows) {
        expect(
          r.colByName('COLUMN_TYPE')?.toLowerCase(),
          equals('decimal(14,4)'),
          reason: '${r.colByName('TABLE_NAME')}.${r.colByName('COLUMN_NAME')} must be decimal(14,4)',
        );
      }
    });

    test('TASK 1.3: Verifies Composite Tenant Indexes and Foreign Key ON DELETE RESTRICT enforcement', () async {
      final fks = await migrationRunner.inspectForeignKeys();
      expect(fks.length, greaterThanOrEqualTo(12));

      final indexes = await migrationRunner.inspectIndexes();
      final indexedTables = indexes.map((i) => i['table']).toSet();
      expect(
        indexedTables,
        containsAll([
          'mc_tenants',
          'mc_devices',
          'mc_staff',
          'mc_auth_sessions',
          'mc_patients',
          'mc_visits',
          'mc_visit_items',
          'mc_visit_item_cost_lines',
          'mc_financial_events',
          'mc_financial_postings',
          'mc_shifts',
          'mc_audit_logs',
          'mc_security_logs',
        ]),
      );

      // Seed Tenant HOSP_A & HOSP_B + Devices + Staff to test Foreign Key ON DELETE RESTRICT
      final govRepo = TenantGovernanceRepository(db);
      await govRepo.upsertTenant(hospitalCode: 'HOSP_A', name: 'Al-Amal Hospital');
      await govRepo.upsertTenant(hospitalCode: 'HOSP_B', name: 'Al-Noor Hospital');

      await govRepo.enrollOrUpdateDevice(
        hospitalCode: 'HOSP_A',
        deviceId: 'DEV-WKS-01',
        deviceName: 'Reception Desktop 1',
        platform: 'WINDOWS',
        hwFingerprintSha256: PasswordHasher.sha256Hex('WIN-HW-01'),
        devicePublicKeyEd25519: 'PUBKEY-01',
        isTrustedSecureRuntime: true,
        status: 'ACTIVE',
      );

      await govRepo.enrollOrUpdateDevice(
        hospitalCode: 'HOSP_A',
        deviceId: 'DEV-KIOSK-UNTRUSTED',
        deviceName: 'Untrusted Web Kiosk',
        platform: 'WINDOWS',
        hwFingerprintSha256: PasswordHasher.sha256Hex('WIN-HW-KIOSK'),
        devicePublicKeyEd25519: 'PUBKEY-KIOSK',
        isTrustedSecureRuntime: false,
        status: 'ACTIVE',
      );

      // Verify ON DELETE RESTRICT blocks deleting tenant HOSP_A while child mc_devices exist
      expect(
        () async => await db.execute("DELETE FROM mc_tenants WHERE hospital_code = 'HOSP_A'"),
        throwsA(anything),
      );
    });

    test('TASK 1.4 & 1.5: Verifies ACID Transaction Rollback, FOR UPDATE Locks, FIN-001 & FIN-004 Cost Split', () async {
      final staffRepo = StaffIdentityRepository(db);
      final cashier = await staffRepo.createStaff(
        hospitalCode: 'HOSP_A',
        staffCode: 'CSH-001',
        fullName: 'Ahmed Cashier',
        email: 'ahmed.cashier@hosp-a.local',
        passwordHash: PasswordHasher.hashPassword('CashierPass!1'),
        role: MedCoreRole.Cashier,
      );
      final doctor1 = await staffRepo.createStaff(
        hospitalCode: 'HOSP_A',
        staffCode: 'DOC-001',
        fullName: 'Dr. Tarek Surgeon',
        email: 'dr.tarek@hosp-a.local',
        passwordHash: PasswordHasher.hashPassword('DoctorPass!1'),
        role: MedCoreRole.Doctor,
        doctorDefinitionCode: 'DEF-DOC-001',
      );

      final cashierScope = ScopeContext(
        hospitalCode: 'HOSP_A',
        actor: cashier,
        deviceId: 'DEV-WKS-01',
        isTrustedSecureDevice: true,
        dataScopeMode: DataScopeMode.tenantWide,
      );

      final patRepo = PatientRepository(db);
      final pat1 = await patRepo.createPatient(
        scope: cashierScope,
        mrn: 'MRN-1001',
        fullName: 'Patient One',
        phone: '01000000001',
        assignedDoctorId: doctor1.id,
      );

      final shiftRepo = ShiftRepository(db);
      final shift = await shiftRepo.openShift(
        scope: cashierScope,
        shiftCode: 'SHF-2026-001',
        openingBalance: Decimal.parse('500.0000'),
      );
      final shiftId = shift['id'] as int;

      final visitService = VisitFinancialService(txManager);

      // 1. Test ACID Rollback when failure occurs mid-transaction after inserting mc_visits & mc_visit_items
      await expectLater(
        () => visitService.createAtomicVisitWithCostSplit(
          scope: cashierScope,
          visitNumber: 'VIS-ROLLBACK-999',
          idempotencyKey: 'IDEMP-ROLLBACK-999',
          patientId: pat1.id,
          doctorId: doctor1.id,
          shiftId: shiftId,
          serviceCode: 'SRV-SURG-01',
          serviceName: 'Minor Procedure',
          serviceLaborGross: Decimal.parse('600.0000'),
          consumableGross: Decimal.parse('400.0000'),
          consumableFifoCost: Decimal.parse('250.0000'),
          discountAmount: Decimal.zero,
          insuranceCoveredAmount: Decimal.zero,
          paidAmount: Decimal.parse('1000.0000'),
          doctorCommissionRatePercent: Decimal.parse('50.0000'),
          simulateFailureAfterVisitInsert: true,
        ),
        throwsA(isA<StateError>()),
      );

      // Verify 0 orphan rows exist in mc_visits, mc_visit_items, or mc_visit_item_cost_lines
      final orphanCheck = await db.execute(
        "SELECT COUNT(*) AS cnt FROM mc_visits WHERE visit_number = 'VIS-ROLLBACK-999'",
      );
      expect(int.parse(orphanCheck.rows.first.colByName('cnt') ?? '0'), equals(0));

      // 2. Test Full Atomic Commit + FIN-004 Service vs Consumable Cost Split + Double-Entry Balance
      final committed = await visitService.createAtomicVisitWithCostSplit(
        scope: cashierScope,
        visitNumber: 'VIS-2026-0001',
        idempotencyKey: 'IDEMP-VIS-0001',
        patientId: pat1.id,
        doctorId: doctor1.id,
        shiftId: shiftId,
        serviceCode: 'SRV-SURG-01',
        serviceName: 'Minor Procedure with Consumables',
        serviceLaborGross: Decimal.parse('600.0000'),
        consumableGross: Decimal.parse('400.0000'),
        consumableFifoCost: Decimal.parse('250.0000'),
        discountAmount: Decimal.zero,
        insuranceCoveredAmount: Decimal.zero,
        paidAmount: Decimal.parse('1000.0000'),
        doctorCommissionRatePercent: Decimal.parse('50.0000'),
      );

      expect(committed['idempotentReplay'], isFalse);
      // 50% commission on 600 Service Labor = 300.0000 (NOT 500.0000 on 1000 total!)
      expect(committed['serviceLaborNet'], equals('600.0000'));
      expect(committed['commissionAmount'], equals('300.0000'));

      // Verify Trial Balance Invariant: SUM(DEBIT) == SUM(CREDIT)
      final eventId = committed['eventId'] as int;
      final tbRes = await db.execute(
        '''
        SELECT
          SUM(CASE WHEN direction = 'DEBIT' THEN amount ELSE 0 END) AS total_debit,
          SUM(CASE WHEN direction = 'CREDIT' THEN amount ELSE 0 END) AS total_credit
        FROM mc_financial_postings
        WHERE event_id = :evid
        ''',
        {'evid': eventId},
      );
      final totalDebit = Decimal.parse(tbRes.rows.first.colByName('total_debit') ?? '0');
      final totalCredit = Decimal.parse(tbRes.rows.first.colByName('total_credit') ?? '0');
      expect(totalDebit, equals(totalCredit));
      expect(totalDebit, equals(Decimal.parse('1550.0000'))); // 1000 cash + 250 COGS + 300 Comm = 1550

      // 3. Test Idempotency Replay
      final replay = await visitService.createAtomicVisitWithCostSplit(
        scope: cashierScope,
        visitNumber: 'VIS-2026-0001',
        idempotencyKey: 'IDEMP-VIS-0001',
        patientId: pat1.id,
        doctorId: doctor1.id,
        shiftId: shiftId,
        serviceCode: 'SRV-SURG-01',
        serviceName: 'Minor Procedure with Consumables',
        serviceLaborGross: Decimal.parse('600.0000'),
        consumableGross: Decimal.parse('400.0000'),
        consumableFifoCost: Decimal.parse('250.0000'),
        discountAmount: Decimal.zero,
        insuranceCoveredAmount: Decimal.zero,
        paidAmount: Decimal.parse('1000.0000'),
        doctorCommissionRatePercent: Decimal.parse('50.0000'),
      );
      expect(replay['idempotentReplay'], isTrue);
      expect(replay['visitId'], equals(committed['visitId']));
    });
  });

  group('GATE 2 — Local Service, Authentication, Employee Identity, 10-Role RBAC & Permission Enforcement', () {
    final roleTokens = <MedCoreRole, String>{};
    final roleStaffIds = <MedCoreRole, int>{};

    test('TASK 2.1, 2.2 & 2.3: Starts LocalMedCoreServer and authenticates all 10 Canonical Roles natively', () async {
      final port = await server!.start(address: '127.0.0.1', port: 0);
      baseUrl = 'http://127.0.0.1:$port';

      // Check /api/v1/health
      final healthResp = await http.get(Uri.parse('$baseUrl/api/v1/health'));
      expect(healthResp.statusCode, equals(200));
      final healthJson = jsonDecode(healthResp.body)['data'];
      expect(healthJson['status'], equals('HEALTHY'));
      expect(healthJson['appliedMigrations'], equals(14));
      expect(healthJson['tableCount'], greaterThanOrEqualTo(86));

      // Seed all 10 Canonical Roles in HOSP_A and authenticate each over HTTP
      final staffRepo = StaffIdentityRepository(db);
      for (final role in MedCoreRole.values) {
        final code = 'EMP-${role.name.toUpperCase()}';
        final email = '${role.name.toLowerCase()}@hosp-a.local';
        final created = await staffRepo.createStaff(
          hospitalCode: 'HOSP_A',
          staffCode: code,
          fullName: 'Staff ${role.name}',
          email: email,
          passwordHash: PasswordHasher.hashPassword('Pass#${role.name}123'),
          role: role,
        );
        roleStaffIds[role] = created.id;

        final loginResp = await http.post(
          Uri.parse('$baseUrl/api/v1/auth/login'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'hospitalCode': 'HOSP_A',
            'identifier': email,
            'password': 'Pass#${role.name}123',
            'deviceId': 'DEV-WKS-01',
          }),
        );
        expect(loginResp.statusCode, equals(200), reason: 'Login failed for role ${role.name}');
        final loginData = jsonDecode(loginResp.body)['data'];
        expect(
          loginData['user']['role'],
          equals(role.name),
          reason: 'Role ${role.name} must NOT be collapsed into Employee!',
        );
        roleTokens[role] = loginData['token'] as String;
      }
      expect(roleTokens.length, equals(10));
    });

    test('TASK 2.2: Closes SEC-FLAW-03 & SEC-FLAW-05 (Blocks Unenrolled Device, Cross-Tenant & Cross-Device Replay)', () async {
      // 1. Login from unenrolled device DEV-ROGUE-99 -> 403 DEVICE_NOT_VERIFIED
      final rogueLogin = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/login'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': 'HOSP_A',
          'identifier': 'doctor@hosp-a.local',
          'password': 'Pass#Doctor123',
          'deviceId': 'DEV-ROGUE-99',
        }),
      );
      expect(rogueLogin.statusCode, equals(403));
      expect(jsonDecode(rogueLogin.body)['error']['code'], equals('DEVICE_NOT_VERIFIED'));

      // 2. Cross-Tenant Token Replay (Token from HOSP_A used with X-Tenant-ID: HOSP_B) -> 403 TENANT_BINDING_MISMATCH
      final docToken = roleTokens[MedCoreRole.Doctor]!;
      final crossTenantResp = await http.get(
        Uri.parse('$baseUrl/api/v1/auth/me'),
        headers: {
          'authorization': 'Bearer $docToken',
          'x-tenant-id': 'HOSP_B',
          'x-medcore-device-id': 'DEV-WKS-01',
        },
      );
      expect(crossTenantResp.statusCode, equals(403));
      expect(jsonDecode(crossTenantResp.body)['error']['code'], equals('TENANT_BINDING_MISMATCH'));

      // 3. Cross-Device Token Replay (Token bound to DEV-WKS-01 used with DEV-KIOSK-UNTRUSTED) -> 403 DEVICE_BINDING_MISMATCH
      final crossDeviceResp = await http.get(
        Uri.parse('$baseUrl/api/v1/auth/me'),
        headers: {
          'authorization': 'Bearer $docToken',
          'x-tenant-id': 'HOSP_A',
          'x-medcore-device-id': 'DEV-KIOSK-UNTRUSTED',
        },
      );
      expect(crossDeviceResp.statusCode, equals(403));
      expect(jsonDecode(crossDeviceResp.body)['error']['code'], equals('DEVICE_BINDING_MISMATCH'));
    });

    test('TASK 2.4 & 2.5: Closes SEC-FLAW-01 (Default mode enforces strict role permissions, never wildcard *)', () async {
      final docToken = roleTokens[MedCoreRole.Doctor]!;
      final recToken = roleTokens[MedCoreRole.Receptionist]!;
      final empToken = roleTokens[MedCoreRole.Employee]!;

      // Doctor in 'default' mode attempting to access HR Employees -> 403 PERMISSION_DENIED
      final docHrResp = await http.get(
        Uri.parse('$baseUrl/api/v1/staff'),
        headers: {
          'authorization': 'Bearer $docToken',
          'x-tenant-id': 'HOSP_A',
          'x-medcore-device-id': 'DEV-WKS-01',
        },
      );
      expect(docHrResp.statusCode, equals(403));
      expect(jsonDecode(docHrResp.body)['error']['code'], equals('PERMISSION_DENIED'));

      // Receptionist in 'default' mode attempting to access Finance Settlements -> 403 PERMISSION_DENIED
      final recSettleResp = await http.get(
        Uri.parse('$baseUrl/api/v1/finance/settlements'),
        headers: {
          'authorization': 'Bearer $recToken',
          'x-tenant-id': 'HOSP_A',
          'x-medcore-device-id': 'DEV-WKS-01',
        },
      );
      expect(recSettleResp.statusCode, equals(403));

      // Employee in 'default' mode attempting to read Patients -> 403 PERMISSION_DENIED
      final empPatResp = await http.get(
        Uri.parse('$baseUrl/api/v1/patients'),
        headers: {
          'authorization': 'Bearer $empToken',
          'x-tenant-id': 'HOSP_A',
          'x-medcore-device-id': 'DEV-WKS-01',
        },
      );
      expect(empPatResp.statusCode, equals(403));
    });

    test('TASK 2.5: Enforces Dimension 2 (_all Tenant-Wide vs Own-Only Scope) at SQL Repository Layer', () async {
      final adminToken = roleTokens[MedCoreRole.HospitalAdmin]!;
      final docToken = roleTokens[MedCoreRole.Doctor]!;
      final recToken = roleTokens[MedCoreRole.Receptionist]!;
      final docRoleId = roleStaffIds[MedCoreRole.Doctor]!;

      // Receptionist creates a patient assigned to Doctor (docRoleId)
      final createPatForDoc = await http.post(
        Uri.parse('$baseUrl/api/v1/patients'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $recToken',
          'x-tenant-id': 'HOSP_A',
          'x-medcore-device-id': 'DEV-WKS-01',
        },
        body: jsonEncode({
          'mrn': 'MRN-DOC-OWN',
          'fullName': 'Doctor Assigned Patient',
          'phone': '01099990001',
          'assignedDoctorId': docRoleId,
        }),
      );
      expect(createPatForDoc.statusCode, equals(201));

      // Receptionist creates another patient assigned to a different doctor (nobody)
      final createOtherPat = await http.post(
        Uri.parse('$baseUrl/api/v1/patients'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $recToken',
          'x-tenant-id': 'HOSP_A',
          'x-medcore-device-id': 'DEV-WKS-01',
        },
        body: jsonEncode({
          'mrn': 'MRN-OTHER-DOC',
          'fullName': 'Other Doctor Patient',
          'phone': '01099990002',
          'assignedDoctorId': 999999,
        }),
      );
      expect(createOtherPat.statusCode, equals(201));

      // 1. Doctor (has Base `patients`, NOT `patients_all`) queries /api/v1/patients -> sees ONLY own assigned patient (1 record)!
      final docListResp = await http.get(
        Uri.parse('$baseUrl/api/v1/patients'),
        headers: {
          'authorization': 'Bearer $docToken',
          'x-tenant-id': 'HOSP_A',
          'x-medcore-device-id': 'DEV-WKS-01',
        },
      );
      expect(docListResp.statusCode, equals(200));
      final docListData = jsonDecode(docListResp.body)['data'];
      expect(docListData['dataScopeApplied'], equals('ownOnly'));
      expect(docListData['count'], equals(1));
      expect(docListData['items'][0]['mrn'], equals('MRN-DOC-OWN'));

      // 2. Receptionist (has `patients_all`) queries /api/v1/patients -> sees ALL 3 patients in HOSP_A!
      final recListResp = await http.get(
        Uri.parse('$baseUrl/api/v1/patients'),
        headers: {
          'authorization': 'Bearer $recToken',
          'x-tenant-id': 'HOSP_A',
          'x-medcore-device-id': 'DEV-WKS-01',
        },
      );
      expect(recListResp.statusCode, equals(200));
      final recListData = jsonDecode(recListResp.body)['data'];
      expect(recListData['dataScopeApplied'], equals('tenantWide'));
      expect(recListData['count'], equals(3));

      // 3. HospitalAdmin dynamically grants `patients_all` to Doctor via PUT /api/v1/staff/<id>/permissions
      final upgradeResp = await http.put(
        Uri.parse('$baseUrl/api/v1/staff/$docRoleId/permissions'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $adminToken',
          'x-tenant-id': 'HOSP_A',
          'x-medcore-device-id': 'DEV-WKS-01',
        },
        body: jsonEncode({
          'permissionsMode': 'custom',
          'customPermissions': ['patients', 'patients_all', 'doctor_ClinicalWorkspace'],
        }),
      );
      expect(upgradeResp.statusCode, equals(200));

      // Now Doctor queries /api/v1/patients -> receives tenantWide scope (all 3 patients)!
      final docUpgradedResp = await http.get(
        Uri.parse('$baseUrl/api/v1/patients'),
        headers: {
          'authorization': 'Bearer $docToken',
          'x-tenant-id': 'HOSP_A',
          'x-medcore-device-id': 'DEV-WKS-01',
        },
      );
      final docUpgradedData = jsonDecode(docUpgradedResp.body)['data'];
      expect(docUpgradedData['dataScopeApplied'], equals('tenantWide'));
      expect(docUpgradedData['count'], equals(3));
    });

    test('TASK 2.5: Enforces Dimension 3 (_secure Device Lock) & Operational Flags (canDelete, canCollectMoney, refundPolicy)', () async {
      final adminToken = roleTokens[MedCoreRole.HospitalAdmin]!;
      final recToken = roleTokens[MedCoreRole.Receptionist]!;
      final cshToken = roleTokens[MedCoreRole.Cashier]!;

      // 1. Test Dimension 3 (`_secure` Device Lock on /api/v1/finance/settlements):
      // Login as HospitalAdmin on DEV-KIOSK-UNTRUSTED (`isTrustedSecureRuntime = false`)
      final kioskLogin = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/login'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': 'HOSP_A',
          'identifier': 'hospitaladmin@hosp-a.local',
          'password': 'Pass#HospitalAdmin123',
          'deviceId': 'DEV-KIOSK-UNTRUSTED',
        }),
      );
      expect(kioskLogin.statusCode, equals(200));
      final kioskAdminToken = jsonDecode(kioskLogin.body)['data']['token'] as String;

      // Calling /api/v1/finance/settlements from untrusted kiosk device -> 403 SECURE_DEVICE_REQUIRED
      final kioskSettleResp = await http.get(
        Uri.parse('$baseUrl/api/v1/finance/settlements'),
        headers: {
          'authorization': 'Bearer $kioskAdminToken',
          'x-tenant-id': 'HOSP_A',
          'x-medcore-device-id': 'DEV-KIOSK-UNTRUSTED',
        },
      );
      expect(kioskSettleResp.statusCode, equals(403));
      expect(jsonDecode(kioskSettleResp.body)['error']['code'], equals('SECURE_DEVICE_REQUIRED'));

      // Calling /api/v1/finance/settlements from trusted Desktop DEV-WKS-01 -> 200 OK
      final wksSettleResp = await http.get(
        Uri.parse('$baseUrl/api/v1/finance/settlements'),
        headers: {
          'authorization': 'Bearer $adminToken',
          'x-tenant-id': 'HOSP_A',
          'x-medcore-device-id': 'DEV-WKS-01',
        },
      );
      expect(wksSettleResp.statusCode, equals(200));
      final settleData = jsonDecode(wksSettleResp.body)['data'];
      expect(settleData['secureDeviceVerified'], isTrue);
      expect(settleData['count'], equals(1));
      expect(settleData['items'][0]['amount'], equals('300.0000'));

      // 2. Test Operational Flag `canDelete`: Receptionist (`canDelete = false`) cannot DELETE patient
      final recDelResp = await http.delete(
        Uri.parse('$baseUrl/api/v1/patients/1'),
        headers: {
          'authorization': 'Bearer $recToken',
          'x-tenant-id': 'HOSP_A',
          'x-medcore-device-id': 'DEV-WKS-01',
        },
      );
      expect(recDelResp.statusCode, equals(403));
      expect(jsonDecode(recDelResp.body)['error']['code'], equals('ACTION_FLAG_DENIED_DELETE'));

      // 3. Test Operational Flag `refundPolicy`:
      // Cashier has `canMakeRefunds = true` & `refundPolicy = approval` -> creates PENDING_APPROVAL dual-control request
      final cshRefundResp = await http.post(
        Uri.parse('$baseUrl/api/v1/visits/1/refund'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $cshToken',
          'x-tenant-id': 'HOSP_A',
          'x-medcore-device-id': 'DEV-WKS-01',
        },
        body: jsonEncode({
          'refundAmount': '200.0000',
          'reason': 'Patient cancelled lab component',
        }),
      );
      expect(cshRefundResp.statusCode, equals(200));
      expect(jsonDecode(cshRefundResp.body)['data']['status'], equals('PENDING_APPROVAL'));

      // HospitalAdmin has `canMakeRefunds = true` & `refundPolicy = direct` -> executes direct refund
      final admRefundResp = await http.post(
        Uri.parse('$baseUrl/api/v1/visits/1/refund'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $adminToken',
          'x-tenant-id': 'HOSP_A',
          'x-medcore-device-id': 'DEV-WKS-01',
        },
        body: jsonEncode({
          'refundAmount': '1000.0000',
          'reason': 'Executive authorized full refund',
        }),
      );
      expect(admRefundResp.statusCode, equals(200));
      expect(jsonDecode(admRefundResp.body)['data']['status'], equals('EXECUTED_DIRECT'));
    });

    test('TASK 2.6: Verifies Truth & Data Explorer (Schema Introspection, Privacy PII Masking, Relational Truth Trace & Exports)', () async {
      final adminToken = roleTokens[MedCoreRole.HospitalAdmin]!;

      // 1. Schema & Structure Introspection
      final schemaResp = await http.get(
        Uri.parse('$baseUrl/api/v1/explorer/schema'),
        headers: {
          'authorization': 'Bearer $adminToken',
          'x-tenant-id': 'HOSP_A',
          'x-medcore-device-id': 'DEV-WKS-01',
        },
      );
      expect(schemaResp.statusCode, equals(200));
      final schemaJson = jsonDecode(schemaResp.body)['data'];
      expect(schemaJson['tableCount'], equals(91));
      expect(schemaJson['tables'], isList);
      final tableNames = (schemaJson['tables'] as List).map((t) => t['tableName'] as String).toList();
      expect(tableNames, containsAll([
        'mc_patients', 'mc_visits', 'mc_financial_events', 'mc_financial_postings',
        'mc_schema_migrations', 'mc_security_root', 'mc_consumed_maintenance_tokens',
      ]));

      // 2. Data Inspection with Privacy Filter ON (PII masked)
      final piiMaskedResp = await http.get(
        Uri.parse('$baseUrl/api/v1/explorer/table/mc_patients?privacy=true'),
        headers: {
          'authorization': 'Bearer $adminToken',
          'x-tenant-id': 'HOSP_A',
          'x-medcore-device-id': 'DEV-WKS-01',
        },
      );
      expect(piiMaskedResp.statusCode, equals(200));
      final maskedData = jsonDecode(piiMaskedResp.body)['data'];
      expect(maskedData['privacyFilterApplied'], isTrue);
      final maskedRecords = maskedData['records'] as List;
      expect(maskedRecords.isNotEmpty, isTrue);
      final pat = maskedRecords.first;
      expect(pat['full_name'], equals('P*** e***')); // 'Patient One' -> masked
      expect(pat['phone'], equals('010****0001'));   // '01000000001' -> masked

      // 3. Relational Truth Trace (Visit -> Patient -> Items -> Cost Lines -> Financial Event -> Postings -> Shift -> Audit)
      final traceResp = await http.get(
        Uri.parse('$baseUrl/api/v1/explorer/trace/VIS-2026-0001'),
        headers: {
          'authorization': 'Bearer $adminToken',
          'x-tenant-id': 'HOSP_A',
          'x-medcore-device-id': 'DEV-WKS-01',
        },
      );
      expect(traceResp.statusCode, equals(200), reason: 'Trace failed: ${traceResp.body}');
      final trace = jsonDecode(traceResp.body)['data'];
      expect(trace['traceType'], equals('VISIT_TRUTH_GRAPH'));
      expect(trace['visitNumber'], equals('VIS-2026-0001'));
      expect(trace['visit']['gross_amount'], equals('1000.0000'));
      expect(trace['visit']['paid_amount'], equals('1000.0000'));
      expect(trace['costLines'], isList);
      expect((trace['costLines'] as List).length, equals(2)); // FIN-004: Service Labor (600.0000) + Consumables FIFO (250.0000)
      final componentTypes = (trace['costLines'] as List).map((c) => c['component_type']).toList();
      expect(componentTypes, containsAll(['SERVICE_LABOR', 'CONSUMABLE_MATERIAL']));
      final consumableLine = (trace['costLines'] as List).firstWhere((c) => c['component_type'] == 'CONSUMABLE_MATERIAL');
      expect(consumableLine['total_cost_fifo'], equals('250.0000'));
      expect(trace['financialEvents'], isList);
      expect((trace['financialEvents'] as List).first['commission_amount'], equals('300.0000'));
      expect(trace['financialPostings'], isList);
      expect((trace['financialPostings'] as List).length, equals(7)); // Balanced double entry postings
      expect(trace['shift']['opening_balance'], equals('500.0000'));
      expect(trace['auditTrail'], isList);

      // 4. Structured CSV Export
      final csvResp = await http.get(
        Uri.parse('$baseUrl/api/v1/explorer/export?table=mc_patients&format=csv&privacy=true'),
        headers: {
          'authorization': 'Bearer $adminToken',
          'x-tenant-id': 'HOSP_A',
          'x-medcore-device-id': 'DEV-WKS-01',
        },
      );
      expect(csvResp.statusCode, equals(200));
      expect(csvResp.headers['content-type'], contains('text/csv'));
      expect(csvResp.body, contains('hospital_code'));
      expect(csvResp.body, contains('010****0001'));

      // 5. Structured TXT Export
      final txtResp = await http.get(
        Uri.parse('$baseUrl/api/v1/explorer/export?table=mc_patients&format=txt&privacy=true'),
        headers: {
          'authorization': 'Bearer $adminToken',
          'x-tenant-id': 'HOSP_A',
          'x-medcore-device-id': 'DEV-WKS-01',
        },
      );
      expect(txtResp.statusCode, equals(200));
      expect(txtResp.headers['content-type'], contains('text/plain'));
      expect(txtResp.body, contains('MEDCORE DESKTOP — AUTHORITATIVE DATA EXPORT'));
      expect(txtResp.body, contains('Table: mc_patients'));
    });
  });
}
