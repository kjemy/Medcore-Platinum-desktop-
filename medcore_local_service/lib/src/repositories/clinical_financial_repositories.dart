import 'dart:convert';
import 'package:decimal/decimal.dart';
import 'package:uuid/uuid.dart';
import '../db/db_client.dart';
import '../db/transaction_manager.dart';
import '../security/permissions_catalog.dart';
import '../security/rbac_evaluator.dart';
import 'scope_context.dart';
import 'tenant_governance_repository.dart';

class PatientRecord {
  final int id;
  final String hospitalCode;
  final String mrn;
  final String fullName;
  final String gender;
  final String phone;
  final String? dateOfBirth;
  final int? age;
  final String? nationalId;
  final String? bloodGroup;
  final String? address;
  final String? insuranceCompanyId;
  final String? insurancePolicyNo;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final List<String> allergies;
  final List<String> chronicConditions;
  final Map<String, dynamic> clinicalHistoryMeta;
  final int? assignedDoctorId;
  final String? departmentId;
  final Decimal balance;
  final int? createdBy;
  final bool isDeleted;

  const PatientRecord({
    required this.id,
    required this.hospitalCode,
    required this.mrn,
    required this.fullName,
    required this.gender,
    required this.phone,
    this.dateOfBirth,
    this.age,
    this.nationalId,
    this.bloodGroup,
    this.address,
    this.insuranceCompanyId,
    this.insurancePolicyNo,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.allergies = const <String>[],
    this.chronicConditions = const <String>[],
    this.clinicalHistoryMeta = const <String, dynamic>{},
    this.assignedDoctorId,
    this.departmentId,
    required this.balance,
    this.createdBy,
    required this.isDeleted,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'hospitalCode': hospitalCode,
        'mrn': mrn,
        'fullName': fullName,
        'gender': gender,
        'phone': phone,
        if (dateOfBirth != null) 'dateOfBirth': dateOfBirth,
        if (age != null) 'age': age,
        if (nationalId != null) 'nationalId': nationalId,
        if (bloodGroup != null) 'bloodGroup': bloodGroup,
        if (address != null) 'address': address,
        if (insuranceCompanyId != null) 'insuranceCompanyId': insuranceCompanyId,
        if (insurancePolicyNo != null) 'insurancePolicyNo': insurancePolicyNo,
        if (emergencyContactName != null) 'emergencyContactName': emergencyContactName,
        if (emergencyContactPhone != null) 'emergencyContactPhone': emergencyContactPhone,
        if (allergies.isNotEmpty) 'allergies': allergies,
        if (chronicConditions.isNotEmpty) 'chronicConditions': chronicConditions,
        if (clinicalHistoryMeta.isNotEmpty) 'clinicalHistoryMeta': clinicalHistoryMeta,
        'assignedDoctorId': assignedDoctorId,
        'departmentId': departmentId,
        'balance': balance.toStringAsFixed(4),
        'createdBy': createdBy,
        'isDeleted': isDeleted,
      };
}

class PatientRepository {
  final SqlExecutor db;
  static const _uuid = Uuid();

  PatientRepository(this.db);

  Future<PatientRecord> createPatient({
    required ScopeContext scope,
    required String mrn,
    required String fullName,
    required String phone,
    String gender = 'male',
    String? dateOfBirth,
    int? age,
    String? nationalId,
    String? bloodGroup,
    String? address,
    String? insuranceCompanyId,
    String? insurancePolicyNo,
    String? emergencyContactName,
    String? emergencyContactPhone,
    List<String>? allergies,
    List<String>? chronicConditions,
    Map<String, dynamic>? clinicalHistoryMeta,
    int? assignedDoctorId,
    String? departmentId,
  }) async {
    final res = await db.execute(
      '''
      INSERT INTO mc_patients (
        hospital_code, mrn, full_name, gender, date_of_birth, age, phone,
        national_id, blood_group, address, insurance_company_id, insurance_policy_no,
        assigned_doctor_id, department_id, balance, created_by, is_deleted
      ) VALUES (
        :hosp, :mrn, :name, :gender, :dob, :age, :phone,
        :nat_id, :blood, :addr, :ins_co, :ins_pol,
        :doc_id, :dept, '0.0000', :creator, 0
      )
      ''',
      {
        'hosp': scope.hospitalCode,
        'mrn': mrn,
        'name': fullName,
        'gender': gender,
        'dob': (dateOfBirth != null && dateOfBirth.trim().isNotEmpty) ? dateOfBirth.trim() : null,
        'age': age,
        'phone': phone,
        'nat_id': (nationalId != null && nationalId.trim().isNotEmpty) ? nationalId.trim() : null,
        'blood': (bloodGroup != null && bloodGroup.trim().isNotEmpty) ? bloodGroup.trim() : null,
        'addr': (address != null && address.trim().isNotEmpty) ? address.trim() : null,
        'ins_co': (insuranceCompanyId != null && insuranceCompanyId.trim().isNotEmpty)
            ? insuranceCompanyId.trim()
            : null,
        'ins_pol': (insurancePolicyNo != null && insurancePolicyNo.trim().isNotEmpty)
            ? insurancePolicyNo.trim()
            : null,
        'doc_id': assignedDoctorId ?? (scope.actor.role == MedCoreRole.Doctor ? scope.actor.id : null),
        'dept': departmentId ?? scope.actor.departmentId,
        'creator': scope.actor.id,
      },
    );
    final id = res.lastInsertID.toInt();

    final hasProfileData = (emergencyContactName != null && emergencyContactName.trim().isNotEmpty) ||
        (emergencyContactPhone != null && emergencyContactPhone.trim().isNotEmpty) ||
        (allergies != null && allergies.isNotEmpty) ||
        (chronicConditions != null && chronicConditions.isNotEmpty) ||
        (clinicalHistoryMeta != null && clinicalHistoryMeta.isNotEmpty);

    if (hasProfileData) {
      await db.execute(
        '''
        INSERT INTO mc_patient_profiles (
          hospital_code, public_id, tenant_id, patient_id, date_of_birth,
          emergency_contact_name, emergency_contact_phone, address,
          insurance_provider_id, insurance_policy_number,
          chronic_conditions_json, allergies_json, medical_history_json,
          status, created_at, updated_at
        ) VALUES (
          :hosp, :pub_id, :tenant, :pat_id, :dob,
          :em_name, :em_phone, :addr,
          :ins_co, :ins_pol,
          :chronic_json, :allergies_json, :hist_json,
          'ACTIVE', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        )
        ''',
        {
          'hosp': scope.hospitalCode,
          'pub_id': _uuid.v4(),
          'tenant': scope.hospitalCode,
          'pat_id': id,
          'dob': (dateOfBirth != null && dateOfBirth.trim().isNotEmpty) ? dateOfBirth.trim() : null,
          'em_name': emergencyContactName?.trim(),
          'em_phone': emergencyContactPhone?.trim(),
          'addr': address?.trim(),
          'ins_co': insuranceCompanyId?.trim(),
          'ins_pol': insurancePolicyNo?.trim(),
          'chronic_json': chronicConditions != null ? jsonEncode(chronicConditions) : null,
          'allergies_json': allergies != null ? jsonEncode(allergies) : null,
          'hist_json': clinicalHistoryMeta != null ? jsonEncode(clinicalHistoryMeta) : null,
        },
      );
    }

    return (await findByIdUnscoped(scope.hospitalCode, id))!;
  }

