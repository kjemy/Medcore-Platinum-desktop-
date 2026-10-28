import 'package:decimal/decimal.dart';
import '../db/db_client.dart';
import 'facility_config_service.dart';

class PatientFinancialLedgerService {
  final DbClient db;
  final FacilityConfigService facilityConfigService;

  PatientFinancialLedgerService(
    this.db, {
    required this.facilityConfigService,
  });

  static const List<Map<String, String>> documentedBackendGaps = [
    {
      'gapId': 'FIN-GAP-REFUND-REVERSAL',
      'status': 'RESOLVED_BATCH1',
      'description':
          'VisitFinancialService.executeRefundReversalInternal atomically posts symmetric double-entry reversing postings (DEBIT <-> CREDIT), updates mc_shifts cash_out/expected_cash, and updates mc_patients.balance.',
    },
    {
      'gapId': 'FIN-GAP-STANDALONE-AR-COLLECTION',
      'status': 'RESOLVED_BATCH2',
      'description':
          'Standalone AR collection posting transaction is fully implemented in VisitFinancialService.collectPatientAr and exposed via /api/v1/finance/ar-collections.',
    },
    {
      'gapId': 'FIN-GAP-LAB-CLINIC-PAYABLE-RULES',
      'status': 'BACKEND_GAP',
      'description':
          'Automated commission payable sub-ledger postings currently model DOCTOR beneficiaries (COMMISSION_ACCRUAL) and Hospital SERVICE_LABOR vs CONSUMABLE_MATERIAL cost lines. Separate contractual payable rules for external laboratories or independent clinics are reported via visit/item attribution and mc_earning_lines where populated, without inventing unconfigured split percentages.',
    },
  ];

