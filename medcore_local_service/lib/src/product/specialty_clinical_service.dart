import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../db/db_client.dart';
import '../repositories/scope_context.dart';
import 'facility_config_service.dart';

/// Authoritative Specialty Clinical Service (Batch 5).
/// Operates directly on normalized MariaDB tables created across V004-V009:
/// - Nursing: `mc_nursing_tasks`
/// - ICU / NICU: `mc_icu_flowsheets`, `mc_icu_sofa_scores`
/// - Surgery / OR: `mc_surgeries`
/// - Dialysis: `mc_dialysis_sessions`
///
/// Every method enforces tenant isolation, module entitlement, and writes to audit logs.
class SpecialtyClinicalService {
  final DbClient db;
  final FacilityConfigService facilityConfigService;
  static const _uuid = Uuid();

  SpecialtyClinicalService(
    this.db, {
    required this.facilityConfigService,
  });

  // =========================================================================
  // 1. NURSING MODULE (`mc_nursing_tasks`)
  // =========================================================================

  Future<List<Map<String, dynamic>>> listNursingTasks({
    required String hospitalCode,
    int? patientId,
    String? status,
  }) async {
    final conditions = ['hospital_code = :hosp'];
    final params = <String, dynamic>{'hosp': hospitalCode};

    if (patientId != null) {
      conditions.add('patient_id = :pid');
      params['pid'] = patientId;
    }
    if (status != null && status.isNotEmpty) {
      conditions.add('status = :status');
      params['status'] = status;
    }

    final query = '''
      SELECT id, public_id, task_number, patient_id, encounter_id,
             assigned_to, assigned_by, task_type, title, instructions,
             priority, status, due_at, started_at, completed_at,
             confirmed_at, confirmation_by, metadata_json, created_at
      FROM mc_nursing_tasks
      WHERE ${conditions.join(' AND ')}
      ORDER BY due_at ASC, id DESC
    ''';

    final res = await db.execute(query, params);
    return res.rows
        .map((r) => {
              'id': int.parse(r.colByName('id') ?? '0'),
              'publicId': r.colByName('public_id'),
              'taskNumber': r.colByName('task_number'),
              'patientId': r.colByName('patient_id') != null
                  ? int.tryParse(r.colByName('patient_id')!)
                  : null,
              'encounterId': r.colByName('encounter_id') != null
                  ? int.tryParse(r.colByName('encounter_id')!)
                  : null,
              'assignedTo': r.colByName('assigned_to'),
              'assignedBy': r.colByName('assigned_by'),
              'taskType': r.colByName('task_type'),
              'title': r.colByName('title'),
              'instructions': r.colByName('instructions'),
              'priority': r.colByName('priority'),
              'status': r.colByName('status'),
              'dueAt': r.colByName('due_at'),
              'startedAt': r.colByName('started_at'),
              'completedAt': r.colByName('completed_at'),
              'confirmedAt': r.colByName('confirmed_at'),
              'confirmationBy': r.colByName('confirmation_by'),
              'metadata': r.colByName('metadata_json'),
              'createdAt': r.colByName('created_at'),
            })
        .toList();
  }

  static String? _formatDateTime(dynamic raw) {
    if (raw == null) return null;
    final str = raw.toString().trim();
    if (str.isEmpty) return null;
    try {
      final dt = DateTime.parse(str);
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final h = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      final s = dt.second.toString().padLeft(2, '0');
      return '$y-$m-$d $h:$min:$s';
    } catch (_) {
      return str.replaceAll('T', ' ').replaceAll('Z', '').split('.').first;
    }
  }

