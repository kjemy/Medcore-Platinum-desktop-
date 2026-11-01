import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../db/db_client.dart';
import 'scope_context.dart';

class DefinitionRecord {
  final int id;
  final String hospitalCode;
  final String publicId;
  final String tenantId;
  final String definitionType;
  final String code;
  final String name;
  final String status;
  final int version;
  final Map<String, dynamic> dataJson;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DefinitionRecord({
    required this.id,
    required this.hospitalCode,
    required this.publicId,
    required this.tenantId,
    required this.definitionType,
    required this.code,
    required this.name,
    required this.status,
    required this.version,
    required this.dataJson,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'hospitalCode': hospitalCode,
        'publicId': publicId,
        'tenantId': tenantId,
        'definitionType': definitionType,
        'code': code,
        'name': name,
        'status': status,
        'version': version,
        'dataJson': dataJson,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}

class DefinitionsRepository {
  final SqlExecutor db;
  static const _uuid = Uuid();

  DefinitionsRepository(this.db);

  /// 21 Standard Master Definitions Domains supported by MedCore:
  static const Set<String> validDefinitionTypes = {
    'clinic',
    'doctor',
    'service',
    'referral_contract',
    'branch',
    'department',
    'room',
    'bed',
    'insurance_company',
    'diagnosis',
    'consumable',
    'lab_test',
    'rad_exam',
    'medication',
    'operation',
    'vaccine',
    'payment_method',
    'tax_rate',
    'discount_type',
    'expense_category',
    'leave_type',
    'temporary_clinic',
  };

  /// Lists definitions by domain type within the authenticated tenant scope.
  Future<List<Map<String, dynamic>>> listDefinitions({
    required ScopeContext scope,
    required String type,
    String? status,
  }) async {
    final sanitizedType = type.trim().toLowerCase();
    String query = '''
      SELECT id, hospital_code, public_id, tenant_id, definition_type,
             code, name, status, version, data_json, created_at, updated_at
      FROM mc_definitions
      WHERE hospital_code = :hosp AND definition_type = :type
    ''';
    final params = <String, dynamic>{
      'hosp': scope.hospitalCode,
      'type': sanitizedType,
    };

    if (status != null && status.isNotEmpty) {
      query += ' AND status = :status';
      params['status'] = status;
    } else {
      query += " AND status != 'DELETED'";
    }
    query += ' ORDER BY name ASC';

    final res = await db.execute(query, params);
    return res.rows.map((row) {
      final m = row.assoc();
      Map<String, dynamic> parsedData = {};
      final rawJson = m['data_json'];
      if (rawJson != null && rawJson.toString().trim().isNotEmpty) {
        try {
          parsedData = jsonDecode(rawJson.toString()) as Map<String, dynamic>;
        } catch (_) {}
      }
      return {
        'id': int.tryParse(m['id'] ?? '0') ?? 0,
        'hospitalCode': m['hospital_code'] ?? '',
        'publicId': m['public_id'] ?? '',
        'tenantId': m['tenant_id'] ?? '',
        'definitionType': m['definition_type'] ?? '',
        'code': m['code'] ?? '',
        'name': m['name'] ?? '',
        'status': m['status'] ?? 'ACTIVE',
        'version': int.tryParse(m['version'] ?? '1') ?? 1,
        'dataJson': parsedData,
        'createdAt': m['created_at'] ?? '',
        'updatedAt': m['updated_at'] ?? '',
      };
    }).toList();
  }

  /// Retrieves a single definition by publicId within the authenticated tenant scope.
  Future<Map<String, dynamic>?> getDefinition({
    required ScopeContext scope,
    required String publicId,
  }) async {
    final res = await db.execute(
      '''
      SELECT id, hospital_code, public_id, tenant_id, definition_type,
             code, name, status, version, data_json, created_at, updated_at
      FROM mc_definitions
      WHERE hospital_code = :hosp AND public_id = :pub_id
      LIMIT 1
      ''',
      {'hosp': scope.hospitalCode, 'pub_id': publicId},
    );
    if (res.rows.isEmpty) return null;
    final m = res.rows.first.assoc();
    Map<String, dynamic> parsedData = {};
    final rawJson = m['data_json'];
    if (rawJson != null && rawJson.toString().trim().isNotEmpty) {
      try {
        parsedData = jsonDecode(rawJson.toString()) as Map<String, dynamic>;
      } catch (_) {}
    }
    return {
      'id': int.tryParse(m['id'] ?? '0') ?? 0,
      'hospitalCode': m['hospital_code'] ?? '',
      'publicId': m['public_id'] ?? '',
      'tenantId': m['tenant_id'] ?? '',
      'definitionType': m['definition_type'] ?? '',
      'code': m['code'] ?? '',
      'name': m['name'] ?? '',
      'status': m['status'] ?? 'ACTIVE',
      'version': int.tryParse(m['version'] ?? '1') ?? 1,
      'dataJson': parsedData,
      'createdAt': m['created_at'] ?? '',
      'updatedAt': m['updated_at'] ?? '',
    };
  }

  /// Creates a new definition record with uniqueness validation.
  Future<Map<String, dynamic>> createDefinition({
    required ScopeContext scope,
    required String type,
    required String code,
    required String name,
    Map<String, dynamic>? dataJson,
  }) async {
    final cleanType = type.trim().toLowerCase();
    final cleanCode = code.trim();
    final cleanName = name.trim();

    if (cleanCode.isEmpty || cleanName.isEmpty) {
      throw ArgumentError('Definition code and name must not be empty.');
    }

    // Check duplicate code within tenant and domain
    final dupRes = await db.execute(
      '''
      SELECT id FROM mc_definitions
      WHERE hospital_code = :hosp AND definition_type = :type AND code = :code AND status != 'DELETED'
      LIMIT 1
      ''',
      {'hosp': scope.hospitalCode, 'type': cleanType, 'code': cleanCode},
    );
    if (dupRes.rows.isNotEmpty) {
      throw StateError('A definition with code "$cleanCode" already exists in domain "$cleanType".');
    }

    final pubId = _uuid.v4();
    final encodedData = dataJson != null ? jsonEncode(dataJson) : null;

    await db.execute(
      '''
      INSERT INTO mc_definitions (
        hospital_code, public_id, tenant_id, definition_type,
        code, name, status, version, data_json, created_by, updated_by,
        created_at, updated_at
      ) VALUES (
        :hosp, :pub_id, :tenant, :type,
        :code, :name, 'ACTIVE', 1, :data, :creator, :creator,
        NOW(), NOW()
      )
      ''',
      {
        'hosp': scope.hospitalCode,
        'pub_id': pubId,
        'tenant': scope.hospitalCode,
        'type': cleanType,
        'code': cleanCode,
        'name': cleanName,
        'data': encodedData,
        'creator': scope.actor.id.toString(),
      },
    );

    return (await getDefinition(scope: scope, publicId: pubId))!;
  }

  /// Updates an existing definition.
  Future<Map<String, dynamic>> updateDefinition({
    required ScopeContext scope,
    required String publicId,
    String? name,
    Map<String, dynamic>? dataJson,
    String? status,
  }) async {
    final existing = await getDefinition(scope: scope, publicId: publicId);
    if (existing == null) {
      throw StateError('Definition with ID "$publicId" not found in current tenant.');
    }

    final newName = name?.trim() ?? existing['name'];
    final newStatus = status?.trim() ?? existing['status'];
    final updatedData = dataJson ?? existing['dataJson'];
    final encodedData = jsonEncode(updatedData);

    await db.execute(
      '''
      UPDATE mc_definitions
      SET name = :name,
          data_json = :data,
          status = :status,
          version = version + 1,
          updated_by = :updater,
          updated_at = NOW()
      WHERE hospital_code = :hosp AND public_id = :pub_id
      ''',
      {
        'hosp': scope.hospitalCode,
        'pub_id': publicId,
        'name': newName,
        'data': encodedData,
        'status': newStatus,
        'updater': scope.actor.id.toString(),
      },
    );

    return (await getDefinition(scope: scope, publicId: publicId))!;
  }

  /// Soft deletes / archives a definition.
  Future<void> archiveDefinition({
    required ScopeContext scope,
    required String publicId,
  }) async {
    final existing = await getDefinition(scope: scope, publicId: publicId);
    if (existing == null) {
      throw StateError('Definition with ID "$publicId" not found in current tenant.');
    }

    await db.execute(
      '''
      UPDATE mc_definitions
      SET status = 'ARCHIVED',
          version = version + 1,
          updated_by = :updater,
          updated_at = NOW()
      WHERE hospital_code = :hosp AND public_id = :pub_id
      ''',
      {
        'hosp': scope.hospitalCode,
        'pub_id': publicId,
        'updater': scope.actor.id.toString(),
      },
    );
  }

  // --------------------------------------------------------------------------
  // Doctor Commission Profiles
  // --------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> listDoctorCommissions({
    required ScopeContext scope,
  }) async {
    final res = await db.execute(
      '''
      SELECT id, hospital_code, public_id, tenant_id, doctor_id, doctor_code,
             commission_mode, consultation_share_pct, procedure_share_pct,
             fixed_consultation_cut, status, created_at, updated_at
      FROM mc_doctor_commission_profiles
      WHERE hospital_code = :hosp AND status != 'DELETED'
      ORDER BY doctor_code ASC
      ''',
      {'hosp': scope.hospitalCode},
    );
    return res.rows.map((r) => r.assoc()).toList();
  }