  /// Enforces Dimension 2 (`_all` vs Individual/Own Scope) directly at the SQL query layer!
  Future<List<PatientRecord>> listPatients(ScopeContext scope) async {
    if (scope.isTenantWide) {
      final res = await db.execute(
        '''
        SELECT p.*,
               pp.emergency_contact_name,
               pp.emergency_contact_phone,
               pp.allergies_json,
               pp.chronic_conditions_json,
               pp.medical_history_json
        FROM mc_patients p
        LEFT JOIN mc_patient_profiles pp
          ON pp.hospital_code = p.hospital_code AND pp.patient_id = p.id
        WHERE p.hospital_code = :hosp AND p.is_deleted = 0
        ORDER BY p.id ASC
        ''',
        {'hosp': scope.hospitalCode},
      );
      return res.rows.map(_mapRow).toList();
    } else {
      // Own-only scope: restrict to records assigned to or created by this employee
      final res = await db.execute(
        '''
        SELECT p.*,
               pp.emergency_contact_name,
               pp.emergency_contact_phone,
               pp.allergies_json,
               pp.chronic_conditions_json,
               pp.medical_history_json
        FROM mc_patients p
        LEFT JOIN mc_patient_profiles pp
          ON pp.hospital_code = p.hospital_code AND pp.patient_id = p.id
        WHERE p.hospital_code = :hosp
          AND p.is_deleted = 0
          AND (p.assigned_doctor_id = :actor_id OR p.created_by = :actor_id)
        ORDER BY p.id ASC
        ''',
        {
          'hosp': scope.hospitalCode,
          'actor_id': scope.actor.id,
        },
      );
      return res.rows.map(_mapRow).toList();
    }
  }

  Future<PatientRecord?> findByIdUnscoped(String hospitalCode, int id) async {
    final res = await db.execute(
      '''
      SELECT p.*,
             pp.emergency_contact_name,
             pp.emergency_contact_phone,
             pp.allergies_json,
             pp.chronic_conditions_json,
             pp.medical_history_json
      FROM mc_patients p
      LEFT JOIN mc_patient_profiles pp
        ON pp.hospital_code = p.hospital_code AND pp.patient_id = p.id
      WHERE p.hospital_code = :hosp AND p.id = :id
      LIMIT 1
      ''',
      {'hosp': hospitalCode, 'id': id},
    );
    if (res.rows.isEmpty) return null;
    return _mapRow(res.rows.first);
  }

  Future<void> softDeletePatient({
    required ScopeContext scope,
    required int patientId,
  }) async {
    if (!scope.actor.operationalFlags.canDelete) {
      throw RbacForbiddenException(
        code: 'ACTION_FLAG_DENIED_DELETE',
        message: 'Employee ${scope.actor.staffCode} has canDelete=false.',
        requiredPermission: 'canDelete',
      );
    }
    await db.execute(
      'UPDATE mc_patients SET is_deleted = 1 WHERE hospital_code = :hosp AND id = :id',
      {'hosp': scope.hospitalCode, 'id': patientId},
    );
  }

  static List<String> _decodeStringList(String? rawJson) {
    if (rawJson == null || rawJson.trim().isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is List) return decoded.map((e) => e.toString()).toList();
    } catch (_) {}
    return const <String>[];
  }

  static Map<String, dynamic> _decodeMap(String? rawJson) {
    if (rawJson == null || rawJson.trim().isEmpty) return const <String, dynamic>{};
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return const <String, dynamic>{};
  }

  PatientRecord _mapRow(dynamic r) {
    return PatientRecord(
      id: int.parse(r.colByName('id') ?? '0'),
      hospitalCode: r.colByName('hospital_code') ?? '',
      mrn: r.colByName('mrn') ?? '',
      fullName: r.colByName('full_name') ?? '',
      gender: r.colByName('gender') ?? 'male',
      phone: r.colByName('phone') ?? '',
      dateOfBirth: r.colByName('date_of_birth'),
      age: r.colByName('age') != null ? int.tryParse(r.colByName('age')!) : null,
      nationalId: r.colByName('national_id'),
      bloodGroup: r.colByName('blood_group'),
      address: r.colByName('address'),
      insuranceCompanyId: r.colByName('insurance_company_id'),
      insurancePolicyNo: r.colByName('insurance_policy_no'),
      emergencyContactName: r.colByName('emergency_contact_name'),
      emergencyContactPhone: r.colByName('emergency_contact_phone'),
      allergies: _decodeStringList(r.colByName('allergies_json')),
      chronicConditions: _decodeStringList(r.colByName('chronic_conditions_json')),
      clinicalHistoryMeta: _decodeMap(r.colByName('medical_history_json')),
      assignedDoctorId: r.colByName('assigned_doctor_id') != null
          ? int.tryParse(r.colByName('assigned_doctor_id')!)
          : null,
      departmentId: r.colByName('department_id'),
      balance: Decimal.parse(r.colByName('balance') ?? '0.0000'),
      createdBy: r.colByName('created_by') != null ? int.tryParse(r.colByName('created_by')!) : null,
      isDeleted: (r.colByName('is_deleted') ?? '0') == '1',
    );
  }
}