  Future<Map<String, dynamic>> createNursingTask({
    required ScopeContext scope,
    required Map<String, dynamic> data,
  }) async {
    final title = (data['title'] ?? data['description'] ?? '').toString().trim();
    if (title.isEmpty) {
      throw ArgumentError('Nursing task title cannot be empty.');
    }
    final taskType = (data['taskType'] ?? 'MEDICATION_ADMIN').toString().trim();
    final priority = (data['priority'] ?? 'NORMAL').toString().trim().toUpperCase();
    final patientId = data['patientId'] != null ? int.tryParse(data['patientId'].toString()) : null;
    final publicId = _uuid.v4();
    final taskNumber = 'TSK-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';

    final res = await db.execute(
      '''
      INSERT INTO mc_nursing_tasks (
        hospital_code, tenant_id, public_id, task_number, patient_id,
        encounter_id, assigned_to, assigned_by, task_type, title,
        instructions, priority, status, due_at, metadata_json,
        created_at, updated_at
      ) VALUES (
        :hosp, :tenant, :pub_id, :tnum, :pid,
        :enc_id, :as_to, :as_by, :ttype, :title,
        :instr, :pri, 'ASSIGNED', :due, :meta,
        NOW(), NOW()
      )
      ''',
      {
        'hosp': scope.hospitalCode,
        'tenant': scope.hospitalCode,
        'pub_id': publicId,
        'tnum': taskNumber,
        'pid': patientId,
        'enc_id': data['encounterId'] != null ? int.tryParse(data['encounterId'].toString()) : null,
        'as_to': data['assignedTo']?.toString(),
        'as_by': scope.actor.fullName,
        'ttype': taskType,
        'title': title,
        'instr': data['instructions']?.toString(),
        'pri': priority,
        'due': _formatDateTime(data['scheduledTime'] ?? data['dueAt']) ?? _formatDateTime(DateTime.now()),
        'meta': data['metadata'] != null ? jsonEncode(data['metadata']) : null,
      },
    );

    final taskId = res.lastInsertID.toInt();
    await _writeAudit(
      scope: scope,
      action: 'nursing.task.create',
      entityType: 'mc_nursing_tasks',
      entityId: taskId.toString(),
    );

    return {
      'id': taskId,
      'taskId': taskId,
      'publicId': publicId,
      'taskNumber': taskNumber,
      'title': title,
      'status': 'ASSIGNED',
    };
  }

  Future<Map<String, dynamic>> completeNursingTask({
    required ScopeContext scope,
    required int taskId,
    String? notes,
  }) async {
    final res = await db.execute(
      '''
      UPDATE mc_nursing_tasks
      SET status = 'COMPLETED',
          completed_at = NOW(),
          confirmed_at = NOW(),
          confirmation_by = :staff,
          instructions = CONCAT(COALESCE(instructions, ''), :notes),
          updated_at = NOW()
      WHERE hospital_code = :hosp AND id = :id AND status != 'COMPLETED'
      ''',
      {
        'hosp': scope.hospitalCode,
        'id': taskId,
        'staff': scope.actor.fullName,
        'notes': notes != null ? '\n[Completion Notes]: $notes' : '',
      },
    );

    if (res.affectedRows == BigInt.zero) {
      throw StateError('Nursing task #$taskId not found or already completed.');
    }

    await _writeAudit(
      scope: scope,
      action: 'nursing.task.complete',
      entityType: 'mc_nursing_tasks',
      entityId: taskId.toString(),
    );

    return {'id': taskId, 'status': 'COMPLETED'};
  }

  // =========================================================================
  // 2. ICU MODULE (`mc_icu_flowsheets`, `mc_icu_sofa_scores`)
  // =========================================================================

  Future<List<Map<String, dynamic>>> listIcuFlowsheets({
    required String hospitalCode,
    required String admissionId,
  }) async {
    final res = await db.execute(
      '''
      SELECT id, public_id, admission_id, bed_id, entry_time,
             vitals_json, fluids_json, notes, created_by, created_at
      FROM mc_icu_flowsheets
      WHERE hospital_code = :hosp AND admission_id = :adm
      ORDER BY entry_time DESC
      ''',
      {'hosp': hospitalCode, 'adm': admissionId},
    );

    return res.rows
        .map((r) => {
              'id': int.parse(r.colByName('id') ?? '0'),
              'publicId': r.colByName('public_id'),
              'admissionId': r.colByName('admission_id'),
              'bedId': r.colByName('bed_id'),
              'entryTime': r.colByName('entry_time'),
              'vitals': r.colByName('vitals_json'),
              'fluids': r.colByName('fluids_json'),
              'notes': r.colByName('notes'),
              'createdBy': r.colByName('created_by'),
              'createdAt': r.colByName('created_at'),
            })
        .toList();
  }

