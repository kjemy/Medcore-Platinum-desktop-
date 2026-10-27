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
import '../security/password_hasher.dart';
import '../security/permissions_catalog.dart';
import '../security/rbac_evaluator.dart';
import '../explorer/data_explorer_service.dart';

class LocalMedCoreServer {
  final DbClient db;
  final DateTime Function()? clock;
  final Duration clockDriftTolerance;
  final String? securityRootDirectory;
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
  HttpServer? _httpServer;

  LocalMedCoreServer(
    this.db, {
    this.clock,
    this.clockDriftTolerance = const Duration(seconds: 5),
    this.securityRootDirectory,
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
    dualControlRepo = DualControlRepository(txManager);
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
      final repo = PatientRepository(db);
      final pat = await repo.createPatient(
        scope: scope,
        mrn: body['mrn'].toString(),
        fullName: body['fullName'].toString(),
        phone: body['phone'].toString(),
        gender: (body['gender'] ?? 'male').toString(),
        assignedDoctorId: body['assignedDoctorId'] != null ? int.parse(body['assignedDoctorId'].toString()) : null,
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
        refundAmount: Decimal.parse((body['refundAmount'] ?? '0.0000').toString()),
        reason: (body['reason'] ?? 'Customer refund request').toString(),
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
      final scope = await _authorize(req, requiredPermission: 'lab_Dashboard');
      final params = req.requestedUri.queryParameters;
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

    return Pipeline().addMiddleware(_errorAndSecurityMiddleware()).addHandler(router.call);
  }

  Middleware _errorAndSecurityMiddleware() {
    return (Handler innerHandler) {
      return (Request req) async {
        try {
          return await innerHandler(req);
        } on AuthException catch (e) {
          return _jsonError(e.statusCode, e.code, e.message);
        } on RbacForbiddenException catch (e) {
          final hosp = req.headers['x-tenant-id'] ?? 'UNKNOWN';
          final devId = req.headers['x-medcore-device-id'];
          await TenantGovernanceRepository(db).logSecurityEvent(
            hospitalCode: hosp,
            deviceId: devId,
            eventType: 'rbac.forbidden.${e.code.toLowerCase()}',
            severity: e.code == 'SECURE_DEVICE_REQUIRED' ? 'HIGH' : 'WARNING',
            routePath: req.requestedUri.path,
            requiredPermission: e.requiredPermission,
            details: {'message': e.message},
          );
          return _jsonError(403, e.code, e.message);
        } on ArgumentError catch (e) {
          return _jsonError(422, 'VALIDATION_ERROR', e.message?.toString() ?? e.toString());
        } on StateError catch (e) {
          return _jsonError(409, 'DOMAIN_STATE_CONFLICT', e.message);
        } catch (e) {
          return _jsonError(500, 'INTERNAL_SERVER_ERROR', e.toString());
        }
      };
    };
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