class ShiftRepository {
  final SqlExecutor db;

  ShiftRepository(this.db);

  Future<Map<String, dynamic>> openShift({
    required ScopeContext scope,
    required String shiftCode,
    required Decimal openingBalance,
  }) async {
    if (!scope.actor.operationalFlags.canCollectMoney) {
      throw RbacForbiddenException(
        code: 'ACTION_FLAG_DENIED_COLLECT_MONEY',
        message: 'Opening a cashier shift requires canCollectMoney=true.',
        requiredPermission: 'canCollectMoney',
      );
    }

    // Ensure cashier does not already have an OPEN shift
    final existing = await db.execute(
      '''
      SELECT id, shift_code FROM mc_shifts
      WHERE hospital_code = :hosp AND cashier_staff_id = :staff_id AND status = 'OPEN'
      LIMIT 1
      ''',
      {'hosp': scope.hospitalCode, 'staff_id': scope.actor.id},
    );
    if (existing.rows.isNotEmpty) {
      throw StateError(
        'Cashier ${scope.actor.staffCode} already has an OPEN shift (${existing.rows.first.colByName('shift_code')}).',
      );
    }

    final res = await db.execute(
      '''
      INSERT INTO mc_shifts (
        hospital_code, shift_code, cashier_staff_id, device_id,
        status, opening_balance, cash_in, cash_out, expected_cash
      ) VALUES (
        :hosp, :code, :staff_id, :dev_id,
        'OPEN', :open_bal, '0.0000', '0.0000', :open_bal
      )
      ''',
      {
        'hosp': scope.hospitalCode,
        'code': shiftCode,
        'staff_id': scope.actor.id,
        'dev_id': scope.deviceId,
        'open_bal': openingBalance.toStringAsFixed(4),
      },
    );
    final id = res.lastInsertID.toInt();
    return {
      'id': id,
      'hospitalCode': scope.hospitalCode,
      'shiftCode': shiftCode,
      'cashierStaffId': scope.actor.id,
      'status': 'OPEN',
      'openingBalance': openingBalance.toStringAsFixed(4),
    };
  }
}

class VisitFinancialService {
  final TransactionManager txManager;
  static const _uuid = Uuid();

  VisitFinancialService(this.txManager);