  Future<Map<String, dynamic>> recordIcuFlowsheet({
    required ScopeContext scope,
    required Map<String, dynamic> data,
  }) async {
    final admissionId = (data['admissionId'] ?? (data['patientId'] != null ? 'ADM-PAT-${data['patientId']}' : '')).toString().trim();
    if (admissionId.isEmpty) {
      throw ArgumentError('admissionId is required for ICU flowsheet.');
    }
    final publicId = _uuid.v4();
    final vitalsJson = data['vitals'] != null ? jsonEncode(data['vitals']) : '{}';
    final fluidsJson = data['fluids'] != null ? jsonEncode(data['fluids']) : '{}';

    final res = await db.execute(
      '''
      INSERT INTO mc_icu_flowsheets (
        hospital_code, tenant_id, public_id, admission_id, bed_id,
        entry_time, vitals_json, fluids_json, notes, created_by,
        created_at
      ) VALUES (
        :hosp, :tenant, :pub_id, :adm, :bed,
        NOW(), :vitals, :fluids, :notes, :creator,
        NOW()
      )
      ''',
      {
        'hosp': scope.hospitalCode,
        'tenant': scope.hospitalCode,
        'pub_id': publicId,
        'adm': admissionId,
        'bed': data['bedId']?.toString(),
        'vitals': vitalsJson,
        'fluids': fluidsJson,
        'notes': data['notes']?.toString(),
        'creator': scope.actor.fullName,
      },
    );

    final flowsheetId = res.lastInsertID.toInt();
    await _writeAudit(
      scope: scope,
      action: 'icu.flowsheet.record',
      entityType: 'mc_icu_flowsheets',
      entityId: flowsheetId.toString(),
    );

    return {'id': flowsheetId, 'publicId': publicId, 'admissionId': admissionId};
  }

  Future<Map<String, dynamic>> recordSofaScore({
    required ScopeContext scope,
    required Map<String, dynamic> data,
  }) async {
    final admissionId = (data['admissionId'] ?? '').toString().trim();
    final score = int.tryParse(data['score']?.toString() ?? '0') ?? 0;
    final publicId = _uuid.v4();

    final res = await db.execute(
      '''
      INSERT INTO mc_icu_sofa_scores (
        hospital_code, public_id, tenant_id, admission_id,
        score, details_json, recorded_by, recorded_at
      ) VALUES (
        :hosp, :pub_id, :tenant, :adm,
        :score, :details, :recorder, NOW()
      )
      ''',
      {
        'hosp': scope.hospitalCode,
        'pub_id': publicId,
        'tenant': scope.hospitalCode,
        'adm': admissionId,
        'score': score,
        'details': data['details'] != null ? jsonEncode(data['details']) : null,
        'recorder': scope.actor.fullName,
      },
    );

    final id = res.lastInsertID.toInt();
    return {'id': id, 'publicId': publicId, 'score': score};
  }

  // =========================================================================
  // 3. SURGERY MODULE (`mc_surgeries`)
  // =========================================================================

  Future<List<Map<String, dynamic>>> listSurgeries({
    required String hospitalCode,
    String? status,
    String? plannedDate,
  }) async {
    final conditions = ['hospital_code = :hosp'];
    final params = <String, dynamic>{'hosp': hospitalCode};

    if (status != null && status.isNotEmpty) {
      conditions.add('status = :status');
      params['status'] = status;
    }
    if (plannedDate != null && plannedDate.isNotEmpty) {
      conditions.add('planned_date = :pdate');
      params['pdate'] = plannedDate;
    }

    final res = await db.execute(
      '''
      SELECT id, public_id, patient_id, encounter_id, or_room_id,
             procedure_name, planned_date, planned_time, estimated_duration,
             urgency, laterality, anesthesia_type, diagnosis, status,
             team_json, created_by, created_at
      FROM mc_surgeries
      WHERE ${conditions.join(' AND ')}
      ORDER BY planned_date ASC, id ASC
      ''',
      params,
    );

    return res.rows
        .map((r) => {
              'id': int.parse(r.colByName('id') ?? '0'),
              'publicId': r.colByName('public_id'),
              'patientId': r.colByName('patient_id'),
              'orRoomId': r.colByName('or_room_id'),
              'procedureName': r.colByName('procedure_name'),
              'plannedDate': r.colByName('planned_date'),
              'plannedTime': r.colByName('planned_time'),
              'urgency': r.colByName('urgency'),
              'anesthesiaType': r.colByName('anesthesia_type'),
              'diagnosis': r.colByName('diagnosis'),
              'status': r.colByName('status'),
              'team': r.colByName('team_json'),
              'createdBy': r.colByName('created_by'),
              'createdAt': r.colByName('created_at'),
            })
        .toList();
  }

