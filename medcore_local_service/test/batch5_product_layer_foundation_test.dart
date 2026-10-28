import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
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
  late Directory backupDir;

  // Test-only ephemeral technician secret generated dynamically at runtime (ZERO hardcoded secrets)
  late String runtimeTechSecret;
  late String runtimeBackupKey;

  final serviceRoot = Directory.current.path;
  final migrationsDir = p.join(serviceRoot, 'sql', 'migrations');

  late String adminToken;
  late String cashierToken;
  late int doctorId;
  late int patientId;
  late int visitId;

  setUpAll(() async {
    securityRoot = Directory.systemTemp.createTempSync('medcore-b5-sec-');
    backupDir = Directory.systemTemp.createTempSync('medcore-b5-bak-');
    runtimeTechSecret = 'TechTest_${PasswordHasher.generateSecureToken(16)}';
    runtimeBackupKey = 'BakKey_${PasswordHasher.generateSecureToken(24)}';

    final config = testDbConfig(databaseName: 'medcore_batch5_test', maxConnections: 10);
    db = DbClient(config);

    final adminConn = await db.openDedicatedConnection(useDatabase: false);
    try {
      await adminConn.execute('DROP DATABASE IF EXISTS `medcore_batch5_test`');
      await adminConn.execute(
        'CREATE DATABASE `medcore_batch5_test` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
      );
    } finally {
      await adminConn.close();
    }

    migrationRunner = MigrationRunner(db: db, migrationsDir: migrationsDir);
    final applied = await migrationRunner.runMigrations();
    expect(applied.length, greaterThanOrEqualTo(15));

    final govRepo = TenantGovernanceRepository(db);
    await govRepo.upsertTenant(hospitalCode: 'HOSP_PROD', name: 'MedCore Dental & Specialty Center');
    await govRepo.enrollOrUpdateDevice(
      hospitalCode: 'HOSP_PROD',
      deviceId: 'DEV-MAIN-HOST',
      deviceName: 'Main Server Workstation',
      platform: 'WINDOWS',
      connectionType: 'LOOPBACK',
      hwFingerprintSha256: PasswordHasher.sha256Hex('MAIN-HOST-HW-01'),
      devicePublicKeyEd25519: 'PUBKEY-MAIN-HOST-01',
      roleScope: 'SERVER_HOST',
      isTrustedSecureRuntime: true,
      status: 'ACTIVE',
    );

    final staffRepo = StaffIdentityRepository(db);
    await staffRepo.createStaff(
      hospitalCode: 'HOSP_PROD',
      staffCode: 'ADM-01',
      fullName: 'Dr. Nadia Admin',
      email: 'admin@hosp-prod.local',
      passwordHash: PasswordHasher.hashPassword('AdminPass!2026'),
      role: MedCoreRole.HospitalAdmin,
    );
    await staffRepo.createStaff(
      hospitalCode: 'HOSP_PROD',
      staffCode: 'CSH-01',
      fullName: 'Omar Cashier',
      email: 'cashier@hosp-prod.local',
      passwordHash: PasswordHasher.hashPassword('CashierPass!2026'),
      role: MedCoreRole.Cashier,
    );
    final doc = await staffRepo.createStaff(
      hospitalCode: 'HOSP_PROD',
      staffCode: 'DOC-01',
      fullName: 'Dr. Karim Specialist',
      email: 'doctor@hosp-prod.local',
      passwordHash: PasswordHasher.hashPassword('DoctorPass!2026'),
      role: MedCoreRole.Doctor,
      departmentId: 'DEPT-DENTAL',
      clinicId: 'CLINIC-DENTAL-A',
    );
    doctorId = doc.id;

    server = LocalMedCoreServer(
      db,
      securityRootDirectory: securityRoot.path,
      technicianSecretHashOverride: PasswordHasher.hashPassword(runtimeTechSecret),
      backupStorageDirectory: backupDir.path,
      backupEncryptionKeyOverride: runtimeBackupKey,
    );
    final port = await server!.start(address: '127.0.0.1', port: 0);
    baseUrl = 'http://127.0.0.1:$port';

    // Authenticate HospitalAdmin and Cashier
    final admLogin = await http.post(
      Uri.parse('$baseUrl/api/v1/auth/login'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'hospitalCode': 'HOSP_PROD',
        'identifier': 'admin@hosp-prod.local',
        'password': 'AdminPass!2026',
        'deviceId': 'DEV-MAIN-HOST',
      }),
    );
    expect(admLogin.statusCode, equals(200));
    adminToken = jsonDecode(admLogin.body)['data']['token'] as String;

    final cshLogin = await http.post(
      Uri.parse('$baseUrl/api/v1/auth/login'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'hospitalCode': 'HOSP_PROD',
        'identifier': 'cashier@hosp-prod.local',
        'password': 'CashierPass!2026',
        'deviceId': 'DEV-MAIN-HOST',
      }),
    );
    expect(cshLogin.statusCode, equals(200));
    cashierToken = jsonDecode(cshLogin.body)['data']['token'] as String;
  });

  tearDownAll(() async {
    await server?.stop();
    await db.close();
    if (securityRoot.existsSync()) securityRoot.deleteSync(recursive: true);
    if (backupDir.existsSync()) backupDir.deleteSync(recursive: true);
  });

  Map<String, String> staffHeaders(String token, {String deviceId = 'DEV-MAIN-HOST'}) => {
        'content-type': 'application/json',
        'authorization': 'Bearer $token',
        'x-tenant-id': 'HOSP_PROD',
        'x-medcore-device-id': deviceId,
      };

  Map<String, String> techHeaders(String techToken, {String deviceId = 'DEV-MAIN-HOST'}) => {
        'content-type': 'application/json',
        'x-medcore-tech-token': techToken,
        'x-tenant-id': 'HOSP_PROD',
        'x-medcore-device-id': deviceId,
      };

  test('1. Protected Technician Mode Isolation: Rejects HospitalAdmin Bearer token and enforces Technician Session', () async {
    // HospitalAdmin trying to read or mutate Technician Mode without X-MedCore-Tech-Token MUST FAIL CLOSED (403)
    final adminAttempt = await http.get(
      Uri.parse('$baseUrl/api/v1/technician/config'),
      headers: staffHeaders(adminToken),
    );
    expect(adminAttempt.statusCode, equals(403));
    expect(jsonDecode(adminAttempt.body)['error']['code'], equals('TECHNICIAN_SESSION_REQUIRED'));

    // Passing HospitalAdmin Bearer token inside X-MedCore-Tech-Token MUST ALSO FAIL CLOSED (403)
    final forgedAttempt = await http.get(
      Uri.parse('$baseUrl/api/v1/technician/config'),
      headers: techHeaders(adminToken),
    );
    expect(forgedAttempt.statusCode, equals(403));

    // Wrong technician secret -> 403 INVALID_TECHNICIAN_CREDENTIALS
    final badSecret = await http.post(
      Uri.parse('$baseUrl/api/v1/technician/session/open'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'hospitalCode': 'HOSP_PROD',
        'deviceId': 'DEV-MAIN-HOST',
        'technicianSecret': 'WRONG_SECRET',
      }),
    );
    expect(badSecret.statusCode, equals(403));
    expect(jsonDecode(badSecret.body)['error']['code'], equals('INVALID_TECHNICIAN_CREDENTIALS'));

    // Valid technician session open -> 201 + mct_... token persisted in mc_technician_sessions
    final openResp = await http.post(
      Uri.parse('$baseUrl/api/v1/technician/session/open'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'hospitalCode': 'HOSP_PROD',
        'deviceId': 'DEV-MAIN-HOST',
        'technicianSecret': runtimeTechSecret,
      }),
    );
    expect(openResp.statusCode, equals(201));
    final techToken = jsonDecode(openResp.body)['data']['technicianToken'] as String;
    expect(techToken.startsWith('mct_'), isTrue);

    // Configure Facility, Edition, Modules (disable Laboratory & ICU), Dental Patient Fields, and Branding
    final putCfg = await http.put(
      Uri.parse('$baseUrl/api/v1/technician/config'),
      headers: techHeaders(techToken),
      body: jsonEncode({
        'facilityName': 'Platinum Smile Dental Center',
        'facilityType': 'DENTAL_CLINIC',
        'branchCode': 'CAIRO-BR1',
        'installationIdentity': 'INST-HOSP_PROD-CAIRO1',
        'edition': 'GOLD',
        'subscriptionStartsUtc': '2026-01-01T00:00:00Z',
        'subscriptionExpiresUtc': '2027-01-01T00:00:00Z',
        'applyFacilityTypePatientPreset': true,
        'enabledModules': {
          'Laboratory': false,
          'ICU': false,
          'Dialysis': false,
          'Patients': true,
          'Reception': true,
          'Shifts': true,
          'Finance': true,
        },
        'patientFields': {
          'nationalId': 'REQUIRED',
          'inpatientAdmissionNotes': 'HIDDEN',
          'icuTriageNotes': 'HIDDEN',
          'nursingIntakeAssessment': 'HIDDEN',
        },
        'branding': {
          'appDisplayName': 'MedCore Dental Gold',
          'facilityDisplayName': 'Platinum Smile Dental Center',
          'editionLabel': 'Gold Edition',
          'primaryColorHex': '#1D4ED8',
          'themeMode': 'DARK',
          'fontScale': 1.1,
          'uiDensity': 'COMPACT',
        },
      }),
    );
    expect(putCfg.statusCode, equals(200), reason: putCfg.body);

    // Direct SQL Read-Back from mc_facility_config and mc_tenants
    final sqlCfg = await db.execute(
      "SELECT facility_name, facility_type, edition, config_version FROM mc_facility_config WHERE hospital_code = 'HOSP_PROD'",
    );
    expect(sqlCfg.rows.length, equals(1));
    expect(sqlCfg.rows.first.colByName('facility_name'), equals('Platinum Smile Dental Center'));
    expect(sqlCfg.rows.first.colByName('facility_type'), equals('DENTAL_CLINIC'));
    expect(sqlCfg.rows.first.colByName('edition'), equals('GOLD'));
    expect(sqlCfg.rows.first.colByName('config_version'), equals('1'));

    final sqlTenant = await db.execute(
      "SELECT name, edition FROM mc_tenants WHERE hospital_code = 'HOSP_PROD'",
    );
    expect(sqlTenant.rows.first.colByName('name'), equals('Platinum Smile Dental Center'));
    expect(sqlTenant.rows.first.colByName('edition'), equals('GOLD'));

    // Close technician session and confirm subsequent reuse is rejected (403)
    await http.post(
      Uri.parse('$baseUrl/api/v1/technician/session/close'),
      headers: techHeaders(techToken),
    );
    final afterClose = await http.get(
      Uri.parse('$baseUrl/api/v1/technician/config'),
      headers: techHeaders(techToken),
    );
    expect(afterClose.statusCode, equals(403));
  });

  test('2. Module Entitlement Enforcement & Centralized Branding Read-Back', () async {
    // Public bootstrap reflects centralized branding
    final bootResp = await http.get(
      Uri.parse('$baseUrl/api/v1/product/bootstrap?hospitalCode=HOSP_PROD'),
    );
    expect(bootResp.statusCode, equals(200));
    final boot = jsonDecode(bootResp.body)['data'];
    expect(boot['branding']['appDisplayName'], equals('MedCore Dental Gold'));
    expect(boot['branding']['primaryColorHex'], equals('#1D4ED8'));
    expect(boot['branding']['themeMode'], equals('DARK'));
    expect(boot['branding']['uiDensity'], equals('COMPACT'));

    // Disabled module `Laboratory` MUST reject API calls with 403 MODULE_NOT_ENTITLED even for HospitalAdmin!
    final labResp = await http.get(
      Uri.parse('$baseUrl/api/v1/orders?orderType=LAB'),
      headers: staffHeaders(adminToken),
    );
    expect(labResp.statusCode, equals(403));
    expect(jsonDecode(labResp.body)['error']['code'], equals('MODULE_NOT_ENTITLED'));

    // Verify mc_security_logs recorded the blocked module entitlement violation
    final secLog = await db.execute(
      "SELECT event_type FROM mc_security_logs WHERE hospital_code = 'HOSP_PROD' AND event_type = 'rbac.forbidden.module_not_entitled'",
    );
    expect(secLog.rows.isNotEmpty, isTrue);
  });

  test('3. Facility-Specific Patient Fields: Enforces REQUIRED fields and strips HIDDEN inpatient/ICU/nursing fields', () async {
    // Missing required `nationalId` -> 422 VALIDATION_ERROR
    final missingNat = await http.post(
      Uri.parse('$baseUrl/api/v1/patients'),
      headers: staffHeaders(adminToken),
      body: jsonEncode({
        'mrn': 'DENT-001',
        'fullName': 'Salma Hassan',
        'phone': '01012345678',
      }),
    );
    expect(missingNat.statusCode, equals(422));
    expect(jsonDecode(missingNat.body)['error']['message'], contains('MISSING_REQUIRED_PATIENT_FIELD'));

    // Providing required `nationalId` + optional `allergies` + rogue hidden `icuTriageNotes` -> 201
    final validPat = await http.post(
      Uri.parse('$baseUrl/api/v1/patients'),
      headers: staffHeaders(adminToken),
      body: jsonEncode({
        'mrn': 'DENT-001',
        'fullName': 'Salma Hassan',
        'phone': '01012345678',
        'gender': 'female',
        'nationalId': '29505051234567',
        'insuranceCompanyId': 'AXA-EG',
        'insurancePolicyNo': 'POL-9988',
        'allergies': ['Penicillin', 'Latex'],
        'icuTriageNotes': 'SHOULD_BE_STRIPPED_WHEN_HIDDEN',
      }),
    );
    expect(validPat.statusCode, equals(201), reason: validPat.body);
    final patData = jsonDecode(validPat.body)['data'];
    patientId = patData['id'] as int;
    expect(patData['nationalId'], equals('29505051234567'));
    expect(patData['allergies'], containsAll(['Penicillin', 'Latex']));
    expect(patData.containsKey('clinicalHistoryMeta'), isFalse);

    // Physical SQL Read-Back from mc_patients & mc_patient_profiles
    final dbPat = await db.execute(
      'SELECT national_id, insurance_company_id FROM mc_patients WHERE id = :id',
      {'id': patientId},
    );
    expect(dbPat.rows.first.colByName('national_id'), equals('29505051234567'));
    expect(dbPat.rows.first.colByName('insurance_company_id'), equals('AXA-EG'));
  });

  test('4. Network / Device Foundation: Discovery != Authorization, Pairing Code Approval & Session Revocation', () async {
    // 1. Request Wi-Fi pairing from a new workstation -> status = PENDING
    final pairReq = await http.post(
      Uri.parse('$baseUrl/api/v1/network/pairing/request'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'hospitalCode': 'HOSP_PROD',
        'deviceId': 'DEV-WIFI-CHAIR-02',
        'deviceName': 'Dental Chair 2 Tablet',
        'connectionType': 'WIFI',
        'platform': 'WINDOWS',
        'roleScope': 'WORKSTATION',
        'medcoreVersion': '1.0.0-rc.1',
        'hwFingerprintSha256': PasswordHasher.sha256Hex('CHAIR-02-HW'),
        'devicePublicKeyEd25519': 'PUBKEY-CHAIR-02',
        'ipAddress': '192.168.10.42',
      }),
    );
    expect(pairReq.statusCode, equals(201));
    final pairData = jsonDecode(pairReq.body)['data'];
    expect(pairData['status'], equals('PENDING'));
    expect(pairData['authorizationGranted'], isFalse);
    final pairingCode = pairData['pairingVerificationCode'] as String;
    expect(pairingCode.length, equals(6));

    // 2. Discovery != Authorization: Login from PENDING device MUST FAIL CLOSED (403 DEVICE_NOT_VERIFIED)
    final prematureLogin = await http.post(
      Uri.parse('$baseUrl/api/v1/auth/login'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'hospitalCode': 'HOSP_PROD',
        'identifier': 'cashier@hosp-prod.local',
        'password': 'CashierPass!2026',
        'deviceId': 'DEV-WIFI-CHAIR-02',
      }),
    );
    expect(prematureLogin.statusCode, equals(403));
    expect(jsonDecode(prematureLogin.body)['error']['code'], equals('DEVICE_NOT_VERIFIED'));

    // 3. Wrong pairing code during approval -> 422
    final badApprove = await http.post(
      Uri.parse('$baseUrl/api/v1/network/devices/DEV-WIFI-CHAIR-02/approve'),
      headers: staffHeaders(adminToken),
      body: jsonEncode({'pairingVerificationCode': '000000'}),
    );
    expect(badApprove.statusCode, equals(422));

    // 4. Correct pairing code -> ACTIVE
    final goodApprove = await http.post(
      Uri.parse('$baseUrl/api/v1/network/devices/DEV-WIFI-CHAIR-02/approve'),
      headers: staffHeaders(adminToken),
      body: jsonEncode({'pairingVerificationCode': pairingCode}),
    );
    expect(goodApprove.statusCode, equals(200));
    expect(jsonDecode(goodApprove.body)['data']['status'], equals('ACTIVE'));

    // 5. Login from approved Wi-Fi device now succeeds
    final wifiLogin = await http.post(
      Uri.parse('$baseUrl/api/v1/auth/login'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'hospitalCode': 'HOSP_PROD',
        'identifier': 'cashier@hosp-prod.local',
        'password': 'CashierPass!2026',
        'deviceId': 'DEV-WIFI-CHAIR-02',
      }),
    );
    expect(wifiLogin.statusCode, equals(200));
    final wifiToken = jsonDecode(wifiLogin.body)['data']['token'] as String;

    // 6. Revoke device -> terminates active session immediately
    final revokeResp = await http.post(
      Uri.parse('$baseUrl/api/v1/network/devices/DEV-WIFI-CHAIR-02/revoke'),
      headers: staffHeaders(adminToken),
      body: jsonEncode({'reason': 'Tablet removed from clinic floor'}),
    );
    expect(revokeResp.statusCode, equals(200));

    final meAfterRevoke = await http.get(
      Uri.parse('$baseUrl/api/v1/auth/me'),
      headers: staffHeaders(wifiToken, deviceId: 'DEV-WIFI-CHAIR-02'),
    );
    expect(meAfterRevoke.statusCode, anyOf(equals(401), equals(403)));
  });

  test('5. Patient Financial Ledger & Financial Documents / Reports Authoritative Read-Back', () async {
    // Open Cashier Shift
    final shiftResp = await http.post(
      Uri.parse('$baseUrl/api/v1/shifts/open'),
      headers: staffHeaders(cashierToken),
      body: jsonEncode({'shiftCode': 'SHF-PROD-01', 'openingBalance': '500.0000'}),
    );
    expect(shiftResp.statusCode, equals(201));
    final shiftId = jsonDecode(shiftResp.body)['data']['id'] as int;

    // Create Atomic Visit: Gross = 800 Labor + 200 Consumables = 1000.0000
    // Discount = 100.0000 -> Net = 900.0000
    // Insurance = 300.0000 -> Patient Responsibility = 600.0000
    // Paid = 400.0000 -> Patient Outstanding Balance = 200.0000
    final visitResp = await http.post(
      Uri.parse('$baseUrl/api/v1/visits'),
      headers: staffHeaders(cashierToken),
      body: jsonEncode({
        'visitNumber': 'VIS-DENT-101',
        'idempotencyKey': 'IDEMP-DENT-101',
        'patientId': patientId,
        'doctorId': doctorId,
        'shiftId': shiftId,
        'serviceCode': 'DENT-ROOT-01',
        'serviceName': 'Root Canal Treatment',
        'serviceLaborGross': '800.0000',
        'consumableGross': '200.0000',
        'consumableFifoCost': '120.0000',
        'discountAmount': '100.0000',
        'insuranceCoveredAmount': '300.0000',
        'paidAmount': '400.0000',
        'doctorCommissionRatePercent': '25.0000',
      }),
    );
    expect(visitResp.statusCode, equals(201), reason: visitResp.body);
    visitId = jsonDecode(visitResp.body)['data']['visitId'] as int;

    // 1. Patient Financial Ledger Account
    final ledgerResp = await http.get(
      Uri.parse('$baseUrl/api/v1/finance/patients/$patientId/ledger'),
      headers: staffHeaders(adminToken),
    );
    expect(ledgerResp.statusCode, equals(200), reason: ledgerResp.body);
    final ledger = jsonDecode(ledgerResp.body)['data'];
    expect(ledger['accountSummary']['authoritativePatientBalance'], equals('200.0000'));
    expect(ledger['accountSummary']['outstandingPatientDebt'], equals('200.0000'));
    expect(ledger['accountSummary']['totalGrossCharges'], equals('1000.0000'));
    expect(ledger['accountSummary']['totalDiscounts'], equals('100.0000'));
    expect(ledger['accountSummary']['totalInsuranceResponsibility'], equals('300.0000'));
    expect(ledger['accountSummary']['totalPaymentsCollected'], equals('400.0000'));
    expect((ledger['visits'] as List).first['responsibleEntity'], equals('SHARED_PATIENT_AND_INSURANCE'));
    expect((ledger['documentedBackendGaps'] as List).isNotEmpty, isTrue);

    // 2. Invoice, Receipt, Patient Statement
    final invResp = await http.get(
      Uri.parse('$baseUrl/api/v1/finance/documents/invoice/$visitId'),
      headers: staffHeaders(adminToken),
    );
    expect(invResp.statusCode, equals(200));
    expect(jsonDecode(invResp.body)['data']['totals']['balanceDue'], equals('200.0000'));

    final rcptResp = await http.get(
      Uri.parse('$baseUrl/api/v1/finance/documents/receipt/$visitId'),
      headers: staffHeaders(adminToken),
    );
    expect(rcptResp.statusCode, equals(200));
    expect(jsonDecode(rcptResp.body)['data']['paymentSummary']['amountReceived'], equals('400.0000'));

    final stmtResp = await http.get(
      Uri.parse('$baseUrl/api/v1/finance/documents/patient-statement/$patientId'),
      headers: staffHeaders(adminToken),
    );
    expect(stmtResp.statusCode, equals(200));
    expect((jsonDecode(stmtResp.body)['data']['statementLines'] as List).length, equals(1));

    // 3. Outstanding Balance Report, Financial History & Allocation Report
    final outResp = await http.get(
      Uri.parse('$baseUrl/api/v1/finance/reports/outstanding-balances'),
      headers: staffHeaders(adminToken),
    );
    expect(outResp.statusCode, equals(200));
    final outData = jsonDecode(outResp.body)['data'];
    expect(outData['summary']['totalPatientOutstandingBalance'], equals('200.0000'));
    expect(outData['summary']['ledgerArPatientBucket'], equals('200.0000'));
    expect(outData['summary']['ledgerArInsuranceBucket'], equals('300.0000'));

    final histResp = await http.get(
      Uri.parse('$baseUrl/api/v1/finance/reports/financial-history'),
      headers: staffHeaders(adminToken),
    );
    expect(histResp.statusCode, equals(200));
    expect(jsonDecode(histResp.body)['data']['trialBalance']['isBalanced'], isTrue);

    final allocResp = await http.get(
      Uri.parse('$baseUrl/api/v1/finance/reports/allocations'),
      headers: staffHeaders(adminToken),
    );
    expect(allocResp.statusCode, equals(200));
    final docAlloc = (jsonDecode(allocResp.body)['data']['doctorCommissionLedger'] as List).first;
    // FIN-004 Service Net = 800 - 100 discount = 700.0000; 25% commission = 175.0000
    expect(docAlloc['accruedCommission'], equals('175.0000'));
  });

  test('6. Maintenance Center & Vendor-Neutral Backup Engine Foundation', () async {
    // 1. Maintenance Overview & Report Generation
    final ovResp = await http.get(
      Uri.parse('$baseUrl/api/v1/maintenance/overview'),
      headers: staffHeaders(adminToken),
    );
    expect(ovResp.statusCode, equals(200), reason: ovResp.body);
    final ov = jsonDecode(ovResp.body)['data'];
    expect(ov['overallStatus'], equals('HEALTHY'));
    expect(ov['migrationStatus']['appliedCount'], greaterThanOrEqualTo(15));
    expect(ov['diagnostics']['financialTrialBalance']['balanced'], isTrue);

    final repResp = await http.post(
      Uri.parse('$baseUrl/api/v1/maintenance/reports'),
      headers: staffHeaders(adminToken),
    );
    expect(repResp.statusCode, equals(201));
    final repData = jsonDecode(repResp.body)['data'];
    // Ensure patient phone PII does not leak into maintenance report
    expect(repResp.body.contains('01012345678'), isFalse);

    final sqlRep = await db.execute(
      'SELECT overall_status FROM mc_maintenance_reports WHERE report_uuid = :u',
      {'u': repData['reportUuid']},
    );
    expect(sqlRep.rows.length, equals(1));

    // 2. Local Verified Backup Execution (Snapshot -> GZip -> Encrypt -> SHA-256 -> Disk Read-Back)
    final bakRunResp = await http.post(
      Uri.parse('$baseUrl/api/v1/backups/run'),
      headers: staffHeaders(adminToken),
      body: jsonEncode({'providerId': 'LOCAL_STORAGE'}),
    );
    expect(bakRunResp.statusCode, equals(201), reason: bakRunResp.body);
    final bakData = jsonDecode(bakRunResp.body)['data'];
    expect(bakData['status'], equals('VERIFIED'));
    expect(bakData['independentlyVerified'], isTrue);
    expect(bakData['encrypted'], isTrue);

    final archiveFile = File(bakData['archivePath'] as String);
    expect(archiveFile.existsSync(), isTrue);
    final diskSha = sha256.convert(archiveFile.readAsBytesSync()).toString();
    expect(diskSha, equals(bakData['archiveSha256']));

    // Independent SQL read-back from mc_backup_runs
    final dbBak = await db.execute(
      'SELECT status, archive_sha256 FROM mc_backup_runs WHERE backup_uuid = :u',
      {'u': bakData['backupUuid']},
    );
    expect(dbBak.rows.first.colByName('status'), equals('VERIFIED'));
    expect(dbBak.rows.first.colByName('archive_sha256'), equals(diskSha));

    // 3. S3-Compatible Provider Contract Validation (Cloudflare R2 / Backblaze B2)
    final s3Provider = S3CompatibleProvider();
    final r2Val = s3Provider.validateConfiguration({
      's3Compatible': {
        'vendorPreset': 'CLOUDFLARE_R2',
        'endpointUrl': 'https://example-acct.r2.cloudflarestorage.com',
        'bucket': 'medcore-hosp-backups',
      },
    });
    expect(r2Val.valid, isTrue);
    expect(r2Val.runtimeReadiness, equals('CONTRACT_VALID_REMOTE_DEFERRED'));
  });
}