  Future<Map<String, dynamic>> upsertDoctorCommissionProfile({
    required ScopeContext scope,
    required int doctorId,
    required String doctorCode,
    String commissionMode = 'PERCENTAGE',
    double consultationSharePct = 0.0,
    double procedureSharePct = 0.0,
    double fixedConsultationCut = 0.0,
  }) async {
    final pubId = _uuid.v4();
    await db.execute(
      '''
      INSERT INTO mc_doctor_commission_profiles (
        hospital_code, tenant_id, public_id, doctor_id, doctor_code,
        commission_mode, consultation_share_pct, procedure_share_pct,
        fixed_consultation_cut, status, created_by, created_at, updated_at
      ) VALUES (
        :hosp, :tenant, :pub_id, :doc_id, :doc_code,
        :mode, :consult_pct, :proc_pct,
        :fixed_cut, 'ACTIVE', :creator, NOW(), NOW()
      )
      ON DUPLICATE KEY UPDATE
        commission_mode = VALUES(commission_mode),
        consultation_share_pct = VALUES(consultation_share_pct),
        procedure_share_pct = VALUES(procedure_share_pct),
        fixed_consultation_cut = VALUES(fixed_consultation_cut),
        status = 'ACTIVE',
        updated_at = NOW()
      ''',
      {
        'hosp': scope.hospitalCode,
        'tenant': scope.hospitalCode,
        'pub_id': pubId,
        'doc_id': doctorId,
        'doc_code': doctorCode,
        'mode': commissionMode,
        'consult_pct': consultationSharePct,
        'proc_pct': procedureSharePct,
        'fixed_cut': fixedConsultationCut,
        'creator': scope.actor.id.toString(),
      },
    );

    final res = await db.execute(
      '''
      SELECT id, hospital_code, public_id, doctor_id, doctor_code,
             commission_mode, consultation_share_pct, procedure_share_pct,
             fixed_consultation_cut, status
      FROM mc_doctor_commission_profiles
      WHERE hospital_code = :hosp AND doctor_code = :doc_code
      LIMIT 1
      ''',
      {'hosp': scope.hospitalCode, 'doc_code': doctorCode},
    );
    return res.rows.first.assoc();
  }

