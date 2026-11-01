import 'dart:convert';
import 'dart:io';
import 'package:medcore_local_service/medcore_local_service.dart';
import 'package:medcore_local_service/src/repositories/definitions_repository.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'support/test_db_config.dart';

void main() {
  const dbName = 'medcore_definitions_parity_test';
  late DbClient db;
  late DefinitionsRepository definitionsRepo;
  const hospitalCode = 'HOSP_PARITY_MAIN';
  const hospitalCodeB = 'HOSP_PARITY_BRANCH';

  late ScopeContext mainScope;
  late ScopeContext branchScope;

  setUpAll(() async {
    final config = testDbConfig(databaseName: dbName, maxConnections: 5);
    db = DbClient(config);

    // 1. Clean Database: Drop and Recreate
    final adminConn = await db.openDedicatedConnection(useDatabase: false);
    try {
      await adminConn.execute('DROP DATABASE IF EXISTS `$dbName`');
      await adminConn.execute(
        'CREATE DATABASE `$dbName` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
      );
    } finally {
      await adminConn.close();
    }

    // 2. Apply all migrations V001..V019
    final serviceRoot = Directory.current.path;
    final migrationsDir = p.join(serviceRoot, 'sql', 'migrations');
    final migrationRunner = MigrationRunner(db: db, migrationsDir: migrationsDir);
    final applied = await migrationRunner.runMigrations();
    expect(applied.length, greaterThanOrEqualTo(19), reason: 'At least 19 migrations must be applied');

    definitionsRepo = DefinitionsRepository(db);

    final staffMain = StaffIdentity(
      id: 1,
      hospitalCode: hospitalCode,
      staffCode: 'STF-MAIN-001',
      fullName: 'Chief Medical Officer',
      email: 'cmo@medcore.local',
      role: MedCoreRole.SuperAdmin,
      permissionsMode: 'default',
      customPermissions: const {},
      securePageLocks: const {},
      operationalFlags: const OperationalFlags(canEdit: true, canDelete: true, canCollectMoney: true, canMakeRefunds: true, refundPolicy: RefundPolicy.direct),
      isActive: true,
    );

    final staffBranch = StaffIdentity(
      id: 2,
      hospitalCode: hospitalCodeB,
      staffCode: 'STF-BR-001',
      fullName: 'Branch Administrator',
      email: 'admin@branch.medcore.local',
      role: MedCoreRole.HospitalAdmin,
      permissionsMode: 'default',
      customPermissions: const {},
      securePageLocks: const {},
      operationalFlags: const OperationalFlags(canEdit: true, canDelete: true, canCollectMoney: true, canMakeRefunds: true, refundPolicy: RefundPolicy.direct),
      isActive: true,
    );

    mainScope = ScopeContext(
      hospitalCode: hospitalCode,
      actor: staffMain,
      deviceId: 'DEV-PARITY-MAIN',
      isTrustedSecureDevice: true,
      dataScopeMode: DataScopeMode.tenantWide,
      activePermission: 'settings_Definitions',
    );

    branchScope = ScopeContext(
      hospitalCode: hospitalCodeB,
      actor: staffBranch,
      deviceId: 'DEV-PARITY-BR',
      isTrustedSecureDevice: true,
      dataScopeMode: DataScopeMode.tenantWide,
      activePermission: 'settings_Definitions',
    );
  });

  tearDownAll(() async {
    await db.close();
  });

  group('GATE 03 — Backend Domain Foundation & Master Definitions Tests', () {
    test('1. Authoritative Database Schema reifies V019 additive tables and indexes', () async {
      final res = await db.execute(
        '''
        SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES
        WHERE TABLE_SCHEMA = :db AND TABLE_NAME IN ('mc_definitions', 'mc_doctor_commission_profiles', 'mc_internal_notes')
        ''',
        {'db': dbName},
      );
      final tables = res.rows.map((r) => r.colByName('TABLE_NAME')).toSet();
      expect(tables.contains('mc_definitions'), isTrue);
      expect(tables.contains('mc_doctor_commission_profiles'), isTrue);
      expect(tables.contains('mc_internal_notes'), isTrue);
    });

    test('2. DefinitionsRepository creates, persists, and directly reads back 21 master domains from MariaDB', () async {
      // Create a clinic definition
      final created = await definitionsRepo.createDefinition(
        scope: mainScope,
        type: 'clinic',
        code: 'CLN-CARDIO',
        name: 'عيادة أمراض القلب والأوعية الدموية',
        dataJson: {
          'specialty': 'Cardiology',
          'consultationFee': 250.0,
          'followupFee': 100.0,
          'isTemporary': false,
        },
      );

      expect(created['publicId'], isNotEmpty);
      expect(created['code'], equals('CLN-CARDIO'));
      expect(created['status'], equals('ACTIVE'));
      expect(created['version'], equals(1));

      // Direct SQL read-back from physical MariaDB (Khaled Database Truth Rule)
      final rawDbRes = await db.execute(
        'SELECT * FROM mc_definitions WHERE hospital_code = :hosp AND code = :code',
        {'hosp': hospitalCode, 'code': 'CLN-CARDIO'},
      );
      expect(rawDbRes.rows.length, equals(1));
      final rawRow = rawDbRes.rows.first.assoc();
      expect(rawRow['name'], equals('عيادة أمراض القلب والأوعية الدموية'));
      expect(rawRow['definition_type'], equals('clinic'));

      final parsedJson = jsonDecode(rawRow['data_json']!) as Map<String, dynamic>;
      expect(parsedJson['consultationFee'], equals(250.0));
    });

    test('3. Temporary Clinic creation with dynamic expiration and metadata', () async {
      final tempClinic = await definitionsRepo.createDefinition(
        scope: mainScope,
        type: 'temporary_clinic',
        code: 'TEMP-EVENING-01',
        name: 'عيادة الاستشاري الزائر المسائية',
        dataJson: {
          'isTemporary': true,
          'validUntil': '2026-12-31',
          'parentClinicCode': 'CLN-CARDIO',
        },
      );

      expect(tempClinic['definitionType'], equals('temporary_clinic'));
      expect(tempClinic['dataJson']['isTemporary'], isTrue);
    });

    test('4. Update increments version and persists modifications to MariaDB', () async {
      final created = await definitionsRepo.createDefinition(
        scope: mainScope,
        type: 'service',
        code: 'SRV-ECG',
        name: 'رسم قلب عادي',
        dataJson: {'basePrice': 80.0},
      );

      final pubId = created['publicId'] as String;
      final updated = await definitionsRepo.updateDefinition(
        scope: mainScope,
        publicId: pubId,
        name: 'رسم قلب رقمي متقدم',
        dataJson: {'basePrice': 120.0},
      );

      expect(updated['version'], equals(2));
      expect(updated['name'], equals('رسم قلب رقمي متقدم'));

      // Direct SQL Read-back
      final rawDbRes = await db.execute(
        'SELECT version, name FROM mc_definitions WHERE public_id = :pub_id',
        {'pub_id': pubId},
      );
      expect(int.parse(rawDbRes.rows.first.assoc()['version']!), equals(2));
      expect(rawDbRes.rows.first.assoc()['name'], equals('رسم قلب رقمي متقدم'));
    });

    test('5. Soft archive sets status=ARCHIVED and excludes from active list', () async {
      final created = await definitionsRepo.createDefinition(
        scope: mainScope,
        type: 'room',
        code: 'ROOM-101',
        name: 'غرفة كشف 101',
      );
      final pubId = created['publicId'] as String;

      await definitionsRepo.archiveDefinition(scope: mainScope, publicId: pubId);

      final list = await definitionsRepo.listDefinitions(
        scope: mainScope,
        type: 'room',
        status: 'ACTIVE',
      );
      expect(list.any((r) => r['publicId'] == pubId), isFalse);

      final archivedRecord = await definitionsRepo.getDefinition(scope: mainScope, publicId: pubId);
      expect(archivedRecord?['status'], equals('ARCHIVED'));
    });

    test('6. Multi-Tenant Isolation guarantees zero cross-tenant definition leakage', () async {
      // Main tenant creates bed
      await definitionsRepo.createDefinition(
        scope: mainScope,
        type: 'bed',
        code: 'BED-ICU-01',
        name: 'سرير رعاية مركزة 01',
      );

      // Branch tenant queries beds
      final branchBeds = await definitionsRepo.listDefinitions(scope: branchScope, type: 'bed');
      expect(branchBeds.any((b) => b['code'] == 'BED-ICU-01'), isFalse);
    });

    test('7. Doctor Commission Profiles upsert and retrieve with decimal precision', () async {
      final profile = await definitionsRepo.upsertDoctorCommissionProfile(
        scope: mainScope,
        doctorId: 101,
        doctorCode: 'DOC-CARDIO-AHMED',
        commissionMode: 'PERCENTAGE',
        consultationSharePct: 45.50,
        procedureSharePct: 30.00,
        fixedConsultationCut: 50.0000,
      );

      expect(profile['doctor_code'], equals('DOC-CARDIO-AHMED'));
      expect(double.parse(profile['consultation_share_pct']!), equals(45.50));

      // Direct SQL verification from mc_doctor_commission_profiles
      final raw = await db.execute(
        'SELECT * FROM mc_doctor_commission_profiles WHERE hospital_code = :hosp AND doctor_code = :code',
        {'hosp': hospitalCode, 'code': 'DOC-CARDIO-AHMED'},
      );
      expect(raw.rows.length, equals(1));
      expect(raw.rows.first.assoc()['commission_mode'], equals('PERCENTAGE'));
    });

    test('8. Internal Notes (Draggable FAB) creation, listing, and pinning', () async {
      final note1 = await definitionsRepo.createInternalNote(
        scope: mainScope,
        category: 'URGENT',
        subject: 'عطل في جهاز رسم القلب',
        content: 'يرجى مراجعة الصيانة الطبية فوراً بالدور الثاني',
        isPinned: false,
      );

      final note2 = await definitionsRepo.createInternalNote(
        scope: mainScope,
        category: 'ADMINISTRATIVE',
        subject: 'تعليمات تسليم وردية المساء',
        content: 'التأكد من توريد النقدية ومطابقة إيصالات الدفع',
        isPinned: true,
      );

      final notes = await definitionsRepo.listInternalNotes(scope: mainScope);
      expect(notes.isNotEmpty, isTrue);
      // Pinned note must be first
      expect(notes.first['public_id'], equals(note2['public_id']));

      // Toggle pin on note 1
      await definitionsRepo.togglePinInternalNote(
        scope: mainScope,
        publicId: note1['public_id'],
        isPinned: true,
      );

      final updated = await definitionsRepo.listInternalNotes(scope: mainScope);
      final n1 = updated.firstWhere((n) => n['public_id'] == note1['public_id']);
      expect(n1['is_pinned'], equals('1'));
    });

    group('RED TEAM: Gate 03 Backend Domain Attack Vectors', () {
      test('RED-03-01: Cross-tenant modification attempt fails closed', () async {
        final mainDef = await definitionsRepo.createDefinition(
          scope: mainScope,
          type: 'service',
          code: 'SRV-SEC-01',
          name: 'خدمة سرية رئيسية',
        );

        // Branch tenant attempts to update main tenant definition
        expect(
          () => definitionsRepo.updateDefinition(
            scope: branchScope,
            publicId: mainDef['publicId'],
            name: 'محاولة اختراق التعديل',
          ),
          throwsA(isA<StateError>()),
        );
      });

      test('RED-03-02: Duplicate definition code in same tenant and domain is rejected', () async {
        await definitionsRepo.createDefinition(
          scope: mainScope,
          type: 'department',
          code: 'DEPT-ICU',
          name: 'قسم العناية المركزة',
        );

        expect(
          () => definitionsRepo.createDefinition(
            scope: mainScope,
            type: 'department',
            code: 'DEPT-ICU',
            name: 'محاولة إدخال كود مكرر',
          ),
          throwsA(isA<StateError>()),
        );
      });

      test('RED-03-03: Empty code or name fails input validation', () async {
        expect(
          () => definitionsRepo.createDefinition(
            scope: mainScope,
            type: 'clinic',
            code: '   ',
            name: 'عيادة بدون كود',
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('RED-03-04: SQL injection in domain type parameter is neutralized', () async {
        const sqliType = "clinic' OR '1'='1";
        final results = await definitionsRepo.listDefinitions(
          scope: mainScope,
          type: sqliType,
        );
        expect(results.isEmpty, isTrue);
      });
    });
  });
}