  /// Demonstrates TASK 1.5 Transaction Boundaries + FIN-001 Monetary Identity + FIN-004 Cost Split:
  /// Executes atomically inside `START TRANSACTION .. COMMIT` with `SELECT ... FOR UPDATE` locks.
  Future<Map<String, dynamic>> createAtomicVisitWithCostSplit({
    required ScopeContext scope,
    required String visitNumber,
    required String idempotencyKey,
    required int patientId,
    required int doctorId,
    required int shiftId,
    required String serviceCode,
    required String serviceName,
    required Decimal serviceLaborGross,
    required Decimal consumableGross,
    required Decimal consumableFifoCost,
    required Decimal discountAmount,
    required Decimal insuranceCoveredAmount,
    required Decimal paidAmount,
    required Decimal doctorCommissionRatePercent,
    bool simulateFailureAfterVisitInsert = false,
  }) async {
    if (paidAmount > Decimal.zero && !scope.actor.operationalFlags.canCollectMoney) {
      throw RbacForbiddenException(
        code: 'ACTION_FLAG_DENIED_COLLECT_MONEY',
        message: 'Collecting visit payment requires canCollectMoney=true.',
        requiredPermission: 'canCollectMoney',
      );
    }

    final totalGross = serviceLaborGross + consumableGross;
    final netAmount = totalGross - discountAmount;
    final patientResp = netAmount - insuranceCoveredAmount;
    final balanceAmount = patientResp - paidAmount;

    // FIN-001 Monetary Identity Validation
    if (discountAmount < Decimal.zero ||
        paidAmount < Decimal.zero ||
        insuranceCoveredAmount < Decimal.zero ||
        balanceAmount < Decimal.zero ||
        (discountAmount + paidAmount + insuranceCoveredAmount + balanceAmount) != totalGross) {
      throw ArgumentError(
        'FIN-001 Financial Equation Mismatch: Discount($discountAmount) + Paid($paidAmount) + Insurance($insuranceCoveredAmount) + Balance($balanceAmount) != Gross($totalGross)',
      );
    }

    // FIN-004 Commission Basis: Calculated strictly on Service/Labor Net (excluding consumables!)
    final serviceNet = serviceLaborGross > discountAmount
        ? (serviceLaborGross - discountAmount)
        : Decimal.zero;
    final commissionAmount =
        ((serviceNet * doctorCommissionRatePercent) / Decimal.fromInt(100)).toDecimal(scaleOnInfinitePrecision: 4);

    return await txManager.runInTransaction((tx) async {
      // 1. Idempotency check inside transaction
      final existing = await tx.execute(
        'SELECT id, visit_number FROM mc_visits WHERE hospital_code = :hosp AND idempotency_key = :idemp LIMIT 1',
        {'hosp': scope.hospitalCode, 'idemp': idempotencyKey},
      );
      if (existing.rows.isNotEmpty) {
        return {
          'idempotentReplay': true,
          'visitId': int.parse(existing.rows.first.colByName('id') ?? '0'),
          'visitNumber': existing.rows.first.colByName('visit_number'),
        };
      }

      // 2. Lock Patient row FOR UPDATE
      final patRes = await tx.selectForUpdate(
        'SELECT id, balance FROM mc_patients WHERE hospital_code = :hosp AND id = :pid AND is_deleted = 0',
        {'hosp': scope.hospitalCode, 'pid': patientId},
      );
      if (patRes.rows.isEmpty) {
        throw StateError('Patient $patientId not found in tenant ${scope.hospitalCode}.');
      }

      // 3. Lock Shift row FOR UPDATE and verify OPEN
      final shiftRes = await tx.selectForUpdate(
        'SELECT id, status, cash_in, expected_cash FROM mc_shifts WHERE hospital_code = :hosp AND id = :sid',
        {'hosp': scope.hospitalCode, 'sid': shiftId},
      );
      if (shiftRes.rows.isEmpty || shiftRes.rows.first.colByName('status') != 'OPEN') {
        throw StateError('FIN-005 Violation: Shift $shiftId is not OPEN.');
      }

      // 4. Insert mc_visits
      final vRes = await tx.execute(
        '''
        INSERT INTO mc_visits (
          hospital_code, visit_number, idempotency_key, patient_id, doctor_id,
          shift_id, status, clinical_status,
          gross_amount, discount_amount, net_amount, insurance_covered_amount,
          patient_responsibility_amount, paid_amount, balance_amount, created_by
        ) VALUES (
          :hosp, :vno, :idemp, :pid, :doc_id,
          :sid, 'ACTIVE', 'WAITING',
          :gross, :disc, :net, :ins,
          :presp, :paid, :bal, :creator
        )
        ''',
        {
          'hosp': scope.hospitalCode,
          'vno': visitNumber,
          'idemp': idempotencyKey,
          'pid': patientId,
          'doc_id': doctorId,
          'sid': shiftId,
          'gross': totalGross.toStringAsFixed(4),
          'disc': discountAmount.toStringAsFixed(4),
          'net': netAmount.toStringAsFixed(4),
          'ins': insuranceCoveredAmount.toStringAsFixed(4),
          'presp': patientResp.toStringAsFixed(4),
          'paid': paidAmount.toStringAsFixed(4),
          'bal': balanceAmount.toStringAsFixed(4),
          'creator': scope.actor.id,
        },
      );
      final visitId = vRes.lastInsertID.toInt();

      // 5. Insert mc_visit_items
      final viRes = await tx.execute(
        '''
        INSERT INTO mc_visit_items (
          hospital_code, visit_id, item_type, service_code, service_name,
          doctor_id, quantity, unit_price, gross_amount, discount_amount, net_amount
        ) VALUES (
          :hosp, :vid, 'SERVICE', :scode, :sname,
          :doc_id, '1.0000', :gross, :gross, :disc, :net
        )
        ''',
        {
          'hosp': scope.hospitalCode,
          'vid': visitId,
          'scode': serviceCode,
          'sname': serviceName,
          'doc_id': doctorId,
          'gross': totalGross.toStringAsFixed(4),
          'disc': discountAmount.toStringAsFixed(4),
          'net': netAmount.toStringAsFixed(4),
        },
      );
      final visitItemId = viRes.lastInsertID.toInt();

      // 6. Insert mc_visit_item_cost_lines (FIN-004: Service Labor vs Consumable Material Split)
      await tx.execute(
        '''
        INSERT INTO mc_visit_item_cost_lines (
          hospital_code, visit_id, visit_item_id, component_type,
          quantity, unit_cost_fifo, total_cost_fifo,
          billed_gross_amount, billed_net_amount, is_commissionable
        ) VALUES (
          :hosp, :vid, :viid, 'SERVICE_LABOR',
          '1.0000', '0.0000', '0.0000',
          :sgross, :snet, 1
        )
        ''',
        {
          'hosp': scope.hospitalCode,
          'vid': visitId,
          'viid': visitItemId,
          'sgross': serviceLaborGross.toStringAsFixed(4),
          'snet': serviceNet.toStringAsFixed(4),
        },
      );

      if (consumableGross > Decimal.zero || consumableFifoCost > Decimal.zero) {
        await tx.execute(
          '''
          INSERT INTO mc_visit_item_cost_lines (
            hospital_code, visit_id, visit_item_id, component_type,
            quantity, unit_cost_fifo, total_cost_fifo,
            billed_gross_amount, billed_net_amount, is_commissionable
          ) VALUES (
            :hosp, :vid, :viid, 'CONSUMABLE_MATERIAL',
            '1.0000', :fifo, :fifo,
            :cgross, :cgross, 0
          )
          ''',
          {
            'hosp': scope.hospitalCode,
            'vid': visitId,
            'viid': visitItemId,
            'fifo': consumableFifoCost.toStringAsFixed(4),
            'cgross': consumableGross.toStringAsFixed(4),
          },
        );
      }

      if (simulateFailureAfterVisitInsert) {
        throw StateError('Simulated mid-transaction failure to verify ACID rollback.');
      }

      // 7. Insert mc_financial_events
      final evUuid = 'EV-${_uuid.v4()}';
      final evRes = await tx.execute(
        '''
        INSERT INTO mc_financial_events (
          event_uuid, hospital_code, idempotency_key, event_type,
          source_module, source_entity_type, source_entity_id, shift_id,
          gross_amount, discount_amount, net_amount, paid_amount,
          insurance_covered_amount, patient_responsibility_amount, balance_amount,
          commission_basis_type, commission_basis_amount, commission_rate, commission_amount,
          status, created_by
        ) VALUES (
          :uuid, :hosp, :idemp, 'VISIT_CREATE',
          'RECEPTION', 'VISIT', :vid, :sid,
          :gross, :disc, :net, :paid,
          :ins, :presp, :bal,
          'SERVICE_NET_ONLY', :cbasis, :crate, :camt,
          'POSTED', :creator
        )
        ''',
        {
          'uuid': evUuid,
          'hosp': scope.hospitalCode,
          'idemp': idempotencyKey,
          'vid': visitId,
          'sid': shiftId,
          'gross': totalGross.toStringAsFixed(4),
          'disc': discountAmount.toStringAsFixed(4),
          'net': netAmount.toStringAsFixed(4),
          'paid': paidAmount.toStringAsFixed(4),
          'ins': insuranceCoveredAmount.toStringAsFixed(4),
          'presp': patientResp.toStringAsFixed(4),
          'bal': balanceAmount.toStringAsFixed(4),
          'cbasis': serviceNet.toStringAsFixed(4),
          'crate': doctorCommissionRatePercent.toStringAsFixed(4),
          'camt': commissionAmount.toStringAsFixed(4),
          'creator': scope.actor.id,
        },
      );
      final eventId = evRes.lastInsertID.toInt();

      // 8. Insert Balanced Double-Entry Postings (SUM(DEBIT) == SUM(CREDIT))
      Future<void> postLeg(String type, String bucket, String dir, Decimal amt, {int? benId}) async {
        if (amt <= Decimal.zero) return;
        await tx.execute(
          '''
          INSERT INTO mc_financial_postings (
            posting_uuid, hospital_code, event_id, posting_type,
            account_bucket, direction, amount, beneficiary_type, beneficiary_id, shift_id, status
          ) VALUES (
            :puuid, :hosp, :evid, :ptype,
            :bucket, :dir, :amt, :btype, :bid, :sid, 'POSTED'
          )
          ''',
          {
            'puuid': 'POST-${_uuid.v4()}',
            'hosp': scope.hospitalCode,
            'evid': eventId,
            'ptype': type,
            'bucket': bucket,
            'dir': dir,
            'amt': amt.toStringAsFixed(4),
            'btype': benId != null ? 'DOCTOR' : null,
            'bid': benId,
            'sid': shiftId,
          },
        );
      }

      await postLeg('REVENUE_SERVICE', 'REVENUE_SERVICE_LABOR', 'CREDIT', serviceLaborGross);
      await postLeg('REVENUE_CONSUMABLES', 'REVENUE_CONSUMABLES_BILLED', 'CREDIT', consumableGross);
      await postLeg('DISCOUNT', 'CONTRA_REVENUE_DISCOUNT', 'DEBIT', discountAmount);
      await postLeg('CASH_IN', 'CASH_ON_HAND', 'DEBIT', paidAmount);
      await postLeg('PATIENT_AR', 'ACCOUNTS_RECEIVABLE_PATIENT', 'DEBIT', balanceAmount);
      await postLeg('INSURANCE_AR', 'ACCOUNTS_RECEIVABLE_INSURANCE', 'DEBIT', insuranceCoveredAmount);
      await postLeg('COGS_CONSUMABLES', 'EXPENSE_COGS_CONSUMABLES', 'DEBIT', consumableFifoCost);
      await postLeg('INVENTORY_RELIEF', 'ASSET_INVENTORY_STOCK', 'CREDIT', consumableFifoCost);
      await postLeg('COMMISSION_EXPENSE', 'EXPENSE_DOCTOR_COMMISSION', 'DEBIT', commissionAmount, benId: doctorId);
      await postLeg('COMMISSION_ACCRUAL', 'PAYABLE_COMMISSION_DOCTOR', 'CREDIT', commissionAmount, benId: doctorId);

      // 9. Update Shift Cash-In & Patient Balance
      if (paidAmount > Decimal.zero) {
        await tx.execute(
          '''
          UPDATE mc_shifts
          SET cash_in = cash_in + :paid, expected_cash = expected_cash + :paid
          WHERE id = :sid
          ''',
          {'paid': paidAmount.toStringAsFixed(4), 'sid': shiftId},
        );
      }
      if (balanceAmount > Decimal.zero) {
        await tx.execute(
          'UPDATE mc_patients SET balance = balance + :bal WHERE id = :pid',
          {'bal': balanceAmount.toStringAsFixed(4), 'pid': patientId},
        );
      }

      // 10. Write Audit Log inside the exact same transaction
      await tx.writeAuditLog(
        hospitalCode: scope.hospitalCode,
        actorStaffId: scope.actor.id,
        actorRole: scope.actor.role.name,
        deviceId: scope.deviceId,
        action: 'visit.create',
        entityType: 'mc_visits',
        entityId: visitId.toString(),
        afterState: {
          'visitNumber': visitNumber,
          'totalGross': totalGross.toStringAsFixed(4),
          'serviceNet': serviceNet.toStringAsFixed(4),
          'commissionAmount': commissionAmount.toStringAsFixed(4),
        },
      );

      return {
        'idempotentReplay': false,
        'visitId': visitId,
        'eventId': eventId,
        'visitNumber': visitNumber,
        'totalGross': totalGross.toStringAsFixed(4),
        'serviceLaborNet': serviceNet.toStringAsFixed(4),
        'consumableGross': consumableGross.toStringAsFixed(4),
        'commissionAmount': commissionAmount.toStringAsFixed(4),
      };
    });
  }

