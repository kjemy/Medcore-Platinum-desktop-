import 'dart:convert';
import 'dart:io';
import 'package:decimal/decimal.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import '../db/db_client.dart';
import '../db/transaction_manager.dart';
import '../repositories/clinical_financial_repositories.dart';
import '../repositories/domain_repositories.dart';
import '../repositories/scope_context.dart';
import '../repositories/staff_auth_repository.dart';
import '../repositories/tenant_governance_repository.dart';
import '../security/auth_service.dart';
import '../security/maintenance_token_service.dart';
import '../security/password_hasher.dart';
import '../security/permissions_catalog.dart';
import '../security/rbac_evaluator.dart';
import '../security/trusted_time_evidence.dart';
import '../explorer/data_explorer_service.dart';
import '../product/facility_config_service.dart';
import '../product/technician_service.dart';
import '../product/maintenance_center_service.dart';
import '../product/network_device_service.dart';
import '../product/patient_financial_ledger_service.dart';
import '../product/backup_engine_foundation.dart';
import '../product/specialty_clinical_service.dart';
import '../product/clinical_event_stream_service.dart';
import '../product/native_printing_service.dart';
import '../product/external_payable_service.dart';
import '../product/lan_pki_service.dart';
import '../product/database_lifecycle_service.dart';
import '../repositories/clinical_template_repository.dart';
import '../repositories/scheduling_resource_repository.dart';

class LocalMedCoreServer {
  final DbClient db;
  final DateTime Function()? clock;
  final Duration clockDriftTolerance;
  final String? securityRootDirectory;
  final String? technicianSecretHashOverride;
  final String? backupStorageDirectory;
  final String? backupEncryptionKeyOverride;
  late final TransactionManager txManager;
  late final AuthService authService;
  late final VisitFinancialService visitFinancialService;
  late final DataExplorerService explorerService;
  late final AppointmentRepository appointmentRepo;
  late final ShiftReconciliationService shiftReconciliationService;
  late final ClinicalEncounterRepository encounterRepo;
  late final PrescriptionRepository prescriptionRepo;
  late final DiagnosticOrderRepository diagnosticRepo;
  late final InventoryPharmacyRepository inventoryPharmacyRepo;
  late final InpatientAdmissionRepository inpatientRepo;
  late final FinancialSettlementRepository settlementRepo;
  late final DualControlRepository dualControlRepo;
  late final FacilityConfigService facilityConfigService;
  late final TechnicianService technicianService;
  late final MaintenanceCenterService maintenanceCenterService;
  late final NetworkDeviceService networkDeviceService;
  late final PatientFinancialLedgerService patientFinancialLedgerService;
  late final BackupEngineService backupEngineService;
  late final SpecialtyClinicalService specialtyClinicalService;
  late final ClinicalEventStreamService eventStreamService;
  late final ExternalPayableService externalPayableService;
  late final LanPkiService lanPkiService;
  late final StaffEvaluationRepository staffEvaluationRepo;
  late final ClinicalTemplateRepository clinicalTemplateRepo;
  late final SchedulingResourceRepository schedulingResourceRepo;
  final String? runtimeDirectoryOverride;
  final String? migrationsDirectoryOverride;
  final bool autoBootstrapCommissioningSecret;
  late final DatabaseLifecycleService databaseLifecycleService;
  HttpServer? _httpServer;

  LocalMedCoreServer(
    this.db, {
    this.clock,
    this.clockDriftTolerance = const Duration(seconds: 5),
    this.securityRootDirectory,
    this.technicianSecretHashOverride,
    this.autoBootstrapCommissioningSecret = false,
    this.backupStorageDirectory,
    this.backupEncryptionKeyOverride,
    this.runtimeDirectoryOverride,
    this.migrationsDirectoryOverride,
    MaintenanceTokenService? maintenanceTokenService,
    TrustedTimeVerifier? trustedTimeVerifier,
  }) {
    txManager = TransactionManager(db);
    authService = AuthService(
      txManager,
      clock: clock,
      clockDriftTolerance: clockDriftTolerance,
      securityRootDirectory: securityRootDirectory,
    );
    visitFinancialService = VisitFinancialService(txManager);
    explorerService = DataExplorerService(db);
    appointmentRepo = AppointmentRepository(db);
    shiftReconciliationService = ShiftReconciliationService(txManager);
    encounterRepo = ClinicalEncounterRepository(txManager);
    prescriptionRepo = PrescriptionRepository(txManager);
    diagnosticRepo = DiagnosticOrderRepository(txManager);
    inventoryPharmacyRepo = InventoryPharmacyRepository(txManager);
    inpatientRepo = InpatientAdmissionRepository(txManager);
    settlementRepo = FinancialSettlementRepository(txManager);
    staffEvaluationRepo = StaffEvaluationRepository(txManager);
    clinicalTemplateRepo = ClinicalTemplateRepository(db);
    schedulingResourceRepo = SchedulingResourceRepository(db);
    dualControlRepo = DualControlRepository(txManager);
    facilityConfigService = FacilityConfigService(db);
    technicianService = TechnicianService(
      db,
      facilityConfigService: facilityConfigService,
      clock: clock,
      clockDriftTolerance: clockDriftTolerance,
      securityRootDirectory: securityRootDirectory,
      installationSecretHashOverride: technicianSecretHashOverride,
      maintenanceTokenService: maintenanceTokenService,
      trustedTimeVerifier: trustedTimeVerifier,
    );
    if (autoBootstrapCommissioningSecret && technicianSecretHashOverride == null) {
      technicianService.ensureCommissioningSecretProvisioned();
    }
    maintenanceCenterService = MaintenanceCenterService(
      db,
      facilityConfigService: facilityConfigService,
      securityRootDirectory: securityRootDirectory,
      boundPortProvider: () => boundPort,
    );
    networkDeviceService = NetworkDeviceService(
      db,
      facilityConfigService: facilityConfigService,
    );
    patientFinancialLedgerService = PatientFinancialLedgerService(
      db,
      facilityConfigService: facilityConfigService,
    );
    backupEngineService = BackupEngineService(
      db,
      facilityConfigService: facilityConfigService,
      storageRootDirectory: backupStorageDirectory,
      encryptionKeyOverride: backupEncryptionKeyOverride,
    );
    specialtyClinicalService = SpecialtyClinicalService(
      db,
      facilityConfigService: facilityConfigService,
    );
    eventStreamService = ClinicalEventStreamService();
    externalPayableService = ExternalPayableService(txManager);
    lanPkiService = LanPkiService(txManager);

    final resolvedMigrationsDir = migrationsDirectoryOverride ??
        (Directory('sql/migrations').existsSync()
            ? 'sql/migrations'
            : (Directory('medcore_local_service/sql/migrations').existsSync()
                ? 'medcore_local_service/sql/migrations'
                : 'sql/migrations'));

    databaseLifecycleService = DatabaseLifecycleService(
      db,
      facilityConfigService: facilityConfigService,
      backupEngineService: backupEngineService,
      explorerService: explorerService,
      migrationsDirectory: resolvedMigrationsDir,
      storageRootDirectory: backupStorageDirectory,
      runtimeDirectoryOverride: runtimeDirectoryOverride,
      encryptionKeyOverride: backupEncryptionKeyOverride,
      securityRootDirectory: securityRootDirectory,
      technicianService: technicianService,
    );
  }

  int? get boundPort => _httpServer?.port;

