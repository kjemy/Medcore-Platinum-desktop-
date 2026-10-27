import 'dart:convert';
import 'package:decimal/decimal.dart';
import 'package:uuid/uuid.dart';
import '../db/db_client.dart';
import '../db/transaction_manager.dart';
import '../security/rbac_evaluator.dart';
import 'scope_context.dart';

/// ---------------------------------------------------------------------------
/// WORKSTREAM 1: Appointments & Scheduling Repository
/// ---------------------------------------------------------------------------
class AppointmentRecord {
  final int id;
  final String hospitalCode;
  final String publicId;
  final String appointmentNumber;
  final int patientId;
  final String doctorId;
  final String? clinicId;
  final String appointmentType;
  final DateTime scheduledAt;
  final int durationMinutes;
  final String status;
  final String? reason;
  final String? notes;

  const AppointmentRecord({
    required this.id,
    required this.hospitalCode,
    required this.publicId,
    required this.appointmentNumber,
    required this.patientId,
    required this.doctorId,
    this.clinicId,
    required this.appointmentType,
    required this.scheduledAt,
    required this.durationMinutes,
    required this.status,
    this.reason,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'hospitalCode': hospitalCode,
        'publicId': publicId,
        'appointmentNumber': appointmentNumber,
        'patientId': patientId,
        'doctorId': doctorId,
        'clinicId': clinicId,
        'appointmentType': appointmentType,
        'scheduledAt': scheduledAt.toIso8601String(),
        'durationMinutes': durationMinutes,
        'status': status,
        'reason': reason,
        'notes': notes,
      };
}

class AppointmentRepository {
  final SqlExecutor db;
  static const _uuid = Uuid();

  AppointmentRepository(this.db);

  Future<AppointmentRecord> createAppointment({
    required ScopeContext scope,
    required String appointmentNumber,
    required int patientId,
    required String doctorId,
    String? clinicId,
    String appointmentType = 'CONSULTATION',
    required DateTime scheduledAt,
    int durationMinutes = 30,
    String? reason,
    String? notes,
    String? idempotencyKey,
  }) async {
    final pubId = _uuid.v4();
    final idemp = idempotencyKey ?? 'IDEMP-APT-${_uuid.v4()}';

    final res = await db.execute(
      '''
      INSERT INTO mc_appointments (
        hospital_code, public_id, tenant_id, appointment_number,
        idempotency_key, patient_id, clinic_id, doctor_id,
        appointment_type, scheduled_at, duration_minutes, status,
        reason, notes, created_by, occurred_at, created_at, updated_at
      ) VALUES (
        :hosp, :pub_id, :tenant, :apt_no,
        :idemp, :pid, :clinic, :doc_id,
        :atype, :sched_at, :duration, 'SCHEDULED',
        :reason, :notes, :creator, NOW(), NOW(), NOW()
      )
      ''',
      {
        'hosp': scope.hospitalCode,
        'pub_id': pubId,
        'tenant': scope.hospitalCode,
        'apt_no': appointmentNumber,
        'idemp': idemp,
        'pid': patientId,
        'clinic': clinicId ?? scope.actor.departmentId,
        'doc_id': doctorId,
        'atype': appointmentType,
        'sched_at': scheduledAt.toIso8601String().substring(0, 19).replaceAll('T', ' '),
        'duration': durationMinutes,
        'reason': reason,
        'notes': notes,
        'creator': scope.actor.id.toString(),
      },
    );

    final id = res.lastInsertID.toInt();
    return (await findById(scope.hospitalCode, id))!;
  }

  Future<List<AppointmentRecord>> listAppointments(ScopeContext scope, {DateTime? date}) async {
    String sql;
    Map<String, dynamic> params;

    if (scope.isTenantWide) {
      sql = '''
        SELECT * FROM mc_appointments
        WHERE hospital_code = :hosp
        ORDER BY scheduled_at ASC
      ''';
      params = {'hosp': scope.hospitalCode};
    } else {
      sql = '''
        SELECT * FROM mc_appointments
        WHERE hospital_code = :hosp
          AND (doctor_id = :doc_id OR created_by = :creator)
        ORDER BY scheduled_at ASC
      ''';
      params = {
        'hosp': scope.hospitalCode,
        'doc_id': scope.actor.id.toString(),
        'creator': scope.actor.id.toString(),
      };
    }

    final res = await db.execute(sql, params);
    return res.rows.map(_mapRow).toList();
  }

  Future<AppointmentRecord?> findById(String hospitalCode, int id) async {
    final res = await db.execute(
      'SELECT * FROM mc_appointments WHERE hospital_code = :hosp AND id = :id LIMIT 1',
      {'hosp': hospitalCode, 'id': id},
    );
    if (res.rows.isEmpty) return null;
    return _mapRow(res.rows.first);
  }

  Future<AppointmentRecord> updateStatus({
    required ScopeContext scope,
    required int appointmentId,
    required String newStatus,
    String? cancellationReason,
  }) async {
    const validStatuses = {'SCHEDULED', 'ARRIVED', 'CHECKED_IN', 'CANCELLED', 'COMPLETED'};
    if (!validStatuses.contains(newStatus)) {
      throw ArgumentError('Invalid appointment status: $newStatus');
    }

    await db.execute(
      '''
      UPDATE mc_appointments
      SET status = :status,
          cancellation_reason = :creason,
          updated_at = NOW()
      WHERE hospital_code = :hosp AND id = :id
      ''',
      {
        'hosp': scope.hospitalCode,
        'id': appointmentId,
        'status': newStatus,
        'creason': cancellationReason,
      },
    );

    return (await findById(scope.hospitalCode, appointmentId))!;
  }

  AppointmentRecord _mapRow(dynamic r) {
    return AppointmentRecord(
      id: int.parse(r.colByName('id') ?? '0'),
      hospitalCode: r.colByName('hospital_code') ?? '',
      publicId: r.colByName('public_id') ?? '',
      appointmentNumber: r.colByName('appointment_number') ?? '',
      patientId: int.parse(r.colByName('patient_id') ?? '0'),
      doctorId: r.colByName('doctor_id') ?? '',
      clinicId: r.colByName('clinic_id'),
      appointmentType: r.colByName('appointment_type') ?? 'CONSULTATION',
      scheduledAt: DateTime.tryParse(r.colByName('scheduled_at') ?? '') ?? DateTime.now(),
      durationMinutes: int.tryParse(r.colByName('duration_minutes') ?? '30') ?? 30,
      status: r.colByName('status') ?? 'SCHEDULED',
      reason: r.colByName('reason'),
      notes: r.colByName('notes'),
    );
  }
}

/// ---------------------------------------------------------------------------
/// WORKSTREAM 2: Cashier Shift Reconciliation Repository (FIN-006)
/// ---------------------------------------------------------------------------
class ShiftReconciliationService {
  final TransactionManager txManager;

  ShiftReconciliationService(this.txManager);

  Future<Map<String, dynamic>?> getCurrentOpenShift({
    required String hospitalCode,
    required int cashierStaffId,
  }) async {
    final res = await txManager.db.execute(
      '''
      SELECT * FROM mc_shifts
      WHERE hospital_code = :hosp AND cashier_staff_id = :staff_id AND status = 'OPEN'
      LIMIT 1
      ''',
      {'hosp': hospitalCode, 'staff_id': cashierStaffId},
    );
    if (res.rows.isEmpty) return null;
    final r = res.rows.first;
    return {
      'id': int.parse(r.colByName('id') ?? '0'),
      'shiftCode': r.colByName('shift_code'),
      'status': r.colByName('status'),
      'openingBalance': r.colByName('opening_balance'),
      'cashIn': r.colByName('cash_in'),
      'cashOut': r.colByName('cash_out'),
      'expectedCash': r.colByName('expected_cash'),
      'openedAt': r.colByName('opened_at'),
    };
  }

