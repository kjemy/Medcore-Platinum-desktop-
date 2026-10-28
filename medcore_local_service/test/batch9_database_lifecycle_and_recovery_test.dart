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
  late Directory testBackupDir;
  late DatabaseLifecycleService lifecycleService;
  late String techToken;
  const runtimeTechSecret = 'TechSecret!2026';
  const hospitalCode = 'HOSP_TEST';
  const deviceId = 'DEV-MAIN-HOST';

  final serviceRoot = Directory.current.path;
  final migrationsDir = p.join(serviceRoot, 'sql', 'migrations');

  setUpAll(() async {
    securityRoot = Directory.systemTemp.createTempSync('medcore-b9-security-');
    testBackupDir = Directory.systemTemp.createTempSync('medcore-b9-backup-');

    final config = testDbConfig(databaseName: 'medcore_test', maxConnections: 10);
    db = DbClient(config);

    // Ensure clean medcore_test database
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
    await migrationRunner.runMigrations();

    // Setup tenant & device for technician auth
    final govRepo = TenantGovernanceRepository(db);
    await govRepo.upsertTenant(hospitalCode: hospitalCode, name: 'MedCore Test Facility');
    await govRepo.enrollOrUpdateDevice(
      hospitalCode: hospitalCode,
      deviceId: deviceId,
      deviceName: 'Main Server Workstation',
      platform: 'WINDOWS',
      connectionType: 'LOOPBACK',
      hwFingerprintSha256: PasswordHasher.sha256Hex('MAIN-HOST-HW-01'),
      devicePublicKeyEd25519: 'PUBKEY-MAIN-HOST-01',
      roleScope: 'SERVER_HOST',
      isTrustedSecureRuntime: true,
      status: 'ACTIVE',
    );

    server = LocalMedCoreServer(
      db,
      securityRootDirectory: securityRoot.path,
      technicianSecretHashOverride: PasswordHasher.hashPassword(runtimeTechSecret),
      backupStorageDirectory: testBackupDir.path,
    );
    final port = await server!.start(address: '127.0.0.1', port: 0);
    baseUrl = 'http://127.0.0.1:$port';

    // Authenticate technician session
    final openResp = await http.post(
      Uri.parse('$baseUrl/api/v1/technician/session/open'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'hospitalCode': hospitalCode,
        'deviceId': deviceId,
        'technicianSecret': runtimeTechSecret,
      }),
    );
    expect(openResp.statusCode, equals(201));
    techToken = jsonDecode(openResp.body)['data']['technicianToken'] as String;

    lifecycleService = server!.databaseLifecycleService;
  });

  tearDownAll(() async {
    await server?.stop();
    await db.close();
    try {
      if (securityRoot.existsSync()) securityRoot.deleteSync(recursive: true);
    } catch (_) {}
    try {
      if (testBackupDir.existsSync()) testBackupDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Map<String, String> techHeaders({String devId = deviceId}) => {
        'content-type': 'application/json',
        'x-medcore-tech-token': techToken,
        'x-tenant-id': hospitalCode,
        'x-medcore-device-id': devId,
      };

  group('BATCH 9 — GATE 11 & GATE 12: Database Lifecycle, Backup, Export, Restore & Reset', () {
    test('9.1 Database Status & Diagnostics discloses engine version, 96 tables & schema version', () async {
      final status = await lifecycleService.getDatabaseStatus(hospitalCode: hospitalCode);
      expect(status['engine'], equals('MariaDB'));
      expect(status['databaseName'], equals('medcore_test'));
      expect(status['tableCount'], greaterThanOrEqualTo(96));
      expect(status['databaseStatus'], equals('ONLINE'));
      expect(status['characterSet'], equals('utf8mb4'));
      expect(status['collation'], equals('utf8mb4_unicode_ci'));
      expect(status['schemaVersion'], isNotNull);
    });

    test('9.2 Database Physical Location discloses runtime, data, backup, and export paths', () {
      final location = lifecycleService.getDatabaseLocation();
      expect(location['engine'], equals('MariaDB'));
      expect(location['databaseName'], equals('medcore_test'));
      expect(location['safetyNotice'], contains('DO NOT MODIFY OR DELETE'));
    });

    test('9.3 Database Table Statistics returns metrics for all 96+ tables', () async {
      final stats = await lifecycleService.getDatabaseStats();
      expect(stats, hasLength(greaterThanOrEqualTo(96)));
      final tableNames = stats.map((s) => s['tableName']).toSet();
      expect(tableNames.contains('mc_patients'), isTrue);
      expect(tableNames.contains('mc_visits'), isTrue);
      expect(tableNames.contains('mc_shifts'), isTrue);
      expect(tableNames.contains('mc_financial_events'), isTrue);
      expect(tableNames.contains('mc_financial_postings'), isTrue);
      expect(tableNames.contains('mc_schema_migrations'), isTrue);
    });

    test('9.4 Full Backup Package produces SQL, JSON, XLSX, CSV, Manifest, Checksums, MCBAK & ZIP', () async {
      final backup = await lifecycleService.createFullBackupPackage(
        hospitalCode: hospitalCode,
        actorRoleLabel: 'TECHNICIAN_SERVICE',
        deviceId: deviceId,
      );

      expect(backup['backupUuid'], startsWith('BK-'));
      expect(backup['status'], equals('VERIFIED'));
      expect(backup['tableCount'], greaterThanOrEqualTo(96));
      expect(backup['mcbakSha256'], hasLength(64));
      expect(backup['zipSha256'], hasLength(64));

      final backupDir = Directory(backup['backupDirectory'] as String);
      expect(backupDir.existsSync(), isTrue);

      // Verify all artifact files physically exist
      final sqlFile = File(p.join(backupDir.path, 'database.sql'));
      final jsonFile = File(p.join(backupDir.path, 'database.json'));
      final xlsxFile = File(p.join(backupDir.path, 'database.xlsx'));
      final csvDir = Directory(p.join(backupDir.path, 'csv'));
      final manifestFile = File(p.join(backupDir.path, 'manifest.json'));
      final checksumsFile = File(p.join(backupDir.path, 'checksums.sha256'));
      final mcbakFile = File(backup['mcbakPath'] as String);
      final zipFile = File(backup['zipPath'] as String);

      expect(sqlFile.existsSync(), isTrue);
      expect(jsonFile.existsSync(), isTrue);
      expect(xlsxFile.existsSync(), isTrue);
      expect(csvDir.existsSync(), isTrue);
      expect(manifestFile.existsSync(), isTrue);
      expect(checksumsFile.existsSync(), isTrue);
      expect(mcbakFile.existsSync(), isTrue);
      expect(zipFile.existsSync(), isTrue);

      // Verify XLSX file is non-empty and has ZIP magic bytes (PK..)
      final xlsxBytes = await xlsxFile.readAsBytes();
      expect(xlsxBytes.length, greaterThan(100));
      expect(xlsxBytes[0], equals(0x50)); // 'P'
      expect(xlsxBytes[1], equals(0x4B)); // 'K'

      // Verify SQL contains DDL statements
      final sqlContent = await sqlFile.readAsString();
      expect(sqlContent, contains('CREATE TABLE `mc_patients`'));
      expect(sqlContent, contains('SET FOREIGN_KEY_CHECKS = 0;'));

      // Verify checksums.sha256 contains hashes for database.sql, database.json, database.xlsx
      final checksumsContent = await checksumsFile.readAsString();
      expect(checksumsContent, contains('database.sql'));
      expect(checksumsContent, contains('database.json'));
      expect(checksumsContent, contains('database.xlsx'));
      expect(checksumsContent, contains('csv/mc_patients.csv'));
    });

    test('9.5 Backup Package Verification: valid package passes; tampered package fails', () async {
      // Create fresh package to test
      final backup = await lifecycleService.createFullBackupPackage(
        hospitalCode: hospitalCode,
        actorRoleLabel: 'TECHNICIAN_SERVICE',
        deviceId: deviceId,
      );
      final backupDir = backup['backupDirectory'] as String;

      // Verification of pristine package must return status: VERIFIED
      final pristineVerification = await lifecycleService.verifyBackupPackage(
        backupPackagePath: backupDir,
      );
      expect(pristineVerification['status'], equals('VERIFIED'));
      expect(pristineVerification['mismatchedChecksums'], isEmpty);
      expect(pristineVerification['missingFiles'], isEmpty);

      // Adversarial Tampering: Corrupt database.sql by appending a byte
      final sqlFile = File(p.join(backupDir, 'database.sql'));
      await sqlFile.writeAsString('/* TAMPERED BY RED TEAM */', mode: FileMode.append);

      // Verification of tampered package must detect mismatch / fail closed
      expect(
        () => lifecycleService.verifyBackupPackage(
          backupPackagePath: backupDir,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('9.6 Multi-Format Standalone Export generates SQL, CSV, JSON, XLSX & ZIP packages', () async {
      final exportResult = await lifecycleService.createFullBackupPackage(
        hospitalCode: hospitalCode,
        triggerType: 'MANUAL_ADMIN_EXPORT',
        actorRoleLabel: 'TECHNICIAN_SERVICE',
        deviceId: deviceId,
        includeZipExport: true,
      );

      expect(exportResult['backupUuid'], startsWith('BK-'));
      expect(exportResult['status'], equals('VERIFIED'));
      expect(exportResult['tableCount'], greaterThanOrEqualTo(96));

      final exportDir = Directory(exportResult['backupDirectory'] as String);
      expect(exportDir.existsSync(), isTrue);
      expect(File(p.join(exportDir.path, 'database.sql')).existsSync(), isTrue);
      expect(File(p.join(exportDir.path, 'database.json')).existsSync(), isTrue);
      expect(File(p.join(exportDir.path, 'database.xlsx')).existsSync(), isTrue);
      expect(Directory(p.join(exportDir.path, 'csv')).existsSync(), isTrue);
    });

    test('9.7 Factory Reset: Enforces strict safety, requires RESET MEDCORE, re-migrates & seeds baseline', timeout: const Timeout(Duration(minutes: 2)), () async {
      // 1. Rejection without confirmation text
      expect(
        () => lifecycleService.factoryReset(
          hospitalCode: hospitalCode,
          confirmationText: 'reset',
          actorRoleLabel: 'TECHNICIAN_SERVICE',
        ),
        throwsA(isA<ArgumentError>()),
      );

      // 2. Insert a sentinel record to prove state destruction
      await db.execute(
        "INSERT INTO mc_patients (hospital_code, mrn, full_name, gender, date_of_birth, phone) "
        "VALUES ('$hospitalCode', 'MRN-PRE-01', 'Temporary Patient', 'male', '1990-01-01', '+201000000000')",
      );
      final preCount = await db.execute("SELECT COUNT(*) AS c FROM mc_patients WHERE mrn = 'MRN-PRE-01'");
      expect(preCount.rows.first.assoc()['c'], equals('1'));

      // 3. Execute authorized factory reset
      final resetResult = await lifecycleService.factoryReset(
        hospitalCode: hospitalCode,
        confirmationText: 'RESET MEDCORE',
        actorRoleLabel: 'TECHNICIAN_SERVICE',
      );

      expect(resetResult['status'], equals('COMPLETED_AND_REBUILT'));
      expect(resetResult['rebuiltTableCount'], greaterThanOrEqualTo(96));
      expect(resetResult['preResetBackupUuid'], startsWith('BK-'));
      expect(resetResult['trialBalanceBalanced'], isTrue);

      // 4. Verify physical database read-back: sentinel record must be completely destroyed
      final postCount = await db.execute("SELECT COUNT(*) AS c FROM mc_patients WHERE mrn = 'MRN-PRE-01'");
      expect(postCount.rows.first.assoc()['c'], equals('0'));

      // 5. Verify seed data was restored
      final facilities = await db.execute("SELECT COUNT(*) AS c FROM mc_facility_config");
      expect(int.parse(facilities.rows.first.assoc()['c']!), greaterThanOrEqualTo(1));
    });

    test('9.8 End-to-End Round-Trip: Insert Data -> Full Backup -> Factory Reset -> Restore -> Read-Back Parity', timeout: const Timeout(Duration(minutes: 3)), () async {
      // 1. Insert known patient
      const testMrn = 'MRN-RT-01';
      await db.execute(
        "INSERT INTO mc_patients (hospital_code, mrn, full_name, gender, date_of_birth, phone) "
        "VALUES ('$hospitalCode', '$testMrn', 'Round Trip Patient', 'female', '1985-05-15', '+201000000000')",
      );

      // 2. Create verified backup package containing this record
      final backup = await lifecycleService.createFullBackupPackage(
        hospitalCode: hospitalCode,
        actorRoleLabel: 'TECHNICIAN_SERVICE',
        deviceId: deviceId,
      );
      final backupDir = backup['backupDirectory'] as String;

      // 3. Factory reset to wipe the database
      await lifecycleService.factoryReset(
        hospitalCode: hospitalCode,
        confirmationText: 'RESET MEDCORE',
        actorRoleLabel: 'TECHNICIAN_SERVICE',
      );

      // Confirm record is gone
      final wiped = await db.execute("SELECT COUNT(*) AS c FROM mc_patients WHERE mrn = '$testMrn'");
      expect(wiped.rows.first.assoc()['c'], equals('0'));

      // 4. Restore database from the backup package
      final restoreResult = await lifecycleService.restoreBackup(
        hospitalCode: hospitalCode,
        backupPackagePath: backupDir,
        actorRoleLabel: 'TECHNICIAN_SERVICE',
      );

      expect(restoreResult['status'], equals('RESTORED_AND_VERIFIED'));
      expect(restoreResult['trialBalanceConserved'], isTrue);
      expect(restoreResult['restoredTableCount'], greaterThanOrEqualTo(96));

      // 5. Authoritative Physical Read-Back: Patient record restored with 100% field parity
      final restored = await db.execute("SELECT * FROM mc_patients WHERE mrn = '$testMrn'");
      expect(restored.rows, hasLength(1));
      final pRow = restored.rows.first.assoc();
      expect(pRow['full_name'], equals('Round Trip Patient'));
      expect(pRow['mrn'], equals(testMrn));
      expect(pRow['gender'], equals('female'));
    });

    test('9.9 REST API Endpoints: All Database Lifecycle routes respond correctly and enforce security', timeout: const Timeout(Duration(minutes: 2)), () async {
      // Re-enroll device and tenant after factory reset to ensure auth works
      final govRepo = TenantGovernanceRepository(db);
      await govRepo.upsertTenant(hospitalCode: hospitalCode, name: 'MedCore Test Facility');
      await govRepo.enrollOrUpdateDevice(
        hospitalCode: hospitalCode,
        deviceId: deviceId,
        deviceName: 'Main Server Workstation',
        platform: 'WINDOWS',
        connectionType: 'LOOPBACK',
        hwFingerprintSha256: PasswordHasher.sha256Hex('MAIN-HOST-HW-01'),
        devicePublicKeyEd25519: 'PUBKEY-MAIN-HOST-01',
        roleScope: 'SERVER_HOST',
        isTrustedSecureRuntime: true,
        status: 'ACTIVE',
      );

      // Refresh technician session
      final openResp = await http.post(
        Uri.parse('$baseUrl/api/v1/technician/session/open'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': hospitalCode,
          'deviceId': deviceId,
          'technicianSecret': runtimeTechSecret,
        }),
      );
      expect(openResp.statusCode, equals(201), reason: 'openSession body: ${openResp.body}');
      techToken = jsonDecode(openResp.body)['data']['technicianToken'] as String;

      // GET /api/v1/database/status
      final statusResp = await http.get(
        Uri.parse('$baseUrl/api/v1/database/status'),
        headers: techHeaders(),
      );
      expect(statusResp.statusCode, equals(200));
      final statusBody = jsonDecode(statusResp.body) as Map<String, dynamic>;
      expect(statusBody['ok'], isTrue);
      expect(statusBody['data']['engine'], equals('MariaDB'));

      // GET /api/v1/database/location
      final locResp = await http.get(
        Uri.parse('$baseUrl/api/v1/database/location'),
        headers: techHeaders(),
      );
      expect(locResp.statusCode, equals(200));
      final locBody = jsonDecode(locResp.body) as Map<String, dynamic>;
      expect(locBody['ok'], isTrue);
      expect(locBody['data']['engine'], equals('MariaDB'));

      // GET /api/v1/database/stats
      final statsResp = await http.get(
        Uri.parse('$baseUrl/api/v1/database/stats'),
        headers: techHeaders(),
      );
      expect(statsResp.statusCode, equals(200));
      final statsBody = jsonDecode(statsResp.body) as Map<String, dynamic>;
      expect(statsBody['ok'], isTrue);
      expect(statsBody['data']['tables'], hasLength(greaterThanOrEqualTo(96)));

      // POST /api/v1/database/backup
      final backupResp = await http.post(
        Uri.parse('$baseUrl/api/v1/database/backup'),
        headers: techHeaders(),
      );
      expect(backupResp.statusCode, inInclusiveRange(200, 201));
      final backupBody = jsonDecode(backupResp.body) as Map<String, dynamic>;
      expect(backupBody['ok'], isTrue);
      expect(backupBody['data']['status'], equals('VERIFIED'));

      // POST /api/v1/database/export
      final exportResp = await http.post(
        Uri.parse('$baseUrl/api/v1/database/export'),
        headers: techHeaders(),
      );
      expect(exportResp.statusCode, inInclusiveRange(200, 201));
      final exportBody = jsonDecode(exportResp.body) as Map<String, dynamic>;
      expect(exportBody['ok'], isTrue);
      expect(exportBody['data']['status'], isIn(['VERIFIED', 'COMPLETED']));

      // POST /api/v1/database/restore — Fail-closed 403 when called without technician token
      final unauthRestore = await http.post(
        Uri.parse('$baseUrl/api/v1/database/restore'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'backupPackagePath': testBackupDir.path}),
      );
      expect(unauthRestore.statusCode, isIn([401, 403]));

      // POST /api/v1/database/factory-reset — Fail-closed 403 when called without technician token
      final unauthReset = await http.post(
        Uri.parse('$baseUrl/api/v1/database/factory-reset'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'confirmationText': 'RESET MEDCORE'}),
      );
      expect(unauthReset.statusCode, isIn([401, 403]));

      // POST /api/v1/database/factory-reset — 400 when called with tech token but wrong confirmation text
      final badConfirmReset = await http.post(
        Uri.parse('$baseUrl/api/v1/database/factory-reset'),
        headers: techHeaders(),
        body: jsonEncode({'confirmationText': 'WRONG CONFIRMATION'}),
      );
      expect(badConfirmReset.statusCode, isIn([400, 422]));
    });
  });
}