  /// Demonstrates Refund Policy Enforcement (`none` | `approval` | `direct`):
  Future<Map<String, dynamic>> initiateRefund({
    required ScopeContext scope,
    required int visitId,
    required Decimal refundAmount,
    required String reason,
    int? shiftId,
  }) async {
    final flags = scope.actor.operationalFlags;
    if (!flags.canMakeRefunds || flags.refundPolicy == RefundPolicy.none) {
      throw RbacForbiddenException(
        code: 'REFUND_POLICY_DENIED',
        message: 'Employee ${scope.actor.staffCode} has refundPolicy=${flags.refundPolicy.name}.',
        requiredPermission: 'canMakeRefunds',
      );
    }

    if (flags.refundPolicy == RefundPolicy.approval) {
      return await txManager.runInTransaction((tx) async {
        final govRepo = TenantGovernanceRepository(tx);
        final reqUuid = 'DCR-${_uuid.v4()}';
        final reqId = await govRepo.createDualControlRequest(
          requestUuid: reqUuid,
          hospitalCode: scope.hospitalCode,
          actionType: 'VISIT_REFUND',
          targetEntityType: 'mc_visits',
          targetEntityId: visitId.toString(),
          requestedAmountDecimal: refundAmount.toStringAsFixed(4),
          payload: {
            'visitId': visitId,
            'refundAmount': refundAmount.toStringAsFixed(4),
            'reason': reason,
            if (shiftId != null) 'shiftId': shiftId,
          },
          requesterStaffId: scope.actor.id,
          reason: reason,
        );
        await tx.writeAuditLog(
          hospitalCode: scope.hospitalCode,
          actorStaffId: scope.actor.id,
          actorRole: scope.actor.role.name,
          deviceId: scope.deviceId,
          action: 'refund.request_approval',
          entityType: 'mc_dual_control_request',
          entityId: reqId.toString(),
        );
        return {
          'status': 'PENDING_APPROVAL',
          'dualControlRequestId': reqId,
          'requestUuid': reqUuid,
        };
      });
    }

    // Direct Refund Policy (`RefundPolicy.direct`) — Batch 1 Full Authoritative Reversal
    return await txManager.runInTransaction((tx) async {
      return await executeRefundReversalInternal(
        tx: tx,
        scope: scope,
        visitId: visitId,
        refundAmount: refundAmount,
        reason: reason,
        shiftId: shiftId,
      );
    });
  }