  Future<Map<String, dynamic>> closeShift({
    required ScopeContext scope,
    required int shiftId,
    required Decimal countedCash,
    String? notes,
  }) async {
    return await txManager.runInTransaction((tx) async {
      // 1. Lock shift FOR UPDATE
      final sRes = await tx.selectForUpdate(
        'SELECT * FROM mc_shifts WHERE hospital_code = :hosp AND id = :id',
        {'hosp': scope.hospitalCode, 'id': shiftId},
      );
      if (sRes.rows.isEmpty) {
        throw StateError('Shift $shiftId not found in tenant ${scope.hospitalCode}.');
      }

      final r = sRes.rows.first;
      if (r.colByName('status') != 'OPEN') {
        throw StateError('Shift $shiftId is already CLOSED.');
      }

      final openBal = Decimal.parse(r.colByName('opening_balance') ?? '0.0000');
      final cashIn = Decimal.parse(r.colByName('cash_in') ?? '0.0000');
      final cashOut = Decimal.parse(r.colByName('cash_out') ?? '0.0000');

      // FIN-006: ExpectedCash = OpeningBalance + CashIn - CashOut
      final expectedCash = openBal + cashIn - cashOut;
      // FIN-006: Variance = CountedCash - ExpectedCash
      final variance = countedCash - expectedCash;

      await tx.execute(
        '''
        UPDATE mc_shifts
        SET status = 'CLOSED',
            expected_cash = :exp_cash,
            counted_cash = :cnt_cash,
            variance_amount = :variance,
            closed_at = NOW(),
            closed_by = :closer,
            notes = :notes
        WHERE hospital_code = :hosp AND id = :id
        ''',
        {
          'hosp': scope.hospitalCode,
          'id': shiftId,
          'exp_cash': expectedCash.toStringAsFixed(4),
          'cnt_cash': countedCash.toStringAsFixed(4),
          'variance': variance.toStringAsFixed(4),
          'closer': scope.actor.id,
          'notes': notes,
        },
      );

      // Audit Log
      await tx.writeAuditLog(
        hospitalCode: scope.hospitalCode,
        actorStaffId: scope.actor.id,
        actorRole: scope.actor.role.name,
        deviceId: scope.deviceId,
        action: 'shift.close',
        entityType: 'mc_shifts',
        entityId: shiftId.toString(),
        afterState: {
          'expectedCash': expectedCash.toStringAsFixed(4),
          'countedCash': countedCash.toStringAsFixed(4),
          'variance': variance.toStringAsFixed(4),
        },
      );

      return {
        'shiftId': shiftId,
        'status': 'CLOSED',
        'openingBalance': openBal.toStringAsFixed(4),
        'cashIn': cashIn.toStringAsFixed(4),
        'cashOut': cashOut.toStringAsFixed(4),
        'expectedCash': expectedCash.toStringAsFixed(4),
        'countedCash': countedCash.toStringAsFixed(4),
        'variance': variance.toStringAsFixed(4),
      };
    });
  }
}

/// ---------------------------------------------------------------------------
/// WORKSTREAM 3: Clinical Encounters, Doctor Queue & SOAP Notes Repository
/// ---------------------------------------------------------------------------
class ClinicalEncounterRepository {
  final TransactionManager txManager;
  static const _uuid = Uuid();

  ClinicalEncounterRepository(this.txManager);

  Future<List<Map<String, dynamic>>> getDoctorQueue(ScopeContext scope) async {
    String sql;
    Map<String, dynamic> params;

    if (scope.isTenantWide) {
      sql = '''
        SELECT v.id, v.visit_number, v.patient_id, v.doctor_id, v.clinical_status,
               v.created_at, p.full_name AS patient_name, p.mrn
        FROM mc_visits v
        JOIN mc_patients p ON v.patient_id = p.id
        WHERE v.hospital_code = :hosp AND v.status = 'ACTIVE'
        ORDER BY v.id ASC
      ''';
      params = {'hosp': scope.hospitalCode};
    } else {
      sql = '''
        SELECT v.id, v.visit_number, v.patient_id, v.doctor_id, v.clinical_status,
               v.created_at, p.full_name AS patient_name, p.mrn
        FROM mc_visits v
        JOIN mc_patients p ON v.patient_id = p.id
        WHERE v.hospital_code = :hosp AND v.status = 'ACTIVE' AND v.doctor_id = :doc_id
        ORDER BY v.id ASC
      ''';
      params = {'hosp': scope.hospitalCode, 'doc_id': scope.actor.id};
    }

    final res = await txManager.db.execute(sql, params);
    return res.rows
        .map((r) => {
              'visitId': int.parse(r.colByName('id') ?? '0'),
              'visitNumber': r.colByName('visit_number'),
              'patientId': int.parse(r.colByName('patient_id') ?? '0'),
              'patientName': r.colByName('patient_name'),
              'mrn': r.colByName('mrn'),
              'doctorId': int.parse(r.colByName('doctor_id') ?? '0'),
              'clinicalStatus': r.colByName('clinical_status'),
              'createdAt': r.colByName('created_at'),
            })
        .toList();
  }

  Future<Map<String, dynamic>> createEncounter({
    required ScopeContext scope,
    required int visitId,
    required int patientId,
    required String encounterNumber,
    String? chiefComplaint,
    Map<String, dynamic>? vitals,
    Map<String, dynamic>? examination,
    Map<String, dynamic>? assessment,
    Map<String, dynamic>? plan,
    List<Map<String, dynamic>>? diagnoses,
    String? notes,
  }) async {
    return await txManager.runInTransaction((tx) async {
      // 1. Lock visit FOR UPDATE
      final vRes = await tx.selectForUpdate(
        'SELECT id, clinical_status FROM mc_visits WHERE hospital_code = :hosp AND id = :id',
        {'hosp': scope.hospitalCode, 'id': visitId},
      );
      if (vRes.rows.isEmpty) {
        throw StateError('Visit $visitId not found.');
      }

      final pubId = _uuid.v4();
      final idemp = 'ENC-${_uuid.v4()}';

      final encRes = await tx.execute(
        '''
        INSERT INTO mc_encounters (
          hospital_code, public_id, tenant_id, encounter_number,
          idempotency_key, patient_id, visit_id, provider_id,
          encounter_type, status, chief_complaint, vitals_json,
          examination_json, assessment_json, plan_json, diagnoses_json,
          notes, started_at, completed_at, occurred_at, created_by,
          created_at, updated_at
        ) VALUES (
          :hosp, :pub_id, :tenant, :enc_no,
          :idemp, :pid, :vid, :prov_id,
          'OUTPATIENT_CONSULTATION', 'COMPLETED', :complaint, :vitals,
          :exam, :assess, :plan, :diag,
          :notes, NOW(), NOW(), NOW(), :creator,
          NOW(), NOW()
        )
        ''',
        {
          'hosp': scope.hospitalCode,
          'pub_id': pubId,
          'tenant': scope.hospitalCode,
          'enc_no': encounterNumber,
          'idemp': idemp,
          'pid': patientId,
          'vid': visitId,
          'prov_id': scope.actor.id.toString(),
          'complaint': chiefComplaint,
          'vitals': vitals != null ? jsonEncode(vitals) : null,
          'exam': examination != null ? jsonEncode(examination) : null,
          'assess': assessment != null ? jsonEncode(assessment) : null,
          'plan': plan != null ? jsonEncode(plan) : null,
          'diag': diagnoses != null ? jsonEncode(diagnoses) : null,
          'notes': notes,
          'creator': scope.actor.id.toString(),
        },
      );

      final encounterId = encRes.lastInsertID.toInt();

      // 2. Transition visit clinical status to COMPLETED
      await tx.execute(
        "UPDATE mc_visits SET clinical_status = 'COMPLETED', updated_at = NOW() WHERE hospital_code = :hosp AND id = :id",
        {'hosp': scope.hospitalCode, 'id': visitId},
      );

      // 3. Audit log
      await tx.writeAuditLog(
        hospitalCode: scope.hospitalCode,
        actorStaffId: scope.actor.id,
        actorRole: scope.actor.role.name,
        deviceId: scope.deviceId,
        action: 'encounter.create',
        entityType: 'mc_encounters',
        entityId: encounterId.toString(),
        afterState: {
          'encounterNumber': encounterNumber,
          'visitId': visitId,
          'patientId': patientId,
          'clinicalStatus': 'COMPLETED',
        },
      );

      return {
        'encounterId': encounterId,
        'publicId': pubId,
        'encounterNumber': encounterNumber,
        'visitId': visitId,
        'status': 'COMPLETED',
      };
    });
  }
}

/// ---------------------------------------------------------------------------
/// WORKSTREAM 4: Electronic Prescriptions (e-Rx) Repository
/// ---------------------------------------------------------------------------
class PrescriptionRepository {
  final TransactionManager txManager;
  static const _uuid = Uuid();

  PrescriptionRepository(this.txManager);

