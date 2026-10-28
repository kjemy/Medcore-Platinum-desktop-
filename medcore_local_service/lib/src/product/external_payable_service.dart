import 'package:decimal/decimal.dart';
import 'package:uuid/uuid.dart';
import '../db/db_client.dart';
import '../db/transaction_manager.dart';

class ExternalPayableRecord {
  final int id;
  final String hospitalCode;
  final String payableUuid;
  final String partyType; // 'LAB' | 'CLINIC' | 'CONSULTANT' | 'REFERRAL'
  final String partyCode;
  final String partyName;
  final int sourceVisitId;
  final int sourceEventId;
  final Decimal grossAmount;
  final Decimal allocatedAmount;
  final Decimal paidAmount;
  final Decimal balanceAmount;
  final String status; // 'PENDING' | 'PARTIAL' | 'SETTLED' | 'REVERSED'
  final String? notes;
  final DateTime createdAt;

  const ExternalPayableRecord({
    required this.id,
    required this.hospitalCode,
    required this.payableUuid,
    required this.partyType,
    required this.partyCode,
    required this.partyName,
    required this.sourceVisitId,
    required this.sourceEventId,
    required this.grossAmount,
    required this.allocatedAmount,
    required this.paidAmount,
    required this.balanceAmount,
    required this.status,
    this.notes,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'hospitalCode': hospitalCode,
        'payableUuid': payableUuid,
        'partyType': partyType,
        'partyCode': partyCode,
        'partyName': partyName,
        'sourceVisitId': sourceVisitId,
        'sourceEventId': sourceEventId,
        'grossAmount': grossAmount.toString(),
        'allocatedAmount': allocatedAmount.toString(),
        'paidAmount': paidAmount.toString(),
        'balanceAmount': balanceAmount.toString(),
        'status': status,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
      };
}

class ExternalPayableService {
  final TransactionManager txManager;
  static const _uuid = Uuid();

  ExternalPayableService(this.txManager);

  /// Allocates a deterministic payable to an external third-party (e.g. outsourced laboratory or external clinic)
  /// within an explicit ACID transaction, creating balanced double-entry postings in the canonical ledger.
  Future<ExternalPayableRecord> allocatePayable({
    required String hospitalCode,
    required int sourceVisitId,
    required int sourceEventId,
    required String partyType,
    required String partyCode,
    required String partyName,
    required Decimal grossAmount,
    required Decimal allocatedAmount,
    int? shiftId,
    int? actorStaffId,
    String? notes,
  }) async {
    if (allocatedAmount <= Decimal.zero) {
      throw ArgumentError('Allocated amount must be positive.');
    }
    if (allocatedAmount > grossAmount) {
      throw ArgumentError('Allocated amount cannot exceed gross service amount.');
    }

    return await txManager.runInTransaction((tx) async {
      final payableUuid = 'EPAY-${_uuid.v4()}';

      // 1. Persist external payable record
      final res = await tx.execute(
        '''
        INSERT INTO mc_external_payables (
          hospital_code, payable_uuid, party_type, party_code, party_name,
          source_visit_id, source_event_id, gross_amount, allocated_amount,
          paid_amount, balance_amount, status, notes
        ) VALUES (
          :hosp, :uuid, :ptype, :pcode, :pname,
          :vid, :eid, :gross, :alloc,
          0.0000, :alloc, 'PENDING', :notes
        )
        ''',
        {
          'hosp': hospitalCode,
          'uuid': payableUuid,
          'ptype': partyType,
          'pcode': partyCode,
          'pname': partyName,
          'vid': sourceVisitId,
          'eid': sourceEventId,
          'gross': grossAmount.toString(),
          'alloc': allocatedAmount.toString(),
          'notes': notes,
        },
      );
      final payableId = res.lastInsertID.toInt();

      // 2. Post balanced ledger entries for external payable sub-ledger:
      // DEBIT: HOSPITAL_REVENUE (Allocation of revenue to external partner)
      // CREDIT: EXTERNAL_LAB_PAYABLE or EXTERNAL_CLINIC_PAYABLE
      final bucket = partyType == 'LAB'
          ? 'EXTERNAL_LAB_PAYABLE'
          : partyType == 'CLINIC'
              ? 'EXTERNAL_CLINIC_PAYABLE'
              : 'EXTERNAL_PARTY_PAYABLE';

      final debitPostUuid = 'PST-${_uuid.v4()}';
      final creditPostUuid = 'PST-${_uuid.v4()}';

      await tx.execute(
        '''
        INSERT INTO mc_financial_postings (
          posting_uuid, hospital_code, event_id, posting_type, account_bucket,
          direction, amount, beneficiary_type, beneficiary_id, shift_id, status
        ) VALUES (
          :uuid, :hosp, :eid, 'REVENUE_SPLIT_ALLOCATION', 'HOSPITAL_REVENUE',
          'DEBIT', :amt, :btype, :bid, :shift, 'POSTED'
        )
        ''',
        {
          'uuid': debitPostUuid,
          'hosp': hospitalCode,
          'eid': sourceEventId,
          'amt': allocatedAmount.toString(),
          'btype': partyType,
          'bid': payableId,
          'shift': shiftId,
        },
      );

      await tx.execute(
        '''
        INSERT INTO mc_financial_postings (
          posting_uuid, hospital_code, event_id, posting_type, account_bucket,
          direction, amount, beneficiary_type, beneficiary_id, shift_id, status
        ) VALUES (
          :uuid, :hosp, :eid, 'EXTERNAL_PAYABLE_ACCRUAL', :bucket,
          'CREDIT', :amt, :btype, :bid, :shift, 'POSTED'
        )
        ''',
        {
          'uuid': creditPostUuid,
          'hosp': hospitalCode,
          'eid': sourceEventId,
          'bucket': bucket,
          'amt': allocatedAmount.toString(),
          'btype': partyType,
          'bid': payableId,
          'shift': shiftId,
        },
      );

      // Audit log
      await tx.writeAuditLog(
        hospitalCode: hospitalCode,
        actorStaffId: actorStaffId,
        action: 'billing.external_payable.allocated',
        entityType: 'mc_external_payables',
        entityId: payableUuid,
        afterState: {
          'payableId': payableId,
          'partyType': partyType,
          'partyCode': partyCode,
          'allocatedAmount': allocatedAmount.toString(),
          'sourceVisitId': sourceVisitId,
        },
      );

      return (await findByIdInTx(tx, hospitalCode, payableId))!;
    });
  }