  /// Atomically executes full double-entry financial reversal for a refunded visit (Batch 1).
  /// Reverses every original posting symmetrically (DEBIT <-> CREDIT) to guarantee SUM(DEBIT) == SUM(CREDIT).
  /// Updates shift cash_out/expected_cash and patient AR balance.
  static Future<Map<String, dynamic>> executeRefundReversalInternal({
    required TxContext tx,
    required ScopeContext scope,
    required int visitId,
    required Decimal refundAmount,
    required String reason,
    int? shiftId,
    String? idempotencyKey,
  }) async {
    final vRes = await tx.execute(
      '''
      SELECT id, hospital_code, visit_number, patient_id, shift_id,
             status, gross_amount, net_amount, paid_amount, balance_amount
      FROM mc_visits
      WHERE hospital_code = :hosp AND id = :vid
      FOR UPDATE
      ''',
      {'hosp': scope.hospitalCode, 'vid': visitId},
    );
    if (vRes.rows.isEmpty) {
      throw StateError('VISIT_NOT_FOUND: Visit $visitId not found in tenant ${scope.hospitalCode}.');
    }
    final visitRow = vRes.rows.first;
    final currentStatus = visitRow.colByName('status') ?? 'ACTIVE';
    if (currentStatus == 'REFUNDED') {
      throw StateError('VISIT_ALREADY_REFUNDED: Visit $visitId is already refunded.');
    }
    if (currentStatus == 'CANCELLED') {
      throw StateError('VISIT_NOT_REFUNDABLE: Visit $visitId is cancelled.');
    }

    final patientId = int.tryParse(visitRow.colByName('patient_id') ?? '0') ?? 0;
    final origVisitShiftId = int.tryParse(visitRow.colByName('shift_id') ?? '0');
    final activeShiftId = shiftId ?? origVisitShiftId;

    // Fetch original financial event
    final evRes = await tx.execute(
      '''
      SELECT id, event_uuid, gross_amount, discount_amount, net_amount,
             paid_amount, insurance_covered_amount, patient_responsibility_amount,
             balance_amount, commission_basis_type, commission_basis_amount,
             commission_rate, commission_amount, shift_id
      FROM mc_financial_events
      WHERE hospital_code = :hosp
        AND source_entity_type = 'VISIT'
        AND source_entity_id = :vid
        AND event_type = 'VISIT_CREATE'
      ORDER BY id ASC
      LIMIT 1
      FOR UPDATE
      ''',
      {'hosp': scope.hospitalCode, 'vid': visitId},
    );

    int? revEventId;
    if (evRes.rows.isNotEmpty) {
      final origEvent = evRes.rows.first;
      final origEventId = int.parse(origEvent.colByName('id')!);
      final origPaid = Decimal.tryParse(origEvent.colByName('paid_amount') ?? '0.0000') ?? Decimal.zero;
      final origBal = Decimal.tryParse(origEvent.colByName('balance_amount') ?? '0.0000') ?? Decimal.zero;

      // 1. Fetch original postings
      final postRes = await tx.execute(
        '''
        SELECT id, posting_type, account_bucket, direction, amount,
               beneficiary_type, beneficiary_id, shift_id
        FROM mc_financial_postings
        WHERE hospital_code = :hosp AND event_id = :evid
        ''',
        {'hosp': scope.hospitalCode, 'evid': origEventId},
      );

      // 2. Insert reversing financial event
      final revEventUuid = 'EV-REV-${_uuid.v4()}';
      final actualIdemp = idempotencyKey ?? 'REFUND-VIS-$visitId-${_uuid.v4()}';
      final insEvRes = await tx.execute(
        '''
        INSERT INTO mc_financial_events (
          event_uuid, hospital_code, idempotency_key, event_type,
          source_module, source_entity_type, source_entity_id, shift_id,
          gross_amount, discount_amount, net_amount, paid_amount,
          insurance_covered_amount, patient_responsibility_amount, balance_amount,
          commission_basis_type, commission_basis_amount, commission_rate, commission_amount,
          reversal_of_event_id, status, created_by
        ) VALUES (
          :uuid, :hosp, :idemp, 'VISIT_REFUND',
          'RECEPTION', 'VISIT', :vid, :sid,
          :gross, :disc, :net, :paid,
          :ins, :presp, :bal,
          :cbasis, :camt_basis, :crate, :camt,
          :orig_evid, 'POSTED', :creator
        )
        ''',
        {
          'uuid': revEventUuid,
          'hosp': scope.hospitalCode,
          'idemp': actualIdemp,
          'vid': visitId,
          'sid': activeShiftId,
          'gross': origEvent.colByName('gross_amount') ?? '0.0000',
          'disc': origEvent.colByName('discount_amount') ?? '0.0000',
          'net': origEvent.colByName('net_amount') ?? '0.0000',
          'paid': origEvent.colByName('paid_amount') ?? '0.0000',
          'ins': origEvent.colByName('insurance_covered_amount') ?? '0.0000',
          'presp': origEvent.colByName('patient_responsibility_amount') ?? '0.0000',
          'bal': origEvent.colByName('balance_amount') ?? '0.0000',
          'cbasis': origEvent.colByName('commission_basis_type'),
          'camt_basis': origEvent.colByName('commission_basis_amount') ?? '0.0000',
          'crate': origEvent.colByName('commission_rate') ?? '0.0000',
          'camt': origEvent.colByName('commission_amount') ?? '0.0000',
          'orig_evid': origEventId,
          'creator': scope.actor.id,
        },
      );
      revEventId = insEvRes.lastInsertID.toInt();

      // 3. Insert symmetric reversal postings: invert CREDIT <-> DEBIT
      for (final pRow in postRes.rows) {
        final origDir = pRow.colByName('direction') ?? 'CREDIT';
        final revDir = origDir == 'CREDIT' ? 'DEBIT' : 'CREDIT';
        final pAmt = pRow.colByName('amount') ?? '0.0000';
        final origType = pRow.colByName('posting_type') ?? 'GENERIC';
        final revType = origType.startsWith('REVERSAL_') ? origType : 'REVERSAL_$origType';

        await tx.execute(
          '''
          INSERT INTO mc_financial_postings (
            posting_uuid, hospital_code, event_id, posting_type,
            account_bucket, direction, amount, beneficiary_type, beneficiary_id, shift_id, status
          ) VALUES (
            :puuid, :hosp, :evid, :ptype,
            :bucket, :dir, :amt, :btype, :bid, :sid, 'POSTED'
          )
          ''',
          {
            'puuid': 'POST-REV-${_uuid.v4()}',
            'hosp': scope.hospitalCode,
            'evid': revEventId,
            'ptype': revType,
            'bucket': pRow.colByName('account_bucket') ?? 'REVENUE',
            'dir': revDir,
            'amt': pAmt,
            'btype': pRow.colByName('beneficiary_type'),
            'bid': pRow.colByName('beneficiary_id') != null ? int.tryParse(pRow.colByName('beneficiary_id')!) : null,
            'sid': activeShiftId,
          },
        );
      }

      // 4. Update Shift cash outflow if visit was paid in cash
      if (origPaid > Decimal.zero && activeShiftId != null) {
        await tx.execute(
          '''
          UPDATE mc_shifts
          SET cash_out = cash_out + :paid, expected_cash = expected_cash - :paid
          WHERE hospital_code = :hosp AND id = :sid AND status = 'OPEN'
          ''',
          {
            'hosp': scope.hospitalCode,
            'sid': activeShiftId,
            'paid': origPaid.toStringAsFixed(4),
          },
        );
      }

      // 5. Update Patient balance if visit had outstanding AR
      if (origBal > Decimal.zero && patientId > 0) {
        await tx.execute(
          '''
          UPDATE mc_patients
          SET balance = balance - :bal
          WHERE hospital_code = :hosp AND id = :pid
          ''',
          {
            'hosp': scope.hospitalCode,
            'pid': patientId,
            'bal': origBal.toStringAsFixed(4),
          },
        );
      }
    }

    // 6. Transition visit status to REFUNDED
    await tx.execute(
      "UPDATE mc_visits SET status = 'REFUNDED' WHERE hospital_code = :hosp AND id = :vid",
      {'hosp': scope.hospitalCode, 'vid': visitId},
    );

    // 7. Write audit log
    await tx.writeAuditLog(
      hospitalCode: scope.hospitalCode,
      actorStaffId: scope.actor.id,
      actorRole: scope.actor.role.name,
      deviceId: scope.deviceId,
      action: 'refund.direct_executed',
      entityType: 'mc_visits',
      entityId: visitId.toString(),
      afterState: {
        'status': 'REFUNDED',
        'refundAmount': refundAmount.toStringAsFixed(4),
        'reason': reason,
        if (revEventId != null) 'reversalEventId': revEventId,
      },
    );

    return {
      'status': 'EXECUTED_DIRECT',
      'visitId': visitId,
      'refundAmount': refundAmount.toStringAsFixed(4),
      if (revEventId != null) 'reversalEventId': revEventId,
    };
  }