  Future<Map<String, dynamic>> createPrescription({
    required ScopeContext scope,
    required int visitId,
    required int patientId,
    String? notes,
    required List<Map<String, dynamic>> items,
  }) async {
    if (items.isEmpty) {
      throw ArgumentError('Prescription must contain at least one item.');
    }

    return await txManager.runInTransaction((tx) async {
      // 1. Insert header
      final pRes = await tx.execute(
        '''
        INSERT INTO mc_prescriptions (
          hospital_code, visit_id, patient_id, doctor_id, doctor_name,
          notes, status, created_at
        ) VALUES (
          :hosp, :vid, :pid, :doc_id, :doc_name,
          :notes, 'ACTIVE', NOW()
        )
        ''',
        {
          'hosp': scope.hospitalCode,
          'vid': visitId,
          'pid': patientId,
          'doc_id': scope.actor.id,
          'doc_name': scope.actor.fullName,
          'notes': notes,
        },
      );
      final prescriptionId = pRes.lastInsertID.toInt();

      // 2. Insert items
      final insertedItems = <Map<String, dynamic>>[];
      for (final item in items) {
        final itemPubId = _uuid.v4();
        final qty = Decimal.parse((item['quantity'] ?? '1.0000').toString());
        final iRes = await tx.execute(
          '''
          INSERT INTO mc_prescription_items (
            hospital_code, public_id, tenant_id, prescription_id,
            medication_code, medication_name, dose, route,
            frequency, duration, quantity, instructions, status, created_at, updated_at
          ) VALUES (
            :hosp, :pub_id, :tenant, :rx_id,
            :mcode, :mname, :dose, :route,
            :freq, :dur, :qty, :inst, 'PENDING', NOW(), NOW()
          )
          ''',
          {
            'hosp': scope.hospitalCode,
            'pub_id': itemPubId,
            'tenant': scope.hospitalCode,
            'rx_id': prescriptionId,
            'mcode': item['medicationCode'] ?? 'MED-001',
            'mname': item['medicationName'] ?? 'Medication',
            'dose': item['dose'] ?? '500mg',
            'route': item['route'] ?? 'Oral',
            'freq': item['frequency'] ?? 'TID',
            'dur': item['duration'] ?? '5 days',
            'qty': qty.toStringAsFixed(4),
            'inst': item['instructions'],
          },
        );
        insertedItems.add({
          'id': iRes.lastInsertID.toInt(),
          'medicationCode': item['medicationCode'],
          'medicationName': item['medicationName'],
          'quantity': qty.toStringAsFixed(4),
          'status': 'PENDING',
        });
      }

      await tx.writeAuditLog(
        hospitalCode: scope.hospitalCode,
        actorStaffId: scope.actor.id,
        actorRole: scope.actor.role.name,
        deviceId: scope.deviceId,
        action: 'prescription.create',
        entityType: 'mc_prescriptions',
        entityId: prescriptionId.toString(),
        afterState: {'itemCount': items.length},
      );

      return {
        'prescriptionId': prescriptionId,
        'visitId': visitId,
        'patientId': patientId,
        'status': 'ACTIVE',
        'items': insertedItems,
      };
    });
  }

  Future<Map<String, dynamic>?> getPrescription(String hospitalCode, int id) async {
    final res = await txManager.db.execute(
      'SELECT * FROM mc_prescriptions WHERE hospital_code = :hosp AND id = :id LIMIT 1',
      {'hosp': hospitalCode, 'id': id},
    );
    if (res.rows.isEmpty) return null;
    final r = res.rows.first;

    final itemRes = await txManager.db.execute(
      'SELECT * FROM mc_prescription_items WHERE hospital_code = :hosp AND prescription_id = :id ORDER BY id ASC',
      {'hosp': hospitalCode, 'id': id},
    );

    return {
      'id': int.parse(r.colByName('id') ?? '0'),
      'visitId': int.parse(r.colByName('visit_id') ?? '0'),
      'patientId': int.parse(r.colByName('patient_id') ?? '0'),
      'doctorId': int.parse(r.colByName('doctor_id') ?? '0'),
      'doctorName': r.colByName('doctor_name'),
      'notes': r.colByName('notes'),
      'status': r.colByName('status'),
      'createdAt': r.colByName('created_at'),
      'items': itemRes.rows
          .map((ir) => {
                'id': int.parse(ir.colByName('id') ?? '0'),
                'medicationCode': ir.colByName('medication_code'),
                'medicationName': ir.colByName('medication_name'),
                'dose': ir.colByName('dose'),
                'route': ir.colByName('route'),
                'frequency': ir.colByName('frequency'),
                'duration': ir.colByName('duration'),
                'quantity': ir.colByName('quantity'),
                'status': ir.colByName('status'),
              })
          .toList(),
    };
  }
}

/// ---------------------------------------------------------------------------
/// WORKSTREAM 5: Diagnostic Orders & Results Entry Repository (LIS / RIS)
/// ---------------------------------------------------------------------------
class DiagnosticOrderRepository {
  final TransactionManager txManager;
  static const _uuid = Uuid();

  DiagnosticOrderRepository(this.txManager);

  Future<Map<String, dynamic>> createOrder({
    required ScopeContext scope,
    required int patientId,
    int? encounterId,
    required String orderType, // 'LAB' or 'RAD'
    String priority = 'ROUTINE',
    String? clinicalIndication,
    required List<Map<String, dynamic>> items,
  }) async {
    if (orderType != 'LAB' && orderType != 'RAD') {
      throw ArgumentError('orderType must be LAB or RAD.');
    }
    if (items.isEmpty) {
      throw ArgumentError('Order must contain at least one item.');
    }

    return await txManager.runInTransaction((tx) async {
      final pubId = _uuid.v4();
      final orderNo = 'ORD-${orderType}-${_uuid.v4().substring(0, 8).toUpperCase()}';
      final idemp = 'IDEMP-$orderNo';

      final oRes = await tx.execute(
        '''
        INSERT INTO mc_clinical_orders (
          hospital_code, public_id, tenant_id, order_number,
          idempotency_key, encounter_id, patient_id, provider_id,
          order_type, priority, status, clinical_indication,
          occurred_at, created_by, created_at, updated_at
        ) VALUES (
          :hosp, :pub_id, :tenant, :ord_no,
          :idemp, :enc_id, :pid, :prov_id,
          :otype, :prio, 'PENDING', :indication,
          NOW(), :creator, NOW(), NOW()
        )
        ''',
        {
          'hosp': scope.hospitalCode,
          'pub_id': pubId,
          'tenant': scope.hospitalCode,
          'ord_no': orderNo,
          'idemp': idemp,
          'enc_id': encounterId,
          'pid': patientId,
          'prov_id': scope.actor.id.toString(),
          'otype': orderType,
          'prio': priority,
          'indication': clinicalIndication,
          'creator': scope.actor.id.toString(),
        },
      );
      final orderId = oRes.lastInsertID.toInt();

      final createdItems = <Map<String, dynamic>>[];
      for (final item in items) {
        final itemPubId = _uuid.v4();
        final qty = Decimal.parse((item['quantity'] ?? '1.0000').toString());
        final price = Decimal.parse((item['price'] ?? '0.0000').toString());

        final iRes = await tx.execute(
          '''
          INSERT INTO mc_clinical_order_items (
            hospital_code, public_id, tenant_id, order_id,
            item_type, item_code, item_name, quantity, price, result_status,
            created_at, updated_at
          ) VALUES (
            :hosp, :pub_id, :tenant, :oid,
            :itype, :icode, :iname, :qty, :price, 'PENDING',
            NOW(), NOW()
          )
          ''',
          {
            'hosp': scope.hospitalCode,
            'pub_id': itemPubId,
            'tenant': scope.hospitalCode,
            'oid': orderId,
            'itype': orderType,
            'icode': item['itemCode'] ?? 'TEST-001',
            'iname': item['itemName'] ?? 'Test Item',
            'qty': qty.toStringAsFixed(4),
            'price': price.toStringAsFixed(4),
          },
        );
        createdItems.add({
          'id': iRes.lastInsertID.toInt(),
          'itemCode': item['itemCode'],
          'itemName': item['itemName'],
          'resultStatus': 'PENDING',
        });
      }

      await tx.writeAuditLog(
        hospitalCode: scope.hospitalCode,
        actorStaffId: scope.actor.id,
        actorRole: scope.actor.role.name,
        deviceId: scope.deviceId,
        action: 'order.create',
        entityType: 'mc_clinical_orders',
        entityId: orderId.toString(),
        afterState: {'orderNumber': orderNo, 'itemCount': items.length},
      );

      return {
        'orderId': orderId,
        'orderNumber': orderNo,
        'orderType': orderType,
        'status': 'PENDING',
        'items': createdItems,
      };
    });
  }