  // --------------------------------------------------------------------------
  // Internal Notes (Draggable FAB)
  // --------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> listInternalNotes({
    required ScopeContext scope,
    String? category,
  }) async {
    String query = '''
      SELECT id, hospital_code, public_id, author_staff_id, author_staff_name,
             category, subject, content, is_pinned, status, created_at
      FROM mc_internal_notes
      WHERE hospital_code = :hosp AND status != 'DELETED'
    ''';
    final params = <String, dynamic>{'hosp': scope.hospitalCode};

    if (category != null && category.isNotEmpty) {
      query += ' AND category = :cat';
      params['cat'] = category;
    }
    query += ' ORDER BY is_pinned DESC, created_at DESC';

    final res = await db.execute(query, params);
    return res.rows.map((r) => r.assoc()).toList();
  }

  Future<Map<String, dynamic>> createInternalNote({
    required ScopeContext scope,
    required String category,
    required String subject,
    required String content,
    bool isPinned = false,
  }) async {
    final pubId = _uuid.v4();
    await db.execute(
      '''
      INSERT INTO mc_internal_notes (
        hospital_code, tenant_id, public_id, author_staff_id, author_staff_name,
        category, subject, content, is_pinned, status, created_at, updated_at
      ) VALUES (
        :hosp, :tenant, :pub_id, :author_id, :author_name,
        :cat, :subj, :cont, :pinned, 'ACTIVE', NOW(), NOW()
      )
      ''',
      {
        'hosp': scope.hospitalCode,
        'tenant': scope.hospitalCode,
        'pub_id': pubId,
        'author_id': scope.actor.id,
        'author_name': scope.actor.fullName,
        'cat': category,
        'subj': subject,
        'cont': content,
        'pinned': isPinned ? 1 : 0,
      },
    );

    final res = await db.execute(
      '''
      SELECT id, hospital_code, public_id, author_staff_id, author_staff_name,
             category, subject, content, is_pinned, status, created_at
      FROM mc_internal_notes
      WHERE hospital_code = :hosp AND public_id = :pub_id
      LIMIT 1
      ''',
      {'hosp': scope.hospitalCode, 'pub_id': pubId},
    );
    return res.rows.first.assoc();
  }

  Future<void> togglePinInternalNote({
    required ScopeContext scope,
    required String publicId,
    required bool isPinned,
  }) async {
    await db.execute(
      '''
      UPDATE mc_internal_notes
      SET is_pinned = :pinned, updated_at = NOW()
      WHERE hospital_code = :hosp AND public_id = :pub_id
      ''',
      {'hosp': scope.hospitalCode, 'pub_id': publicId, 'pinned': isPinned ? 1 : 0},
    );
  }
}