  /// Settles (pays out) an outstanding external payable
  Future<ExternalPayableRecord> settlePayable({
    required String hospitalCode,
    required int payableId,
    required Decimal settleAmount,
    required String idempotencyKey,
    required String paymentMethod, // 'CASH' | 'BANK'
    int? shiftId,
    int? actorStaffId,
    String? referenceNumber,
  }) async {
    return await txManager.runInTransaction((tx) async {
      final current = await findByIdInTx(tx, hospitalCode, payableId, forUpdate: true);
      if (current == null) {
        throw StateError('External payable $payableId not found in facility $hospitalCode.');
      }
      if (current.status == 'SETTLED' || current.balanceAmount <= Decimal.zero) {
        throw StateError('Payable is already settled.');
      }
      if (settleAmount <= Decimal.zero || settleAmount > current.balanceAmount) {
        throw ArgumentError('Invalid settlement amount: must be > 0 and <= balance (${current.balanceAmount}).');
      }

      final newPaid = current.paidAmount + settleAmount;
      final newBalance = current.balanceAmount - settleAmount;
      final newStatus = newBalance == Decimal.zero ? 'SETTLED' : 'PARTIAL';

      await tx.execute(
        '''
        UPDATE mc_external_payables
        SET paid_amount = :paid,
            balance_amount = :bal,
            status = :status
        WHERE id = :id AND hospital_code = :hosp
        ''',
        {
          'paid': newPaid.toString(),
          'bal': newBalance.toString(),
          'status': newStatus,
          'id': payableId,
          'hosp': hospitalCode,
        },
      );

      // Create settlement financial event
      final eventUuid = 'EVT-EXTSETTLE-${_uuid.v4()}';
      final eventRes = await tx.execute(
        '''
        INSERT INTO mc_financial_events (
          event_uuid, hospital_code, idempotency_key, event_type,
          source_module, source_entity_type, source_entity_id, shift_id,
          gross_amount, net_amount, paid_amount, balance_amount, status
        ) VALUES (
          :uuid, :hosp, :idemp, 'EXTERNAL_PAYABLE_SETTLEMENT',
          'BILLING', 'mc_external_payables', :pid, :shift,
          :amt, :amt, :amt, 0.0000, 'POSTED'
        )
        ''',
        {
          'uuid': eventUuid,
          'hosp': hospitalCode,
          'idemp': idempotencyKey,
          'pid': payableId,
          'shift': shiftId,
          'amt': settleAmount.toString(),
        },
      );
      final eventId = eventRes.lastInsertID.toInt();

      final bucket = current.partyType == 'LAB'
          ? 'EXTERNAL_LAB_PAYABLE'
          : current.partyType == 'CLINIC'
              ? 'EXTERNAL_CLINIC_PAYABLE'
              : 'EXTERNAL_PARTY_PAYABLE';
      final cashBucket = paymentMethod == 'BANK' ? 'BANK_ACCOUNT' : 'CASH_DRAWER';

      // Balanced postings:
      // DEBIT: EXTERNAL_LAB_PAYABLE (Reduction of liability)
      // CREDIT: CASH_DRAWER / BANK (Outflow of asset)
      await tx.execute(
        '''
        INSERT INTO mc_financial_postings (
          posting_uuid, hospital_code, event_id, posting_type, account_bucket,
          direction, amount, beneficiary_type, beneficiary_id, shift_id, status
        ) VALUES (
          :uuid1, :hosp, :eid, 'PAYABLE_LIABILITY_CLEARING', :bucket,
          'DEBIT', :amt, :btype, :bid, :shift, 'POSTED'
        ), (
          :uuid2, :hosp, :eid, 'TREASURY_DISBURSEMENT', :cashBucket,
          'CREDIT', :amt, :btype, :bid, :shift, 'POSTED'
        )
        ''',
        {
          'uuid1': 'PST-${_uuid.v4()}',
          'uuid2': 'PST-${_uuid.v4()}',
          'hosp': hospitalCode,
          'eid': eventId,
          'bucket': bucket,
          'cashBucket': cashBucket,
          'amt': settleAmount.toString(),
          'btype': current.partyType,
          'bid': payableId,
          'shift': shiftId,
        },
      );

      await tx.writeAuditLog(
        hospitalCode: hospitalCode,
        actorStaffId: actorStaffId,
        action: 'billing.external_payable.settled',
        entityType: 'mc_external_payables',
        entityId: current.payableUuid,
        afterState: {
          'payableId': payableId,
          'settledAmount': settleAmount.toString(),
          'remainingBalance': newBalance.toString(),
          'status': newStatus,
        },
      );

      return (await findByIdInTx(tx, hospitalCode, payableId))!;
    });
  }