  Future<List<Map<String, dynamic>>> listOrders(
    ScopeContext scope, {
    String? orderType,
    String? status,
  }) async {
    final conditions = ['hospital_code = :hosp'];
    final params = <String, dynamic>{'hosp': scope.hospitalCode};

    if (orderType != null) {
      conditions.add('order_type = :otype');
      params['otype'] = orderType;
    }
    if (status != null) {
      conditions.add('status = :status');
      params['status'] = status;
    }

    final sql = '''
      SELECT * FROM mc_clinical_orders
      WHERE ${conditions.join(' AND ')}
      ORDER BY id DESC
    ''';

    final res = await txManager.db.execute(sql, params);
    return res.rows
        .map((r) => {
              'id': int.parse(r.colByName('id') ?? '0'),
              'orderNumber': r.colByName('order_number'),
              'patientId': int.parse(r.colByName('patient_id') ?? '0'),
              'orderType': r.colByName('order_type'),
              'priority': r.colByName('priority'),
              'status': r.colByName('status'),
              'clinicalIndication': r.colByName('clinical_indication'),
              'occurredAt': r.colByName('occurred_at'),
            })
        .toList();
  }

  Future<Map<String, dynamic>> recordResult({
    required ScopeContext scope,
    required int orderId,
    required int orderItemId,
    required String resultType,
    required Map<String, dynamic> resultJson,
    bool isCriticalPanic = false,
    String? notes,
  }) async {
    return await txManager.runInTransaction((tx) async {
      // 1. Lock order & item FOR UPDATE
      final oRes = await tx.selectForUpdate(
        'SELECT id, status FROM mc_clinical_orders WHERE hospital_code = :hosp AND id = :id',
        {'hosp': scope.hospitalCode, 'id': orderId},
      );
      if (oRes.rows.isEmpty) throw StateError('Order $orderId not found.');

      final pubId = _uuid.v4();
      final idemp = 'RES-${_uuid.v4()}';

      // 2. Insert result
      final rRes = await tx.execute(
        '''
        INSERT INTO mc_clinical_results (
          hospital_code, public_id, tenant_id, order_id, item_id,
          result_type, result_json, status, idempotency_key,
          entered_by, entered_at, critical_flag, notes, created_at, updated_at
        ) VALUES (
          :hosp, :pub_id, :tenant, :oid, :item_id,
          :rtype, :rjson, 'COMPLETED', :idemp,
          :entered_by, NOW(), :crit, :notes, NOW(), NOW()
        )
        ''',
        {
          'hosp': scope.hospitalCode,
          'pub_id': pubId,
          'tenant': scope.hospitalCode,
          'oid': orderId,
          'item_id': orderItemId,
          'rtype': resultType,
          'rjson': jsonEncode(resultJson),
          'idemp': idemp,
          'entered_by': scope.actor.fullName,
          'crit': isCriticalPanic ? 1 : 0,
          'notes': notes,
        },
      );
      final resultId = rRes.lastInsertID.toInt();

      // 3. Update order item status
      await tx.execute(
        "UPDATE mc_clinical_order_items SET result_status = 'COMPLETED', updated_at = NOW() WHERE hospital_code = :hosp AND id = :id",
        {'hosp': scope.hospitalCode, 'id': orderItemId},
      );

      // 4. Update order status to COMPLETED
      await tx.execute(
        "UPDATE mc_clinical_orders SET status = 'COMPLETED', updated_at = NOW() WHERE hospital_code = :hosp AND id = :id",
        {'hosp': scope.hospitalCode, 'id': orderId},
      );

      // 5. Audit log
      await tx.writeAuditLog(
        hospitalCode: scope.hospitalCode,
        actorStaffId: scope.actor.id,
        actorRole: scope.actor.role.name,
        deviceId: scope.deviceId,
        action: 'result.record',
        entityType: 'mc_clinical_results',
        entityId: resultId.toString(),
        afterState: {
          'orderId': orderId,
          'orderItemId': orderItemId,
          'criticalFlag': isCriticalPanic,
        },
      );

      return {
        'resultId': resultId,
        'orderId': orderId,
        'orderItemId': orderItemId,
        'status': 'COMPLETED',
        'criticalFlag': isCriticalPanic,
      };
    });
  }
}

/// ---------------------------------------------------------------------------
/// WORKSTREAM 6: FIFO Inventory & Pharmacy Dispensing Repository (CLN-004 & FIN-004)
/// ---------------------------------------------------------------------------
class InventoryPharmacyRepository {
  final TransactionManager txManager;
  static const _uuid = Uuid();

  InventoryPharmacyRepository(this.txManager);

  Future<List<Map<String, dynamic>>> listItems(ScopeContext scope) async {
    final res = await txManager.db.execute(
      'SELECT * FROM mc_inventory_items WHERE hospital_code = :hosp ORDER BY id ASC',
      {'hosp': scope.hospitalCode},
    );
    return res.rows
        .map((r) => {
              'id': int.parse(r.colByName('id') ?? '0'),
              'itemNumber': r.colByName('item_number'),
              'itemCode': r.colByName('item_code'),
              'name': r.colByName('name'),
              'unit': r.colByName('unit'),
              'status': r.colByName('status'),
            })
        .toList();
  }

  Future<List<Map<String, dynamic>>> listBatches(ScopeContext scope, {int? itemId}) async {
    String sql = 'SELECT * FROM mc_inventory_batches WHERE hospital_code = :hosp';
    final params = <String, dynamic>{'hosp': scope.hospitalCode};
    if (itemId != null) {
      sql += ' AND item_id = :item_id';
      params['item_id'] = itemId;
    }
    sql += ' ORDER BY expiry_date ASC, id ASC';

    final res = await txManager.db.execute(sql, params);
    return res.rows
        .map((r) => {
              'id': int.parse(r.colByName('id') ?? '0'),
              'itemId': int.parse(r.colByName('item_id') ?? '0'),
              'batchNumber': r.colByName('batch_number'),
              'expiryDate': r.colByName('expiry_date'),
              'unitCost': r.colByName('unit_cost'),
              'currency': r.colByName('currency'),
            })
        .toList();
  }