  /// Complete Patient Financial Account read directly from MariaDB.
  Future<Map<String, dynamic>> getPatientLedger({
    required String hospitalCode,
    required int patientId,
  }) async {
    final patRes = await db.execute(
      '''
      SELECT id, hospital_code, mrn, full_name, gender, phone,
             insurance_company_id, insurance_policy_no, balance, created_at
      FROM mc_patients
      WHERE hospital_code = :hosp AND id = :id AND is_deleted = 0
      LIMIT 1
      ''',
      {'hosp': hospitalCode, 'id': patientId},
    );
    if (patRes.rows.isEmpty) {
      throw StateError('Patient #$patientId not found in facility $hospitalCode.');
    }
    final pr = patRes.rows.first;
    final currentBalance = Decimal.parse(pr.colByName('balance') ?? '0.0000');

    // Visits for this patient
    final visitsRes = await db.execute(
      '''
      SELECT v.*, s.shift_code, st.full_name AS doctor_name
      FROM mc_visits v
      LEFT JOIN mc_shifts s ON s.id = v.shift_id AND s.hospital_code = v.hospital_code
      LEFT JOIN mc_staff st ON st.id = v.doctor_id AND st.hospital_code = v.hospital_code
      WHERE v.hospital_code = :hosp AND v.patient_id = :pid
      ORDER BY v.id ASC
      ''',
      {'hosp': hospitalCode, 'pid': patientId},
    );

    var totalGross = Decimal.zero;
    var totalDiscount = Decimal.zero;
    var totalNet = Decimal.zero;
    var totalInsurance = Decimal.zero;
    var totalPatientResp = Decimal.zero;
    var totalPaid = Decimal.zero;
    var activeVisitsOutstanding = Decimal.zero;
    var refundedVisitsAmount = Decimal.zero;

    var hospitalServiceLaborNet = Decimal.zero;
    var hospitalConsumablesNet = Decimal.zero;
    var hospitalConsumablesFifoCost = Decimal.zero;
    var doctorCommissionTotal = Decimal.zero;
    final departmentAttribution = <String, Decimal>{};
    final clinicAttribution = <String, Decimal>{};
    final itemTypeAttribution = <String, Decimal>{};

    final visits = <Map<String, dynamic>>[];
    final visitIds = <int>[];

    for (final vr in visitsRes.rows) {
      final vid = int.parse(vr.colByName('id') ?? '0');
      visitIds.add(vid);
      final status = vr.colByName('status') ?? 'ACTIVE';
      final gross = Decimal.parse(vr.colByName('gross_amount') ?? '0.0000');
      final disc = Decimal.parse(vr.colByName('discount_amount') ?? '0.0000');
      final net = Decimal.parse(vr.colByName('net_amount') ?? '0.0000');
      final ins = Decimal.parse(vr.colByName('insurance_covered_amount') ?? '0.0000');
      final patResp = Decimal.parse(vr.colByName('patient_responsibility_amount') ?? '0.0000');
      final paid = Decimal.parse(vr.colByName('paid_amount') ?? '0.0000');
      final bal = Decimal.parse(vr.colByName('balance_amount') ?? '0.0000');

      totalGross += gross;
      totalDiscount += disc;
      totalNet += net;
      totalInsurance += ins;
      totalPatientResp += patResp;
      totalPaid += paid;
      if (status == 'REFUNDED') {
        refundedVisitsAmount += paid;
      } else {
        activeVisitsOutstanding += bal;
      }

      final dept = vr.colByName('department_id');
      if (dept != null && dept.isNotEmpty) {
        departmentAttribution[dept] = (departmentAttribution[dept] ?? Decimal.zero) + net;
      }
      final clinic = vr.colByName('clinic_id');
      if (clinic != null && clinic.isNotEmpty) {
        clinicAttribution[clinic] = (clinicAttribution[clinic] ?? Decimal.zero) + net;
      }

      String responsibleEntity;
      if (ins > Decimal.zero && patResp > Decimal.zero) {
        responsibleEntity = 'SHARED_PATIENT_AND_INSURANCE';
      } else if (ins > Decimal.zero && patResp == Decimal.zero) {
        responsibleEntity = 'INSURANCE_PAYER';
      } else {
        responsibleEntity = 'PATIENT_SELF';
      }

      // Fetch visit items + cost lines
      final itemsRes = await db.execute(
        '''
        SELECT * FROM mc_visit_items
        WHERE hospital_code = :hosp AND visit_id = :vid
        ORDER BY id ASC
        ''',
        {'hosp': hospitalCode, 'vid': vid},
      );
      final costLinesRes = await db.execute(
        '''
        SELECT * FROM mc_visit_item_cost_lines
        WHERE hospital_code = :hosp AND visit_id = :vid
        ORDER BY id ASC
        ''',
        {'hosp': hospitalCode, 'vid': vid},
      );

      for (final ir in itemsRes.rows) {
        final itype = (ir.colByName('item_type') ?? 'SERVICE').toUpperCase();
        final inet = Decimal.parse(ir.colByName('net_amount') ?? '0.0000');
        itemTypeAttribution[itype] = (itemTypeAttribution[itype] ?? Decimal.zero) + inet;
      }

      for (final cr in costLinesRes.rows) {
        final ctype = cr.colByName('component_type') ?? 'SERVICE_LABOR';
        final cnet = Decimal.parse(cr.colByName('billed_net_amount') ?? '0.0000');
        final cfifo = Decimal.parse(cr.colByName('total_cost_fifo') ?? '0.0000');
        if (ctype == 'CONSUMABLE_MATERIAL') {
          hospitalConsumablesNet += cnet;
          hospitalConsumablesFifoCost += cfifo;
        } else {
          hospitalServiceLaborNet += cnet;
        }
      }

      visits.add({
        'visitId': vid,
        'visitNumber': vr.colByName('visit_number'),
        'invoiceNumber': vr.colByName('invoice_number') ?? 'INV-${vr.colByName('visit_number')}',
        'visitType': vr.colByName('visit_type'),
        'status': status,
        'doctorId': vr.colByName('doctor_id') != null ? int.tryParse(vr.colByName('doctor_id')!) : null,
        'doctorName': vr.colByName('doctor_name'),
        'departmentId': dept,
        'clinicId': clinic,
        'shiftCode': vr.colByName('shift_code'),
        'currency': vr.colByName('currency') ?? 'EGP',
        'grossAmount': gross.toStringAsFixed(4),
        'discountAmount': disc.toStringAsFixed(4),
        'netAmount': net.toStringAsFixed(4),
        'insuranceCoveredAmount': ins.toStringAsFixed(4),
        'patientResponsibilityAmount': patResp.toStringAsFixed(4),
        'paidAmount': paid.toStringAsFixed(4),
        'balanceAmount': bal.toStringAsFixed(4),
        'responsibleEntity': responsibleEntity,
        'createdAt': vr.colByName('created_at'),
        'items': itemsRes.rows
            .map((ir) => {
                  'id': int.parse(ir.colByName('id') ?? '0'),
                  'itemType': ir.colByName('item_type'),
                  'serviceCode': ir.colByName('service_code'),
                  'serviceName': ir.colByName('service_name'),
                  'quantity': ir.colByName('quantity'),
                  'unitPrice': ir.colByName('unit_price'),
                  'grossAmount': ir.colByName('gross_amount'),
                  'discountAmount': ir.colByName('discount_amount'),
                  'netAmount': ir.colByName('net_amount'),
                })
            .toList(),
        'costLines': costLinesRes.rows
            .map((cr) => {
                  'id': int.parse(cr.colByName('id') ?? '0'),
                  'visitItemId': int.parse(cr.colByName('visit_item_id') ?? '0'),
                  'componentType': cr.colByName('component_type'),
                  'totalCostFifo': cr.colByName('total_cost_fifo'),
                  'billedGrossAmount': cr.colByName('billed_gross_amount'),
                  'billedNetAmount': cr.colByName('billed_net_amount'),
                  'isCommissionable': (cr.colByName('is_commissionable') ?? '0') == '1',
                })
            .toList(),
      });
    }

    // Fetch immutable financial events & postings linked to this patient's visits
    final chronologicalHistory = <Map<String, dynamic>>[];
    final dualControlRefunds = <Map<String, dynamic>>[];

    for (final v in visits) {
      final vid = v['visitId'] as int;
      final evRes = await db.execute(
        '''
        SELECT * FROM mc_financial_events
        WHERE hospital_code = :hosp AND source_entity_type IN ('VISIT', 'mc_visits') AND source_entity_id = :vid
        ORDER BY id ASC
        ''',
        {'hosp': hospitalCode, 'vid': vid},
      );
      for (final er in evRes.rows) {
        final evId = int.parse(er.colByName('id') ?? '0');
        final commAmt = Decimal.parse(er.colByName('commission_amount') ?? '0.0000');
        doctorCommissionTotal += commAmt;

        final postRes = await db.execute(
          '''
          SELECT * FROM mc_financial_postings
          WHERE hospital_code = :hosp AND event_id = :eid
          ORDER BY id ASC
          ''',
          {'hosp': hospitalCode, 'eid': evId},
        );

        chronologicalHistory.add({
          'entryType': er.colByName('event_type'),
          'eventUuid': er.colByName('event_uuid'),
          'documentReference': v['invoiceNumber'],
          'visitNumber': v['visitNumber'],
          'visitStatus': v['status'],
          'dateUtc': er.colByName('created_at'),
          'responsibleEntity': v['responsibleEntity'],
          'grossAmount': er.colByName('gross_amount'),
          'discountAmount': er.colByName('discount_amount'),
          'netAmount': er.colByName('net_amount'),
          'paidAmount': er.colByName('paid_amount'),
          'insuranceCoveredAmount': er.colByName('insurance_covered_amount'),
          'patientResponsibilityAmount': er.colByName('patient_responsibility_amount'),
          'balanceAmount': er.colByName('balance_amount'),
          'doctorCommissionAmount': er.colByName('commission_amount'),
          'currency': er.colByName('currency') ?? 'EGP',
          'postings': postRes.rows
              .map((p) => {
                    'postingUuid': p.colByName('posting_uuid'),
                    'postingType': p.colByName('posting_type'),
                    'accountBucket': p.colByName('account_bucket'),
                    'direction': p.colByName('direction'),
                    'amount': p.colByName('amount'),
                    'beneficiaryType': p.colByName('beneficiary_type'),
                    'beneficiaryId': p.colByName('beneficiary_id'),
                  })
              .toList(),
        });
      }

      // Check dual-control refund requests for this visit
      final dcRes = await db.execute(
        '''
        SELECT request_uuid, action_type, requested_amount, status, reason, created_at, decided_at
        FROM mc_dual_control_request
        WHERE hospital_code = :hosp AND target_entity_type = 'mc_visits' AND target_entity_id = :vid
        ORDER BY id ASC
        ''',
        {'hosp': hospitalCode, 'vid': vid.toString()},
      );
      for (final dcr in dcRes.rows) {
        dualControlRefunds.add({
          'requestUuid': dcr.colByName('request_uuid'),
          'visitNumber': v['visitNumber'],
          'actionType': dcr.colByName('action_type'),
          'requestedAmount': dcr.colByName('requested_amount'),
          'status': dcr.colByName('status'),
          'reason': dcr.colByName('reason'),
          'createdAt': dcr.colByName('created_at'),
          'decidedAt': dcr.colByName('decided_at'),
        });
      }
    }

    // Fetch standalone AR collections for this patient (Batch 2)
    final arRes = await db.execute(
      '''
      SELECT * FROM mc_financial_events
      WHERE hospital_code = :hosp AND source_entity_type = 'PATIENT' AND source_entity_id = :pid AND event_type = 'AR_COLLECTION'
      ORDER BY id ASC
      ''',
      {'hosp': hospitalCode, 'pid': patientId},
    );
    for (final er in arRes.rows) {
      final evId = int.parse(er.colByName('id') ?? '0');
      final postRes = await db.execute(
        '''
        SELECT * FROM mc_financial_postings
        WHERE hospital_code = :hosp AND event_id = :eid
        ORDER BY id ASC
        ''',
        {'hosp': hospitalCode, 'eid': evId},
      );
      chronologicalHistory.add({
        'entryType': er.colByName('event_type'),
        'eventUuid': er.colByName('event_uuid'),
        'documentReference': 'AR-COLL-${er.colByName('id')}',
        'visitNumber': 'N/A',
        'visitStatus': 'COLLECTED',
        'dateUtc': er.colByName('created_at'),
        'responsibleEntity': 'PATIENT_SELF',
        'grossAmount': er.colByName('gross_amount'),
        'discountAmount': '0.0000',
        'netAmount': er.colByName('net_amount'),
        'paidAmount': er.colByName('paid_amount'),
        'insuranceCoveredAmount': '0.0000',
        'patientResponsibilityAmount': er.colByName('paid_amount'),
        'balanceAmount': er.colByName('balance_amount'),
        'doctorCommissionAmount': '0.0000',
        'currency': er.colByName('currency') ?? 'EGP',
        'postings': postRes.rows
            .map((p) => {
                  'postingUuid': p.colByName('posting_uuid'),
                  'postingType': p.colByName('posting_type'),
                  'accountBucket': p.colByName('account_bucket'),
                  'direction': p.colByName('direction'),
                  'amount': p.colByName('amount'),
                  'beneficiaryType': p.colByName('beneficiary_type'),
                  'beneficiaryId': p.colByName('beneficiary_id'),
                })
            .toList(),
      });
    }

    final hospitalRetainedServiceRevenue = hospitalServiceLaborNet - doctorCommissionTotal;

    return {
      'patient': {
        'id': patientId,
        'hospitalCode': hospitalCode,
        'mrn': pr.colByName('mrn'),
        'fullName': pr.colByName('full_name'),
        'gender': pr.colByName('gender'),
        'phone': pr.colByName('phone'),
        'insuranceCompanyId': pr.colByName('insurance_company_id'),
        'insurancePolicyNo': pr.colByName('insurance_policy_no'),
        'registeredAt': pr.colByName('created_at'),
      },
      'accountSummary': {
        'currency': visits.isNotEmpty ? visits.first['currency'] : 'EGP',
        'authoritativePatientBalance': currentBalance.toStringAsFixed(4),
        'outstandingPatientDebt': currentBalance > Decimal.zero
            ? currentBalance.toStringAsFixed(4)
            : '0.0000',
        'activeVisitsBalanceSum': activeVisitsOutstanding.toStringAsFixed(4),
        'totalGrossCharges': totalGross.toStringAsFixed(4),
        'totalDiscounts': totalDiscount.toStringAsFixed(4),
        'totalNetBilled': totalNet.toStringAsFixed(4),
        'totalInsuranceResponsibility': totalInsurance.toStringAsFixed(4),
        'totalPatientResponsibility': totalPatientResp.toStringAsFixed(4),
        'totalPaymentsCollected': totalPaid.toStringAsFixed(4),
        'visitsMarkedRefundedAmount': refundedVisitsAmount.toStringAsFixed(4),
      },
      'financialAttribution': {
        'hospitalServiceLaborBilled': hospitalServiceLaborNet.toStringAsFixed(4),
        'hospitalRetainedLaborAfterDoctorCommission':
            hospitalRetainedServiceRevenue.toStringAsFixed(4),
        'hospitalConsumablesBilled': hospitalConsumablesNet.toStringAsFixed(4),
        'hospitalConsumablesFifoCost': hospitalConsumablesFifoCost.toStringAsFixed(4),
        'doctorCommissionAccrued': doctorCommissionTotal.toStringAsFixed(4),
        'byDepartment': {
          for (final e in departmentAttribution.entries)
            e.key: e.value.toStringAsFixed(4),
        },
        'byClinic': {
          for (final e in clinicAttribution.entries)
            e.key: e.value.toStringAsFixed(4),
        },
        'byServiceCategory': {
          for (final e in itemTypeAttribution.entries)
            e.key: e.value.toStringAsFixed(4),
        },
      },
      'visits': visits,
      'financialHistory': chronologicalHistory,
      'refundRequests': dualControlRefunds,
      'documentedBackendGaps': documentedBackendGaps,
    };
  }