  Handler get handler {
    final router = Router();

    // 1. Health & Readiness Probe (Public)
    router.get('/api/v1/health', (Request req) async {
      final tablesRes = await db.execute(
        'SELECT COUNT(*) AS cnt FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = :db',
        {'db': db.config.databaseName},
      );
      final migRes = await db.execute('SELECT COUNT(*) AS cnt FROM mc_schema_migrations');
      final tableCount = int.parse(tablesRes.rows.first.colByName('cnt') ?? '0');
      final migCount = int.parse(migRes.rows.first.colByName('cnt') ?? '0');

      return _jsonOk({
        'service': 'MedCore Local Service',
        'status': 'HEALTHY',
        'database': db.config.databaseName,
        'tableCount': tableCount,
        'appliedMigrations': migCount,
      });
    });

    // 2. Native Offline Login (Public Entrypoint -> Issues Tenant & Device Bound Session)
    router.post('/api/v1/auth/login', (Request req) async {
      final body = await _readJsonBody(req);
      final hospitalCode = (body['hospitalCode'] ?? req.headers['x-tenant-id'] ?? '').toString().trim();
      final identifier = (body['identifier'] ?? body['email'] ?? '').toString().trim();
      final password = (body['password'] ?? '').toString();
      final deviceId = (body['deviceId'] ?? req.headers['x-medcore-device-id'] ?? '').toString().trim();

      if (hospitalCode.isEmpty || identifier.isEmpty || password.isEmpty || deviceId.isEmpty) {
        return _jsonError(400, 'MISSING_AUTH_FIELDS', 'hospitalCode, identifier, password, and deviceId are required.');
      }

      final result = await authService.login(
        hospitalCode: hospitalCode,
        identifier: identifier,
        password: password,
        deviceId: deviceId,
        ipAddress: req.headers['x-forwarded-for'] ?? '127.0.0.1',
      );
      return _jsonOk(result);
    });

    // 3. Logout
    router.post('/api/v1/auth/logout', (Request req) async {
      final token = _extractBearerToken(req);
      if (token != null) {
        await authService.logout(token);
      }
      return _jsonOk({'loggedOut': true});
    });

    // 4. Current Authenticated Employee Profile (/me)
    router.get('/api/v1/auth/me', (Request req) async {
      final authCtx = await _authenticate(req);
      return _jsonOk({
        'sessionUuid': authCtx.session.sessionUuid,
        'device': {
          'deviceId': authCtx.device.deviceId,
          'isTrustedSecureRuntime': authCtx.device.isTrustedSecureRuntime,
        },
        'user': authCtx.staff.toPublicJson(authCtx.effectivePermissions),
      });
    });

    // 5. RBAC Catalog & Live Permission Check
    router.get('/api/v1/rbac/catalog', (Request req) async {
      await _authenticate(req);
      return _jsonOk({
        'rolesCount': MedCoreRole.values.length,
        'roles': MedCoreRole.values.map((r) => r.name).toList(),
        'basePermissionsCount': PermissionsCatalog.basePermissions.length,
        'allScopePermissionsCount': PermissionsCatalog.allScopePermissions.length,
        'securePagePermissionsCount': PermissionsCatalog.securePagePermissions.length,
        'totalUiPermissionsCount': PermissionsCatalog.all261Permissions.length,
        'backendDotPermissionsCount': PermissionsCatalog.backendToUiPermissions.length,
      });
    });

    // 6. Staff Management (Requires hr_Employees / settings_Permissions)
    router.get('/api/v1/staff', (Request req) async {
      final scope = await _authorize(req, requiredPermission: 'hr_Employees');
      final repo = StaffIdentityRepository(db);
      final staffList = await repo.listByTenant(scope.hospitalCode);
      return _jsonOk({
        'count': staffList.length,
        'items': staffList
            .map((s) => s.toPublicJson(RbacEvaluator.resolveEffectivePermissions(s)))
            .toList(),
      });
    });

    router.post('/api/v1/staff', (Request req) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'hr_Employees',
        requireCanEdit: true,
      );
      final body = await _readJsonBody(req);
      final role = MedCoreRole.fromString((body['role'] ?? 'Employee').toString());
      final passwordHash = PasswordHasher.hashPassword((body['password'] ?? 'ChangeMe123!').toString());
      final repo = StaffIdentityRepository(db);

      final created = await repo.createStaff(
        hospitalCode: scope.hospitalCode,
        staffCode: body['staffCode'].toString(),
        fullName: body['fullName'].toString(),
        email: body['email'].toString(),
        phone: body['phone']?.toString(),
        role: role,
        departmentId: body['departmentId']?.toString(),
        clinicId: body['clinicId']?.toString(),
        doctorDefinitionCode: body['doctorDefinitionCode']?.toString(),
        passwordHash: passwordHash,
        permissionsMode: (body['permissionsMode'] ?? 'default').toString(),
      );
      return _jsonOk(
        created.toPublicJson(RbacEvaluator.resolveEffectivePermissions(created)),
        statusCode: 201,
      );
    });

    router.put('/api/v1/staff/<id>/permissions', (Request req, String id) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'settings_Permissions',
        requireCanEdit: true,
      );
      final body = await _readJsonBody(req);
      final staffId = int.parse(id);
      final mode = (body['permissionsMode'] ?? 'default').toString();
      final customPerms = (body['customPermissions'] as List?)?.map((e) => e.toString()).toSet();
      final secureLocks = (body['securePageLocks'] as List?)?.map((e) => e.toString()).toSet();

      OperationalFlags? flags;
      if (body['operationalFlags'] is Map) {
        final m = body['operationalFlags'] as Map;
        flags = OperationalFlags(
          canEdit: m['canEdit'] == true,
          canDelete: m['canDelete'] == true,
          canCollectMoney: m['canCollectMoney'] == true,
          canMakeRefunds: m['canMakeRefunds'] == true,
          refundPolicy: RefundPolicy.fromString(m['refundPolicy']?.toString()),
        );
      }

      final repo = StaffIdentityRepository(db);
      final updated = await repo.updatePermissionsAndFlags(
        hospitalCode: scope.hospitalCode,
        staffId: staffId,
        permissionsMode: mode,
        customPermissions: customPerms,
        securePageLocks: secureLocks,
        operationalFlags: flags,
      );
      return _jsonOk(updated.toPublicJson(RbacEvaluator.resolveEffectivePermissions(updated)));
    });

    // 6b. Admin Employee Account Management (Batch 1)
    router.get('/api/v1/admin/employees', (Request req) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'settings_Users',
        requireCanEdit: false,
      );
      final repo = StaffIdentityRepository(db);
      final employees = await repo.listByTenant(scope.hospitalCode);
      return _jsonOk({
        'hospitalCode': scope.hospitalCode,
        'count': employees.length,
        'employees': employees
            .map((e) => e.toPublicJson(RbacEvaluator.resolveEffectivePermissions(e)))
            .toList(),
      });
    });

    router.post('/api/v1/admin/employees', (Request req) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'settings_Users',
        requireCanEdit: true,
      );
      final body = await _readJsonBody(req);
      final staffCode = (body['staffCode'] ?? '').toString().trim();
      final fullName = (body['fullName'] ?? '').toString().trim();
      final email = (body['email'] ?? '').toString().trim();
      final password = (body['password'] ?? '').toString();
      final roleStr = (body['role'] ?? 'Employee').toString().trim();

      if (staffCode.isEmpty || fullName.isEmpty || email.isEmpty || password.isEmpty) {
        return _jsonError(400, 'MISSING_REQUIRED_FIELDS', 'staffCode, fullName, email, and password are required.');
      }
      if (password.length < 8) {
        return _jsonError(400, 'WEAK_PASSWORD', 'Password must be at least 8 characters long.');
      }

      final repo = StaffIdentityRepository(db);
      final existing = await repo.findByEmailOrCode(scope.hospitalCode, staffCode);
      if (existing != null) {
        return _jsonError(409, 'DUPLICATE_STAFF_CODE', 'Employee with staff code $staffCode already exists.');
      }
      final existingEmail = await repo.findByEmailOrCode(scope.hospitalCode, email);
      if (existingEmail != null) {
        return _jsonError(409, 'DUPLICATE_EMAIL', 'Employee with email $email already exists.');
      }

      final role = MedCoreRole.fromString(roleStr);
      final passwordHash = PasswordHasher.hashPassword(password);
      final forcePasswordChange = body['forcePasswordChange'] == true;

      final created = await repo.createStaff(
        hospitalCode: scope.hospitalCode,
        staffCode: staffCode,
        fullName: fullName,
        email: email,
        phone: body['phone']?.toString(),
        nationalId: body['nationalId']?.toString(),
        passwordHash: passwordHash,
        role: role,
        departmentId: body['departmentId']?.toString(),
        clinicId: body['clinicId']?.toString(),
        doctorDefinitionCode: body['doctorDefinitionCode']?.toString(),
        specialty: body['specialty']?.toString(),
        permissionsMode: (body['permissionsMode'] ?? 'default').toString(),
        customPermissions: (body['customPermissions'] as List?)?.map((e) => e.toString()).toSet(),
        securePageLocks: (body['securePageLocks'] as List?)?.map((e) => e.toString()).toSet(),
        isActive: body['isActive'] != false,
        forcePasswordChange: forcePasswordChange,
      );

      await txManager.runInTransaction((tx) async {
        await tx.writeAuditLog(
          hospitalCode: scope.hospitalCode,
          actorStaffId: scope.actor.id,
          actorRole: scope.actor.role.name,
          deviceId: scope.deviceId,
          action: 'admin.employee.created',
          entityType: 'mc_staff',
          entityId: created.staffCode,
          afterState: {
            'staffId': created.id,
            'role': created.role.name,
            'forcePasswordChange': forcePasswordChange,
          },
        );
      });

      return _jsonOk(
        created.toPublicJson(RbacEvaluator.resolveEffectivePermissions(created)),
        statusCode: 201,
      );
    });

    router.put('/api/v1/admin/employees/<id>', (Request req, String id) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'settings_Users',
        requireCanEdit: true,
      );
      final staffId = int.tryParse(id);
      if (staffId == null) return _jsonError(400, 'INVALID_STAFF_ID', 'Invalid staff ID.');

      final body = await _readJsonBody(req);
      final repo = StaffIdentityRepository(db);
      final current = await repo.findById(scope.hospitalCode, staffId);
      if (current == null) {
        return _jsonError(404, 'STAFF_NOT_FOUND', 'Employee $staffId not found in facility ${scope.hospitalCode}.');
      }

      final fullName = (body['fullName'] ?? current.identity.fullName).toString().trim();
      final phone = body['phone']?.toString() ?? current.identity.phone;
      final nationalId = body['nationalId']?.toString() ?? current.identity.nationalId;
      final role = body['role'] != null ? MedCoreRole.fromString(body['role'].toString()) : current.identity.role;

      await repo.updateStaffProfile(
        hospitalCode: scope.hospitalCode,
        staffId: staffId,
        fullName: fullName,
        phone: phone,
        nationalId: nationalId,
        role: role,
        departmentId: body['departmentId']?.toString() ?? current.identity.departmentId,
        clinicId: body['clinicId']?.toString() ?? current.identity.clinicId,
        doctorDefinitionCode: body['doctorDefinitionCode']?.toString() ?? current.identity.doctorDefinitionCode,
        specialty: body['specialty']?.toString() ?? current.identity.specialty,
      );

      if (body['permissionsMode'] != null || body['customPermissions'] != null) {
        final mode = (body['permissionsMode'] ?? current.identity.permissionsMode).toString();
        final cPerms = (body['customPermissions'] as List?)?.map((e) => e.toString()).toSet() ?? current.identity.customPermissions;
        final sLocks = (body['securePageLocks'] as List?)?.map((e) => e.toString()).toSet() ?? current.identity.securePageLocks;
        await repo.updatePermissionsAndFlags(
          hospitalCode: scope.hospitalCode,
          staffId: staffId,
          permissionsMode: mode,
          customPermissions: cPerms,
          securePageLocks: sLocks,
        );
      }

      await txManager.runInTransaction((tx) async {
        await tx.writeAuditLog(
          hospitalCode: scope.hospitalCode,
          actorStaffId: scope.actor.id,
          actorRole: scope.actor.role.name,
          deviceId: scope.deviceId,
          action: 'admin.employee.updated',
          entityType: 'mc_staff',
          entityId: current.identity.staffCode,
          afterState: {'updatedStaffId': staffId, 'role': role.name},
        );
      });

      final reloaded = (await repo.findById(scope.hospitalCode, staffId))!.identity;
      return _jsonOk(reloaded.toPublicJson(RbacEvaluator.resolveEffectivePermissions(reloaded)));
    });

    router.post('/api/v1/admin/employees/<id>/reset-password', (Request req, String id) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'settings_Users',
        requireCanEdit: true,
      );
      final staffId = int.tryParse(id);
      if (staffId == null) return _jsonError(400, 'INVALID_STAFF_ID', 'Invalid staff ID.');

      final body = await _readJsonBody(req);
      final newPassword = (body['newPassword'] ?? '').toString();
      if (newPassword.length < 8) {
        return _jsonError(400, 'WEAK_PASSWORD', 'New password must be at least 8 characters long.');
      }

      final repo = StaffIdentityRepository(db);
      final current = await repo.findById(scope.hospitalCode, staffId);
      if (current == null) {
        return _jsonError(404, 'STAFF_NOT_FOUND', 'Employee $staffId not found in facility.');
      }

      final forceChange = body['forcePasswordChange'] != false;
      final newHash = PasswordHasher.hashPassword(newPassword);

      await repo.updatePassword(
        hospitalCode: scope.hospitalCode,
        staffId: staffId,
        newPasswordHash: newHash,
        forcePasswordChange: forceChange,
      );

      final sessionRepo = AuthSessionRepository(db);
      final revokedCount = await sessionRepo.revokeAllSessionsForStaff(
        scope.hospitalCode,
        staffId,
        'ADMIN_PASSWORD_RESET',
      );

      await txManager.runInTransaction((tx) async {
        await tx.writeAuditLog(
          hospitalCode: scope.hospitalCode,
          actorStaffId: scope.actor.id,
          actorRole: scope.actor.role.name,
          deviceId: scope.deviceId,
          action: 'admin.employee.password_reset',
          entityType: 'mc_staff',
          entityId: current.identity.staffCode,
          afterState: {
            'targetStaffId': staffId,
            'forcePasswordChange': forceChange,
            'revokedSessions': revokedCount,
          },
        );
      });

      return _jsonOk({
        'status': 'PASSWORD_RESET_SUCCESS',
        'staffId': staffId,
        'forcePasswordChange': forceChange,
        'revokedSessionsCount': revokedCount,
      });
    });

    router.post('/api/v1/admin/employees/<id>/status', (Request req, String id) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'settings_Users',
        requireCanEdit: true,
      );
      final staffId = int.tryParse(id);
      if (staffId == null) return _jsonError(400, 'INVALID_STAFF_ID', 'Invalid staff ID.');

      final body = await _readJsonBody(req);
      if (!body.containsKey('isActive')) {
        return _jsonError(400, 'MISSING_FIELD', 'isActive boolean field is required.');
      }
      final isActive = body['isActive'] == true;

      final repo = StaffIdentityRepository(db);
      final current = await repo.findById(scope.hospitalCode, staffId);
      if (current == null) {
        return _jsonError(404, 'STAFF_NOT_FOUND', 'Employee $staffId not found.');
      }

      await repo.updateStatus(
        hospitalCode: scope.hospitalCode,
        staffId: staffId,
        isActive: isActive,
      );

      int revokedCount = 0;
      if (!isActive) {
        final sessionRepo = AuthSessionRepository(db);
        revokedCount = await sessionRepo.revokeAllSessionsForStaff(
          scope.hospitalCode,
          staffId,
          'ACCOUNT_DEACTIVATED',
        );
      }

      await txManager.runInTransaction((tx) async {
        await tx.writeAuditLog(
          hospitalCode: scope.hospitalCode,
          actorStaffId: scope.actor.id,
          actorRole: scope.actor.role.name,
          deviceId: scope.deviceId,
          action: isActive ? 'admin.employee.enabled' : 'admin.employee.disabled',
          entityType: 'mc_staff',
          entityId: current.identity.staffCode,
          afterState: {'targetStaffId': staffId, 'isActive': isActive, 'revokedSessions': revokedCount},
        );
      });

      return _jsonOk({
        'staffId': staffId,
        'isActive': isActive,
        'revokedSessionsCount': revokedCount,
      });
    });

    router.post('/api/v1/admin/employees/<id>/revoke-sessions', (Request req, String id) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'settings_Users',
        requireCanEdit: true,
      );
      final staffId = int.tryParse(id);
      if (staffId == null) return _jsonError(400, 'INVALID_STAFF_ID', 'Invalid staff ID.');

      final repo = StaffIdentityRepository(db);
      final current = await repo.findById(scope.hospitalCode, staffId);
      if (current == null) return _jsonError(404, 'STAFF_NOT_FOUND', 'Employee not found.');

      final sessionRepo = AuthSessionRepository(db);
      final revokedCount = await sessionRepo.revokeAllSessionsForStaff(
        scope.hospitalCode,
        staffId,
        'ADMIN_SESSION_REVOCATION',
      );

      await txManager.runInTransaction((tx) async {
        await tx.writeAuditLog(
          hospitalCode: scope.hospitalCode,
          actorStaffId: scope.actor.id,
          actorRole: scope.actor.role.name,
          deviceId: scope.deviceId,
          action: 'admin.employee.sessions_revoked',
          entityType: 'mc_staff',
          entityId: current.identity.staffCode,
          afterState: {'targetStaffId': staffId, 'revokedSessions': revokedCount},
        );
      });

      return _jsonOk({'staffId': staffId, 'revokedSessionsCount': revokedCount});
    });

    router.get('/api/v1/admin/employees/<id>/audit', (Request req, String id) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'settings_Users',
        requireCanEdit: false,
      );
      final staffId = int.tryParse(id);
      if (staffId == null) return _jsonError(400, 'INVALID_STAFF_ID', 'Invalid staff ID.');

      final res = await db.execute(
        '''
        SELECT * FROM mc_audit_logs
        WHERE hospital_code = :hosp AND (entity_type = 'mc_staff' OR actor_staff_id = :sid)
        ORDER BY id DESC LIMIT 50
        ''',
        {'hosp': scope.hospitalCode, 'sid': staffId},
      );

      return _jsonOk({
        'staffId': staffId,
        'auditEntries': res.rows.map((r) => r.assoc()).toList(),
      });
    });

    // =========================================================================
    // HR Staff Evaluations (GAP-015 / HR-002)
    // =========================================================================
    router.get('/api/v1/hr/evaluations', (Request req) async {
      final scope = await _authorize(req, requiredPermission: 'hr_Employees');
      final staffIdParam = req.url.queryParameters['staffId'];
      final staffId = staffIdParam != null ? int.tryParse(staffIdParam) : null;
      final evals = await staffEvaluationRepo.listEvaluations(
        scope: scope,
        staffId: staffId,
      );
      return _jsonOk({
        'hospitalCode': scope.hospitalCode,
        'count': evals.length,
        'evaluations': evals,
      });
    });

    router.post('/api/v1/hr/evaluations', (Request req) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'hr_Employees',
        requireCanEdit: true,
      );
      final body = await _readJsonBody(req);
      final staffId = int.tryParse(body['staffId'].toString());
      if (staffId == null) {
        return _jsonError(400, 'INVALID_STAFF_ID', 'staffId is required and must be an integer.');
      }
      final res = await staffEvaluationRepo.createEvaluation(
        scope: scope,
        staffId: staffId,
        evaluationPeriod: (body['evaluationPeriod'] ?? '2026-Q1').toString(),
        score: Decimal.parse((body['score'] ?? '0.00').toString()),
        rating: (body['rating'] ?? 'GOOD').toString(),
        strengths: body['strengths']?.toString(),
        improvements: body['improvements']?.toString(),
        notes: body['notes']?.toString(),
        status: (body['status'] ?? 'FINALIZED').toString(),
      );
      return _jsonOk(res, statusCode: 201);
    });

    router.post('/api/v1/auth/change-password', (Request req) async {
      final authHeader = req.headers['authorization'] ?? '';
      if (!authHeader.startsWith('Bearer ')) {
        return _jsonError(401, 'MISSING_TOKEN', 'Authorization header is required.');
      }
      final token = authHeader.substring(7).trim();
      final hospCode = (req.headers['x-tenant-id'] ?? req.headers['x-hospital-code'] ?? '').trim();
      final devId = (req.headers['x-medcore-device-id'] ?? req.headers['x-device-id'] ?? '').trim();

      final authCtx = await authService.verifySession(
        rawToken: token,
        requestedHospitalCode: hospCode,
        requestedDeviceId: devId,
      );

      final body = await _readJsonBody(req);
      final oldPassword = (body['oldPassword'] ?? '').toString();
      final newPassword = (body['newPassword'] ?? '').toString();

      if (oldPassword.isEmpty || newPassword.isEmpty) {
        return _jsonError(400, 'MISSING_FIELDS', 'oldPassword and newPassword are required.');
      }
      if (newPassword.length < 8) {
        return _jsonError(400, 'WEAK_PASSWORD', 'New password must be at least 8 characters long.');
      }

      final repo = StaffIdentityRepository(db);
      final current = await repo.findById(authCtx.staff.hospitalCode, authCtx.staff.id);
      if (current == null) return _jsonError(404, 'STAFF_NOT_FOUND', 'Staff record not found.');

      if (!PasswordHasher.verifyPassword(oldPassword, current.passwordHash)) {
        return _jsonError(401, 'INVALID_OLD_PASSWORD', 'Current password verification failed.');
      }

      final newHash = PasswordHasher.hashPassword(newPassword);
      await repo.updatePassword(
        hospitalCode: authCtx.staff.hospitalCode,
        staffId: authCtx.staff.id,
        newPasswordHash: newHash,
        forcePasswordChange: false,
      );

      return _jsonOk({
        'status': 'PASSWORD_CHANGED_SUCCESS',
        'staffId': authCtx.staff.id,
      });
    });

    // 7. Patients Endpoints (Demonstrates Base vs `_all` Data Scope + `canEdit` / `canDelete`)
    router.get('/api/v1/patients', (Request req) async {
      final scope = await _authorize(req, requiredPermission: 'patients');
      final repo = PatientRepository(db);
      final list = await repo.listPatients(scope);
      return _jsonOk({
        'dataScopeApplied': scope.dataScopeMode.name,
        'count': list.length,
        'items': list.map((p) => p.toJson()).toList(),
      });
    });

    router.post('/api/v1/patients', (Request req) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'patients.write',
        requireCanEdit: true,
      );
      final body = await _readJsonBody(req);
      final cfg = await facilityConfigService.getConfiguration(scope.hospitalCode);
      facilityConfigService.validatePatientPayloadAgainstFacilityConfig(
        config: cfg,
        body: body,
      );

      bool isFieldAllowed(String key) =>
          (cfg.patientFields[key] ?? PatientFieldRequirement.optional) !=
          PatientFieldRequirement.hidden;

      List<String>? parseStringList(dynamic raw) {
        if (raw is List) return raw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
        if (raw is String && raw.trim().isNotEmpty) {
          return raw.split(',').map((e) => e.trim()).where((s) => s.isNotEmpty).toList();
        }
        return null;
      }

      final historyMeta = <String, dynamic>{};
      if (isFieldAllowed('inpatientAdmissionNotes') &&
          body['inpatientAdmissionNotes'] != null &&
          body['inpatientAdmissionNotes'].toString().trim().isNotEmpty) {
        historyMeta['inpatientAdmissionNotes'] = body['inpatientAdmissionNotes'].toString().trim();
      }
      if (isFieldAllowed('icuTriageNotes') &&
          body['icuTriageNotes'] != null &&
          body['icuTriageNotes'].toString().trim().isNotEmpty) {
        historyMeta['icuTriageNotes'] = body['icuTriageNotes'].toString().trim();
      }
      if (isFieldAllowed('nursingIntakeAssessment') &&
          body['nursingIntakeAssessment'] != null &&
          body['nursingIntakeAssessment'].toString().trim().isNotEmpty) {
        historyMeta['nursingIntakeAssessment'] = body['nursingIntakeAssessment'].toString().trim();
      }

      final repo = PatientRepository(db);
      final pat = await repo.createPatient(
        scope: scope,
        mrn: body['mrn'].toString(),
        fullName: body['fullName'].toString(),
        phone: body['phone'].toString(),
        gender: (body['gender'] ?? 'male').toString(),
        dateOfBirth: isFieldAllowed('dateOfBirth') ? body['dateOfBirth']?.toString() : null,
        age: (isFieldAllowed('age') && body['age'] != null && body['age'].toString().trim().isNotEmpty)
            ? int.tryParse(body['age'].toString())
            : null,
        nationalId: isFieldAllowed('nationalId') ? body['nationalId']?.toString() : null,
        bloodGroup: isFieldAllowed('bloodGroup') ? body['bloodGroup']?.toString() : null,
        address: isFieldAllowed('address') ? body['address']?.toString() : null,
        insuranceCompanyId:
            isFieldAllowed('insuranceCompanyId') ? body['insuranceCompanyId']?.toString() : null,
        insurancePolicyNo:
            isFieldAllowed('insurancePolicyNo') ? body['insurancePolicyNo']?.toString() : null,
        emergencyContactName:
            isFieldAllowed('emergencyContactName') ? body['emergencyContactName']?.toString() : null,
        emergencyContactPhone:
            isFieldAllowed('emergencyContactPhone') ? body['emergencyContactPhone']?.toString() : null,
        allergies: isFieldAllowed('allergies') ? parseStringList(body['allergies']) : null,
        chronicConditions:
            isFieldAllowed('chronicConditions') ? parseStringList(body['chronicConditions']) : null,
        clinicalHistoryMeta: historyMeta.isNotEmpty ? historyMeta : null,
        assignedDoctorId:
            body['assignedDoctorId'] != null ? int.parse(body['assignedDoctorId'].toString()) : null,
        departmentId: body['departmentId']?.toString(),
      );
      return _jsonOk(pat.toJson(), statusCode: 201);
    });

    router.delete('/api/v1/patients/<id>', (Request req, String id) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'patients.write',
        requireCanDelete: true,
      );
      final repo = PatientRepository(db);
      await repo.softDeletePatient(scope: scope, patientId: int.parse(id));
      return _jsonOk({'deleted': true, 'patientId': int.parse(id)});
    });

    // 8. Cashier Shift Endpoint (Requires `shifts` + `canCollectMoney`)
    router.post('/api/v1/shifts/open', (Request req) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'shifts',
        requireCanCollectMoney: true,
      );
      final body = await _readJsonBody(req);
      final repo = ShiftRepository(db);
      final shift = await repo.openShift(
        scope: scope,
        shiftCode: body['shiftCode'].toString(),
        openingBalance: Decimal.parse((body['openingBalance'] ?? '0.0000').toString()),
      );
      return _jsonOk(shift, statusCode: 201);
    });

    // 9. Atomic Visit Creation with Cost Split (Requires `reception_QuickCheckIn` + `canCollectMoney` if paid > 0)
    router.post('/api/v1/visits', (Request req) async {
      final body = await _readJsonBody(req);
      final paid = Decimal.parse((body['paidAmount'] ?? '0.0000').toString());
      final scope = await _authorize(
        req,
        requiredPermission: 'reception_QuickCheckIn',
        requireCanEdit: true,
        requireCanCollectMoney: paid > Decimal.zero,
      );

      final res = await visitFinancialService.createAtomicVisitWithCostSplit(
        scope: scope,
        visitNumber: body['visitNumber'].toString(),
        idempotencyKey: body['idempotencyKey'].toString(),
        patientId: int.parse(body['patientId'].toString()),
        doctorId: int.parse(body['doctorId'].toString()),
        shiftId: int.parse(body['shiftId'].toString()),
        serviceCode: (body['serviceCode'] ?? 'SRV-001').toString(),
        serviceName: (body['serviceName'] ?? 'Consultation').toString(),
        serviceLaborGross: Decimal.parse((body['serviceLaborGross'] ?? '0.0000').toString()),
        consumableGross: Decimal.parse((body['consumableGross'] ?? '0.0000').toString()),
        consumableFifoCost: Decimal.parse((body['consumableFifoCost'] ?? '0.0000').toString()),
        discountAmount: Decimal.parse((body['discountAmount'] ?? '0.0000').toString()),
        insuranceCoveredAmount: Decimal.parse((body['insuranceCoveredAmount'] ?? '0.0000').toString()),
        paidAmount: paid,
        doctorCommissionRatePercent: Decimal.parse((body['doctorCommissionRatePercent'] ?? '0.0000').toString()),
      );
      return _jsonOk(res, statusCode: 201);
    });

    // 10. Visit Refund Endpoint (Enforces `canMakeRefunds` & `refundPolicy`: none | approval | direct)
    router.post('/api/v1/visits/<id>/refund', (Request req, String id) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'finance_Invoices',
        requireCanMakeRefunds: true,
      );
      final body = await _readJsonBody(req);
      final res = await visitFinancialService.initiateRefund(
        scope: scope,
        visitId: int.parse(id),
        refundAmount: Decimal.parse((body['refundAmount'] ?? body['amount'] ?? '0.0000').toString()),
        reason: (body['reason'] ?? 'Customer refund request').toString(),
        shiftId: body['shiftId'] != null ? int.tryParse(body['shiftId'].toString()) : null,
      );
      return _jsonOk(res);
    });

    // 11. Protected Financial Settlements Route (Demonstrates `_secure` Page/Device Lock enforcement)
    router.get('/api/v1/finance/settlements', (Request req) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'finance_Settlements',
        tenantSecureLocks: const {'finance_Settlements_secure'},
      );
      final res = await db.execute(
        '''
        SELECT id, posting_uuid, beneficiary_id, amount, status
        FROM mc_financial_postings
        WHERE hospital_code = :hosp AND posting_type = 'COMMISSION_ACCRUAL'
        ORDER BY id ASC
        ''',
        {'hosp': scope.hospitalCode},
      );
      return _jsonOk({
        'secureDeviceVerified': scope.isTrustedSecureDevice,
        'count': res.rows.length,
        'items': res.rows
            .map((r) => {
                  'id': int.parse(r.colByName('id') ?? '0'),
                  'postingUuid': r.colByName('posting_uuid'),
                  'beneficiaryId': int.tryParse(r.colByName('beneficiary_id') ?? ''),
                  'amount': r.colByName('amount'),
                  'status': r.colByName('status'),
                })
            .toList(),
      });
    });

    // =========================================================================
    // WORKSTREAM 1: Appointments & Scheduling (CLN-001)
    // =========================================================================
    router.get('/api/v1/appointments', (Request req) async {
      final scope = await _authorize(req, requiredPermission: 'appointments');
      final list = await appointmentRepo.listAppointments(scope);
      return _jsonOk({
        'dataScopeApplied': scope.dataScopeMode.name,
        'count': list.length,
        'items': list.map((a) => a.toJson()).toList(),
      });
    });

    router.post('/api/v1/appointments', (Request req) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'appointments',
        requireCanEdit: true,
      );
      final body = await _readJsonBody(req);
      final apt = await appointmentRepo.createAppointment(
        scope: scope,
        appointmentNumber: body['appointmentNumber'].toString(),
        patientId: int.parse(body['patientId'].toString()),
        doctorId: body['doctorId'].toString(),
        clinicId: body['clinicId']?.toString(),
        appointmentType: (body['appointmentType'] ?? 'CONSULTATION').toString(),
        scheduledAt: DateTime.parse(body['scheduledAt'].toString()),
        durationMinutes: int.tryParse(body['durationMinutes']?.toString() ?? '30') ?? 30,
        reason: body['reason']?.toString(),
        notes: body['notes']?.toString(),
        idempotencyKey: body['idempotencyKey']?.toString(),
      );
      return _jsonOk(apt.toJson(), statusCode: 201);
    });

    router.put('/api/v1/appointments/<id>/status', (Request req, String id) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'appointments',
        requireCanEdit: true,
      );
      final body = await _readJsonBody(req);
      final apt = await appointmentRepo.updateStatus(
        scope: scope,
        appointmentId: int.parse(id),
        newStatus: body['status'].toString(),
        cancellationReason: body['cancellationReason']?.toString(),
      );
      return _jsonOk(apt.toJson());
    });

    // =========================================================================
    // MULTI-RESOURCE SCHEDULING & CONFLICT ENGINE (Batch 13 / Master Completion)
    // =========================================================================
    router.get('/api/v1/scheduling/resources', (Request req) async {
      final scope = await _authorize(req, requiredPermission: 'appointments');
      final params = req.requestedUri.queryParameters;
      SchedulingResourceType? rType;
      if (params['resourceType'] != null && params['resourceType']!.isNotEmpty) {
        rType = SchedulingResourceType.fromString(params['resourceType']!);
      }
      final resources = await schedulingResourceRepo.listResources(
        scope.hospitalCode,
        resourceType: rType,
        onlyActive: params['onlyActive'] == 'true',
      );
      return _jsonOk({
        'count': resources.length,
        'items': resources.map((r) => r.toJson()).toList(),
      });
    });

    router.post('/api/v1/scheduling/resources', (Request req) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'appointments',
        requireCanEdit: true,
      );
      final body = await _readJsonBody(req);
      final rType = SchedulingResourceType.fromString(body['resourceType'].toString());
      final res = await schedulingResourceRepo.upsertResource(
        hospitalCode: scope.hospitalCode,
        resourceCode: body['resourceCode'].toString(),
        name: body['name'].toString(),
        resourceType: rType,
        departmentId: body['departmentId']?.toString(),
        metadata: body['metadata'] is Map ? Map<String, dynamic>.from(body['metadata'] as Map) : null,
        isActive: body['isActive'] != false,
      );
      return _jsonOk(res.toJson(), statusCode: 201);
    });

    router.get('/api/v1/scheduling/rules', (Request req) async {
      final scope = await _authorize(req, requiredPermission: 'appointments');
      final params = req.requestedUri.queryParameters;
      final rules = await schedulingResourceRepo.listRules(
        scope.hospitalCode,
        onlyActive: params['onlyActive'] == 'true',
      );
      return _jsonOk({
        'count': rules.length,
        'items': rules.map((r) => r.toJson()).toList(),
      });
    });

    router.post('/api/v1/scheduling/rules', (Request req) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'appointments',
        requireCanEdit: true,
      );
      final body = await _readJsonBody(req);
      final pType = SchedulingResourceType.fromString(body['primaryResourceType'].toString());
      final coTypes = body['requiredCoResourceTypes'] is List
          ? (body['requiredCoResourceTypes'] as List).map((e) => e.toString()).toList()
          : <String>[];
      final rule = await schedulingResourceRepo.upsertRule(
        hospitalCode: scope.hospitalCode,
        ruleCode: body['ruleCode'].toString(),
        name: body['name'].toString(),
        appointmentType: body['appointmentType'].toString(),
        primaryResourceType: pType,
        requiredCoResourceTypes: coTypes,
        defaultDurationMinutes: body['defaultDurationMinutes'] is int
            ? body['defaultDurationMinutes'] as int
            : int.parse(body['defaultDurationMinutes']?.toString() ?? '30'),
        bufferBeforeMinutes: body['bufferBeforeMinutes'] is int
            ? body['bufferBeforeMinutes'] as int
            : int.parse(body['bufferBeforeMinutes']?.toString() ?? '0'),
        bufferAfterMinutes: body['bufferAfterMinutes'] is int
            ? body['bufferAfterMinutes'] as int
            : int.parse(body['bufferAfterMinutes']?.toString() ?? '0'),
        isActive: body['isActive'] != false,
      );
      return _jsonOk(rule.toJson(), statusCode: 201);
    });

    router.post('/api/v1/scheduling/conflicts/check', (Request req) async {
      final scope = await _authorize(req, requiredPermission: 'appointments');
      final body = await _readJsonBody(req);
      final rIds = (body['resourceIds'] as List).map((e) => int.parse(e.toString())).toList();
      final start = DateTime.parse(body['start'].toString()).toUtc();
      final end = DateTime.parse(body['end'].toString()).toUtc();
      final excludeAptId = body['excludeAppointmentId'] != null ? int.parse(body['excludeAppointmentId'].toString()) : null;

      final conflicts = await schedulingResourceRepo.checkConflicts(
        hospitalCode: scope.hospitalCode,
        resourceIds: rIds,
        startUtc: start,
        endUtc: end,
        excludeAppointmentId: excludeAptId,
      );
      return _jsonOk({
        'hasConflict': conflicts.isNotEmpty,
        'conflicts': conflicts,
      });
    });

    router.post('/api/v1/scheduling/appointments/multi-resource', (Request req) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'appointments',
        requireCanEdit: true,
      );
      final body = await _readJsonBody(req);
      final aptNumber = body['appointmentNumber'].toString();
      final patientId = int.parse(body['patientId'].toString());
      final aptType = body['appointmentType']?.toString() ?? 'CONSULTATION';
      final doctorId = body['doctorId'] != null ? int.parse(body['doctorId'].toString()) : null;
      final aptDateTime = DateTime.parse(body['appointmentDateTime'].toString()).toUtc();
      final notes = body['notes']?.toString();
      final resourceIds = (body['resourceIds'] as List).map((e) => int.parse(e.toString())).toList();

      // Resolve rule if provided or look up by appointment type
      SchedulingRuleRecord? rule;
      if (body['ruleCode'] != null) {
        rule = await schedulingResourceRepo.getRuleByCode(scope.hospitalCode, body['ruleCode'].toString());
      }
      rule ??= await schedulingResourceRepo.getRuleByAppointmentType(scope.hospitalCode, aptType);

      final duration = body['durationMinutes'] != null
          ? int.parse(body['durationMinutes'].toString())
          : (rule?.defaultDurationMinutes ?? 30);
      final bufferBefore = rule?.bufferBeforeMinutes ?? 0;
      final bufferAfter = rule?.bufferAfterMinutes ?? 0;

      // 1. Create Appointment in atomic transaction
      final apt = await appointmentRepo.createAppointment(
        scope: scope,
        appointmentNumber: aptNumber,
        patientId: patientId,
        doctorId: (doctorId ?? scope.actor.id).toString(),
        appointmentType: aptType,
        scheduledAt: aptDateTime,
        durationMinutes: duration,
        notes: notes,
      );

      // 2. Allocate resources atomically with conflict check
      try {
        final allocations = await schedulingResourceRepo.allocateResourcesTransaction(
          hospitalCode: scope.hospitalCode,
          appointmentId: apt.id,
          resourceIds: resourceIds,
          requestedStartUtc: aptDateTime,
          durationMinutes: duration,
          bufferBeforeMinutes: bufferBefore,
          bufferAfterMinutes: bufferAfter,
        );

        return _jsonOk({
          'appointment': apt.toJson(),
          'allocations': allocations.map((a) => a.toJson()).toList(),
          'ruleApplied': rule?.ruleCode,
          'durationMinutes': duration,
          'bufferBeforeMinutes': bufferBefore,
          'bufferAfterMinutes': bufferAfter,
        }, statusCode: 201);
      } catch (e) {
        // Rollback appointment status to CANCELLED if allocation failed
        await appointmentRepo.updateStatus(
          scope: scope,
          appointmentId: apt.id,
          newStatus: 'CANCELLED',
          cancellationReason: 'RESOURCE_ALLOCATION_CONFLICT: $e',
        );
        rethrow;
      }
    });

    router.post('/api/v1/scheduling/appointments/<id>/release', (Request req, String id) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'appointments',
        requireCanEdit: true,
      );
      await schedulingResourceRepo.releaseAllocationsForAppointment(
        scope.hospitalCode,
        int.parse(id),
      );
      return _jsonOk({'released': true});
    });

    router.get('/api/v1/scheduling/appointments/<id>/allocations', (Request req, String id) async {
      final scope = await _authorize(req, requiredPermission: 'appointments');
      final allocations = await schedulingResourceRepo.listAllocationsForAppointment(
        scope.hospitalCode,
        int.parse(id),
      );
      return _jsonOk({
        'count': allocations.length,
        'items': allocations.map((a) => a.toJson()).toList(),
      });
    });

    // =========================================================================
    // WORKSTREAM 2: Shift Reconciliation & Current Shift (FIN-006)
    // =========================================================================
    router.get('/api/v1/shifts/current', (Request req) async {
      final scope = await _authorize(req, requiredPermission: 'shifts');
      final current = await shiftReconciliationService.getCurrentOpenShift(
        hospitalCode: scope.hospitalCode,
        cashierStaffId: scope.actor.id,
      );
      return _jsonOk({'openShift': current});
    });

    router.post('/api/v1/shifts/close', (Request req) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'shifts',
        requireCanCollectMoney: true,
      );
      final body = await _readJsonBody(req);
      final res = await shiftReconciliationService.closeShift(
        scope: scope,
        shiftId: int.parse(body['shiftId'].toString()),
        countedCash: Decimal.parse(body['countedCash'].toString()),
        notes: body['notes']?.toString(),
      );
      return _jsonOk(res);
    });

    // =========================================================================
    // WORKSTREAM 3: Doctor Queue, Encounters & SOAP Notes (CLN-001)
    // =========================================================================
    router.get('/api/v1/doctor/queue', (Request req) async {
      final scope = await _authorize(req, requiredPermission: 'clinic_DoctorQueue');
      final queue = await encounterRepo.getDoctorQueue(scope);
      return _jsonOk({
        'dataScopeApplied': scope.dataScopeMode.name,
        'count': queue.length,
        'items': queue,
      });
    });

    router.post('/api/v1/encounters', (Request req) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'clinic_DoctorQueue',
        requireCanEdit: true,
      );
      final body = await _readJsonBody(req);
      final res = await encounterRepo.createEncounter(
        scope: scope,
        visitId: int.parse(body['visitId'].toString()),
        patientId: int.parse(body['patientId'].toString()),
        encounterNumber: body['encounterNumber'].toString(),
        chiefComplaint: body['chiefComplaint']?.toString(),
        vitals: body['vitals'] is Map ? Map<String, dynamic>.from(body['vitals'] as Map) : null,
        examination: body['examination'] is Map ? Map<String, dynamic>.from(body['examination'] as Map) : null,
        assessment: body['assessment'] is Map ? Map<String, dynamic>.from(body['assessment'] as Map) : null,
        plan: body['plan'] is Map ? Map<String, dynamic>.from(body['plan'] as Map) : null,
        diagnoses: body['diagnoses'] is List
            ? (body['diagnoses'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : null,
        notes: body['notes']?.toString(),
      );
      return _jsonOk(res, statusCode: 201);
    });

    // =========================================================================
    // WORKSTREAM 4: Electronic Prescriptions (e-Rx)
    // =========================================================================
    router.post('/api/v1/prescriptions', (Request req) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'clinic_Prescriptions',
        requireCanEdit: true,
      );
      final body = await _readJsonBody(req);
      final rawItems = body['items'] as List;
      final items = rawItems.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      final res = await prescriptionRepo.createPrescription(
        scope: scope,
        visitId: int.parse(body['visitId'].toString()),
        patientId: int.parse(body['patientId'].toString()),
        notes: body['notes']?.toString(),
        items: items,
      );
      return _jsonOk(res, statusCode: 201);
    });

    router.get('/api/v1/prescriptions/<id>', (Request req, String id) async {
      final scope = await _authorize(req, requiredPermission: 'clinic_Prescriptions');
      final res = await prescriptionRepo.getPrescription(scope.hospitalCode, int.parse(id));
      if (res == null) return _jsonError(404, 'NOT_FOUND', 'Prescription $id not found.');
      return _jsonOk(res);
    });

    // =========================================================================
    // WORKSTREAM 5: Diagnostic Orders & Results Entry (LIS / RIS - CLN-003)
    // =========================================================================
    router.post('/api/v1/orders', (Request req) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'clinic_DoctorQueue',
        requireCanEdit: true,
      );
      final body = await _readJsonBody(req);
      final rawItems = body['items'] as List;
      final items = rawItems.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      final res = await diagnosticRepo.createOrder(
        scope: scope,
        patientId: int.parse(body['patientId'].toString()),
        encounterId: body['encounterId'] != null ? int.parse(body['encounterId'].toString()) : null,
        orderType: body['orderType'].toString(),
        priority: (body['priority'] ?? 'ROUTINE').toString(),
        clinicalIndication: body['clinicalIndication']?.toString(),
        items: items,
      );
      return _jsonOk(res, statusCode: 201);
    });

    router.get('/api/v1/orders', (Request req) async {
      final params = req.requestedUri.queryParameters;
      final requestedOrderType = params['orderType']?.trim().toUpperCase();

      String requiredPerm;
      if (requestedOrderType == 'RAD') {
        requiredPerm = 'rad_Dashboard';
      } else if (requestedOrderType == 'LAB') {
        requiredPerm = 'lab_Dashboard';
      } else {
        requiredPerm = 'lab_Dashboard';
      }

      final scope = await _authorize(req, requiredPermission: requiredPerm);
      final orders = await diagnosticRepo.listOrders(
        scope,
        orderType: params['orderType'],
        status: params['status'],
      );
      return _jsonOk({'count': orders.length, 'items': orders});
    });

    router.post('/api/v1/orders/<id>/results', (Request req, String id) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'lab_ResultsEntry',
        requireCanEdit: true,
      );
      final body = await _readJsonBody(req);
      final res = await diagnosticRepo.recordResult(
        scope: scope,
        orderId: int.parse(id),
        orderItemId: int.parse(body['orderItemId'].toString()),
        resultType: (body['resultType'] ?? 'NUMERIC').toString(),
        resultJson: Map<String, dynamic>.from(body['resultJson'] as Map),
        isCriticalPanic: body['isCriticalPanic'] == true,
        notes: body['notes']?.toString(),
      );
      return _jsonOk(res);
    });

    // =========================================================================
    // DYNAMIC CLINICAL TEMPLATE ENGINE (Batch 13 / Master Completion)
    // =========================================================================
    router.get('/api/v1/clinical/templates', (Request req) async {
      final scope = await _authorize(req, requiredPermission: 'doctor_ClinicalWorkspace');
      final params = req.requestedUri.queryParameters;
      final templates = await clinicalTemplateRepo.listTemplates(
        scope.hospitalCode,
        status: params['status'],
        specialty: params['specialty'],
      );
      return _jsonOk({
        'count': templates.length,
        'items': templates.map((t) => t.toJson()).toList(),
      });
    });

    router.post('/api/v1/clinical/templates', (Request req) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'doctor_ClinicalWorkspace',
        requireCanEdit: true,
      );
      final body = await _readJsonBody(req);
      final rawContent = body['content'] ?? body['contentJson'] ?? <String, dynamic>{};
      final content = rawContent is Map ? Map<String, dynamic>.from(rawContent) : <String, dynamic>{};
      final template = await clinicalTemplateRepo.createTemplate(
        hospitalCode: scope.hospitalCode,
        templateNumber: body['templateNumber'].toString(),
        title: body['title'].toString(),
        code: body['code']?.toString(),
        specialty: body['specialty']?.toString(),
        category: body['category']?.toString() ?? 'GENERAL',
        content: content,
        createdBy: scope.actor.staffCode,
      );
      return _jsonOk(template.toJson(), statusCode: 201);
    });

    router.get('/api/v1/clinical/templates/usages', (Request req) async {
      final scope = await _authorize(req, requiredPermission: 'doctor_ClinicalWorkspace');
      final params = req.requestedUri.queryParameters;
      final usages = await clinicalTemplateRepo.listTemplateUsages(
        scope.hospitalCode,
        encounterId: params['encounterId'] != null ? int.parse(params['encounterId']!) : null,
        patientId: params['patientId'] != null ? int.parse(params['patientId']!) : null,
      );
      return _jsonOk({
        'count': usages.length,
        'items': usages.map((u) => u.toJson()).toList(),
      });
    });

    router.post('/api/v1/clinical/templates/usages', (Request req) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'doctor_ClinicalWorkspace',
        requireCanEdit: true,
      );
      final body = await _readJsonBody(req);
      final rawSnapshot = body['snapshot'] ?? body['valuesJson'] ?? <String, dynamic>{};
      final usage = await clinicalTemplateRepo.recordTemplateUsage(
        hospitalCode: scope.hospitalCode,
        templateId: int.parse(body['templateId'].toString()),
        templateVersion: int.parse(body['templateVersion'].toString()),
        encounterId: body['encounterId'] != null ? int.parse(body['encounterId'].toString()) : null,
        patientId: body['patientId'] != null ? int.parse(body['patientId'].toString()) : null,
        snapshot: rawSnapshot is Map ? Map<String, dynamic>.from(rawSnapshot) : const {},
        usedBy: scope.actor.staffCode,
      );
      return _jsonOk(usage.toJson(), statusCode: 201);
    });

    router.get('/api/v1/clinical/templates/active/<number>', (Request req, String number) async {
      final scope = await _authorize(req, requiredPermission: 'doctor_ClinicalWorkspace');
      final template = await clinicalTemplateRepo.getActiveTemplateByNumber(scope.hospitalCode, number);
      if (template == null) {
        return _jsonError(404, 'NOT_FOUND', 'Active template for $number not found.');
      }
      return _jsonOk(template.toJson());
    });

    router.get('/api/v1/clinical/templates/<id>', (Request req, String id) async {
      final scope = await _authorize(req, requiredPermission: 'doctor_ClinicalWorkspace');
      final parsedId = int.tryParse(id);
      if (parsedId == null) {
        return _jsonError(404, 'NOT_FOUND', 'Invalid template id: $id');
      }
      final template = await clinicalTemplateRepo.getTemplateById(scope.hospitalCode, parsedId);
      if (template == null) {
        return _jsonError(404, 'NOT_FOUND', 'Clinical template $id not found.');
      }
      return _jsonOk(template.toJson());
    });

    router.put('/api/v1/clinical/templates/<id>', (Request req, String id) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'doctor_ClinicalWorkspace',
        requireCanEdit: true,
      );
      final body = await _readJsonBody(req);
      final rawContent = body['content'] ?? body['contentJson'];
      final content = rawContent is Map ? Map<String, dynamic>.from(rawContent) : null;
      final template = await clinicalTemplateRepo.updateTemplateDraft(
        hospitalCode: scope.hospitalCode,
        id: int.parse(id),
        title: body['title']?.toString(),
        specialty: body['specialty']?.toString(),
        category: body['category']?.toString(),
        content: content,
        updatedBy: scope.actor.staffCode,
      );
      return _jsonOk(template.toJson());
    });

    router.post('/api/v1/clinical/templates/<id>/version', (Request req, String id) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'doctor_ClinicalWorkspace',
        requireCanEdit: true,
      );
      final body = await _readJsonBody(req);
      final existing = await clinicalTemplateRepo.getTemplateById(scope.hospitalCode, int.parse(id));
      if (existing == null) {
        return _jsonError(404, 'NOT_FOUND', 'Clinical template $id not found.');
      }
      final rawContent = body['content'] ?? body['contentJson'];
      final newVer = await clinicalTemplateRepo.createNextVersion(
        hospitalCode: scope.hospitalCode,
        templateNumber: existing.templateNumber,
        newContent: rawContent is Map ? Map<String, dynamic>.from(rawContent) : null,
        createdBy: scope.actor.staffCode,
      );
      return _jsonOk(newVer.toJson(), statusCode: 201);
    });

    router.post('/api/v1/clinical/templates/<id>/activate', (Request req, String id) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'doctor_ClinicalWorkspace',
        requireCanEdit: true,
      );
      final template = await clinicalTemplateRepo.activateTemplate(
        hospitalCode: scope.hospitalCode,
        id: int.parse(id),
        updatedBy: scope.actor.staffCode,
      );
      return _jsonOk(template.toJson());
    });

    router.post('/api/v1/clinical/templates/<id>/deactivate', (Request req, String id) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'doctor_ClinicalWorkspace',
        requireCanEdit: true,
      );
      final template = await clinicalTemplateRepo.deactivateTemplate(
        hospitalCode: scope.hospitalCode,
        id: int.parse(id),
        updatedBy: scope.actor.staffCode,
      );
      return _jsonOk(template.toJson());
    });

    // =========================================================================
    // WORKSTREAM 6: Inventory & Pharmacy Dispensing (CLN-004 & FIN-004)
    // =========================================================================
    router.get('/api/v1/inventory/items', (Request req) async {
      final scope = await _authorize(req, requiredPermission: 'inventory_ItemsCatalog');
      final items = await inventoryPharmacyRepo.listItems(scope);
      return _jsonOk({'count': items.length, 'items': items});
    });

    router.get('/api/v1/inventory/batches', (Request req) async {
      final scope = await _authorize(req, requiredPermission: 'inventory_StockBatches');
      final itemId = req.requestedUri.queryParameters['itemId'] != null
          ? int.tryParse(req.requestedUri.queryParameters['itemId']!)
          : null;
      final batches = await inventoryPharmacyRepo.listBatches(scope, itemId: itemId);
      return _jsonOk({'count': batches.length, 'items': batches});
    });

    router.post('/api/v1/pharmacy/dispense', (Request req) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'pharmacy_Dispensing',
        requireCanCollectMoney: true,
      );
      final body = await _readJsonBody(req);
      final res = await inventoryPharmacyRepo.dispensePrescriptionItem(
        scope: scope,
        prescriptionId: int.parse(body['prescriptionId'].toString()),
        prescriptionItemId: int.parse(body['prescriptionItemId'].toString()),
        inventoryItemId: int.parse(body['inventoryItemId'].toString()),
        shiftId: int.parse(body['shiftId'].toString()),
        quantity: Decimal.parse(body['quantity'].toString()),
      );
      return _jsonOk(res);
    });

    // =========================================================================
    // WORKSTREAM 7: Inpatient Bed Map & Admissions (CLN-005)
    // =========================================================================
    router.get('/api/v1/beds', (Request req) async {
      final scope = await _authorize(req, requiredPermission: 'inpatient_BedMap');
      final dept = req.requestedUri.queryParameters['departmentId'];
      final beds = await inpatientRepo.listBeds(scope, departmentId: dept);
      return _jsonOk({'count': beds.length, 'items': beds});
    });

    router.post('/api/v1/admissions', (Request req) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'inpatient_Admissions',
        requireCanEdit: true,
      );
      final body = await _readJsonBody(req);
      final res = await inpatientRepo.admitPatient(
        scope: scope,
        patientId: body['patientId'].toString(),
        bedId: body['bedId'].toString(),
        departmentId: body['departmentId']?.toString(),
        roomId: body['roomId']?.toString(),
        admissionType: (body['admissionType'] ?? 'EMERGENCY').toString(),
        attendingDoctorId: body['attendingDoctorId']?.toString(),
        diagnosisJson: body['diagnosisJson']?.toString(),
      );
      return _jsonOk(res, statusCode: 201);
    });

    router.post('/api/v1/admissions/<id>/discharge', (Request req, String id) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'inpatient_Discharge',
        requireCanEdit: true,
      );
      final body = await _readJsonBody(req);
      final res = await inpatientRepo.dischargePatient(
        scope: scope,
        admissionId: int.parse(id),
        dischargeReason: body['dischargeReason']?.toString(),
      );
      return _jsonOk(res);
    });

    // =========================================================================
    // WORKSTREAM 8: Financial Commission Settlement & Dual Control (FIN-007 & SEC-005)
    // =========================================================================
    // 1. Step 1 of Two-Person Integrity: Cashier requests commission settlement
    router.post('/api/v1/finance/settlements/request', (Request req) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'finance_Settlements',
        tenantSecureLocks: const {'finance_Settlements_secure'},
        requireCanMakeRefunds: true,
      );
      final body = await _readJsonBody(req);
      final res = await settlementRepo.requestSettlement(
        scope: scope,
        doctorId: int.parse(body['doctorId'].toString()),
        settleAmount: Decimal.parse(body['settleAmount'].toString()),
        shiftId: int.parse(body['shiftId'].toString()),
        currency: body['currency']?.toString(),
        notes: body['notes']?.toString(),
      );
      return _jsonOk(res, statusCode: 201);
    });

    // 2. Step 3 of Two-Person Integrity: Cashier delivers/pays out an APPROVED settlement
    router.post('/api/v1/finance/settlements/<id>/deliver', (Request req, String id) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'finance_Settlements',
        tenantSecureLocks: const {'finance_Settlements_secure'},
        requireCanMakeRefunds: true,
      );
      final body = await _readJsonBody(req);
      final res = await settlementRepo.deliverSettlement(
        scope: scope,
        settlementId: int.parse(id),
        shiftId: int.parse(body['shiftId'].toString()),
      );
      return _jsonOk(res);
    });

    // 3. Main settlement endpoint:
    // Requires approved settlementId for delivery; rejects direct single-actor payouts
    router.post('/api/v1/finance/settlements', (Request req) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'finance_Settlements',
        tenantSecureLocks: const {'finance_Settlements_secure'},
        requireCanMakeRefunds: true,
      );
      final body = await _readJsonBody(req);
      if (body.containsKey('settlementId')) {
        final res = await settlementRepo.deliverSettlement(
          scope: scope,
          settlementId: int.parse(body['settlementId'].toString()),
          shiftId: int.parse(body['shiftId'].toString()),
        );
        return _jsonOk(res);
      }

      // If caller attempts direct single-step settlement with doctorId and settleAmount
      // Fail closed! Direct single-actor settlement without dual-control approval is forbidden!
      throw RbacForbiddenException(
        code: 'DUAL_CONTROL_APPROVAL_REQUIRED',
        message: 'Two-person integrity violation: Direct commission settlement without dual-control approval is forbidden. Submit request via /api/v1/finance/settlements/request first.',
        requiredPermission: 'finance_Settlements',
      );
    });

    router.get('/api/v1/dual-control/requests', (Request req) async {
      final scope = await _authorize(req, requiredPermission: 'settings_Permissions');
      final requests = await dualControlRepo.listPendingRequests(scope);
      return _jsonOk({'count': requests.length, 'items': requests});
    });

    router.post('/api/v1/dual-control/requests/<id>/decide', (Request req, String id) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'settings_Permissions',
        requireCanEdit: true,
      );
      final body = await _readJsonBody(req);
      final res = await dualControlRepo.decideRequest(
        scope: scope,
        requestId: int.parse(id),
        approve: body['approve'] == true,
        decisionNotes: body['decisionNotes']?.toString(),
      );
      return _jsonOk(res);
    });

    // 12. TRUTH & DATA EXPLORER (Authoritative View & Inspection Layer)
    // 12.1 Schema & Structure Introspection
    router.get('/api/v1/explorer/schema', (Request req) async {
      await _authenticate(req);
      final schema = await explorerService.getDatabaseStructure();
      return _jsonOk(schema);
    });

    // 12.2 Table Record Browsing with Tenant Isolation & Privacy Masking
    router.get('/api/v1/explorer/table/<tableName>', (Request req, String tableName) async {
      final scope = await _authorize(req, requiredPermission: 'dashboard');
      final params = req.requestedUri.queryParameters;
      final limit = int.tryParse(params['limit'] ?? '50') ?? 50;
      final offset = int.tryParse(params['offset'] ?? '0') ?? 0;
      final search = params['search'];
      final privacy = params['privacy'] != 'false';

      final records = await explorerService.queryTableRecords(
        tableName: tableName,
        scope: scope,
        limit: limit,
        offset: offset,
        search: search,
        privacyFilter: privacy,
      );
      return _jsonOk(records);
    });

    // 12.3 Relational Business Graph / Truth Trace (Visit -> Patient -> Postings -> Ledger -> Audit)
    router.get('/api/v1/explorer/trace/<visitNumber>', (Request req, String visitNumber) async {
      final authCtx = await _authenticate(req);
      final privacy = req.requestedUri.queryParameters['privacy'] != 'false';
      final graph = await explorerService.traceTruthGraph(
        hospitalCode: authCtx.session.hospitalCode,
        visitNumber: visitNumber,
        privacyFilter: privacy,
      );
      return _jsonOk(graph);
    });

    // 12.4 Structured Data Export (CSV & TXT)
    router.get('/api/v1/explorer/export', (Request req) async {
      final scope = await _authorize(req, requiredPermission: 'dashboard');
      final params = req.requestedUri.queryParameters;
      final tableName = params['table'] ?? '';
      final format = (params['format'] ?? 'csv').toLowerCase();
      final privacy = params['privacy'] != 'false';

      if (tableName.isEmpty) {
        return _jsonError(400, 'MISSING_TABLE_PARAMETER', 'Query parameter "table" is required.');
      }

      if (format == 'txt') {
        final txt = await explorerService.exportTableDataTxt(
          tableName: tableName,
          scope: scope,
          privacyFilter: privacy,
        );
        return Response.ok(
          txt,
          headers: {
            'content-type': 'text/plain; charset=utf-8',
            'content-disposition': 'attachment; filename="${tableName}_export.txt"',
          },
        );
      } else {
        final csv = await explorerService.exportTableDataCsv(
          tableName: tableName,
          scope: scope,
          privacyFilter: privacy,
        );
        return Response.ok(
          csv,
          headers: {
            'content-type': 'text/csv; charset=utf-8',
            'content-disposition': 'attachment; filename="${tableName}_export.csv"',
          },
        );
      }
    });

    // =========================================================================
    // 13. PRODUCT LAYER FOUNDATION — BOOTSTRAP, FACILITY CONFIG & SHIFTS QUERY
    // =========================================================================

    // Public-safe facility branding & connection bootstrap (no clinical/financial data)
    router.get('/api/v1/product/bootstrap', (Request req) async {
      final hospitalCode = (req.requestedUri.queryParameters['hospitalCode'] ??
              req.headers['x-tenant-id'] ??
              '')
          .trim();
      if (hospitalCode.isEmpty) {
        return _jsonError(400, 'MISSING_HOSPITAL_CODE', 'Query parameter hospitalCode or X-Tenant-ID header is required.');
      }
      final cfg = await facilityConfigService.getConfiguration(hospitalCode);
      return _jsonOk(cfg.toPublicBootstrapJson());
    });

    // Authenticated full facility configuration (branding, enabled modules, patient field requirements)
    router.get('/api/v1/product/config', (Request req) async {
      final authCtx = await _authenticate(req);
      final cfg = await facilityConfigService.getConfiguration(authCtx.staff.hospitalCode);
      return _jsonOk(cfg.toFullJson());
    });

    // Cashier shifts listing for active shift bar & shift management workspace
    router.get('/api/v1/shifts', (Request req) async {
      final scope = await _authorize(req, requiredPermission: 'shifts');
      final res = await db.execute(
        scope.isTenantWide
            ? '''
              SELECT s.*, st.full_name AS cashier_name, st.staff_code AS cashier_code
              FROM mc_shifts s
              LEFT JOIN mc_staff st ON st.id = s.cashier_staff_id AND st.hospital_code = s.hospital_code
              WHERE s.hospital_code = :hosp
              ORDER BY s.id DESC
              LIMIT 50
              '''
            : '''
              SELECT s.*, st.full_name AS cashier_name, st.staff_code AS cashier_code
              FROM mc_shifts s
              LEFT JOIN mc_staff st ON st.id = s.cashier_staff_id AND st.hospital_code = s.hospital_code
              WHERE s.hospital_code = :hosp AND s.cashier_staff_id = :actor_id
              ORDER BY s.id DESC
              LIMIT 50
              ''',
        {
          'hosp': scope.hospitalCode,
          'actor_id': scope.actor.id,
        },
      );
      return _jsonOk({
        'count': res.rows.length,
        'items': res.rows
            .map((r) => {
                  'id': int.parse(r.colByName('id') ?? '0'),
                  'shiftCode': r.colByName('shift_code'),
                  'cashierStaffId': int.parse(r.colByName('cashier_staff_id') ?? '0'),
                  'cashierName': r.colByName('cashier_name'),
                  'cashierCode': r.colByName('cashier_code'),
                  'status': r.colByName('status'),
                  'openingBalance': r.colByName('opening_balance'),
                  'cashIn': r.colByName('cash_in'),
                  'cashOut': r.colByName('cash_out'),
                  'expectedCash': r.colByName('expected_cash'),
                  'countedCash': r.colByName('counted_cash'),
                  'varianceAmount': r.colByName('variance_amount'),
                  'openedAt': r.colByName('opened_at'),
                  'closedAt': r.colByName('closed_at'),
                })
            .toList(),
      });
    });

    // =========================================================================
    // 14. PROTECTED TECHNICIAN / SERVICE MODE (STRICTLY SEPARATED FROM STAFF ROLES)
    // =========================================================================

    router.post('/api/v1/technician/time-challenge', (Request req) async {
      final body = await _readJsonBody(req);
      final hospitalCode =
          (body['hospitalCode'] ?? req.headers['x-tenant-id'] ?? '').toString().trim();
      if (hospitalCode.isEmpty) {
        return _jsonError(400, 'MISSING_HOSPITAL_CODE', 'hospitalCode is required.');
      }
      final res = await technicianService.createTrustedTimeChallenge(hospitalCode: hospitalCode);
      return _jsonOk(res);
    });

    router.post('/api/v1/technician/session/open', (Request req) async {
      final body = await _readJsonBody(req);
      final hospitalCode =
          (body['hospitalCode'] ?? req.headers['x-tenant-id'] ?? '').toString().trim();
      final deviceId =
          (body['deviceId'] ?? req.headers['x-medcore-device-id'] ?? '').toString().trim();
      if (hospitalCode.isEmpty || deviceId.isEmpty) {
        return _jsonError(400, 'MISSING_TECHNICIAN_CONTEXT', 'hospitalCode and deviceId are required.');
      }
      final res = await technicianService.openSession(
        hospitalCode: hospitalCode,
        deviceId: deviceId,
        installationTechnicianSecret: body['technicianSecret']?.toString(),
        rawAuthorityToken: body['authorityToken']?.toString(),
        challengeId: body['challengeId']?.toString(),
        rawTrustedTimeResponse: body['trustedTimeResponse']?.toString(),
        ipAddress: req.headers['x-forwarded-for'] ?? '127.0.0.1',
      );
      return _jsonOk(res, statusCode: 201);
    });

    router.post('/api/v1/technician/session/close', (Request req) async {
      final rawTech = req.headers['x-medcore-tech-token'];
      await technicianService.closeSession(rawTech);
      return _jsonOk({'closed': true});
    });

    // 14.1b Technician Secret Rotation (Technician Session ONLY)
    router.post('/api/v1/technician/secret/rotate', (Request req) async {
      final techCtx = await _verifyTechnicianRequest(req);
      final body = await _readJsonBody(req);
      final newSecret = body['newSecret']?.toString();
      final res = await technicianService.rotateTechnicianSecret(
        hospitalCode: techCtx.hospitalCode,
        newSecret: newSecret,
        actorRole: 'TECHNICIAN_SERVICE',
        deviceId: techCtx.deviceId,
        ipAddress: req.headers['x-forwarded-for'] ?? '127.0.0.1',
      );
      return _jsonOk(res);
    });

    // 14.1c Cryptographic Technician Credential Recovery Challenge
    router.post('/api/v1/technician/recovery/challenge', (Request req) async {
      final body = await _readJsonBody(req);
      final hospitalCode =
          (body['hospitalCode'] ?? req.headers['x-tenant-id'] ?? '').toString().trim();
      final deviceId =
          (body['deviceId'] ?? req.headers['x-medcore-device-id'] ?? '').toString().trim();
      if (hospitalCode.isEmpty) {
        return _jsonError(400, 'MISSING_HOSPITAL_CODE', 'hospitalCode is required.');
      }
      final res = await technicianService.createTrustedTimeChallenge(hospitalCode: hospitalCode);
      final authReq = res['authorityRequest'] as Map<String, dynamic>;
      return _jsonOk({
        'challengeId': res['challengeId'],
        'hospitalCode': hospitalCode,
        'deviceId': deviceId,
        'nonce': authReq['nonce'],
        'installationId': authReq['inst'],
        'expiresAtUtc': DateTime.now().toUtc().add(const Duration(minutes: 5)).toIso8601String(),
        'authorityRequest': authReq,
      });
    });

    // 14.1d Cryptographic Technician Credential Recovery Execution
    router.post('/api/v1/technician/recovery/verify', (Request req) async {
      final body = await _readJsonBody(req);
      final hospitalCode =
          (body['hospitalCode'] ?? req.headers['x-tenant-id'] ?? '').toString().trim();
      final deviceId =
          (body['deviceId'] ?? req.headers['x-medcore-device-id'] ?? '').toString().trim();
      final challengeId = (body['challengeId'] ?? '').toString().trim();
      final trustedTimeResponse =
          (body['trustedTimeResponse'] ?? body['rawTrustedTimeResponse'] ?? '').toString().trim();
      final authorityToken =
          (body['authorityToken'] ?? body['rawRecoveryAuthorityToken'] ?? '').toString().trim();
      final newSecret = body['newSecret']?.toString();

      if (hospitalCode.isEmpty ||
          deviceId.isEmpty ||
          challengeId.isEmpty ||
          authorityToken.isEmpty ||
          trustedTimeResponse.isEmpty) {
        return _jsonError(
          400,
          'MISSING_RECOVERY_PARAMS',
          'hospitalCode, deviceId, challengeId, authorityToken, and trustedTimeResponse are required.',
        );
      }

      final res = await technicianService.recoverTechnicianSecretWithAuthorityToken(
        hospitalCode: hospitalCode,
        deviceId: deviceId,
        challengeId: challengeId,
        rawTrustedTimeResponse: trustedTimeResponse,
        rawAuthorityToken: authorityToken,
        newSecret: newSecret,
        ipAddress: req.headers['x-forwarded-for'] ?? '127.0.0.1',
      );
      return _jsonOk(res);
    });

    router.get('/api/v1/technician/config', (Request req) async {
      final techCtx = await _verifyTechnicianRequest(req);
      final cfg = await facilityConfigService.getConfiguration(techCtx.hospitalCode);
      return _jsonOk({
        'technicianSession': techCtx.toJson(),
        'supportedEditions': MedCoreModuleCatalog.supportedEditions,
        'supportedFacilityTypes': MedCoreModuleCatalog.supportedFacilityTypes,
        'allModules': MedCoreModuleCatalog.allModules,
        'configuration': cfg.toFullJson(),
      });
    });

    router.put('/api/v1/technician/config', (Request req) async {
      final techCtx = await _verifyTechnicianRequest(req);
      final body = await _readJsonBody(req);
      final updated = await facilityConfigService.saveConfigurationFromTechnician(
        hospitalCode: techCtx.hospitalCode,
        technicianSessionUuid: techCtx.sessionUuid,
        payload: body,
        deviceId: techCtx.deviceId,
        ipAddress: req.headers['x-forwarded-for'] ?? '127.0.0.1',
      );
      return _jsonOk(updated.toFullJson());
    });

    // 14.1 Initial Hospital Administrator Provisioning & Handover (Technician Session ONLY)
    router.get('/api/v1/technician/initial-admin/status', (Request req) async {
      final techCtx = await _verifyTechnicianRequest(req);
      final staffRows = await db.execute(
        '''
        SELECT id, staff_code, full_name, email, role, phone, is_active,
               force_password_change, created_at, last_login_at
        FROM mc_staff
        WHERE hospital_code = :hosp
        ORDER BY id ASC
        ''',
        {'hosp': techCtx.hospitalCode},
      );
      final staffList = staffRows.rows.map((r) => {
        'id': r.colByName('id'),
        'staffCode': r.colByName('staff_code'),
        'fullName': r.colByName('full_name'),
        'email': r.colByName('email'),
        'role': r.colByName('role'),
        'phone': r.colByName('phone'),
        'isActive': r.colByName('is_active')?.toString() == '1',
        'forcePasswordChange': r.colByName('force_password_change')?.toString() == '1',
        'createdAt': r.colByName('created_at')?.toString(),
        'lastLoginAt': r.colByName('last_login_at')?.toString(),
      }).toList();
      final admins = staffList.where((s) => s['role'] == 'HospitalAdmin' || s['role'] == 'SuperAdmin').toList();
      return _jsonOk({
        'hospitalCode': techCtx.hospitalCode,
        'hasAdmin': admins.isNotEmpty,
        'totalStaffCount': staffList.length,
        'administrators': admins,
        'allStaff': staffList,
      });
    });

    router.post('/api/v1/technician/initial-admin', (Request req) async {
      final techCtx = await _verifyTechnicianRequest(req);
      final body = await _readJsonBody(req);
      final staffCode = (body['staffCode'] ?? 'ADM-001').toString().trim();
      final fullName = (body['fullName'] ?? '').toString().trim();
      final email = (body['email'] ?? '').toString().trim();
      var password = (body['password'] ?? '').toString();
      final phone = body['phone']?.toString().trim();
      final nationalId = body['nationalId']?.toString().trim();

      if (staffCode.isEmpty || fullName.isEmpty || email.isEmpty) {
        return _jsonError(
          400,
          'MISSING_REQUIRED_FIELDS',
          'staffCode, fullName, and email are required to provision Hospital Administrator.',
        );
      }
      if (!email.contains('@') || !email.contains('.')) {
        return _jsonError(400, 'INVALID_EMAIL_FORMAT', 'Valid email address is required.');
      }

      // If no password supplied, securely generate a one-time credential
      if (password.isEmpty) {
        password = 'MedCore-${PasswordHasher.generateSecureToken(8)}!';
      } else if (password.length < 8) {
        return _jsonError(400, 'WEAK_PASSWORD', 'Administrator password must be at least 8 characters long.');
      }

      final repo = StaffIdentityRepository(db);
      final existingCode = await repo.findByEmailOrCode(techCtx.hospitalCode, staffCode);
      if (existingCode != null) {
        return _jsonError(
          409,
          'DUPLICATE_STAFF_CODE',
          'Staff member with staffCode "$staffCode" already exists in facility ${techCtx.hospitalCode}.',
        );
      }
      final existingEmail = await repo.findByEmailOrCode(techCtx.hospitalCode, email);
      if (existingEmail != null) {
        return _jsonError(
          409,
          'DUPLICATE_EMAIL',
          'Staff member with email "$email" already exists in facility ${techCtx.hospitalCode}.',
        );
      }

      final passwordHash = PasswordHasher.hashPassword(password);
      final created = await repo.createStaff(
        hospitalCode: techCtx.hospitalCode,
        staffCode: staffCode,
        fullName: fullName,
        email: email,
        phone: phone?.isEmpty == true ? null : phone,
        nationalId: nationalId?.isEmpty == true ? null : nationalId,
        passwordHash: passwordHash,
        role: MedCoreRole.HospitalAdmin,
        permissionsMode: 'default',
        isActive: true,
        forcePasswordChange: true,
      );

      await txManager.runInTransaction((tx) async {
        await tx.writeAuditLog(
          hospitalCode: techCtx.hospitalCode,
          actorRole: 'TECHNICIAN_SERVICE',
          deviceId: techCtx.deviceId,
          action: 'technician.initial_admin.provisioned',
          entityType: 'mc_staff',
          entityId: created.staffCode,
          afterState: {
            'staffId': created.id,
            'role': created.role.name,
            'staffCode': created.staffCode,
            'email': created.email,
            'forcePasswordChange': true,
            'sessionUuid': techCtx.sessionUuid,
          },
          ipAddress: req.headers['x-forwarded-for'] ?? '127.0.0.1',
        );
      });

      return _jsonOk(
        {
          'status': 'SUCCESS',
          'message': 'Initial Hospital Administrator provisioned successfully with forced password change.',
          'admin': created.toPublicJson(RbacEvaluator.resolveEffectivePermissions(created)),
          'handoverTemporaryPassword': password,
          'facilityCode': techCtx.hospitalCode,
          'provisionedAt': DateTime.now().toUtc().toIso8601String(),
          'technicianSessionUuid': techCtx.sessionUuid,
          'forcePasswordChange': true,
        },
        statusCode: 201,
      );
    });

    router.post('/api/v1/technician/clock-recovery', (Request req) async {
      final body = await _readJsonBody(req);
      final hospitalCode =
          (body['hospitalCode'] ?? req.headers['x-tenant-id'] ?? '').toString().trim();
      final challengeId = (body['challengeId'] ?? '').toString().trim();
      final rawTimeResp = (body['trustedTimeResponse'] ?? '').toString().trim();
      final rawMaintToken = (body['maintenanceToken'] ?? '').toString().trim();
      if (hospitalCode.isEmpty ||
          challengeId.isEmpty ||
          rawTimeResp.isEmpty ||
          rawMaintToken.isEmpty) {
        return _jsonError(
          400,
          'MISSING_RECOVERY_FIELDS',
          'hospitalCode, challengeId, trustedTimeResponse, and maintenanceToken are required.',
        );
      }
      final res = await technicianService.recoverClockRollback(
        hospitalCode: hospitalCode,
        challengeId: challengeId,
        rawTrustedTimeResponse: rawTimeResp,
        rawMaintenanceToken: rawMaintToken,
        expectedInstallationIdOverride: body['expectedInstallationId']?.toString(),
      );
      return _jsonOk(res);
    });

    // =========================================================================
    // 15. MAINTENANCE CENTER & FULL REPORT GENERATION
    // =========================================================================

    router.get('/api/v1/maintenance/overview', (Request req) async {
      final access = await _authorizeStaffOrTechnician(
        req,
        requiredStaffPermission: 'security_Center',
      );
      final overview = await maintenanceCenterService.getOverview(
        hospitalCode: access.hospitalCode,
      );
      return _jsonOk(overview);
    });

    router.post('/api/v1/maintenance/reports', (Request req) async {
      final access = await _authorizeStaffOrTechnician(
        req,
        requiredStaffPermission: 'security_Center',
      );
      final report = await maintenanceCenterService.generateReport(
        hospitalCode: access.hospitalCode,
        generatedByMode: access.mode,
        generatedByActor: access.actorIdentifier,
        deviceId: access.deviceId,
        ipAddress: req.headers['x-forwarded-for'] ?? '127.0.0.1',
      );
      return _jsonOk(report, statusCode: 201);
    });

    // =========================================================================
    // 16. NETWORK / DEVICE FOUNDATION (CONNECT VIA LAN / CONNECT VIA WI-FI)
    // =========================================================================

    router.get('/api/v1/network/discovery', (Request req) async {
      final hospitalCode = (req.requestedUri.queryParameters['hospitalCode'] ??
              req.headers['x-tenant-id'] ??
              '')
          .trim();
      if (hospitalCode.isEmpty) {
        return _jsonError(400, 'MISSING_HOSPITAL_CODE', 'hospitalCode is required.');
      }
      final desc = await networkDeviceService.getDiscoveryDescriptor(hospitalCode: hospitalCode);
      return _jsonOk(desc);
    });

    router.post('/api/v1/network/pairing/request', (Request req) async {
      final body = await _readJsonBody(req);
      final hospitalCode =
          (body['hospitalCode'] ?? req.headers['x-tenant-id'] ?? '').toString().trim();
      final res = await networkDeviceService.requestDevicePairing(
        hospitalCode: hospitalCode,
        deviceId: (body['deviceId'] ?? '').toString(),
        deviceName: (body['deviceName'] ?? '').toString(),
        connectionType: (body['connectionType'] ?? 'LAN').toString(),
        platform: (body['platform'] ?? 'WINDOWS').toString(),
        roleScope: (body['roleScope'] ?? 'WORKSTATION').toString(),
        medcoreVersion: (body['medcoreVersion'] ?? '1.0.0-rc.1').toString(),
        hwFingerprintSha256: (body['hwFingerprintSha256'] ?? '').toString(),
        devicePublicKeyEd25519: (body['devicePublicKeyEd25519'] ?? '').toString(),
        ipAddress: body['ipAddress']?.toString() ?? req.headers['x-forwarded-for'] ?? '127.0.0.1',
      );
      return _jsonOk(res, statusCode: 201);
    });

    router.get('/api/v1/network/topology', (Request req) async {
      final access = await _authorizeStaffOrTechnician(
        req,
        requiredStaffPermission: 'settings_Devices',
      );
      final topo = await networkDeviceService.getTopologyAndDevices(
        hospitalCode: access.hospitalCode,
      );
      return _jsonOk(topo);
    });

    router.post('/api/v1/network/devices/<deviceId>/approve',
        (Request req, String deviceId) async {
      final access = await _authorizeStaffOrTechnician(
        req,
        requiredStaffPermission: 'settings_Devices',
        requireCanEditForStaff: true,
      );
      final body = await _readJsonBody(req);
      final approved = await networkDeviceService.approveDevice(
        hospitalCode: access.hospitalCode,
        targetDeviceId: Uri.decodeComponent(deviceId),
        pairingVerificationCode: body['pairingVerificationCode']?.toString(),
        isTrustedSecureRuntime: body['isTrustedSecureRuntime'] != false,
        roleScopeOverride: body['roleScope']?.toString(),
        approvedByStaffId: access.staffId,
        actorRoleLabel: access.actorRoleLabel,
        actorDeviceId: access.deviceId,
        ipAddress: req.headers['x-forwarded-for'] ?? '127.0.0.1',
      );
      return _jsonOk(approved);
    });

    router.post('/api/v1/network/devices/<deviceId>/revoke',
        (Request req, String deviceId) async {
      final access = await _authorizeStaffOrTechnician(
        req,
        requiredStaffPermission: 'settings_Devices',
        requireCanEditForStaff: true,
      );
      final body = await _readJsonBody(req);
      final revoked = await networkDeviceService.revokeDevice(
        hospitalCode: access.hospitalCode,
        targetDeviceId: Uri.decodeComponent(deviceId),
        revokedByStaffId: access.staffId,
        actorRoleLabel: access.actorRoleLabel,
        actorDeviceId: access.deviceId,
        reason: body['reason']?.toString(),
        ipAddress: req.headers['x-forwarded-for'] ?? '127.0.0.1',
      );
      return _jsonOk(revoked);
    });

    // LAN PKI & Certificate Hierarchy (Batch 3)
    router.get('/api/v1/network/certificates', (Request req) async {
      final access = await _authorizeStaffOrTechnician(
        req,
        requiredStaffPermission: 'settings_Devices',
      );
      final list = await lanPkiService.listCertificates(access.hospitalCode);
      return _jsonOk({
        'hospitalCode': access.hospitalCode,
        'count': list.length,
        'certificates': list.map((c) => c.toJson()).toList(),
      });
    });

    router.post('/api/v1/network/certificates/issue', (Request req) async {
      final access = await _authorizeStaffOrTechnician(
        req,
        requiredStaffPermission: 'settings_Devices',
        requireCanEditForStaff: true,
      );
      final body = await _readJsonBody(req);
      final devId = body['deviceId'].toString();
      final commonName = body['commonName'].toString();

      final cert = await lanPkiService.issueDeviceCertificate(
        hospitalCode: access.hospitalCode,
        deviceId: devId,
        commonName: commonName,
        actorStaffId: access.staffId,
      );
      return _jsonOk(cert.toJson(), statusCode: 201);
    });

    router.post('/api/v1/network/certificates/<uuid>/revoke', (Request req, String uuid) async {
      final access = await _authorizeStaffOrTechnician(
        req,
        requiredStaffPermission: 'settings_Devices',
        requireCanEditForStaff: true,
      );
      final body = await _readJsonBody(req);
      final reason = (body['reason'] ?? 'ADMIN_REVOKED').toString();

      await lanPkiService.revokeCertificate(
        hospitalCode: access.hospitalCode,
        certUuid: uuid,
        reason: reason,
        actorStaffId: access.staffId,
      );
      return _jsonOk({'status': 'CERTIFICATE_REVOKED', 'certUuid': uuid});
    });

    // =========================================================================
    // 17. PATIENT FINANCIAL LEDGER & FINANCIAL DOCUMENTS / REPORTS
    // =========================================================================

    router.get('/api/v1/finance/patients/<patientId>/ledger',
        (Request req, String patientId) async {
      final scope = await _authorize(req, requiredPermission: 'finance_Invoices');
      final ledger = await patientFinancialLedgerService.getPatientLedger(
        hospitalCode: scope.hospitalCode,
        patientId: int.parse(patientId),
      );
      return _jsonOk(ledger);
    });

    // Standalone PATIENT_AR Collection (Batch 2)
    router.post('/api/v1/finance/ar-collections', (Request req) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'finance_Invoices',
      );
      final body = await _readJsonBody(req);
      final patientId = int.parse(body['patientId'].toString());
      final amount = Decimal.parse(body['amount'].toString());
      int? shiftId;
      if (body['shiftId'] != null) {
        shiftId = int.tryParse(body['shiftId'].toString());
      }
      if (shiftId == null) {
        final shiftRes = await db.execute(
          '''
          SELECT id FROM mc_shifts
          WHERE hospital_code = :hosp AND cashier_staff_id = :staff_id AND status = 'OPEN'
          ORDER BY id DESC LIMIT 1
          ''',
          {'hosp': scope.hospitalCode, 'staff_id': scope.actor.id},
        );
        if (shiftRes.rows.isNotEmpty) {
          shiftId = int.tryParse(shiftRes.rows.first.assoc()['id']?.toString() ?? '');
        }
      }
      if (shiftId == null) {
        throw ArgumentError('shiftId is required or an active cashier shift must be open.');
      }
      final paymentMethod = (body['paymentMethod'] ?? 'CASH').toString();
      final idempotencyKey = body['idempotencyKey']?.toString();
      final notes = body['notes']?.toString();

      final res = await visitFinancialService.collectPatientAr(
        scope: scope,
        patientId: patientId,
        amount: amount,
        shiftId: shiftId,
        paymentMethod: paymentMethod,
        idempotencyKey: idempotencyKey,
        notes: notes,
      );
      return _jsonOk(res, statusCode: 201);
    });

    // External Laboratory & Clinic Payables (Batch 2 - FIN-GAP-LAB-CLINIC-PAYABLE-RULES)
    router.get('/api/v1/finance/external-payables', (Request req) async {
      final scope = await _authorize(req, requiredPermission: 'finance_Invoices');
      final partyType = req.url.queryParameters['partyType'];
      final status = req.url.queryParameters['status'];
      final vidStr = req.url.queryParameters['visitId'];
      final vid = vidStr != null ? int.tryParse(vidStr) : null;

      final list = await externalPayableService.listPayables(
        scope.hospitalCode,
        partyType: partyType,
        status: status,
        sourceVisitId: vid,
      );
      return _jsonOk({
        'hospitalCode': scope.hospitalCode,
        'count': list.length,
        'items': list.map((p) => p.toJson()).toList(),
      });
    });

    router.post('/api/v1/finance/external-payables', (Request req) async {
      final scope = await _authorize(req, requiredPermission: 'finance_Invoices', requireCanEdit: true);
      final body = await _readJsonBody(req);
      final vid = int.parse(body['sourceVisitId'].toString());
      final eid = int.parse(body['sourceEventId'].toString());
      final partyType = body['partyType'].toString().toUpperCase();
      final partyCode = body['partyCode'].toString();
      final partyName = body['partyName'].toString();
      final gross = Decimal.parse(body['grossAmount'].toString());
      final alloc = Decimal.parse(body['allocatedAmount'].toString());
      final shiftId = body['shiftId'] != null ? int.tryParse(body['shiftId'].toString()) : null;

      final created = await externalPayableService.allocatePayable(
        hospitalCode: scope.hospitalCode,
        sourceVisitId: vid,
        sourceEventId: eid,
        partyType: partyType,
        partyCode: partyCode,
        partyName: partyName,
        grossAmount: gross,
        allocatedAmount: alloc,
        shiftId: shiftId,
        actorStaffId: scope.actor.id,
        notes: body['notes']?.toString(),
      );
      return _jsonOk(created.toJson(), statusCode: 201);
    });

    router.post('/api/v1/finance/external-payables/<id>/settle', (Request req, String id) async {
      final scope = await _authorize(req, requiredPermission: 'finance_Revenue', requireCanEdit: true);
      final payableId = int.parse(id);
      final body = await _readJsonBody(req);
      final settleAmount = Decimal.parse(body['settleAmount'].toString());
      final idemp = (body['idempotencyKey'] ?? 'IDEMP-EXTPAY-' + payableId.toString() + '-' + DateTime.now().millisecondsSinceEpoch.toString()).toString();
      final method = (body['paymentMethod'] ?? 'CASH').toString();
      final shiftId = body['shiftId'] != null ? int.tryParse(body['shiftId'].toString()) : null;

      final settled = await externalPayableService.settlePayable(
        hospitalCode: scope.hospitalCode,
        payableId: payableId,
        settleAmount: settleAmount,
        idempotencyKey: idemp,
        paymentMethod: method,
        shiftId: shiftId,
        actorStaffId: scope.actor.id,
      );
      return _jsonOk(settled.toJson());
    });

    router.get('/api/v1/finance/documents/invoice/<visitId>',
        (Request req, String visitId) async {
      final scope = await _authorize(req, requiredPermission: 'finance_Invoices');
      final doc = await patientFinancialLedgerService.getInvoiceDocument(
        hospitalCode: scope.hospitalCode,
        visitId: int.parse(visitId),
      );
      return _jsonOk(doc);
    });

    router.get('/api/v1/finance/documents/receipt/<visitId>',
        (Request req, String visitId) async {
      final scope = await _authorize(req, requiredPermission: 'finance_Invoices');
      final doc = await patientFinancialLedgerService.getReceiptDocument(
        hospitalCode: scope.hospitalCode,
        visitId: int.parse(visitId),
      );
      return _jsonOk(doc);
    });

    router.get('/api/v1/finance/documents/patient-statement/<patientId>',
        (Request req, String patientId) async {
      final scope = await _authorize(req, requiredPermission: 'finance_Invoices');
      final doc = await patientFinancialLedgerService.getPatientStatementDocument(
        hospitalCode: scope.hospitalCode,
        patientId: int.parse(patientId),
      );
      return _jsonOk(doc);
    });

    router.get('/api/v1/finance/reports/outstanding-balances', (Request req) async {
      final scope = await _authorize(req, requiredPermission: 'finance_Revenue');
      final rep = await patientFinancialLedgerService.getOutstandingBalancesReport(
        hospitalCode: scope.hospitalCode,
      );
      return _jsonOk(rep);
    });

    router.get('/api/v1/finance/reports/financial-history', (Request req) async {
      final scope = await _authorize(req, requiredPermission: 'finance_Revenue');
      final limit = int.tryParse(req.requestedUri.queryParameters['limit'] ?? '100') ?? 100;
      final rep = await patientFinancialLedgerService.getFinancialHistoryReport(
        hospitalCode: scope.hospitalCode,
        limit: limit,
      );
      return _jsonOk(rep);
    });

    router.get('/api/v1/finance/reports/allocations', (Request req) async {
      final scope = await _authorize(req, requiredPermission: 'finance_Revenue');
      final rep = await patientFinancialLedgerService.getAllocationReport(
        hospitalCode: scope.hospitalCode,
      );
      return _jsonOk(rep);
    });

    // =========================================================================
    // 18. BACKUP ENGINE FOUNDATION & REMOTE / HYBRID READINESS
    // =========================================================================

    router.get('/api/v1/backups/status', (Request req) async {
      final access = await _authorizeStaffOrTechnician(
        req,
        requiredStaffPermission: 'settings_Backups',
      );
      final status = await backupEngineService.getBackupArchitectureStatus(
        hospitalCode: access.hospitalCode,
      );
      return _jsonOk(status);
    });

    router.post('/api/v1/backups/run', (Request req) async {
      final access = await _authorizeStaffOrTechnician(
        req,
        requiredStaffPermission: 'settings_Backups',
        requireCanEditForStaff: true,
      );
      final body = await _readJsonBody(req);
      final run = await backupEngineService.executeBackup(
        hospitalCode: access.hospitalCode,
        triggerType: access.mode == 'TECHNICIAN_SESSION'
            ? 'SERVICE_TOOL'
            : (body['triggerType'] ?? 'MANUAL_ADMIN').toString(),
        providerOverride: body['providerId']?.toString(),
        createdByStaffId: access.staffId,
        actorRoleLabel: access.actorRoleLabel,
        deviceId: access.deviceId,
        ipAddress: req.headers['x-forwarded-for'] ?? '127.0.0.1',
      );
      return _jsonOk(run, statusCode: 201);
    });

    // =========================================================================
    // 19. SPECIALTY CLINICAL WORKSPACES (Batch 5: Nursing, ICU, Surgery, Dialysis)
    // =========================================================================

    // Nursing Tasks
    router.get('/api/v1/clinical/nursing/tasks', (Request req) async {
      final scope = await _authorize(req, requiredPermission: 'nurse_NursingStation');
      final params = req.requestedUri.queryParameters;
      final patientId = params['patientId'] != null ? int.tryParse(params['patientId']!) : null;
      final tasks = await specialtyClinicalService.listNursingTasks(
        hospitalCode: scope.hospitalCode,
        patientId: patientId,
        status: params['status'],
      );
      return _jsonOk({'count': tasks.length, 'items': tasks});
    });

    router.post('/api/v1/clinical/nursing/tasks', (Request req) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'nurse_NursingStation',
        requireCanEdit: true,
      );
      final body = await _readJsonBody(req);
      final res = await specialtyClinicalService.createNursingTask(
        scope: scope,
        data: body,
      );
      return _jsonOk(res, statusCode: 201);
    });

    router.post('/api/v1/clinical/nursing/tasks/<id>/complete', (Request req, String id) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'nurse_NursingStation',
        requireCanEdit: true,
      );
      final body = await _readJsonBody(req);
      final res = await specialtyClinicalService.completeNursingTask(
        scope: scope,
        taskId: int.parse(id),
        notes: body['notes']?.toString(),
      );
      return _jsonOk(res);
    });

    // ICU Flowsheets & SOFA Scores
    router.get('/api/v1/clinical/icu/flowsheets', (Request req) async {
      final scope = await _authorize(req, requiredPermission: 'icu_nicu_Dashboard');
      final admissionId = req.requestedUri.queryParameters['admissionId'] ?? 'ADM-01';
      final sheets = await specialtyClinicalService.listIcuFlowsheets(
        hospitalCode: scope.hospitalCode,
        admissionId: admissionId,
      );
      return _jsonOk({'count': sheets.length, 'items': sheets});
    });

    router.post('/api/v1/clinical/icu/flowsheets', (Request req) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'icu_nicu_ICUMonitoring',
        requireCanEdit: true,
      );
      final body = await _readJsonBody(req);
      final res = await specialtyClinicalService.recordIcuFlowsheet(
        scope: scope,
        data: body,
      );
      return _jsonOk(res, statusCode: 201);
    });

    router.post('/api/v1/clinical/icu/scores', (Request req) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'icu_nicu_ICUMonitoring',
        requireCanEdit: true,
      );
      final body = await _readJsonBody(req);
      final res = await specialtyClinicalService.recordSofaScore(
        scope: scope,
        data: body,
      );
      return _jsonOk(res, statusCode: 201);
    });

    // Surgery & OR Scheduling
    router.get('/api/v1/clinical/surgeries', (Request req) async {
      final scope = await _authorize(req, requiredPermission: 'surgery_OTSchedule');
      final params = req.requestedUri.queryParameters;
      final surgeries = await specialtyClinicalService.listSurgeries(
        hospitalCode: scope.hospitalCode,
        status: params['status'],
        plannedDate: params['plannedDate'],
      );
      return _jsonOk({'count': surgeries.length, 'items': surgeries});
    });

    router.post('/api/v1/clinical/surgeries', (Request req) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'surgery_OTSchedule',
        requireCanEdit: true,
      );
      final body = await _readJsonBody(req);
      final res = await specialtyClinicalService.scheduleSurgery(
        scope: scope,
        data: body,
      );
      return _jsonOk(res, statusCode: 201);
    });

    router.put('/api/v1/clinical/surgeries/<id>/status', (Request req, String id) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'surgery_OperatingTheaters',
        requireCanEdit: true,
      );
      final body = await _readJsonBody(req);
      final res = await specialtyClinicalService.updateSurgeryStatus(
        scope: scope,
        surgeryId: int.parse(id),
        newStatus: body['status'].toString(),
      );
      return _jsonOk(res);
    });

    // Dialysis Sessions
    router.get('/api/v1/clinical/dialysis/sessions', (Request req) async {
      final scope = await _authorize(req, requiredPermission: 'dialysis_Sessions');
      final params = req.requestedUri.queryParameters;
      final sessions = await specialtyClinicalService.listDialysisSessions(
        hospitalCode: scope.hospitalCode,
        patientId: params['patientId'],
        status: params['status'],
      );
      return _jsonOk({'count': sessions.length, 'items': sessions});
    });

    router.post('/api/v1/clinical/dialysis/sessions', (Request req) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'dialysis_Sessions',
        requireCanEdit: true,
      );
      final body = await _readJsonBody(req);
      final res = await specialtyClinicalService.scheduleDialysisSession(
        scope: scope,
        data: body,
      );
      return _jsonOk(res, statusCode: 201);
    });

    router.put('/api/v1/clinical/dialysis/sessions/<id>/complete', (Request req, String id) async {
      final scope = await _authorize(
        req,
        requiredPermission: 'dialysis_Sessions',
        requireCanEdit: true,
      );
      final body = await _readJsonBody(req);
      final res = await specialtyClinicalService.completeDialysisSession(
        scope: scope,
        sessionId: int.parse(id),
        data: body,
      );
      return _jsonOk(res);
    });

    // =========================================================================
    // 20. REAL-TIME CLINICAL EVENT STREAM (Batch 15)
    // =========================================================================
    router.get('/api/v1/clinical/events/stream', (Request req) async {
      final scope = await _authorize(req, requiredPermission: 'clinical.read');
      final topicsParam = req.requestedUri.queryParameters['topics'];
      final filterTopics = topicsParam != null
          ? topicsParam.split(',').map((t) => t.trim()).toSet()
          : null;

      final sseStream = eventStreamService.createSseStream(
        hospitalCode: scope.hospitalCode,
        filterTopics: filterTopics,
      );

      return Response.ok(
        sseStream,
        headers: {
          'content-type': 'text/event-stream',
          'cache-control': 'no-cache',
          'connection': 'keep-alive',
          'x-accel-buffering': 'no',
        },
      );
    });

    // =========================================================================
    // 21. RESTORE VERIFICATION (Batch 17)
    // =========================================================================
    router.post('/api/v1/backups/verify-restore', (Request req) async {
      final access = await _authorizeStaffOrTechnician(
        req,
        requiredStaffPermission: 'sec_AuditLogs',
      );
      final body = await _readJsonBody(req);
      final archiveFilePath = body['archiveFilePath']?.toString();
      if (archiveFilePath == null || archiveFilePath.isEmpty) {
        throw ArgumentError('archiveFilePath is required.');
      }
      final expectedSha256 = body['expectedSha256']?.toString();
      final res = await backupEngineService.verifyBackupArchiveForRestore(
        hospitalCode: access.hospitalCode,
        archiveFilePath: archiveFilePath,
        expectedSha256: expectedSha256,
      );
      return _jsonOk(res);
    });

    // =========================================================================
    // 22. NATIVE PRINTING FORMATTER (Batch 18)
    // =========================================================================
    router.post('/api/v1/printing/format', (Request req) async {
      final scope = await _authorize(req, requiredPermission: 'finance_Invoices');
      final body = await _readJsonBody(req);
      final format = (body['format'] ?? 'ESC_POS').toString().toUpperCase();
      final docType = (body['documentType'] ?? 'RECEIPT').toString();
      final docId = (body['documentId'] ?? 'DOC-1').toString();

      List<int> bytes;
      if (format == 'ZPL') {
        final zpl = NativePrintingService.generateZplBarcodeLabel(
          facilityName: body['facilityName']?.toString() ?? 'MedCore',
          patientName: body['patientName']?.toString() ?? 'Unknown',
          patientMrn: body['patientMrn']?.toString() ?? 'MRN-000',
          barcodeContent: docId,
          labelTitle: body['labelTitle']?.toString() ?? 'Specimen',
          timestampString: DateTime.now().toIso8601String(),
        );
        bytes = utf8.encode(zpl);
      } else {
        bytes = NativePrintingService.generateEscPosThermalReceipt(
          facilityName: body['facilityName']?.toString() ?? 'MedCore Hospital',
          receiptNumber: docId,
          dateString: DateTime.now().toIso8601String().substring(0, 10),
          cashierName: scope.actor.fullName,
          patientName: body['patientName']?.toString() ?? 'Walk-In Patient',
          patientMrn: body['patientMrn']?.toString() ?? 'MRN-000',
          items: body['items'] != null
              ? (body['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()
              : const [],
          grossAmount: Decimal.tryParse(body['grossAmount']?.toString() ?? '0') ?? Decimal.zero,
          discountAmount: Decimal.tryParse(body['discountAmount']?.toString() ?? '0') ?? Decimal.zero,
          netAmount: Decimal.tryParse(body['netAmount']?.toString() ?? '0') ?? Decimal.zero,
          paidAmount: Decimal.tryParse(body['paidAmount']?.toString() ?? '0') ?? Decimal.zero,
          balanceAmount: Decimal.tryParse(body['balanceAmount']?.toString() ?? '0') ?? Decimal.zero,
          currency: body['currency']?.toString() ?? 'EGP',
        );
      }

      final job = NativePrintingService.dispatchPrintJob(
        format: format,
        documentType: docType,
        documentId: docId,
        rawBytes: bytes,
        printerEndpoint: body['printerEndpoint']?.toString(),
      );
      return _jsonOk(job);
    });

    // =========================================================================
    // 23. TECHNICIAN ENGINEERING BUNDLE (Batch 19)
    // =========================================================================
    router.post('/api/v1/maintenance/engineering-bundle', (Request req) async {
      final access = await _authorizeStaffOrTechnician(
        req,
        requiredStaffPermission: 'sec_AuditLogs',
      );
      final bundle = await maintenanceCenterService.exportEngineeringBundle(
        hospitalCode: access.hospitalCode,
        requestedByActor: access.mode == 'TECHNICIAN_SESSION' ? 'TECHNICIAN' : access.actorRoleLabel,
        deviceId: access.deviceId,
      );
      return _jsonOk(bundle);
    });

    // =========================================================================
    // 24. AUTHORITATIVE DATABASE LIFECYCLE, EXPORT, RESTORE & FACTORY RESET
    // =========================================================================

    // 24.1 Database Status
    router.get('/api/v1/database/status', (Request req) async {
      final access = await _authorizeStaffOrTechnician(
        req,
        requiredStaffPermission: 'settings_Backups',
      );
      final status = await databaseLifecycleService.getDatabaseStatus(
        hospitalCode: access.hospitalCode,
      );
      return _jsonOk(status);
    });

    // 24.2 Database Location
    router.get('/api/v1/database/location', (Request req) async {
      await _authorizeStaffOrTechnician(
        req,
        requiredStaffPermission: 'settings_Backups',
      );
      final location = databaseLifecycleService.getDatabaseLocation();
      return _jsonOk(location);
    });

    // 24.3 Database Stats
    router.get('/api/v1/database/stats', (Request req) async {
      await _authorizeStaffOrTechnician(
        req,
        requiredStaffPermission: 'settings_Backups',
      );
      final stats = await databaseLifecycleService.getDatabaseStats();
      return _jsonOk({'tables': stats, 'count': stats.length});
    });

    // 24.4 Database Schema
    router.get('/api/v1/database/schema', (Request req) async {
      await _authorizeStaffOrTechnician(
        req,
        requiredStaffPermission: 'settings_Backups',
      );
      final schema = await explorerService.getDatabaseStructure();
      return _jsonOk(schema);
    });

    // 24.5 Full Multi-Artifact Backup
    router.post('/api/v1/database/backup', (Request req) async {
      final access = await _authorizeStaffOrTechnician(
        req,
        requiredStaffPermission: 'settings_Backups',
        requireCanEditForStaff: true,
      );
      final body = await _readJsonBody(req);
      final backup = await databaseLifecycleService.createFullBackupPackage(
        hospitalCode: access.hospitalCode,
        triggerType: access.mode == 'TECHNICIAN_SESSION'
            ? 'SERVICE_TOOL'
            : (body['triggerType'] ?? 'MANUAL_ADMIN').toString(),
        createdByStaffId: access.staffId,
        actorRoleLabel: access.actorRoleLabel,
        deviceId: access.deviceId,
        ipAddress: req.headers['x-forwarded-for'] ?? '127.0.0.1',
        includeZipExport: body['includeZipExport'] != false,
      );
      return _jsonOk(backup, statusCode: 201);
    });

    // 24.6 Multi-Format Export (SQL, CSV, JSON, XLSX, ZIP)
    router.post('/api/v1/database/export', (Request req) async {
      final access = await _authorizeStaffOrTechnician(
        req,
        requiredStaffPermission: 'settings_Backups',
        requireCanEditForStaff: true,
      );
      final exportRes = await databaseLifecycleService.createFullBackupPackage(
        hospitalCode: access.hospitalCode,
        triggerType: 'MANUAL_ADMIN_EXPORT',
        createdByStaffId: access.staffId,
        actorRoleLabel: access.actorRoleLabel,
        deviceId: access.deviceId,
        ipAddress: req.headers['x-forwarded-for'] ?? '127.0.0.1',
        includeZipExport: true,
      );
      return _jsonOk(exportRes, statusCode: 201);
    });

    // 24.7 Verify Backup Package / Archive
    router.post('/api/v1/database/verify', (Request req) async {
      await _authorizeStaffOrTechnician(
        req,
        requiredStaffPermission: 'settings_Backups',
      );
      final body = await _readJsonBody(req);
      final targetPath = (body['backupPath'] ?? body['archiveFilePath'] ?? '').toString().trim();
      if (targetPath.isEmpty) {
        return _jsonError(400, 'MISSING_PATH', 'backupPath or archiveFilePath is required.');
      }
      final expectedSha = body['expectedSha256']?.toString();
      final res = await databaseLifecycleService.verifyBackupPackage(
        backupPackagePath: targetPath,
        expectedSha256: expectedSha,
      );
      return _jsonOk(res);
    });

    // 24.8 Safe Database Restore (Technician Session ONLY)
    router.post('/api/v1/database/restore', (Request req) async {
      final techCtx = await _verifyTechnicianRequest(req);
      final body = await _readJsonBody(req);
      final targetPath = (body['backupPath'] ?? body['archiveFilePath'] ?? '').toString().trim();
      if (targetPath.isEmpty) {
        return _jsonError(400, 'MISSING_PATH', 'backupPath or archiveFilePath is required.');
      }
      final expectedSha = body['expectedSha256']?.toString();
      final res = await databaseLifecycleService.restoreBackup(
        hospitalCode: techCtx.hospitalCode,
        backupPackagePath: targetPath,
        expectedSha256: expectedSha,
        actorRoleLabel: 'TECHNICIAN_SERVICE',
        deviceId: techCtx.deviceId,
        ipAddress: req.headers['x-forwarded-for'] ?? '127.0.0.1',
      );
      return _jsonOk(res);
    });

    // 24.9 True Factory Reset (Technician Session ONLY + "RESET MEDCORE")
    router.post('/api/v1/database/factory-reset', (Request req) async {
      final techCtx = await _verifyTechnicianRequest(req);
      final body = await _readJsonBody(req);
      final confirmation = (body['confirmationText'] ?? '').toString().trim();
      final mandatoryBackup = body['requireMandatoryBackup'] != false;

      final res = await databaseLifecycleService.factoryReset(
        hospitalCode: techCtx.hospitalCode,
        confirmationText: confirmation,
        requireMandatoryBackup: mandatoryBackup,
        actorRoleLabel: 'TECHNICIAN_SERVICE',
        deviceId: techCtx.deviceId,
        ipAddress: req.headers['x-forwarded-for'] ?? '127.0.0.1',
      );
      return _jsonOk(res);
    });

    // 24.10 Rebuild Database (Technician Session ONLY)
    router.post('/api/v1/database/rebuild', (Request req) async {
      final techCtx = await _verifyTechnicianRequest(req);
      final res = await databaseLifecycleService.rebuildDatabase(
        hospitalCode: techCtx.hospitalCode,
      );
      return _jsonOk(res);
    });

    // 24.11 Copy Runtime Files (Technician Session ONLY)
    router.post('/api/v1/database/runtime-files/copy', (Request req) async {
      final techCtx = await _verifyTechnicianRequest(req);
      final body = await _readJsonBody(req);
      final dest = (body['destinationDirectory'] ?? '').toString().trim();
      if (dest.isEmpty) {
        return _jsonError(400, 'MISSING_DESTINATION', 'destinationDirectory is required.');
      }
      final res = await databaseLifecycleService.copyDatabaseRuntimeFiles(
        destinationDirectory: dest,
        hospitalCode: techCtx.hospitalCode,
      );
      return _jsonOk(res);
    });

    return Pipeline().addMiddleware(_errorAndSecurityMiddleware()).addHandler(router.call);
  }

  Middleware _errorAndSecurityMiddleware() {
    return (Handler innerHandler) {
      return (Request req) async {
        try {
          return await innerHandler(req);
        } on AuthException catch (e) {
          return _jsonError(e.statusCode, e.code, e.message);
        } on MaintenanceTokenException catch (e) {
          return _jsonError(403, e.code, e.message);
        } on RbacForbiddenException catch (e) {
          final hosp = req.headers['x-tenant-id'] ?? 'UNKNOWN';
          final devId = req.headers['x-medcore-device-id'];
          await TenantGovernanceRepository(db).logSecurityEvent(
            hospitalCode: hosp,
            deviceId: devId,
            eventType: 'rbac.forbidden.${e.code.toLowerCase()}',
            severity: (e.code == 'SECURE_DEVICE_REQUIRED' || e.code == 'MODULE_NOT_ENTITLED')
                ? 'HIGH'
                : 'WARNING',
            routePath: req.requestedUri.path,
            requiredPermission: e.requiredPermission,
            details: {'message': e.message},
          );
          return _jsonError(403, e.code, e.message);
        } on ArgumentError catch (e) {
          return _jsonError(422, 'VALIDATION_ERROR', e.message?.toString() ?? e.toString());
        } on StateError catch (e) {
          return _jsonError(409, 'DOMAIN_STATE_CONFLICT', e.message);
        } on UnsupportedError catch (e) {
          return _jsonError(501, 'FEATURE_RUNTIME_DEFERRED', e.message ?? e.toString());
        } catch (e) {
          return _jsonError(500, 'INTERNAL_SERVER_ERROR', e.toString());
        }
      };
    };
  }

  Future<TechnicianSessionContext> _verifyTechnicianRequest(Request req) async {
    final techToken = req.headers['x-medcore-tech-token'];
    final hospitalCode = (req.headers['x-tenant-id'] ?? '').trim();
    final deviceId = (req.headers['x-medcore-device-id'] ?? '').trim();
    if (hospitalCode.isEmpty || deviceId.isEmpty) {
      throw AuthException(
        'MISSING_SECURITY_HEADERS',
        'Both X-Tenant-ID and X-MedCore-Device-ID headers are required.',
        401,
      );
    }
    return await technicianService.verifyTechnicianSession(
      rawTechToken: techToken,
      requestedHospitalCode: hospitalCode,
      requestedDeviceId: deviceId,
      routePath: req.requestedUri.path,
      ipAddress: req.headers['x-forwarded-for'] ?? '127.0.0.1',
    );
  }

  Future<_OperationalAccessContext> _authorizeStaffOrTechnician(
    Request req, {
    required String requiredStaffPermission,
    bool requireCanEditForStaff = false,
  }) async {
    final techHeader = (req.headers['x-medcore-tech-token'] ?? '').trim();
    if (techHeader.isNotEmpty) {
      final techCtx = await _verifyTechnicianRequest(req);
      return _OperationalAccessContext(
        hospitalCode: techCtx.hospitalCode,
        deviceId: techCtx.deviceId,
        mode: 'TECHNICIAN_SESSION',
        actorIdentifier: techCtx.sessionUuid,
        actorRoleLabel: 'TECHNICIAN_SERVICE',
      );
    }

    final scope = await _authorize(
      req,
      requiredPermission: requiredStaffPermission,
      requireCanEdit: requireCanEditForStaff,
    );
    return _OperationalAccessContext(
      hospitalCode: scope.hospitalCode,
      deviceId: scope.deviceId,
      mode: 'STAFF_AUTHORIZED',
      actorIdentifier: scope.actor.staffCode,
      actorRoleLabel: scope.actor.role.name,
      staffId: scope.actor.id,
    );
  }

  Future<AuthenticatedRequestContext> _authenticate(Request req) async {
    final token = _extractBearerToken(req);
    if (token == null || token.isEmpty) {
      throw AuthException('MISSING_TOKEN', 'Authorization Bearer token is required.', 401);
    }
    final hospitalCode = (req.headers['x-tenant-id'] ?? '').trim();
    final deviceId = (req.headers['x-medcore-device-id'] ?? '').trim();
    if (hospitalCode.isEmpty || deviceId.isEmpty) {
      throw AuthException(
        'MISSING_SECURITY_HEADERS',
        'Both X-Tenant-ID and X-MedCore-Device-ID headers are required.',
        401,
      );
    }
    return await authService.verifySession(
      rawToken: token,
      requestedHospitalCode: hospitalCode,
      requestedDeviceId: deviceId,
      routePath: req.requestedUri.path,
      ipAddress: req.headers['x-forwarded-for'] ?? '127.0.0.1',
    );
  }

  Future<ScopeContext> _authorize(
    Request req, {
    required String requiredPermission,
    Set<String> tenantSecureLocks = const <String>{},
    bool requireCanEdit = false,
    bool requireCanDelete = false,
    bool requireCanCollectMoney = false,
    bool requireCanMakeRefunds = false,
  }) async {
    final authCtx = await _authenticate(req);
    await facilityConfigService.enforceModuleEntitlement(
      hospitalCode: authCtx.staff.hospitalCode,
      requiredPermission: requiredPermission,
    );
    return RbacEvaluator.enforceAndBuildScope(
      staff: authCtx.staff,
      deviceId: authCtx.device.deviceId,
      isTrustedSecureDevice: authCtx.device.isTrustedSecureRuntime,
      requiredPermission: requiredPermission,
      tenantSecureLocks: tenantSecureLocks,
      requireCanEdit: requireCanEdit,
      requireCanDelete: requireCanDelete,
      requireCanCollectMoney: requireCanCollectMoney,
      requireCanMakeRefunds: requireCanMakeRefunds,
      correlationId: req.headers['x-correlation-id'],
      ipAddress: req.headers['x-forwarded-for'] ?? '127.0.0.1',
    );
  }

  static String? _extractBearerToken(Request req) {
    final auth = req.headers['authorization'] ?? '';
    if (auth.toLowerCase().startsWith('bearer ')) {
      return auth.substring(7).trim();
    }
    return null;
  }

  static Future<Map<String, dynamic>> _readJsonBody(Request req) async {
    final raw = await req.readAsString();
    if (raw.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    return Map<String, dynamic>.from(decoded as Map);
  }

  static Response _jsonOk(Map<String, dynamic> data, {int statusCode = 200}) {
    return Response(
      statusCode,
      body: jsonEncode({'ok': true, 'data': data}),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  static Response _jsonError(int statusCode, String code, String message) {
    return Response(
      statusCode,
      body: jsonEncode({
        'ok': false,
        'error': {'code': code, 'message': message},
      }),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  Future<int> start({String address = '127.0.0.1', int port = 0}) async {
    _httpServer = await shelf_io.serve(handler, address, port);
    return _httpServer!.port;
  }

  Future<void> stop() async {
    await _httpServer?.close(force: true);
    _httpServer = null;
  }
}

class _OperationalAccessContext {
  final String hospitalCode;
  final String deviceId;
  final String mode;
  final String actorIdentifier;
  final String actorRoleLabel;
  final int? staffId;

  const _OperationalAccessContext({
    required this.hospitalCode,
    required this.deviceId,
    required this.mode,
    required this.actorIdentifier,
    required this.actorRoleLabel,
    this.staffId,
  });
}