  Future<Map<String, dynamic>> dispensePrescriptionItem({
    required ScopeContext scope,
    required int prescriptionId,
    required int prescriptionItemId,
    required int inventoryItemId,
    required int shiftId,
    required Decimal quantity,
  }) async {
    return await txManager.runInTransaction((tx) async {
      // 1. Lock prescription item FOR UPDATE
      final piRes = await tx.selectForUpdate(
        'SELECT * FROM mc_prescription_items WHERE hospital_code = :hosp AND id = :id AND prescription_id = :rx_id',
        {
          'hosp': scope.hospitalCode,
          'id': prescriptionItemId,
          'rx_id': prescriptionId,
        },
      );
      if (piRes.rows.isEmpty) {
        throw StateError('Prescription item $prescriptionItemId not found.');
      }
      if (piRes.rows.first.colByName('status') == 'DISPENSED') {
        throw StateError('Prescription item $prescriptionItemId is already DISPENSED.');
      }

      // 2. Lock earliest non-expired batch FOR UPDATE (CLN-004 FIFO Invariant)
      final bRes = await tx.selectForUpdate(
        '''
        SELECT * FROM mc_inventory_batches
        WHERE hospital_code = :hosp AND item_id = :item_id AND expiry_date >= CURDATE()
        ORDER BY expiry_date ASC, id ASC
        LIMIT 1
        ''',
        {'hosp': scope.hospitalCode, 'item_id': inventoryItemId},
      );
      if (bRes.rows.isEmpty) {
        throw StateError('No valid non-expired batch found for item $inventoryItemId.');
      }
      final batch = bRes.rows.first;
      final batchId = int.parse(batch.colByName('id') ?? '0');
      final unitCost = Decimal.parse(batch.colByName('unit_cost') ?? '0.0000');
      final totalFifoCost = quantity * unitCost;

      // 3. Record inventory movement (reduction)
      final movNo = 'MOV-${_uuid.v4().substring(0, 8).toUpperCase()}';
      await tx.execute(
        '''
        INSERT INTO mc_inventory_movements (
          hospital_code, public_id, tenant_id, movement_number,
          movement_type, item_id, batch_id, quantity, unit_cost,
          occurred_at, created_by
        ) VALUES (
          :hosp, :pub_id, :tenant, :mno,
          'PHARMACY_DISPENSE', :iid, :bid, :qty, :ucost,
          NOW(), :creator
        )
        ''',
        {
          'hosp': scope.hospitalCode,
          'pub_id': _uuid.v4(),
          'tenant': scope.hospitalCode,
          'mno': movNo,
          'iid': inventoryItemId,
          'bid': batchId,
          'qty': quantity.toStringAsFixed(4),
          'ucost': unitCost.toStringAsFixed(4),
          'creator': scope.actor.id.toString(),
        },
      );

      // 4. Record pharmacy dispense
      final dRes = await tx.execute(
        '''
        INSERT INTO mc_pharmacy_dispenses (
          hospital_code, public_id, tenant_id, prescription_id,
          prescription_item_id, inventory_item_id, batch_id,
          quantity, unit_cost, dispensed_by, status, occurred_at
        ) VALUES (
          :hosp, :pub_id, :tenant, :rx_id,
          :piid, :iid, :bid,
          :qty, :ucost, :dispenser, 'DISPENSED', NOW()
        )
        ''',
        {
          'hosp': scope.hospitalCode,
          'pub_id': _uuid.v4(),
          'tenant': scope.hospitalCode,
          'rx_id': prescriptionId,
          'piid': prescriptionItemId,
          'iid': inventoryItemId,
          'bid': batchId,
          'qty': quantity.toStringAsFixed(4),
          'ucost': unitCost.toStringAsFixed(4),
          'dispenser': scope.actor.fullName,
        },
      );
      final dispenseId = dRes.lastInsertID.toInt();

      // 5. Update prescription item status to DISPENSED
      await tx.execute(
        "UPDATE mc_prescription_items SET status = 'DISPENSED', updated_at = NOW() WHERE hospital_code = :hosp AND id = :id",
        {'hosp': scope.hospitalCode, 'id': prescriptionItemId},
      );

      // 6. Balanced double-entry financial postings for COGS (FIN-002 & FIN-004)
      if (totalFifoCost > Decimal.zero) {
        final evUuid = 'EV-${_uuid.v4()}';
        final evRes = await tx.execute(
          '''
          INSERT INTO mc_financial_events (
            event_uuid, hospital_code, idempotency_key, event_type,
            source_module, source_entity_type, source_entity_id, shift_id,
            gross_amount, discount_amount, net_amount, paid_amount,
            insurance_covered_amount, patient_responsibility_amount, balance_amount,
            status, created_by
          ) VALUES (
            :uuid, :hosp, :idemp, 'PHARMACY_DISPENSE',
            'PHARMACY', 'DISPENSE', :did, :sid,
            :amt, '0.0000', :amt, '0.0000',
            '0.0000', '0.0000', '0.0000',
            'POSTED', :creator
          )
          ''',
          {
            'uuid': evUuid,
            'hosp': scope.hospitalCode,
            'idemp': 'IDEMP-$movNo',
            'did': dispenseId,
            'sid': shiftId,
            'amt': totalFifoCost.toStringAsFixed(4),
            'creator': scope.actor.id,
          },
        );
        final eventId = evRes.lastInsertID.toInt();

        // Leg 1: Expense COGS
        await tx.execute(
          '''
          INSERT INTO mc_financial_postings (
            posting_uuid, hospital_code, event_id, posting_type,
            account_bucket, direction, amount, shift_id, status
          ) VALUES (
            :puuid, :hosp, :evid, 'COGS_DISPENSE',
            'EXPENSE_COGS_CONSUMABLES', 'DEBIT', :amt, :sid, 'POSTED'
          )
          ''',
          {
            'puuid': 'POST-${_uuid.v4()}',
            'hosp': scope.hospitalCode,
            'evid': eventId,
            'amt': totalFifoCost.toStringAsFixed(4),
            'sid': shiftId,
          },
        );
        // Leg 2: Inventory Relief Asset
        await tx.execute(
          '''
          INSERT INTO mc_financial_postings (
            posting_uuid, hospital_code, event_id, posting_type,
            account_bucket, direction, amount, shift_id, status
          ) VALUES (
            :puuid, :hosp, :evid, 'INVENTORY_RELIEF',
            'ASSET_INVENTORY_STOCK', 'CREDIT', :amt, :sid, 'POSTED'
          )
          ''',
          {
            'puuid': 'POST-${_uuid.v4()}',
            'hosp': scope.hospitalCode,
            'evid': eventId,
            'amt': totalFifoCost.toStringAsFixed(4),
            'sid': shiftId,
          },
        );
      }

      // 7. Audit log
      await tx.writeAuditLog(
        hospitalCode: scope.hospitalCode,
        actorStaffId: scope.actor.id,
        actorRole: scope.actor.role.name,
        deviceId: scope.deviceId,
        action: 'pharmacy.dispense',
        entityType: 'mc_pharmacy_dispenses',
        entityId: dispenseId.toString(),
        afterState: {
          'prescriptionItemId': prescriptionItemId,
          'batchId': batchId,
          'quantity': quantity.toStringAsFixed(4),
          'totalFifoCost': totalFifoCost.toStringAsFixed(4),
        },
      );

      return {
        'dispenseId': dispenseId,
        'prescriptionItemId': prescriptionItemId,
        'batchId': batchId,
        'quantity': quantity.toStringAsFixed(4),
        'unitCost': unitCost.toStringAsFixed(4),
        'totalCost': totalFifoCost.toStringAsFixed(4),
        'status': 'DISPENSED',
      };
    });
  }
}

/// ---------------------------------------------------------------------------
/// WORKSTREAM 7: Inpatient Bed Map & Admissions Repository (CLN-005)
/// ---------------------------------------------------------------------------
class InpatientAdmissionRepository {
  final TransactionManager txManager;
  static const _uuid = Uuid();

  InpatientAdmissionRepository(this.txManager);

  Future<List<Map<String, dynamic>>> listBeds(ScopeContext scope, {String? departmentId}) async {
    String sql = 'SELECT * FROM mc_ward_beds WHERE hospital_code = :hosp';
    final params = <String, dynamic>{'hosp': scope.hospitalCode};
    if (departmentId != null) {
      sql += ' AND department_id = :dept';
      params['dept'] = departmentId;
    }
    sql += ' ORDER BY room_id ASC, bed_number ASC';

    final res = await txManager.db.execute(sql, params);
    return res.rows
        .map((r) => {
              'id': int.parse(r.colByName('id') ?? '0'),
              'departmentId': r.colByName('department_id'),
              'roomId': r.colByName('room_id'),
              'bedNumber': r.colByName('bed_number'),
              'status': r.colByName('status'),
            })
        .toList();
  }

  Future<Map<String, dynamic>> admitPatient({
    required ScopeContext scope,
    required String patientId,
    required String bedId,
    String? departmentId,
    String? roomId,
    String admissionType = 'EMERGENCY',
    String? attendingDoctorId,
    String? diagnosisJson,
  }) async {
    return await txManager.runInTransaction((tx) async {
      // 1. Lock bed FOR UPDATE (CLN-005 Exclusive Bed Lock)
      final bRes = await tx.selectForUpdate(
        'SELECT id, status FROM mc_ward_beds WHERE hospital_code = :hosp AND id = :id',
        {'hosp': scope.hospitalCode, 'id': int.parse(bedId)},
      );
      if (bRes.rows.isEmpty) throw StateError('Bed $bedId not found.');
      final currentBedStatus = bRes.rows.first.colByName('status');
      if (currentBedStatus != 'AVAILABLE') {
        throw StateError('CLN-005 Violation: Bed $bedId is $currentBedStatus (not AVAILABLE).');
      }

      // 2. Update bed to OCCUPIED
      await tx.execute(
        "UPDATE mc_ward_beds SET status = 'OCCUPIED' WHERE hospital_code = :hosp AND id = :id",
        {'hosp': scope.hospitalCode, 'id': int.parse(bedId)},
      );

      // 3. Create admission record
      final pubId = _uuid.v4();
      final idemp = 'ADM-${_uuid.v4()}';
      final aRes = await tx.execute(
        '''
        INSERT INTO mc_admissions (
          hospital_code, tenant_id, public_id, patient_id,
          admission_type, department_id, room_id, bed_id,
          admission_date, attending_doctor_id, diagnosis_json,
          status, created_by, idempotency_key, created_at
        ) VALUES (
          :hosp, :tenant, :pub_id, :pid,
          :atype, :dept, :room, :bed,
          NOW(), :att_doc, :diag,
          'Admitted', :creator, :idemp, NOW()
        )
        ''',
        {
          'hosp': scope.hospitalCode,
          'tenant': scope.hospitalCode,
          'pub_id': pubId,
          'pid': patientId,
          'atype': admissionType,
          'dept': departmentId,
          'room': roomId,
          'bed': bedId,
          'att_doc': attendingDoctorId ?? scope.actor.id.toString(),
          'diag': diagnosisJson,
          'creator': scope.actor.fullName,
          'idemp': idemp,
        },
      );
      final admissionId = aRes.lastInsertID.toInt();

      await tx.writeAuditLog(
        hospitalCode: scope.hospitalCode,
        actorStaffId: scope.actor.id,
        actorRole: scope.actor.role.name,
        deviceId: scope.deviceId,
        action: 'admission.create',
        entityType: 'mc_admissions',
        entityId: admissionId.toString(),
        afterState: {'bedId': bedId, 'patientId': patientId, 'status': 'Admitted'},
      );

      return {
        'admissionId': admissionId,
        'patientId': patientId,
        'bedId': bedId,
        'status': 'Admitted',
      };
    });
  }