  /// Standalone PATIENT_AR Collection (Batch 2):
  /// Allows collecting debt post-visit from a patient into an active cashier shift.
  /// Postings: DEBIT CASH_ON_HAND / CREDIT ACCOUNTS_RECEIVABLE_PATIENT
  /// Invariant: SUM(DEBIT) == SUM(CREDIT)
  Future<Map<String, dynamic>> collectPatientAr({
    required ScopeContext scope,
    required int patientId,
    required Decimal amount,
    required int shiftId,
    required String paymentMethod,
    String? idempotencyKey,
    String? notes,
  }) async {
    if (amount <= Decimal.zero) {
      throw StateError('INVALID_COLLECTION_AMOUNT: Amount must be strictly greater than 0.');
    }

    final actualIdemp = idempotencyKey ?? 'AR-COLL-$patientId-${_uuid.v4()}';

    return await txManager.runInTransaction((tx) async {
      // 1. Idempotency check
      final existingRes = await tx.execute(
        '''
        SELECT id, event_uuid, gross_amount, paid_amount, balance_amount
        FROM mc_financial_events
        WHERE hospital_code = :hosp AND idempotency_key = :idemp
        LIMIT 1
        ''',
        {'hosp': scope.hospitalCode, 'idemp': actualIdemp},
      );
      if (existingRes.rows.isNotEmpty) {
        final row = existingRes.rows.first;
        return {
          'idempotentReplay': true,
          'eventId': int.parse(row.colByName('id')!),
          'eventUuid': row.colByName('event_uuid'),
          'collectedAmount': row.colByName('paid_amount'),
          'remainingBalance': row.colByName('balance_amount'),
        };
      }

      // 2. Lock and verify shift is OPEN
      final shiftRes = await tx.execute(
        '''
        SELECT id, status, cashier_staff_id, expected_cash
        FROM mc_shifts
        WHERE hospital_code = :hosp AND id = :sid
        FOR UPDATE
        ''',
        {'hosp': scope.hospitalCode, 'sid': shiftId},
      );
      if (shiftRes.rows.isEmpty) {
        throw StateError('SHIFT_NOT_FOUND: Shift $shiftId not found in tenant ${scope.hospitalCode}.');
      }
      if (shiftRes.rows.first.colByName('status') != 'OPEN') {
        throw StateError('SHIFT_NOT_OPEN: Cannot collect AR into closed shift $shiftId.');
      }

      // 3. Lock and verify patient balance
      final patRes = await tx.execute(
        '''
        SELECT id, mrn, full_name, balance
        FROM mc_patients
        WHERE hospital_code = :hosp AND id = :pid
        FOR UPDATE
        ''',
        {'hosp': scope.hospitalCode, 'pid': patientId},
      );
      if (patRes.rows.isEmpty) {
        throw StateError('PATIENT_NOT_FOUND: Patient $patientId not found in tenant ${scope.hospitalCode}.');
      }
      final currentBalance = Decimal.tryParse(patRes.rows.first.colByName('balance') ?? '0.0000') ?? Decimal.zero;
      if (amount > currentBalance) {
        throw StateError('OVER_COLLECTION_DENIED: Requested collection of $amount exceeds outstanding balance $currentBalance.');
      }

      final newBalance = currentBalance - amount;

      // 4. Create financial event
      final eventUuid = 'EV-AR-${_uuid.v4()}';
      final evRes = await tx.execute(
        '''
        INSERT INTO mc_financial_events (
          event_uuid, hospital_code, idempotency_key, event_type,
          source_module, source_entity_type, source_entity_id, shift_id,
          gross_amount, discount_amount, net_amount, paid_amount,
          insurance_covered_amount, patient_responsibility_amount, balance_amount,
          status, created_by
        ) VALUES (
          :uuid, :hosp, :idemp, 'AR_COLLECTION',
          'FINANCE', 'PATIENT', :pid, :sid,
          :amt, '0.0000', :amt, :amt,
          '0.0000', :amt, :bal,
          'POSTED', :creator
        )
        ''',
        {
          'uuid': eventUuid,
          'hosp': scope.hospitalCode,
          'idemp': actualIdemp,
          'pid': patientId,
          'sid': shiftId,
          'amt': amount.toStringAsFixed(4),
          'bal': newBalance.toStringAsFixed(4),
          'creator': scope.actor.id,
        },
      );
      final eventId = evRes.lastInsertID.toInt();

      // 5. Insert Balanced Double-Entry Postings (SUM(DEBIT) == SUM(CREDIT))
      // Leg 1: Cash/Payment Inflow (DEBIT CASH_ON_HAND)
      await tx.execute(
        '''
        INSERT INTO mc_financial_postings (
          posting_uuid, hospital_code, event_id, posting_type,
          account_bucket, direction, amount, shift_id, status
        ) VALUES (
          :puuid, :hosp, :evid, 'AR_COLLECTION_CASH',
          'CASH_ON_HAND', 'DEBIT', :amt, :sid, 'POSTED'
        )
        ''',
        {
          'puuid': 'POST-AR-CASH-${_uuid.v4()}',
          'hosp': scope.hospitalCode,
          'evid': eventId,
          'amt': amount.toStringAsFixed(4),
          'sid': shiftId,
        },
      );

      // Leg 2: AR Asset Relief (CREDIT ACCOUNTS_RECEIVABLE_PATIENT)
      await tx.execute(
        '''
        INSERT INTO mc_financial_postings (
          posting_uuid, hospital_code, event_id, posting_type,
          account_bucket, direction, amount, shift_id, status
        ) VALUES (
          :puuid, :hosp, :evid, 'AR_COLLECTION_RELIEF',
          'ACCOUNTS_RECEIVABLE_PATIENT', 'CREDIT', :amt, :sid, 'POSTED'
        )
        ''',
        {
          'puuid': 'POST-AR-RELIEF-${_uuid.v4()}',
          'hosp': scope.hospitalCode,
          'evid': eventId,
          'amt': amount.toStringAsFixed(4),
          'sid': shiftId,
        },
      );

      // 6. Update Shift Cash
      await tx.execute(
        '''
        UPDATE mc_shifts
        SET cash_in = cash_in + :amt, expected_cash = expected_cash + :amt
        WHERE hospital_code = :hosp AND id = :sid
        ''',
        {
          'hosp': scope.hospitalCode,
          'sid': shiftId,
          'amt': amount.toStringAsFixed(4),
        },
      );

      // 7. Update Patient Balance
      await tx.execute(
        '''
        UPDATE mc_patients
        SET balance = :bal
        WHERE hospital_code = :hosp AND id = :pid
        ''',
        {
          'hosp': scope.hospitalCode,
          'pid': patientId,
          'bal': newBalance.toStringAsFixed(4),
        },
      );

      // 8. Write Audit Log
      await tx.writeAuditLog(
        hospitalCode: scope.hospitalCode,
        actorStaffId: scope.actor.id,
        actorRole: scope.actor.role.name,
        deviceId: scope.deviceId,
        action: 'ar.collection',
        entityType: 'mc_financial_events',
        entityId: eventId.toString(),
        afterState: {
          'patientId': patientId,
          'collectedAmount': amount.toStringAsFixed(4),
          'remainingBalance': newBalance.toStringAsFixed(4),
          'shiftId': shiftId,
          'paymentMethod': paymentMethod,
          'notes': notes,
        },
      );

      return {
        'idempotentReplay': false,
        'eventId': eventId,
        'eventUuid': eventUuid,
        'patientId': patientId,
        'collectedAmount': amount.toStringAsFixed(4),
        'remainingBalance': newBalance.toStringAsFixed(4),
        'shiftId': shiftId,
      };
    });
  }
}