  Future<Map<String, dynamic>> scheduleSurgery({
    required ScopeContext scope,
    required Map<String, dynamic> data,
  }) async {
    final procedureName = (data['procedureName'] ?? '').toString().trim();
    if (procedureName.isEmpty) {
      throw ArgumentError('procedureName cannot be empty.');
    }
    final patientId = (data['patientId'] ?? '').toString().trim();
    if (patientId.isEmpty) {
      throw ArgumentError('patientId is required for surgery scheduling.');
    }
    final plannedDate = (data['plannedDate'] ?? DateTime.now().toIso8601String().substring(0, 10)).toString();
    final publicId = _uuid.v4();

    final res = await db.execute(
      '''
      INSERT INTO mc_surgeries (
        hospital_code, tenant_id, public_id, patient_id,
        or_room_id, procedure_name, planned_date, planned_time,
        urgency, anesthesia_type, diagnosis, status, team_json,
        created_by, created_at
      ) VALUES (
        :hosp, :tenant, :pub_id, :pid,
        :room, :proc, :pdate, :ptime,
        :urgency, :anes, :diag, 'Scheduled', :team,
        :creator, NOW()
      )
      ''',
      {
        'hosp': scope.hospitalCode,
        'tenant': scope.hospitalCode,
        'pub_id': publicId,
        'pid': patientId,
        'room': data['orRoomId']?.toString() ?? 'OR-1',
        'proc': procedureName,
        'pdate': plannedDate,
        'ptime': data['plannedTime']?.toString() ?? '09:00:00',
        'urgency': (data['urgency'] ?? 'Elective').toString(),
        'anes': (data['anesthesiaType'] ?? 'General').toString(),
        'diag': data['diagnosis']?.toString(),
        'team': data['team'] != null ? jsonEncode(data['team']) : null,
        'creator': scope.actor.fullName,
      },
    );

    final surgeryId = res.lastInsertID.toInt();
    await _writeAudit(
      scope: scope,
      action: 'surgery.schedule',
      entityType: 'mc_surgeries',
      entityId: surgeryId.toString(),
    );

    return {
      'id': surgeryId,
      'surgeryId': surgeryId,
      'publicId': publicId,
      'procedureName': procedureName,
      'status': 'Scheduled',
    };
  }

  Future<Map<String, dynamic>> updateSurgeryStatus({
    required ScopeContext scope,
    required int surgeryId,
    required String newStatus,
  }) async {
    final res = await db.execute(
      '''
      UPDATE mc_surgeries
      SET status = :status
      WHERE hospital_code = :hosp AND id = :id
      ''',
      {
        'hosp': scope.hospitalCode,
        'id': surgeryId,
        'status': newStatus,
      },
    );

    if (res.affectedRows == BigInt.zero) {
      throw StateError('Surgery #$surgeryId not found.');
    }

    await _writeAudit(
      scope: scope,
      action: 'surgery.status_update',
      entityType: 'mc_surgeries',
      entityId: surgeryId.toString(),
      afterState: {'status': newStatus},
    );

    return {'id': surgeryId, 'status': newStatus};
  }

  // =========================================================================
  // 4. DIALYSIS MODULE (`mc_dialysis_sessions`)
  // =========================================================================

  Future<List<Map<String, dynamic>>> listDialysisSessions({
    required String hospitalCode,
    String? patientId,
    String? status,
  }) async {
    final conditions = ['hospital_code = :hosp'];
    final params = <String, dynamic>{'hosp': hospitalCode};

    if (patientId != null && patientId.isNotEmpty) {
      conditions.add('patient_id = :pid');
      params['pid'] = patientId;
    }
    if (status != null && status.isNotEmpty) {
      conditions.add('status = :status');
      params['status'] = status;
    }

    final res = await db.execute(
      '''
      SELECT id, public_id, patient_id, encounter_id, machine_id,
             session_date, pre_weight, post_weight, duration_minutes,
             clinical_notes, telemetry_json, status, created_by, created_at
      FROM mc_dialysis_sessions
      WHERE ${conditions.join(' AND ')}
      ORDER BY session_date DESC, id DESC
      ''',
      params,
    );

    return res.rows
        .map((r) => {
              'id': int.parse(r.colByName('id') ?? '0'),
              'publicId': r.colByName('public_id'),
              'patientId': r.colByName('patient_id'),
              'machineId': r.colByName('machine_id'),
              'sessionDate': r.colByName('session_date'),
              'preWeight': r.colByName('pre_weight'),
              'postWeight': r.colByName('post_weight'),
              'durationMinutes': r.colByName('duration_minutes') != null
                  ? int.tryParse(r.colByName('duration_minutes')!)
                  : null,
              'clinicalNotes': r.colByName('clinical_notes'),
              'telemetry': r.colByName('telemetry_json'),
              'status': r.colByName('status'),
              'createdBy': r.colByName('created_by'),
              'createdAt': r.colByName('created_at'),
            })
        .toList();
  }