  Future<Map<String, dynamic>> dischargePatient({
    required ScopeContext scope,
    required int admissionId,
    String? dischargeReason,
  }) async {
    return await txManager.runInTransaction((tx) async {
      // 1. Lock admission FOR UPDATE
      final aRes = await tx.selectForUpdate(
        'SELECT * FROM mc_admissions WHERE hospital_code = :hosp AND id = :id',
        {'hosp': scope.hospitalCode, 'id': admissionId},
      );
      if (aRes.rows.isEmpty) throw StateError('Admission $admissionId not found.');
      final adm = aRes.rows.first;
      if (adm.colByName('status') != 'Admitted') {
        throw StateError('Admission $admissionId is already discharged.');
      }
      final bedId = adm.colByName('bed_id');

      // 2. Update admission to Discharged
      await tx.execute(
        '''
        UPDATE mc_admissions
        SET status = 'Discharged',
            actual_discharge_date = NOW(),
            discharge_date = NOW(),
            discharge_reason = :reason,
            updated_at = NOW()
        WHERE hospital_code = :hosp AND id = :id
        ''',
        {
          'hosp': scope.hospitalCode,
          'id': admissionId,
          'reason': dischargeReason ?? 'Routine discharge',
        },
      );

      // 3. Release bed back to AVAILABLE
      if (bedId != null && bedId.isNotEmpty) {
        await tx.execute(
          "UPDATE mc_ward_beds SET status = 'AVAILABLE' WHERE hospital_code = :hosp AND id = :bid",
          {'hosp': scope.hospitalCode, 'bid': int.parse(bedId)},
        );
      }

      await tx.writeAuditLog(
        hospitalCode: scope.hospitalCode,
        actorStaffId: scope.actor.id,
        actorRole: scope.actor.role.name,
        deviceId: scope.deviceId,
        action: 'admission.discharge',
        entityType: 'mc_admissions',
        entityId: admissionId.toString(),
        afterState: {'admissionId': admissionId, 'bedId': bedId, 'status': 'Discharged'},
      );

      return {
        'admissionId': admissionId,
        'bedId': bedId,
        'status': 'Discharged',
      };
    });
  }
}

/// ---------------------------------------------------------------------------
/// WORKSTREAM 8: Financial Settlement & Dual Control Repository (FIN-007 & SEC-005)
/// ---------------------------------------------------------------------------
class FinancialSettlementRepository {
  final TransactionManager txManager;
  static const _uuid = Uuid();

  FinancialSettlementRepository(this.txManager);

  /// Step 1 of Two-Person Integrity: Cashier requests commission settlement.
  /// Creates a record in `mc_financial_settlements` with status 'REQUESTED' and a
  /// corresponding dual control request in `mc_dual_control_request` with status 'PENDING'.
  Future<Map<String, dynamic>> requestSettlement({
    required ScopeContext scope,
    required int doctorId,
    required Decimal settleAmount,
    required int shiftId,
    String? notes,
  }) async {
    if (settleAmount <= Decimal.zero) {
      throw ArgumentError('Settlement amount must be positive and greater than zero.');
    }
    return await txManager.runInTransaction((tx) async {
      // 1. Verify doctor exists in tenant
      final docRes = await tx.execute(
        'SELECT id FROM mc_staff WHERE hospital_code = :hosp AND id = :docId',
        {'hosp': scope.hospitalCode, 'docId': doctorId},
      );
      if (docRes.rows.isEmpty) {
        throw StateError('Doctor $doctorId not found in tenant ${scope.hospitalCode}.');
      }

      // 2. Lock and verify shift is OPEN (FIN-006 & Invariant 2)
      final sRes = await tx.selectForUpdate(
        'SELECT * FROM mc_shifts WHERE hospital_code = :hosp AND id = :sid',
        {'hosp': scope.hospitalCode, 'sid': shiftId},
      );
      if (sRes.rows.isEmpty) {
        throw StateError('Shift $shiftId not found in tenant ${scope.hospitalCode}.');
      }
      if (sRes.rows.first.colByName('status') != 'OPEN') {
        throw StateError('Shift $shiftId is already CLOSED. Cannot request settlement on closed shift.');
      }

      // 3. Lock unpaid commission accrual postings FOR UPDATE and check balance
      final pRes = await tx.selectForUpdate(
        '''
        SELECT id, amount FROM mc_financial_postings
        WHERE hospital_code = :hosp
          AND posting_type = 'COMMISSION_ACCRUAL'
          AND beneficiary_id = :doc_id
          AND status = 'POSTED'
        ORDER BY id ASC
        ''',
        {'hosp': scope.hospitalCode, 'doc_id': doctorId},
      );

      var totalAccrued = Decimal.zero;
      for (final row in pRes.rows) {
        totalAccrued += Decimal.parse(row.colByName('amount') ?? '0.0000');
      }

      if (totalAccrued < settleAmount) {
        throw StateError(
          'Insufficient accrued commission: Accrued($totalAccrued) < Requested($settleAmount).',
        );
      }

      // 4. Insert Settlement Record with status 'REQUESTED' (pending dual control approval)
      final pubId = _uuid.v4();
      final setNo = 'SET-${_uuid.v4().substring(0, 8).toUpperCase()}';
      final sIns = await tx.execute(
        '''
        INSERT INTO mc_financial_settlements (
          hospital_code, public_id, tenant_id, earning_line_id, settlement_number,
          settlement_type, amount, currency, beneficiary_type, beneficiary_id,
          status, requested_by, approved_by, delivered_by,
          requested_at, approved_at, delivered_at, idempotency_key
        ) VALUES (
          :hosp, :pub_id, :tenant, 0, :sno,
          'COMMISSION_PAYOUT', :amt, 'EGP', 'DOCTOR', :doc_id,
          'REQUESTED', :requester, NULL, NULL,
          NOW(), NULL, NULL, :idemp
        )
        ''',
        {
          'hosp': scope.hospitalCode,
          'pub_id': pubId,
          'tenant': scope.hospitalCode,
          'sno': setNo,
          'amt': settleAmount.toStringAsFixed(4),
          'doc_id': doctorId.toString(),
          'requester': scope.actor.fullName,
          'idemp': 'IDEMP-$setNo',
        },
      );
      final settlementId = sIns.lastInsertID.toInt();

      // 5. Create dual control request in mc_dual_control_request (SEC-005)
      final reqUuid = 'REQ-SET-${_uuid.v4().substring(0, 8).toUpperCase()}';
      final rIns = await tx.execute(
        '''
        INSERT INTO mc_dual_control_request (
          request_uuid, hospital_code, action_type,
          target_entity_type, target_entity_id, requested_amount,
          payload_json, requester_staff_id, status, reason, created_at
        ) VALUES (
          :ruuid, :hosp, 'COMMISSION_SETTLEMENT',
          'mc_financial_settlements', :target_id, :amt,
          :payload, :requester_id, 'PENDING', :reason, NOW()
        )
        ''',
        {
          'ruuid': reqUuid,
          'hosp': scope.hospitalCode,
          'target_id': settlementId.toString(),
          'amt': settleAmount.toStringAsFixed(4),
          'payload': jsonEncode({
            'settlementId': settlementId,
            'settlementNumber': setNo,
            'doctorId': doctorId,
            'settleAmount': settleAmount.toStringAsFixed(4),
            'shiftId': shiftId,
          }),
          'requester_id': scope.actor.id,
          'reason': notes ?? 'Doctor commission settlement request',
        },
      );
      final requestId = rIns.lastInsertID.toInt();

      await tx.writeAuditLog(
        hospitalCode: scope.hospitalCode,
        actorStaffId: scope.actor.id,
        actorRole: scope.actor.role.name,
        deviceId: scope.deviceId,
        action: 'finance.settlement_requested',
        entityType: 'mc_financial_settlements',
        entityId: settlementId.toString(),
        afterState: {
          'settlementId': settlementId,
          'requestId': requestId,
          'doctorId': doctorId,
          'amount': settleAmount.toStringAsFixed(4),
          'shiftId': shiftId,
          'status': 'REQUESTED',
        },
      );

      return {
        'settlementId': settlementId,
        'requestId': requestId,
        'settlementNumber': setNo,
        'doctorId': doctorId,
        'amount': settleAmount.toStringAsFixed(4),
        'status': 'REQUESTED',
      };
    });
  }