  /// Authoritative Visit Invoice Document.
  Future<Map<String, dynamic>> getInvoiceDocument({
    required String hospitalCode,
    required int visitId,
  }) async {
    final cfg = await facilityConfigService.getConfiguration(hospitalCode);
    final vRes = await db.execute(
      '''
      SELECT v.*, p.mrn, p.full_name AS patient_name, p.phone AS patient_phone,
             p.insurance_company_id, p.insurance_policy_no,
             st.full_name AS doctor_name, sh.shift_code
      FROM mc_visits v
      INNER JOIN mc_patients p ON p.id = v.patient_id AND p.hospital_code = v.hospital_code
      LEFT JOIN mc_staff st ON st.id = v.doctor_id AND st.hospital_code = v.hospital_code
      LEFT JOIN mc_shifts sh ON sh.id = v.shift_id AND sh.hospital_code = v.hospital_code
      WHERE v.hospital_code = :hosp AND v.id = :vid
      LIMIT 1
      ''',
      {'hosp': hospitalCode, 'vid': visitId},
    );
    if (vRes.rows.isEmpty) {
      throw StateError('Visit #$visitId not found for tenant $hospitalCode.');
    }
    final vr = vRes.rows.first;
    final itemsRes = await db.execute(
      '''
      SELECT * FROM mc_visit_items
      WHERE hospital_code = :hosp AND visit_id = :vid
      ORDER BY id ASC
      ''',
      {'hosp': hospitalCode, 'vid': visitId},
    );
    final costRes = await db.execute(
      '''
      SELECT * FROM mc_visit_item_cost_lines
      WHERE hospital_code = :hosp AND visit_id = :vid
      ORDER BY id ASC
      ''',
      {'hosp': hospitalCode, 'vid': visitId},
    );

    final visitNo = vr.colByName('visit_number') ?? '';
    final invoiceNo = vr.colByName('invoice_number') ?? 'INV-$visitNo';

    return {
      'documentType': 'INVOICE',
      'documentNumber': invoiceNo,
      'visitId': visitId,
      'visitNumber': visitNo,
      'issuedAt': vr.colByName('created_at'),
      'status': vr.colByName('status'),
      'facility': {
        'hospitalCode': hospitalCode,
        'facilityName': cfg.facilityName,
        'branchCode': cfg.branchCode,
        'editionLabel': cfg.branding.editionLabel,
      },
      'patient': {
        'patientId': int.parse(vr.colByName('patient_id') ?? '0'),
        'mrn': vr.colByName('mrn'),
        'fullName': vr.colByName('patient_name'),
        'phone': vr.colByName('patient_phone'),
        'insuranceCompanyId': vr.colByName('insurance_company_id'),
        'insurancePolicyNo': vr.colByName('insurance_policy_no'),
      },
      'clinicalContext': {
        'visitType': vr.colByName('visit_type'),
        'doctorName': vr.colByName('doctor_name'),
        'departmentId': vr.colByName('department_id'),
        'clinicId': vr.colByName('clinic_id'),
        'shiftCode': vr.colByName('shift_code'),
      },
      'lineItems': itemsRes.rows
          .map((ir) => {
                'id': int.parse(ir.colByName('id') ?? '0'),
                'itemType': ir.colByName('item_type'),
                'serviceCode': ir.colByName('service_code'),
                'serviceName': ir.colByName('service_name'),
                'quantity': ir.colByName('quantity'),
                'unitPrice': ir.colByName('unit_price'),
                'grossAmount': ir.colByName('gross_amount'),
                'discountAmount': ir.colByName('discount_amount'),
                'netAmount': ir.colByName('net_amount'),
              })
          .toList(),
      'costSplitBreakdown': costRes.rows
          .map((cr) => {
                'componentType': cr.colByName('component_type'),
                'billedGrossAmount': cr.colByName('billed_gross_amount'),
                'billedNetAmount': cr.colByName('billed_net_amount'),
                'isCommissionable': (cr.colByName('is_commissionable') ?? '0') == '1',
              })
          .toList(),
      'totals': {
        'currency': vr.colByName('currency') ?? 'EGP',
        'grossAmount': vr.colByName('gross_amount'),
        'discountAmount': vr.colByName('discount_amount'),
        'netAmount': vr.colByName('net_amount'),
        'insuranceCoveredAmount': vr.colByName('insurance_covered_amount'),
        'patientResponsibilityAmount': vr.colByName('patient_responsibility_amount'),
        'paidAmount': vr.colByName('paid_amount'),
        'balanceDue': vr.colByName('balance_amount'),
      },
    };
  }

