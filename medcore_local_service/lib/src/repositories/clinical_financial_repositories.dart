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
        'assignedDoctorId': assignedDoctorId,
        'departmentId': departmentId,
        'balance': balance.toStringAsFixed(4),
        'createdBy': createdBy,
        'isDeleted': isDeleted,
      };
}

class PatientRepository {
  final SqlExecutor db;

  PatientRepository(this.db);

  Future<PatientRecord> createPatient({
    required ScopeContext scope,
    required String mrn,
    required String fullName,
    required String phone,
    String gender = 'male',
    int? assignedDoctorId,
    String? departmentId,
  }) async {
    final res = await db.execute(
      '''
      INSERT INTO mc_patients (
        hospital_code, mrn, full_name, gender, phone,
        assigned_doctor_id, department_id, balance, created_by, is_deleted
      ) VALUES (
        :hosp, :mrn, :name, :gender, :phone,
        :doc_id, :dept, '0.0000', :creator, 0
      )
      ''',
      {
        'hosp': scope.hospitalCode,
        'mrn': mrn,
        'name': fullName,
        'gender': gender,
        'phone': phone,
        'doc_id': assignedDoctorId ?? (scope.actor.role == MedCoreRole.Doctor ? scope.actor.id : null),
        'dept': departmentId ?? scope.actor.departmentId,
        'creator': scope.actor.id,
      },
    );
    final id = res.lastInsertID.toInt();
    return (await findByIdUnscoped(scope.hospitalCode, id))!;
  }

  /// Enforces Dimension 2 (`_all` vs Individual/Own Scope) directly at the SQL query layer!
  Future<List<PatientRecord>> listPatients(ScopeContext scope) async {
    if (scope.isTenantWide) {
      final res = await db.execute(
        '''
        SELECT * FROM mc_patients
        WHERE hospital_code = :hosp AND is_deleted = 0
        ORDER BY id ASC
        ''',
        {'hosp': scope.hospitalCode},
      );
      return res.rows.map(_mapRow).toList();
    } else {
      // Own-only scope: restrict to records assigned to or created by this employee
      final res = await db.execute(
        '''
        SELECT * FROM mc_patients
        WHERE hospital_code = :hosp
          AND is_deleted = 0
          AND (assigned_doctor_id = :actor_id OR created_by = :actor_id)
        ORDER BY id ASC
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
      'SELECT * FROM mc_patients WHERE hospital_code = :hosp AND id = :id LIMIT 1',
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

  PatientRecord _mapRow(dynamic r) {
    return PatientRecord(
      id: int.parse(r.colByName('id') ?? '0'),
      hospitalCode: r.colByName('hospital_code') ?? '',
      mrn: r.colByName('mrn') ?? '',
      fullName: r.colByName('full_name') ?? '',
      gender: r.colByName('gender') ?? 'male',
      phone: r.colByName('phone') ?? '',
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

    // Direct Refund Policy (`RefundPolicy.direct`)
    return await txManager.runInTransaction((tx) async {
      await tx.execute(
        "UPDATE mc_visits SET status = 'REFUNDED' WHERE hospital_code = :hosp AND id = :vid",
        {'hosp': scope.hospitalCode, 'vid': visitId},
      );
      await tx.writeAuditLog(
        hospitalCode: scope.hospitalCode,
        actorStaffId: scope.actor.id,
        actorRole: scope.actor.role.name,
        deviceId: scope.deviceId,
        action: 'refund.direct_executed',
        entityType: 'mc_visits',
        entityId: visitId.toString(),
      );
      return {
        'status': 'EXECUTED_DIRECT',
        'visitId': visitId,
        'refundAmount': refundAmount.toStringAsFixed(4),
      };
    });
  }
}