  /// Step 3 of Two-Person Integrity: Cashier delivers/pays out an APPROVED settlement.
  /// Consumes accrued commission postings, posts balanced double-entry (DEBIT Payable, CREDIT Cash),
  /// updates open shift cash_out, marks settlement 'SETTLED', and marks dual control request 'EXECUTED'.
  Future<Map<String, dynamic>> deliverSettlement({
    required ScopeContext scope,
    required int settlementId,
    required int shiftId,
  }) async {
    return await txManager.runInTransaction((tx) async {
      // 1. Lock Settlement Record FOR UPDATE
      final sRes = await tx.selectForUpdate(
        '''
        SELECT * FROM mc_financial_settlements
        WHERE hospital_code = :hosp AND id = :id
        ''',
        {'hosp': scope.hospitalCode, 'id': settlementId},
      );
      if (sRes.rows.isEmpty) {
        throw StateError('Settlement $settlementId not found in tenant ${scope.hospitalCode}.');
      }
      final sRow = sRes.rows.first;
      final sStatus = sRow.colByName('status');
      if (sStatus == 'REQUESTED') {
        throw RbacForbiddenException(
          code: 'DUAL_CONTROL_APPROVAL_REQUIRED',
          message: 'Two-person integrity violation: Settlement $settlementId has not been approved by an independent supervisor.',
          requiredPermission: 'finance_Settlements',
        );
      }
      if (sStatus == 'SETTLED') {
        throw StateError('Settlement $settlementId is already SETTLED.');
      }
      if (sStatus != 'APPROVED') {
        throw StateError('Settlement $settlementId is in invalid status $sStatus.');
      }

      final settleAmount = Decimal.parse(sRow.colByName('amount') ?? '0.0000');
      final doctorId = int.parse(sRow.colByName('beneficiary_id') ?? '0');
      final setNo = sRow.colByName('settlement_number') ?? '';

      // 2. Lock shift FOR UPDATE and verify OPEN (FIN-006 & Invariant 2)
      final shiftRes = await tx.selectForUpdate(
        'SELECT * FROM mc_shifts WHERE hospital_code = :hosp AND id = :sid',
        {'hosp': scope.hospitalCode, 'sid': shiftId},
      );
      if (shiftRes.rows.isEmpty) {
        throw StateError('Shift $shiftId not found in tenant ${scope.hospitalCode}.');
      }
      if (shiftRes.rows.first.colByName('status') != 'OPEN') {
        throw StateError('Shift $shiftId is CLOSED. Cannot deliver settlement on closed shift.');
      }

      // 3. Lock unpaid commission accrual postings FOR UPDATE
      final pRes = await tx.selectForUpdate(
        '''
        SELECT id, event_id, posting_uuid, posting_type, account_bucket, direction, amount,
               beneficiary_type, beneficiary_id, shift_id
        FROM mc_financial_postings
        WHERE hospital_code = :hosp
          AND posting_type = 'COMMISSION_ACCRUAL'
          AND beneficiary_id = :doc_id
          AND status = 'POSTED'
        ORDER BY id ASC
        ''',
        {'hosp': scope.hospitalCode, 'doc_id': doctorId},
      );

      var totalAccrued = Decimal.zero;
      for (final row in pRes.rows) {
        totalAccrued += Decimal.parse(row.colByName('amount') ?? '0.0000');
      }

      if (totalAccrued < settleAmount) {
        throw StateError(
          'Insufficient accrued commission: Accrued($totalAccrued) < Requested($settleAmount).',
        );
      }

      // 4. Consume accrual postings up to settleAmount with partial split support (FIN-007 & F-FIN-01)
      var remainingToSettle = settleAmount;

      for (final row in pRes.rows) {
        if (remainingToSettle <= Decimal.zero) break;

        final pId = int.parse(row.colByName('id')!);
        final pAmt = Decimal.parse(row.colByName('amount') ?? '0.0000');

        if (pAmt <= remainingToSettle) {
          // Fully consumed posting row
          await tx.execute(
            '''
            UPDATE mc_financial_postings
            SET status = 'SETTLED', settlement_id = :sid
            WHERE hospital_code = :hosp AND id = :pid
            ''',
            {'hosp': scope.hospitalCode, 'sid': settlementId, 'pid': pId},
          );
          remainingToSettle -= pAmt;
        } else {
          // Partially consumed posting row (F-FIN-01 Splittable Remainder Preservation):
          // The consumed portion matches remainingToSettle; the remainder stays POSTED
          final consumedAmt = remainingToSettle;
          final leftoverAmt = pAmt - consumedAmt;

          // Update existing row to represent the consumed portion linked to this settlement
          await tx.execute(
            '''
            UPDATE mc_financial_postings
            SET amount = :consumedAmt, status = 'SETTLED', settlement_id = :sid
            WHERE hospital_code = :hosp AND id = :pid
            ''',
            {
              'hosp': scope.hospitalCode,
              'consumedAmt': consumedAmt.toStringAsFixed(4),
              'sid': settlementId,
              'pid': pId,
            },
          );

          // Insert new row for the leftover unconsumed accrual balance
          final newRemainderUuid = 'POST-${_uuid.v4()}';
          await tx.execute(
            '''
            INSERT INTO mc_financial_postings (
              posting_uuid, hospital_code, event_id, posting_type,
              account_bucket, direction, amount,
              beneficiary_type, beneficiary_id, shift_id, status
            ) VALUES (
              :puuid, :hosp, :evid, :ptype,
              :bucket, :dir, :amt,
              :btype, :bid, :sid, 'POSTED'
            )
            ''',
            {
              'puuid': newRemainderUuid,
              'hosp': scope.hospitalCode,
              'evid': row.colByName('event_id')!,
              'ptype': row.colByName('posting_type')!,
              'bucket': row.colByName('account_bucket')!,
              'dir': row.colByName('direction')!,
              'amt': leftoverAmt.toStringAsFixed(4),
              'btype': row.colByName('beneficiary_type'),
              'bid': row.colByName('beneficiary_id'),
              'sid': row.colByName('shift_id'),
            },
          );

          remainingToSettle = Decimal.zero;
          break;
        }
      }

      // 5. Insert Financial Event Header for Settlement (FIN-002)
      final evUuid = 'EV-${_uuid.v4()}';
      final evRes = await tx.execute(
        '''
        INSERT INTO mc_financial_events (
          event_uuid, hospital_code, idempotency_key, event_type,
          source_module, source_entity_type, source_entity_id, shift_id,
          gross_amount, discount_amount, net_amount, paid_amount,
          insurance_covered_amount, patient_responsibility_amount, balance_amount,
          status, created_by
        ) VALUES (
          :uuid, :hosp, :idemp, 'COMMISSION_SETTLEMENT',
          'FINANCE', 'SETTLEMENT', :sid_entity, :sid,
          :amt, '0.0000', :amt, :amt,
          '0.0000', '0.0000', '0.0000',
          'POSTED', :creator
        )
        ''',
        {
          'uuid': evUuid,
          'hosp': scope.hospitalCode,
          'idemp': 'IDEMP-DELIV-$setNo',
          'sid_entity': settlementId,
          'sid': shiftId,
          'amt': settleAmount.toStringAsFixed(4),
          'creator': scope.actor.id,
        },
      );
      final eventId = evRes.lastInsertID.toInt();

      // 6. Post Balanced Double-Entry Settlement Legs (FIN-007 Fixes P3 Double-Debit Bug!)
      // Leg 1: Liability Reduction (DEBIT PAYABLE_COMMISSION_DOCTOR)
      await tx.execute(
        '''
        INSERT INTO mc_financial_postings (
          posting_uuid, hospital_code, event_id, posting_type,
          account_bucket, direction, amount, beneficiary_type, beneficiary_id, shift_id, settlement_id, status
        ) VALUES (
          :puuid, :hosp, :evid, 'SETTLEMENT_LIABILITY',
          'PAYABLE_COMMISSION_DOCTOR', 'DEBIT', :amt, 'DOCTOR', :doc_id, :sid, :setid, 'POSTED'
        )
        ''',
        {
          'puuid': 'POST-${_uuid.v4()}',
          'hosp': scope.hospitalCode,
          'evid': eventId,
          'amt': settleAmount.toStringAsFixed(4),
          'doc_id': doctorId,
          'sid': shiftId,
          'setid': settlementId,
        },
      );

      // Leg 2: Treasury Cash Outflow (CREDIT CASH_ON_HAND) -> Strictly CREDIT!
      await tx.execute(
        '''
        INSERT INTO mc_financial_postings (
          posting_uuid, hospital_code, event_id, posting_type,
          account_bucket, direction, amount, shift_id, settlement_id, status
        ) VALUES (
          :puuid, :hosp, :evid, 'SETTLEMENT_PAYMENT',
          'CASH_ON_HAND', 'CREDIT', :amt, :sid, :setid, 'POSTED'
        )
        ''',
        {
          'puuid': 'POST-${_uuid.v4()}',
          'hosp': scope.hospitalCode,
          'evid': eventId,
          'amt': settleAmount.toStringAsFixed(4),
          'sid': shiftId,
          'setid': settlementId,
        },
      );

      // 7. Update Shift cash_out and expected_cash with strict status = 'OPEN' check (FIN-006 & Invariant 2)
      final shiftUpd = await tx.execute(
        '''
        UPDATE mc_shifts
        SET cash_out = cash_out + :amt, expected_cash = expected_cash - :amt
        WHERE hospital_code = :hosp AND id = :sid AND status = 'OPEN'
        ''',
        {'hosp': scope.hospitalCode, 'amt': settleAmount.toStringAsFixed(4), 'sid': shiftId},
      );
      if (shiftUpd.affectedRows == BigInt.zero) {
        throw StateError('Failed to update shift $shiftId: Shift may have been closed concurrently.');
      }

      // 8. Update Settlement Record to SETTLED with deliverer
      await tx.execute(
        '''
        UPDATE mc_financial_settlements
        SET status = 'SETTLED', delivered_by = :deliverer, delivered_at = NOW()
        WHERE hospital_code = :hosp AND id = :id
        ''',
        {
          'hosp': scope.hospitalCode,
          'deliverer': scope.actor.fullName,
          'id': settlementId,
        },
      );

      // 9. Update Dual Control Request to EXECUTED
      await tx.execute(
        '''
        UPDATE mc_dual_control_request
        SET status = 'EXECUTED'
        WHERE hospital_code = :hosp
          AND target_entity_type = 'mc_financial_settlements'
          AND target_entity_id = :id
        ''',
        {'hosp': scope.hospitalCode, 'id': settlementId.toString()},
      );

      // 10. Audit Log
      await tx.writeAuditLog(
        hospitalCode: scope.hospitalCode,
        actorStaffId: scope.actor.id,
        actorRole: scope.actor.role.name,
        deviceId: scope.deviceId,
        action: 'finance.settle_commission',
        entityType: 'mc_financial_settlements',
        entityId: settlementId.toString(),
        afterState: {
          'settlementId': settlementId,
          'doctorId': doctorId,
          'amount': settleAmount.toStringAsFixed(4),
          'shiftId': shiftId,
          'status': 'SETTLED',
          'deliveredBy': scope.actor.fullName,
        },
      );

      return {
        'settlementId': settlementId,
        'settlementNumber': setNo,
        'doctorId': doctorId,
        'amount': settleAmount.toStringAsFixed(4),
        'status': 'SETTLED',
        'deliveredBy': scope.actor.fullName,
      };
    });
  }

