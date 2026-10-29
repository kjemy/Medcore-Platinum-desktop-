import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../db/db_client.dart';

enum TemplateStatus {
  draft,
  validated,
  published,
  active,
  retired;

  static TemplateStatus fromString(String val) {
    switch (val.toUpperCase()) {
      case 'DRAFT':
        return TemplateStatus.draft;
      case 'VALIDATED':
        return TemplateStatus.validated;
      case 'PUBLISHED':
        return TemplateStatus.published;
      case 'ACTIVE':
        return TemplateStatus.active;
      case 'RETIRED':
        return TemplateStatus.retired;
      default:
        return TemplateStatus.draft;
    }
  }

  String get dbValue => name.toUpperCase();
}

class ClinicalTemplateRecord {
  final int id;
  final String hospitalCode;
  final String publicId;
  final String templateNumber;
  final String? code;
  final String title;
  final String? specialty;
  final String category;
  final int version;
  final TemplateStatus status;
  final Map<String, dynamic> content;
  final String? createdBy;
  final String? updatedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ClinicalTemplateRecord({
    required this.id,
    required this.hospitalCode,
    required this.publicId,
    required this.templateNumber,
    this.code,
    required this.title,
    this.specialty,
    required this.category,
    required this.version,
    required this.status,
    required this.content,
    this.createdBy,
    this.updatedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ClinicalTemplateRecord.fromRow(Map<String, dynamic> row) {
    Map<String, dynamic> parsedContent = {};
    final rawContent = row['content_json']?.toString();
    if (rawContent != null && rawContent.trim().isNotEmpty) {
      try {
        parsedContent = jsonDecode(rawContent) as Map<String, dynamic>;
      } catch (_) {}
    }

    return ClinicalTemplateRecord(
      id: int.parse(row['id'].toString()),
      hospitalCode: (row['hospital_code'] ?? '').toString(),
      publicId: (row['public_id'] ?? '').toString(),
      templateNumber: (row['template_number'] ?? '').toString(),
      code: row['code']?.toString(),
      title: (row['title'] ?? '').toString(),
      specialty: row['specialty']?.toString(),
      category: (row['category'] ?? 'GENERAL').toString(),
      version: int.tryParse(row['version']?.toString() ?? '1') ?? 1,
      status: TemplateStatus.fromString((row['status'] ?? 'DRAFT').toString()),
      content: parsedContent,
      createdBy: row['created_by']?.toString(),
      updatedBy: row['updated_by']?.toString(),
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now().toUtc(),
      updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? '') ?? DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'publicId': publicId,
        'hospitalCode': hospitalCode,
        'templateNumber': templateNumber,
        'code': code,
        'title': title,
        'specialty': specialty,
        'category': category,
        'version': version,
        'status': status.dbValue,
        'content': content,
        'createdBy': createdBy,
        'updatedBy': updatedBy,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}

class TemplateUsageRecord {
  final int id;
  final String hospitalCode;
  final String publicId;
  final int templateId;
  final int templateVersion;
  final int? encounterId;
  final int? patientId;
  final String? providerId;
  final Map<String, dynamic> snapshot;
  final DateTime usedAt;
  final String? usedBy;

  const TemplateUsageRecord({
    required this.id,
    required this.hospitalCode,
    required this.publicId,
    required this.templateId,
    required this.templateVersion,
    this.encounterId,
    this.patientId,
    this.providerId,
    required this.snapshot,
    required this.usedAt,
    this.usedBy,
  });

  factory TemplateUsageRecord.fromRow(Map<String, dynamic> row) {
    Map<String, dynamic> parsedSnapshot = {};
    final raw = row['snapshot_json']?.toString();
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        parsedSnapshot = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {}
    }

    return TemplateUsageRecord(
      id: int.parse(row['id'].toString()),
      hospitalCode: (row['hospital_code'] ?? '').toString(),
      publicId: (row['public_id'] ?? '').toString(),
      templateId: int.parse(row['template_id'].toString()),
      templateVersion: int.parse(row['template_version'].toString()),
      encounterId: int.tryParse(row['encounter_id']?.toString() ?? ''),
      patientId: int.tryParse(row['patient_id']?.toString() ?? ''),
      providerId: row['provider_id']?.toString(),
      snapshot: parsedSnapshot,
      usedAt: DateTime.tryParse(row['used_at']?.toString() ?? '') ?? DateTime.now().toUtc(),
      usedBy: row['used_by']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'publicId': publicId,
        'hospitalCode': hospitalCode,
        'templateId': templateId,
        'templateVersion': templateVersion,
        'encounterId': encounterId,
        'patientId': patientId,
        'providerId': providerId,
        'snapshot': snapshot,
        'usedAt': usedAt.toIso8601String(),
        'usedBy': usedBy,
      };
}

class ClinicalTemplateRepository {
  final SqlExecutor db;
  static const _uuid = Uuid();

  ClinicalTemplateRepository(this.db);

  Future<ClinicalTemplateRecord> createTemplate({
    required String hospitalCode,
    required String templateNumber,
    required String title,
    String? code,
    String? specialty,
    String category = 'GENERAL',
    required Map<String, dynamic> content,
    String? createdBy,
  }) async {
    final pubId = _uuid.v4();
    final res = await db.execute(
      '''
      INSERT INTO mc_clinical_templates (
        hospital_code, public_id, tenant_id, template_number,
        code, title, specialty, category, version,
        status, content_json, created_by, updated_by,
        created_at, updated_at
      ) VALUES (
        :hosp, :pub_id, :tenant, :tmpl_no,
        :code, :title, :spec, :cat, 1,
        'DRAFT', :content, :creator, :creator,
        NOW(), NOW()
      )
      ''',
      {
        'hosp': hospitalCode,
        'pub_id': pubId,
        'tenant': hospitalCode,
        'tmpl_no': templateNumber,
        'code': code ?? templateNumber,
        'title': title,
        'spec': specialty,
        'cat': category,
        'content': jsonEncode(content),
        'creator': createdBy ?? 'SYSTEM',
      },
    );

    final id = res.lastInsertID.toInt();
    return (await getTemplateById(hospitalCode, id))!;
  }

  Future<ClinicalTemplateRecord> updateTemplateDraft({
    required String hospitalCode,
    required int id,
    String? title,
    String? specialty,
    String? category,
    Map<String, dynamic>? content,
    String? updatedBy,
  }) async {
    final existing = await getTemplateById(hospitalCode, id);
    if (existing == null) {
      throw StateError('Template with ID $id not found in facility $hospitalCode.');
    }
    if (existing.status != TemplateStatus.draft && existing.status != TemplateStatus.validated) {
      throw StateError('Cannot modify template with status ${existing.status.dbValue}. Published/Active versions are immutable.');
    }

    final newTitle = title ?? existing.title;
    final newSpec = specialty ?? existing.specialty;
    final newCat = category ?? existing.category;
    final newContent = content != null ? jsonEncode(content) : jsonEncode(existing.content);

    await db.execute(
      '''
      UPDATE mc_clinical_templates
      SET title = :title,
          specialty = :spec,
          category = :cat,
          content_json = :content,
          updated_by = :updater,
          updated_at = NOW()
      WHERE id = :id AND hospital_code = :hosp
      ''',
      {
        'title': newTitle,
        'spec': newSpec,
        'cat': newCat,
        'content': newContent,
        'updater': updatedBy ?? 'SYSTEM',
        'id': id,
        'hosp': hospitalCode,
      },
    );

    return (await getTemplateById(hospitalCode, id))!;
  }

  Future<ClinicalTemplateRecord> createNextVersion({
    required String hospitalCode,
    required String templateNumber,
    Map<String, dynamic>? newContent,
    String? createdBy,
  }) async {
    // Determine highest existing version
    final rows = await db.execute(
      '''
      SELECT MAX(version) AS max_ver, title, specialty, category, code, content_json
      FROM mc_clinical_templates
      WHERE hospital_code = :hosp AND template_number = :tnum
      GROUP BY title, specialty, category, code, content_json
      ORDER BY max_ver DESC LIMIT 1
      ''',
      {'hosp': hospitalCode, 'tnum': templateNumber},
    );

    if (rows.rows.isEmpty) {
      throw StateError('Template number $templateNumber does not exist in facility $hospitalCode.');
    }

    final row = rows.rows.first;
    final nextVer = (int.tryParse(row.colByName('max_ver')?.toString() ?? '1') ?? 1) + 1;
    final title = row.colByName('title')?.toString() ?? templateNumber;
    final specialty = row.colByName('specialty')?.toString();
    final category = row.colByName('category')?.toString() ?? 'GENERAL';
    final code = row.colByName('code')?.toString();
    final contentStr = newContent != null ? jsonEncode(newContent) : (row.colByName('content_json') ?? '{}');

    final pubId = _uuid.v4();
    final res = await db.execute(
      '''
      INSERT INTO mc_clinical_templates (
        hospital_code, public_id, tenant_id, template_number,
        code, title, specialty, category, version,
        status, content_json, created_by, updated_by,
        created_at, updated_at
      ) VALUES (
        :hosp, :pub_id, :tenant, :tmpl_no,
        :code, :title, :spec, :cat, :ver,
        'DRAFT', :content, :creator, :creator,
        NOW(), NOW()
      )
      ''',
      {
        'hosp': hospitalCode,
        'pub_id': pubId,
        'tenant': hospitalCode,
        'tmpl_no': templateNumber,
        'code': code,
        'title': title,
        'spec': specialty,
        'cat': category,
        'ver': nextVer,
        'content': contentStr,
        'creator': createdBy ?? 'SYSTEM',
      },
    );

    final id = res.lastInsertID.toInt();
    return (await getTemplateById(hospitalCode, id))!;
  }

  Future<ClinicalTemplateRecord> activateTemplate({
    required String hospitalCode,
    required int id,
    String? updatedBy,
  }) async {
    final template = await getTemplateById(hospitalCode, id);
    if (template == null) {
      throw StateError('Template $id not found in facility $hospitalCode.');
    }

    // Step 1: Invalidate/Retire any existing ACTIVE template with the same templateNumber
    await db.execute(
      '''
      UPDATE mc_clinical_templates
      SET status = 'RETIRED', updated_at = NOW(), updated_by = :updater
      WHERE hospital_code = :hosp
        AND template_number = :tnum
        AND status = 'ACTIVE'
        AND id != :id
      ''',
      {
        'hosp': hospitalCode,
        'tnum': template.templateNumber,
        'id': id,
        'updater': updatedBy ?? 'SYSTEM',
      },
    );

    // Step 2: Set current template to ACTIVE
    await db.execute(
      '''
      UPDATE mc_clinical_templates
      SET status = 'ACTIVE', updated_at = NOW(), updated_by = :updater
      WHERE id = :id AND hospital_code = :hosp
      ''',
      {
        'id': id,
        'hosp': hospitalCode,
        'updater': updatedBy ?? 'SYSTEM',
      },
    );

    return (await getTemplateById(hospitalCode, id))!;
  }

  Future<ClinicalTemplateRecord> deactivateTemplate({
    required String hospitalCode,
    required int id,
    String? updatedBy,
  }) async {
    await db.execute(
      '''
      UPDATE mc_clinical_templates
      SET status = 'RETIRED', updated_at = NOW(), updated_by = :updater
      WHERE id = :id AND hospital_code = :hosp
      ''',
      {
        'id': id,
        'hosp': hospitalCode,
        'updater': updatedBy ?? 'SYSTEM',
      },
    );

    return (await getTemplateById(hospitalCode, id))!;
  }

  Future<ClinicalTemplateRecord?> getTemplateById(String hospitalCode, int id) async {
    final rows = await db.execute(
      'SELECT * FROM mc_clinical_templates WHERE id = :id AND hospital_code = :hosp LIMIT 1',
      {'id': id, 'hosp': hospitalCode},
    );
    if (rows.rows.isEmpty) return null;
    return ClinicalTemplateRecord.fromRow(rows.rows.first.assoc());
  }

  Future<ClinicalTemplateRecord?> getActiveTemplateByNumber(String hospitalCode, String templateNumber) async {
    final rows = await db.execute(
      '''
      SELECT * FROM mc_clinical_templates
      WHERE hospital_code = :hosp AND template_number = :tnum AND status = 'ACTIVE'
      ORDER BY version DESC LIMIT 1
      ''',
      {'hosp': hospitalCode, 'tnum': templateNumber},
    );
    if (rows.rows.isEmpty) return null;
    return ClinicalTemplateRecord.fromRow(rows.rows.first.assoc());
  }

  Future<List<ClinicalTemplateRecord>> listTemplates(
    String hospitalCode, {
    String? status,
    String? specialty,
  }) async {
    var sql = 'SELECT * FROM mc_clinical_templates WHERE hospital_code = :hosp';
    final params = <String, dynamic>{'hosp': hospitalCode};

    if (status != null && status.isNotEmpty) {
      sql += ' AND status = :st';
      params['st'] = status.toUpperCase();
    }
    if (specialty != null && specialty.isNotEmpty) {
      sql += ' AND specialty = :spec';
      params['spec'] = specialty;
    }

    sql += ' ORDER BY template_number ASC, version DESC';

    final rows = await db.execute(sql, params);
    return rows.rows.map((r) => ClinicalTemplateRecord.fromRow(r.assoc())).toList();
  }

  Future<TemplateUsageRecord> recordTemplateUsage({
    required String hospitalCode,
    required int templateId,
    required int templateVersion,
    int? encounterId,
    int? patientId,
    String? providerId,
    required Map<String, dynamic> snapshot,
    String? usedBy,
  }) async {
    final pubId = _uuid.v4();
    final res = await db.execute(
      '''
      INSERT INTO mc_clinical_template_usages (
        hospital_code, public_id, tenant_id, template_id,
        template_version, encounter_id, patient_id, provider_id,
        snapshot_json, used_at, used_by
      ) VALUES (
        :hosp, :pub_id, :tenant, :tid,
        :tver, :enc_id, :pid, :prov_id,
        :snap, NOW(), :user
      )
      ''',
      {
        'hosp': hospitalCode,
        'pub_id': pubId,
        'tenant': hospitalCode,
        'tid': templateId,
        'tver': templateVersion,
        'enc_id': encounterId,
        'pid': patientId,
        'prov_id': providerId,
        'snap': jsonEncode(snapshot),
        'user': usedBy ?? 'SYSTEM',
      },
    );

    final id = res.lastInsertID.toInt();
    final rows = await db.execute(
      'SELECT * FROM mc_clinical_template_usages WHERE id = :id AND hospital_code = :hosp',
      {'id': id, 'hosp': hospitalCode},
    );
    return TemplateUsageRecord.fromRow(rows.rows.first.assoc());
  }

  Future<List<TemplateUsageRecord>> listTemplateUsages(
    String hospitalCode, {
    int? encounterId,
    int? patientId,
  }) async {
    var sql = 'SELECT * FROM mc_clinical_template_usages WHERE hospital_code = :hosp';
    final params = <String, dynamic>{'hosp': hospitalCode};

    if (encounterId != null) {
      sql += ' AND encounter_id = :enc';
      params['enc'] = encounterId;
    }
    if (patientId != null) {
      sql += ' AND patient_id = :pid';
      params['pid'] = patientId;
    }

    sql += ' ORDER BY id DESC';
    final rows = await db.execute(sql, params);
    return rows.rows.map((r) => TemplateUsageRecord.fromRow(r.assoc())).toList();
  }
}