  /// Authoritative Cashier Payment Receipt Document.
  Future<Map<String, dynamic>> getReceiptDocument({
    required String hospitalCode,
    required int visitId,
  }) async {
    final invoice = await getInvoiceDocument(hospitalCode: hospitalCode, visitId: visitId);
    final evRes = await db.execute(
      '''
      SELECT e.event_uuid, e.paid_amount, e.created_at,
             sh.shift_code, st.full_name AS cashier_name, st.staff_code AS cashier_code
      FROM mc_financial_events e
      LEFT JOIN mc_shifts sh ON sh.id = e.shift_id AND sh.hospital_code = e.hospital_code
      LEFT JOIN mc_staff st ON st.id = sh.cashier_staff_id AND st.hospital_code = e.hospital_code
      WHERE e.hospital_code = :hosp
        AND e.source_entity_type IN ('VISIT', 'mc_visits')
        AND e.source_entity_id = :vid
      ORDER BY e.id ASC
      LIMIT 1
      ''',
      {'hosp': hospitalCode, 'vid': visitId},
    );

    final er = evRes.rows.isNotEmpty ? evRes.rows.first : null;
    final visitNo = invoice['visitNumber'];

    return {
      'documentType': 'PAYMENT_RECEIPT',
      'receiptNumber': 'RCPT-$visitNo',
      'invoiceNumber': invoice['documentNumber'],
      'visitId': visitId,
      'visitNumber': visitNo,
      'visitStatus': invoice['status'],
      'financialEventUuid': er?.colByName('event_uuid'),
      'collectedAtUtc': er?.colByName('created_at') ?? invoice['issuedAt'],
      'facility': invoice['facility'],
      'patient': invoice['patient'],
      'cashierShift': {
        'shiftCode': er?.colByName('shift_code') ??
            (invoice['clinicalContext'] as Map<String, dynamic>)['shiftCode'],
        'cashierName': er?.colByName('cashier_name'),
        'cashierStaffCode': er?.colByName('cashier_code'),
      },
      'paymentSummary': {
        'currency': (invoice['totals'] as Map<String, dynamic>)['currency'],
        'patientResponsibilityAmount':
            (invoice['totals'] as Map<String, dynamic>)['patientResponsibilityAmount'],
        'amountReceived': er?.colByName('paid_amount') ??
            (invoice['totals'] as Map<String, dynamic>)['paidAmount'],
        'remainingPatientBalanceOnVisit':
            (invoice['totals'] as Map<String, dynamic>)['balanceDue'],
      },
    };
  }