  /// Direct single-actor settlement attempt fails closed per SEC-005 Two-Person Integrity.
  Future<Map<String, dynamic>> settleDoctorCommissions({
    required ScopeContext scope,
    required int doctorId,
    required Decimal settleAmount,
    required int shiftId,
  }) async {
    throw RbacForbiddenException(
      code: 'DUAL_CONTROL_APPROVAL_REQUIRED',
      message: 'Two-person integrity violation: Direct commission settlement without dual-control approval is forbidden. Submit request via /api/v1/finance/settlements/request first.',
      requiredPermission: 'finance_Settlements',
    );
  }
}

class DualControlRepository {
  final TransactionManager txManager;

  DualControlRepository(this.txManager);

  Future<List<Map<String, dynamic>>> listPendingRequests(ScopeContext scope) async {
    final res = await txManager.db.execute(
      '''
      SELECT * FROM mc_dual_control_request
      WHERE hospital_code = :hosp AND status = 'PENDING'
      ORDER BY id ASC
      ''',
      {'hosp': scope.hospitalCode},
    );
    return res.rows
        .map((r) => {
              'id': int.parse(r.colByName('id') ?? '0'),
              'requestUuid': r.colByName('request_uuid'),
              'actionType': r.colByName('action_type'),
              'targetEntityType': r.colByName('target_entity_type'),
              'targetEntityId': r.colByName('target_entity_id'),
              'requestedAmount': r.colByName('requested_amount'),
              'requesterStaffId': int.tryParse(r.colByName('requester_staff_id') ?? ''),
              'status': r.colByName('status'),
              'reason': r.colByName('reason'),
              'createdAt': r.colByName('created_at'),
            })
        .toList();
  }

  Future<Map<String, dynamic>> decideRequest({
    required ScopeContext scope,
    required int requestId,
    required bool approve,
    String? decisionNotes,
  }) async {
    return await txManager.runInTransaction((tx) async {
      // 1. Lock request FOR UPDATE
      final rRes = await tx.selectForUpdate(
        'SELECT * FROM mc_dual_control_request WHERE hospital_code = :hosp AND id = :id',
        {'hosp': scope.hospitalCode, 'id': requestId},
      );
      if (rRes.rows.isEmpty) throw StateError('Dual control request $requestId not found.');
      final req = rRes.rows.first;

      if (req.colByName('status') != 'PENDING') {
        throw StateError('Request $requestId is already decided (${req.colByName('status')}).');
      }

      final requesterId = int.tryParse(req.colByName('requester_staff_id') ?? '');
      // SEC-005 Two-Person Integrity: Approver cannot be the Requester!
      if (requesterId != null && requesterId == scope.actor.id) {
        throw RbacForbiddenException(
          code: 'DUAL_CONTROL_SELF_APPROVAL_FORBIDDEN',
          message: 'Two-person integrity violation: Approver cannot approve their own request.',
          requiredPermission: 'dual_control.approve',
        );
      }

      final newStatus = approve ? 'APPROVED' : 'REJECTED';
      await tx.execute(
        '''
        UPDATE mc_dual_control_request
        SET status = :status,
            approver_staff_id = :approver,
            decision_notes = :notes,
            decided_at = NOW()
        WHERE hospital_code = :hosp AND id = :id
        ''',
        {
          'hosp': scope.hospitalCode,
          'id': requestId,
          'status': newStatus,
          'approver': scope.actor.id,
          'notes': decisionNotes ?? (approve ? 'Approved by supervisor' : 'Rejected'),
        },
      );

      // If approved and action is VISIT_REFUND, execute the refund logic
      final actionType = req.colByName('action_type');
      if (approve && actionType == 'VISIT_REFUND') {
        final visitId = int.parse(req.colByName('target_entity_id') ?? '0');
        await tx.execute(
          "UPDATE mc_visits SET status = 'REFUNDED' WHERE hospital_code = :hosp AND id = :vid",
          {'hosp': scope.hospitalCode, 'vid': visitId},
        );
      }

      // If action is COMMISSION_SETTLEMENT, update mc_financial_settlements (SEC-005 Two-Person Rule)
      if (actionType == 'COMMISSION_SETTLEMENT') {
        final settlementId = int.parse(req.colByName('target_entity_id') ?? '0');
        final targetStatus = approve ? 'APPROVED' : 'REJECTED';
        await tx.execute(
          '''
          UPDATE mc_financial_settlements
          SET status = :status, approved_by = :approver, approved_at = NOW()
          WHERE hospital_code = :hosp AND id = :sid AND status = 'REQUESTED'
          ''',
          {
            'hosp': scope.hospitalCode,
            'status': targetStatus,
            'approver': scope.actor.fullName,
            'sid': settlementId,
          },
        );
      }

      await tx.writeAuditLog(
        hospitalCode: scope.hospitalCode,
        actorStaffId: scope.actor.id,
        actorRole: scope.actor.role.name,
        deviceId: scope.deviceId,
        action: 'dual_control.decide',
        entityType: 'mc_dual_control_request',
        entityId: requestId.toString(),
        afterState: {'requestId': requestId, 'status': newStatus},
      );

      return {
        'requestId': requestId,
        'status': newStatus,
        'approverStaffId': scope.actor.id,
      };
    });
  }
}