  Future<ExternalPayableRecord?> findById(String hospitalCode, int id) async {
    final rows = await txManager.db.execute(
      'SELECT * FROM mc_external_payables WHERE hospital_code = :hosp AND id = :id LIMIT 1',
      {'hosp': hospitalCode, 'id': id},
    );
    if (rows.rows.isEmpty) return null;
    return _mapRow(rows.rows.first);
  }

  Future<ExternalPayableRecord?> findByIdInTx(SqlExecutor tx, String hospitalCode, int id, {bool forUpdate = false}) async {
    final sql = 'SELECT * FROM mc_external_payables WHERE hospital_code = :hosp AND id = :id LIMIT 1' +
        (forUpdate ? ' FOR UPDATE' : '');
    final rows = await tx.execute(sql, {'hosp': hospitalCode, 'id': id});
    if (rows.rows.isEmpty) return null;
    return _mapRow(rows.rows.first);
  }

  Future<List<ExternalPayableRecord>> listPayables(
    String hospitalCode, {
    String? partyType,
    String? status,
    int? sourceVisitId,
  }) async {
    final conditions = ['hospital_code = :hosp'];
    final params = <String, dynamic>{'hosp': hospitalCode};

    if (partyType != null && partyType.isNotEmpty) {
      conditions.add('party_type = :ptype');
      params['ptype'] = partyType;
    }
    if (status != null && status.isNotEmpty) {
      conditions.add('status = :status');
      params['status'] = status;
    }
    if (sourceVisitId != null) {
      conditions.add('source_visit_id = :vid');
      params['vid'] = sourceVisitId;
    }

    final query = 'SELECT * FROM mc_external_payables WHERE ${conditions.join(' AND ')} ORDER BY id DESC';
    final res = await txManager.db.execute(query, params);
    return res.rows.map(_mapRow).toList();
  }

  ExternalPayableRecord _mapRow(dynamic r) {
    return ExternalPayableRecord(
      id: int.parse(r.colByName('id') ?? '0'),
      hospitalCode: r.colByName('hospital_code') ?? '',
      payableUuid: r.colByName('payable_uuid') ?? '',
      partyType: r.colByName('party_type') ?? '',
      partyCode: r.colByName('party_code') ?? '',
      partyName: r.colByName('party_name') ?? '',
      sourceVisitId: int.parse(r.colByName('source_visit_id') ?? '0'),
      sourceEventId: int.parse(r.colByName('source_event_id') ?? '0'),
      grossAmount: Decimal.parse(r.colByName('gross_amount') ?? '0.0000'),
      allocatedAmount: Decimal.parse(r.colByName('allocated_amount') ?? '0.0000'),
      paidAmount: Decimal.parse(r.colByName('paid_amount') ?? '0.0000'),
      balanceAmount: Decimal.parse(r.colByName('balance_amount') ?? '0.0000'),
      status: r.colByName('status') ?? 'PENDING',
      notes: r.colByName('notes'),
      createdAt: DateTime.tryParse('${r.colByName('created_at')}Z') ?? DateTime.now().toUtc(),
    );
  }
}