  /// Authoritative Patient Statement of Account Document.
  Future<Map<String, dynamic>> getPatientStatementDocument({
    required String hospitalCode,
    required int patientId,
  }) async {
    final cfg = await facilityConfigService.getConfiguration(hospitalCode);
    final ledger = await getPatientLedger(hospitalCode: hospitalCode, patientId: patientId);

    var runningPatientBalance = Decimal.zero;
    final statementLines = <Map<String, dynamic>>[];

    for (final v in (ledger['visits'] as List<dynamic>)) {
      final vm = v as Map<String, dynamic>;
      final patResp = Decimal.parse(vm['patientResponsibilityAmount'].toString());
      final paid = Decimal.parse(vm['paidAmount'].toString());
      runningPatientBalance += (patResp - paid);

      statementLines.add({
        'date': vm['createdAt'],
        'reference': vm['invoiceNumber'],
        'visitNumber': vm['visitNumber'],
        'status': vm['status'],
        'description': 'Visit Checkout (${vm['visitType']})',
        'grossCharge': vm['grossAmount'],
        'discount': vm['discountAmount'],
        'insuranceCovered': vm['insuranceCoveredAmount'],
        'patientDebit': patResp.toStringAsFixed(4),
        'patientPaymentCredit': paid.toStringAsFixed(4),
        'visitRemainingBalance': vm['balanceAmount'],
        'runningComputedBalance': runningPatientBalance.toStringAsFixed(4),
      });
    }

    return {
      'documentType': 'PATIENT_STATEMENT',
      'generatedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'facility': {
        'hospitalCode': hospitalCode,
        'facilityName': cfg.facilityName,
        'branchCode': cfg.branchCode,
        'editionLabel': cfg.branding.editionLabel,
      },
      'patient': ledger['patient'],
      'accountSummary': ledger['accountSummary'],
      'statementLines': statementLines,
      'documentedBackendGaps': documentedBackendGaps,
    };
  }

  /// Authoritative Outstanding Balance Report (Patients & Visits with open debt + Insurance AR).
  Future<Map<String, dynamic>> getOutstandingBalancesReport({
    required String hospitalCode,
  }) async {
    final patRes = await db.execute(
      '''
      SELECT id, mrn, full_name, phone, insurance_company_id, balance, updated_at
      FROM mc_patients
      WHERE hospital_code = :hosp AND is_deleted = 0 AND balance > 0
      ORDER BY balance DESC, id ASC
      ''',
      {'hosp': hospitalCode},
    );

    final visitRes = await db.execute(
      '''
      SELECT v.id, v.visit_number, v.invoice_number, v.patient_id,
             p.mrn, p.full_name AS patient_name,
             v.net_amount, v.insurance_covered_amount,
             v.patient_responsibility_amount, v.paid_amount, v.balance_amount,
             v.status, v.created_at
      FROM mc_visits v
      INNER JOIN mc_patients p ON p.id = v.patient_id AND p.hospital_code = v.hospital_code
      WHERE v.hospital_code = :hosp AND (v.balance_amount > 0 OR v.insurance_covered_amount > 0)
      ORDER BY v.balance_amount DESC, v.id DESC
      ''',
      {'hosp': hospitalCode},
    );

    final arBucketsRes = await db.execute(
      '''
      SELECT account_bucket,
             COALESCE(SUM(CASE WHEN direction = 'DEBIT' THEN amount ELSE -amount END), 0) AS net_receivable
      FROM mc_financial_postings
      WHERE hospital_code = :hosp
        AND status = 'POSTED'
        AND account_bucket IN ('ACCOUNTS_RECEIVABLE_PATIENT', 'ACCOUNTS_RECEIVABLE_INSURANCE')
      GROUP BY account_bucket
      ''',
      {'hosp': hospitalCode},
    );

    var totalPatientBalances = Decimal.zero;
    final patientsWithDebt = patRes.rows.map((r) {
      final b = Decimal.parse(r.colByName('balance') ?? '0.0000');
      totalPatientBalances += b;
      return {
        'patientId': int.parse(r.colByName('id') ?? '0'),
        'mrn': r.colByName('mrn'),
        'fullName': r.colByName('full_name'),
        'phone': r.colByName('phone'),
        'insuranceCompanyId': r.colByName('insurance_company_id'),
        'outstandingBalance': b.toStringAsFixed(4),
        'updatedAt': r.colByName('updated_at'),
      };
    }).toList();

    final arLedgerBuckets = <String, String>{
      'ACCOUNTS_RECEIVABLE_PATIENT': '0.0000',
      'ACCOUNTS_RECEIVABLE_INSURANCE': '0.0000',
    };
    for (final r in arBucketsRes.rows) {
      final bucket = r.colByName('account_bucket') ?? '';
      final val = Decimal.parse(r.colByName('net_receivable') ?? '0.0000');
      arLedgerBuckets[bucket] = val.toStringAsFixed(4);
    }

    return {
      'reportType': 'OUTSTANDING_BALANCE_REPORT',
      'hospitalCode': hospitalCode,
      'generatedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'summary': {
        'patientsWithDebtCount': patientsWithDebt.length,
        'totalPatientOutstandingBalance': totalPatientBalances.toStringAsFixed(4),
        'ledgerArPatientBucket': arLedgerBuckets['ACCOUNTS_RECEIVABLE_PATIENT'],
        'ledgerArInsuranceBucket': arLedgerBuckets['ACCOUNTS_RECEIVABLE_INSURANCE'],
      },
      'patientsWithDebt': patientsWithDebt,
      'openReceivableVisits': visitRes.rows
          .map((r) => {
                'visitId': int.parse(r.colByName('id') ?? '0'),
                'visitNumber': r.colByName('visit_number'),
                'invoiceNumber':
                    r.colByName('invoice_number') ?? 'INV-${r.colByName('visit_number')}',
                'patientId': int.parse(r.colByName('patient_id') ?? '0'),
                'mrn': r.colByName('mrn'),
                'patientName': r.colByName('patient_name'),
                'netAmount': r.colByName('net_amount'),
                'insuranceCoveredAmount': r.colByName('insurance_covered_amount'),
                'patientResponsibilityAmount':
                    r.colByName('patient_responsibility_amount'),
                'paidAmount': r.colByName('paid_amount'),
                'patientBalanceDue': r.colByName('balance_amount'),
                'status': r.colByName('status'),
                'createdAt': r.colByName('created_at'),
              })
          .toList(),
    };
  }

  /// Authoritative Financial History & Double-Entry Trial Balance Report.
  Future<Map<String, dynamic>> getFinancialHistoryReport({
    required String hospitalCode,
    int limit = 100,
  }) async {
    final safeLimit = limit.clamp(1, 500);
    final eventsRes = await db.execute(
      '''
      SELECT * FROM mc_financial_events
      WHERE hospital_code = :hosp
      ORDER BY id DESC
      LIMIT $safeLimit
      ''',
      {'hosp': hospitalCode},
    );

    final bucketRes = await db.execute(
      '''
      SELECT account_bucket,
             COALESCE(SUM(CASE WHEN direction = 'DEBIT' THEN amount ELSE 0 END), 0) AS debits,
             COALESCE(SUM(CASE WHEN direction = 'CREDIT' THEN amount ELSE 0 END), 0) AS credits,
             COUNT(*) AS legs_count
      FROM mc_financial_postings
      WHERE hospital_code = :hosp AND status = 'POSTED'
      GROUP BY account_bucket
      ORDER BY account_bucket ASC
      ''',
      {'hosp': hospitalCode},
    );

    var grandDebits = Decimal.zero;
    var grandCredits = Decimal.zero;
    final buckets = bucketRes.rows.map((r) {
      final d = Decimal.parse(r.colByName('debits') ?? '0.0000');
      final c = Decimal.parse(r.colByName('credits') ?? '0.0000');
      grandDebits += d;
      grandCredits += c;
      return {
        'accountBucket': r.colByName('account_bucket'),
        'totalDebits': d.toStringAsFixed(4),
        'totalCredits': c.toStringAsFixed(4),
        'legsCount': int.tryParse(r.colByName('legs_count') ?? '0') ?? 0,
      };
    }).toList();

    return {
      'reportType': 'FINANCIAL_HISTORY_AND_TRIAL_BALANCE',
      'hospitalCode': hospitalCode,
      'generatedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'trialBalance': {
        'isBalanced': grandDebits == grandCredits,
        'totalDebits': grandDebits.toStringAsFixed(4),
        'totalCredits': grandCredits.toStringAsFixed(4),
        'buckets': buckets,
      },
      'events': eventsRes.rows
          .map((er) => {
                'id': int.parse(er.colByName('id') ?? '0'),
                'eventUuid': er.colByName('event_uuid'),
                'eventType': er.colByName('event_type'),
                'sourceModule': er.colByName('source_module'),
                'sourceEntityType': er.colByName('source_entity_type'),
                'sourceEntityId': int.parse(er.colByName('source_entity_id') ?? '0'),
                'grossAmount': er.colByName('gross_amount'),
                'discountAmount': er.colByName('discount_amount'),
                'netAmount': er.colByName('net_amount'),
                'paidAmount': er.colByName('paid_amount'),
                'insuranceCoveredAmount': er.colByName('insurance_covered_amount'),
                'balanceAmount': er.colByName('balance_amount'),
                'commissionAmount': er.colByName('commission_amount'),
                'currency': er.colByName('currency'),
                'status': er.colByName('status'),
                'createdAt': er.colByName('created_at'),
              })
          .toList(),
      'documentedBackendGaps': documentedBackendGaps,
    };
  }

  /// Authoritative Doctor / Clinic / Lab / Hospital Allocation Report.
  /// Strictly derives values from `mc_financial_postings`, `mc_earning_lines`,
  /// `mc_financial_settlements`, `mc_visits`, `mc_visit_items`, and `mc_visit_item_cost_lines`.
  Future<Map<String, dynamic>> getAllocationReport({
    required String hospitalCode,
  }) async {
    // 1. Doctor Commission Sub-Ledger Allocation (from mc_financial_postings)
    final docPostingsRes = await db.execute(
      '''
      SELECT fp.beneficiary_id AS doctor_id,
             st.staff_code,
             st.full_name AS doctor_name,
             st.department_id,
             st.clinic_id,
             COALESCE(SUM(CASE WHEN fp.account_bucket = 'PAYABLE_COMMISSION_DOCTOR' AND fp.direction = 'CREDIT' THEN fp.amount ELSE 0 END), 0) AS accrued_commission,
             COALESCE(SUM(CASE WHEN fp.account_bucket = 'PAYABLE_COMMISSION_DOCTOR' AND fp.direction = 'DEBIT' THEN fp.amount ELSE 0 END), 0) AS settled_or_debited
      FROM mc_financial_postings fp
      LEFT JOIN mc_staff st ON st.id = fp.beneficiary_id AND st.hospital_code = fp.hospital_code
      WHERE fp.hospital_code = :hosp
        AND fp.status = 'POSTED'
        AND fp.beneficiary_type = 'DOCTOR'
      GROUP BY fp.beneficiary_id, st.staff_code, st.full_name, st.department_id, st.clinic_id
      ORDER BY accrued_commission DESC
      ''',
      {'hosp': hospitalCode},
    );

    final doctorAllocations = docPostingsRes.rows.map((r) {
      final accrued = Decimal.parse(r.colByName('accrued_commission') ?? '0.0000');
      final settled = Decimal.parse(r.colByName('settled_or_debited') ?? '0.0000');
      return {
        'doctorId': r.colByName('doctor_id') != null ? int.tryParse(r.colByName('doctor_id')!) : null,
        'staffCode': r.colByName('staff_code'),
        'doctorName': r.colByName('doctor_name') ?? 'Doctor #${r.colByName('doctor_id')}',
        'departmentId': r.colByName('department_id'),
        'clinicId': r.colByName('clinic_id'),
        'accruedCommission': accrued.toStringAsFixed(4),
        'settledCommission': settled.toStringAsFixed(4),
        'netPayableBalance': (accrued - settled).toStringAsFixed(4),
      };
    }).toList();

    // 2. Earning Lines & Settlements (mc_earning_lines + mc_financial_settlements)
    final earningLinesRes = await db.execute(
      '''
      SELECT beneficiary_type, beneficiary_id, earning_type, settlement_status,
             COALESCE(SUM(amount), 0) AS total_amount, COUNT(*) AS line_count
      FROM mc_earning_lines
      WHERE hospital_code = :hosp
      GROUP BY beneficiary_type, beneficiary_id, earning_type, settlement_status
      ORDER BY total_amount DESC
      ''',
      {'hosp': hospitalCode},
    );

    // 3. Clinic / Department / Service Category Attribution (Lab, Radiology, Outpatient, etc.)
    final serviceAttributionRes = await db.execute(
      '''
      SELECT COALESCE(v.department_id, 'UNASSIGNED_DEPT') AS department_id,
             COALESCE(v.clinic_id, 'UNASSIGNED_CLINIC') AS clinic_id,
             vi.item_type,
             COUNT(vi.id) AS item_count,
             COALESCE(SUM(vi.gross_amount), 0) AS gross_billed,
             COALESCE(SUM(vi.discount_amount), 0) AS discount_total,
             COALESCE(SUM(vi.net_amount), 0) AS net_billed
      FROM mc_visit_items vi
      INNER JOIN mc_visits v ON v.id = vi.visit_id AND v.hospital_code = vi.hospital_code
      WHERE vi.hospital_code = :hosp
      GROUP BY v.department_id, v.clinic_id, vi.item_type
      ORDER BY net_billed DESC
      ''',
      {'hosp': hospitalCode},
    );

    // 4. Hospital Service Labor vs Consumable FIFO Split (FIN-004)
    final costSplitRes = await db.execute(
      '''
      SELECT component_type,
             COALESCE(SUM(billed_gross_amount), 0) AS billed_gross,
             COALESCE(SUM(billed_net_amount), 0) AS billed_net,
             COALESCE(SUM(total_cost_fifo), 0) AS fifo_cogs
      FROM mc_visit_item_cost_lines
      WHERE hospital_code = :hosp
      GROUP BY component_type
      ORDER BY component_type ASC
      ''',
      {'hosp': hospitalCode},
    );

    return {
      'reportType': 'DOCTOR_CLINIC_LAB_HOSPITAL_ALLOCATION_REPORT',
      'hospitalCode': hospitalCode,
      'generatedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'doctorCommissionLedger': doctorAllocations,
      'earningLinesSummary': earningLinesRes.rows
          .map((r) => {
                'beneficiaryType': r.colByName('beneficiary_type'),
                'beneficiaryId': r.colByName('beneficiary_id'),
                'earningType': r.colByName('earning_type'),
                'settlementStatus': r.colByName('settlement_status'),
                'totalAmount': r.colByName('total_amount'),
                'lineCount': int.tryParse(r.colByName('line_count') ?? '0') ?? 0,
              })
          .toList(),
      'clinicDepartmentAndLabServiceAttribution': serviceAttributionRes.rows
          .map((r) => {
                'departmentId': r.colByName('department_id'),
                'clinicId': r.colByName('clinic_id'),
                'itemType': r.colByName('item_type'),
                'itemCount': int.tryParse(r.colByName('item_count') ?? '0') ?? 0,
                'grossBilled': r.colByName('gross_billed'),
                'discountTotal': r.colByName('discount_total'),
                'netBilled': r.colByName('net_billed'),
              })
          .toList(),
      'hospitalComponentSplit': costSplitRes.rows
          .map((r) => {
                'componentType': r.colByName('component_type'),
                'billedGross': r.colByName('billed_gross'),
                'billedNet': r.colByName('billed_net'),
                'fifoCogs': r.colByName('fifo_cogs'),
              })
          .toList(),
      'documentedBackendGaps': documentedBackendGaps,
    };
  }
}