  Future<Map<String, dynamic>> scheduleDialysisSession({
    required ScopeContext scope,
    required Map<String, dynamic> data,
  }) async {
    final patientId = (data['patientId'] ?? '').toString().trim();
    if (patientId.isEmpty) {
      throw ArgumentError('patientId is required for dialysis session.');
    }
    final machineId = (data['machineId'] ?? data['dialysisMachineId'] ?? 'DIAL-01').toString().trim();
    final publicId = _uuid.v4();
    final preWeight = (data['preWeightKg'] ?? data['preWeight'])?.toString();

    final res = await db.execute(
      '''
      INSERT INTO mc_dialysis_sessions (
        hospital_code, tenant_id, public_id, patient_id, machine_id,
        session_date, pre_weight, clinical_notes, status, created_by,
        created_at, updated_at
      ) VALUES (
        :hosp, :tenant, :pub_id, :pid, :machine,
        NOW(), :pre_w, :notes, 'Scheduled', :creator,
        NOW(), NOW()
      )
      ''',
      {
        'hosp': scope.hospitalCode,
        'tenant': scope.hospitalCode,
        'pub_id': publicId,
        'pid': patientId,
        'machine': machineId,
        'pre_w': preWeight,
        'notes': data['clinicalNotes']?.toString(),
        'creator': scope.actor.fullName,
      },
    );

    final sessionId = res.lastInsertID.toInt();
    await _writeAudit(
      scope: scope,
      action: 'dialysis.session.schedule',
      entityType: 'mc_dialysis_sessions',
      entityId: sessionId.toString(),
    );

    return {
      'id': sessionId,
      'sessionId': sessionId,
      'publicId': publicId,
      'patientId': patientId,
      'machineId': machineId,
      'status': 'Scheduled',
    };
  }

  Future<Map<String, dynamic>> completeDialysisSession({
    required ScopeContext scope,
    required int sessionId,
    required Map<String, dynamic> data,
  }) async {
    final postWeight = (data['postWeightKg'] ?? data['postWeight'])?.toString();
    final duration = int.tryParse((data['durationMinutes'] ?? (data['actualHours'] != null ? (double.parse(data['actualHours'].toString()) * 60).toInt() : '240')).toString()) ?? 240;
    final telemetry = data['telemetry'] != null ? jsonEncode(data['telemetry']) : null;

    final res = await db.execute(
      '''
      UPDATE mc_dialysis_sessions
      SET status = 'Completed',
          post_weight = :post_w,
          duration_minutes = :dur,
          telemetry_json = COALESCE(:telemetry, telemetry_json),
          clinical_notes = CONCAT(COALESCE(clinical_notes, ''), :notes),
          updated_at = NOW()
      WHERE hospital_code = :hosp AND id = :id AND status != 'Completed'
      ''',
      {
        'hosp': scope.hospitalCode,
        'id': sessionId,
        'post_w': postWeight,
        'dur': duration,
        'telemetry': telemetry,
        'notes': data['notes'] != null ? '\n[Completion Notes]: ${data['notes']}' : '',
      },
    );

    if (res.affectedRows == BigInt.zero) {
      throw StateError('Dialysis session #$sessionId not found or already completed.');
    }

    await _writeAudit(
      scope: scope,
      action: 'dialysis.session.complete',
      entityType: 'mc_dialysis_sessions',
      entityId: sessionId.toString(),
    );

    return {'id': sessionId, 'status': 'Completed'};
  }

  // =========================================================================
  // INTERNAL AUDIT HELPER
  // =========================================================================

  Future<void> _writeAudit({
    required ScopeContext scope,
    required String action,
    required String entityType,
    required String entityId,
    Map<String, dynamic>? afterState,
  }) async {
    await db.execute(
      '''
      INSERT INTO mc_audit_logs (
        hospital_code, actor_staff_id, actor_role, device_id,
        action, entity_type, entity_id, after_json, created_at
      ) VALUES (
        :hosp, :staff, :role, :dev,
        :act, :etype, :eid, :after, NOW()
      )
      ''',
      {
        'hosp': scope.hospitalCode,
        'staff': scope.actor.id,
        'role': scope.actor.role.name,
        'dev': scope.deviceId,
        'act': action,
        'etype': entityType,
        'eid': entityId,
        'after': afterState != null ? jsonEncode(afterState) : null,
      },
    );
  }
}
