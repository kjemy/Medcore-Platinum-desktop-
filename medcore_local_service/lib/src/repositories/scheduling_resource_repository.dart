import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../db/db_client.dart';

enum SchedulingResourceType {
  doctor,
  room,
  theater,
  equipment,
  device,
  chair;

  static SchedulingResourceType fromString(String val) {
    switch (val.toUpperCase()) {
      case 'DOCTOR':
        return SchedulingResourceType.doctor;
      case 'ROOM':
        return SchedulingResourceType.room;
      case 'THEATER':
        return SchedulingResourceType.theater;
      case 'EQUIPMENT':
        return SchedulingResourceType.equipment;
      case 'DEVICE':
        return SchedulingResourceType.device;
      case 'CHAIR':
        return SchedulingResourceType.chair;
      default:
        return SchedulingResourceType.room;
    }
  }

  String get dbValue => name.toUpperCase();
}

class SchedulingResourceRecord {
  final int id;
  final String hospitalCode;
  final String publicId;
  final String resourceCode;
  final String name;
  final SchedulingResourceType resourceType;
  final String? departmentId;
  final int capacity;
  final bool isActive;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SchedulingResourceRecord({
    required this.id,
    required this.hospitalCode,
    required this.publicId,
    required this.resourceCode,
    required this.name,
    required this.resourceType,
    this.departmentId,
    required this.capacity,
    required this.isActive,
    required this.metadata,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SchedulingResourceRecord.fromRow(Map<String, dynamic> row) {
    Map<String, dynamic> meta = {};
    final raw = row['metadata_json']?.toString();
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        meta = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {}
    }

    return SchedulingResourceRecord(
      id: int.parse(row['id'].toString()),
      hospitalCode: (row['hospital_code'] ?? '').toString(),
      publicId: (row['public_id'] ?? '').toString(),
      resourceCode: (row['resource_code'] ?? '').toString(),
      name: (row['name'] ?? '').toString(),
      resourceType: SchedulingResourceType.fromString((row['resource_type'] ?? 'ROOM').toString()),
      departmentId: row['department_id']?.toString(),
      capacity: int.tryParse(row['capacity']?.toString() ?? '1') ?? 1,
      isActive: (row['is_active']?.toString() == '1') || (row['is_active'] == true),
      metadata: meta,
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now().toUtc(),
      updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? '') ?? DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'publicId': publicId,
        'hospitalCode': hospitalCode,
        'resourceCode': resourceCode,
        'name': name,
        'resourceType': resourceType.dbValue,
        'departmentId': departmentId,
        'capacity': capacity,
        'isActive': isActive,
        'metadata': metadata,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}

class SchedulingRuleRecord {
  final int id;
  final String hospitalCode;
  final String publicId;
  final String ruleCode;
  final String name;
  final String appointmentType;
  final SchedulingResourceType primaryResourceType;
  final List<String> requiredCoResourceTypes;
  final int defaultDurationMinutes;
  final int bufferBeforeMinutes;
  final int bufferAfterMinutes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SchedulingRuleRecord({
    required this.id,
    required this.hospitalCode,
    required this.publicId,
    required this.ruleCode,
    required this.name,
    required this.appointmentType,
    required this.primaryResourceType,
    required this.requiredCoResourceTypes,
    required this.defaultDurationMinutes,
    required this.bufferBeforeMinutes,
    required this.bufferAfterMinutes,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SchedulingRuleRecord.fromRow(Map<String, dynamic> row) {
    List<String> coTypes = [];
    final raw = row['required_co_resource_types_json']?.toString();
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final parsed = jsonDecode(raw) as List;
        coTypes = parsed.map((e) => e.toString()).toList();
      } catch (_) {}
    }

    return SchedulingRuleRecord(
      id: int.parse(row['id'].toString()),
      hospitalCode: (row['hospital_code'] ?? '').toString(),
      publicId: (row['public_id'] ?? '').toString(),
      ruleCode: (row['rule_code'] ?? '').toString(),
      name: (row['name'] ?? '').toString(),
      appointmentType: (row['appointment_type'] ?? 'CONSULTATION').toString(),
      primaryResourceType: SchedulingResourceType.fromString((row['primary_resource_type'] ?? 'DOCTOR').toString()),
      requiredCoResourceTypes: coTypes,
      defaultDurationMinutes: int.tryParse(row['default_duration_minutes']?.toString() ?? '30') ?? 30,
      bufferBeforeMinutes: int.tryParse(row['buffer_before_minutes']?.toString() ?? '0') ?? 0,
      bufferAfterMinutes: int.tryParse(row['buffer_after_minutes']?.toString() ?? '0') ?? 0,
      isActive: (row['is_active']?.toString() == '1') || (row['is_active'] == true),
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now().toUtc(),
      updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? '') ?? DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'publicId': publicId,
        'hospitalCode': hospitalCode,
        'ruleCode': ruleCode,
        'name': name,
        'appointmentType': appointmentType,
        'primaryResourceType': primaryResourceType.dbValue,
        'requiredCoResourceTypes': requiredCoResourceTypes,
        'defaultDurationMinutes': defaultDurationMinutes,
        'bufferBeforeMinutes': bufferBeforeMinutes,
        'bufferAfterMinutes': bufferAfterMinutes,
        'isActive': isActive,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}

class ResourceAllocationRecord {
  final int id;
  final String hospitalCode;
  final String publicId;
  final int appointmentId;
  final int resourceId;
  final DateTime allocatedStart;
  final DateTime allocatedEnd;
  final String status;
  final DateTime createdAt;

  const ResourceAllocationRecord({
    required this.id,
    required this.hospitalCode,
    required this.publicId,
    required this.appointmentId,
    required this.resourceId,
    required this.allocatedStart,
    required this.allocatedEnd,
    required this.status,
    required this.createdAt,
  });

  factory ResourceAllocationRecord.fromRow(Map<String, dynamic> row) {
    return ResourceAllocationRecord(
      id: int.parse(row['id'].toString()),
      hospitalCode: (row['hospital_code'] ?? '').toString(),
      publicId: (row['public_id'] ?? '').toString(),
      appointmentId: int.parse(row['appointment_id'].toString()),
      resourceId: int.parse(row['resource_id'].toString()),
      allocatedStart: DateTime.parse(row['allocated_start'].toString().replaceAll(' ', 'T')),
      allocatedEnd: DateTime.parse(row['allocated_end'].toString().replaceAll(' ', 'T')),
      status: (row['status'] ?? 'CONFIRMED').toString(),
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'publicId': publicId,
        'hospitalCode': hospitalCode,
        'appointmentId': appointmentId,
        'resourceId': resourceId,
        'allocatedStart': allocatedStart.toIso8601String(),
        'allocatedEnd': allocatedEnd.toIso8601String(),
        'status': status,
        'createdAt': createdAt.toIso8601String(),
      };
}

class SchedulingResourceRepository {
  final SqlExecutor db;
  static const _uuid = Uuid();

  SchedulingResourceRepository(this.db);

  // 1. Resource Management
  Future<SchedulingResourceRecord> upsertResource({
    required String hospitalCode,
    required String resourceCode,
    required String name,
    required SchedulingResourceType resourceType,
    String? departmentId,
    int capacity = 1,
    bool isActive = true,
    Map<String, dynamic>? metadata,
  }) async {
    final pubId = _uuid.v4();
    final metaStr = metadata != null ? jsonEncode(metadata) : '{}';

    await db.execute(
      '''
      INSERT INTO mc_scheduling_resources (
        hospital_code, public_id, tenant_id, resource_code,
        name, resource_type, department_id, capacity,
        is_active, metadata_json, created_at, updated_at
      ) VALUES (
        :hosp, :pub_id, :tenant, :code,
        :name, :type, :dept, :cap,
        :active, :meta, NOW(), NOW()
      )
      ON DUPLICATE KEY UPDATE
        name = VALUES(name),
        resource_type = VALUES(resource_type),
        department_id = VALUES(department_id),
        capacity = VALUES(capacity),
        is_active = VALUES(is_active),
        metadata_json = VALUES(metadata_json),
        updated_at = NOW()
      ''',
      {
        'hosp': hospitalCode,
        'pub_id': pubId,
        'tenant': hospitalCode,
        'code': resourceCode,
        'name': name,
        'type': resourceType.dbValue,
        'dept': departmentId,
        'cap': capacity,
        'active': isActive ? 1 : 0,
        'meta': metaStr,
      },
    );

    final res = await getResourceByCode(hospitalCode, resourceCode);
    return res!;
  }

  Future<SchedulingResourceRecord?> getResourceByCode(String hospitalCode, String resourceCode) async {
    final rows = await db.execute(
      'SELECT * FROM mc_scheduling_resources WHERE hospital_code = :hosp AND resource_code = :code LIMIT 1',
      {'hosp': hospitalCode, 'code': resourceCode},
    );
    if (rows.rows.isEmpty) return null;
    return SchedulingResourceRecord.fromRow(rows.rows.first.assoc());
  }

  Future<SchedulingResourceRecord?> getResourceById(String hospitalCode, int id) async {
    final rows = await db.execute(
      'SELECT * FROM mc_scheduling_resources WHERE hospital_code = :hosp AND id = :id LIMIT 1',
      {'hosp': hospitalCode, 'id': id},
    );
    if (rows.rows.isEmpty) return null;
    return SchedulingResourceRecord.fromRow(rows.rows.first.assoc());
  }

  Future<List<SchedulingResourceRecord>> listResources(
    String hospitalCode, {
    SchedulingResourceType? resourceType,
    bool? onlyActive,
  }) async {
    var sql = 'SELECT * FROM mc_scheduling_resources WHERE hospital_code = :hosp';
    final params = <String, dynamic>{'hosp': hospitalCode};

    if (resourceType != null) {
      sql += ' AND resource_type = :type';
      params['type'] = resourceType.dbValue;
    }
    if (onlyActive == true) {
      sql += ' AND is_active = 1';
    }

    sql += ' ORDER BY resource_type ASC, name ASC';
    final rows = await db.execute(sql, params);
    return rows.rows.map((r) => SchedulingResourceRecord.fromRow(r.assoc())).toList();
  }

  // 2. Rule Management
  Future<SchedulingRuleRecord> upsertRule({
    required String hospitalCode,
    required String ruleCode,
    required String name,
    required String appointmentType,
    required SchedulingResourceType primaryResourceType,
    List<String> requiredCoResourceTypes = const [],
    int defaultDurationMinutes = 30,
    int bufferBeforeMinutes = 0,
    int bufferAfterMinutes = 0,
    bool isActive = true,
  }) async {
    final pubId = _uuid.v4();
    final coTypesJson = jsonEncode(requiredCoResourceTypes.map((e) => e.toUpperCase()).toList());

    await db.execute(
      '''
      INSERT INTO mc_scheduling_rules (
        hospital_code, public_id, tenant_id, rule_code,
        name, appointment_type, primary_resource_type,
        required_co_resource_types_json, default_duration_minutes,
        buffer_before_minutes, buffer_after_minutes, is_active,
        created_at, updated_at
      ) VALUES (
        :hosp, :pub_id, :tenant, :code,
        :name, :atype, :ptype,
        :co_types, :dur, :buf_before, :buf_after,
        :active, NOW(), NOW()
      )
      ON DUPLICATE KEY UPDATE
        name = VALUES(name),
        appointment_type = VALUES(appointment_type),
        primary_resource_type = VALUES(primary_resource_type),
        required_co_resource_types_json = VALUES(required_co_resource_types_json),
        default_duration_minutes = VALUES(default_duration_minutes),
        buffer_before_minutes = VALUES(buffer_before_minutes),
        buffer_after_minutes = VALUES(buffer_after_minutes),
        is_active = VALUES(is_active),
        updated_at = NOW()
      ''',
      {
        'hosp': hospitalCode,
        'pub_id': pubId,
        'tenant': hospitalCode,
        'code': ruleCode,
        'name': name,
        'atype': appointmentType,
        'ptype': primaryResourceType.dbValue,
        'co_types': coTypesJson,
        'dur': defaultDurationMinutes,
        'buf_before': bufferBeforeMinutes,
        'buf_after': bufferAfterMinutes,
        'active': isActive ? 1 : 0,
      },
    );

    final res = await getRuleByCode(hospitalCode, ruleCode);
    return res!;
  }

  Future<SchedulingRuleRecord?> getRuleByCode(String hospitalCode, String ruleCode) async {
    final rows = await db.execute(
      'SELECT * FROM mc_scheduling_rules WHERE hospital_code = :hosp AND rule_code = :code LIMIT 1',
      {'hosp': hospitalCode, 'code': ruleCode},
    );
    if (rows.rows.isEmpty) return null;
    return SchedulingRuleRecord.fromRow(rows.rows.first.assoc());
  }

  Future<SchedulingRuleRecord?> getRuleByAppointmentType(String hospitalCode, String appointmentType) async {
    final rows = await db.execute(
      '''
      SELECT * FROM mc_scheduling_rules
      WHERE hospital_code = :hosp AND appointment_type = :atype AND is_active = 1
      LIMIT 1
      ''',
      {'hosp': hospitalCode, 'atype': appointmentType},
    );
    if (rows.rows.isEmpty) return null;
    return SchedulingRuleRecord.fromRow(rows.rows.first.assoc());
  }

  Future<List<SchedulingRuleRecord>> listRules(String hospitalCode, {bool? onlyActive}) async {
    var sql = 'SELECT * FROM mc_scheduling_rules WHERE hospital_code = :hosp';
    final params = <String, dynamic>{'hosp': hospitalCode};

    if (onlyActive == true) {
      sql += ' AND is_active = 1';
    }
    sql += ' ORDER BY appointment_type ASC';

    final rows = await db.execute(sql, params);
    return rows.rows.map((r) => SchedulingRuleRecord.fromRow(r.assoc())).toList();
  }

  // 3. Conflict Detection & Multi-Resource Slot Allocation Engine
  Future<List<Map<String, dynamic>>> checkConflicts({
    required String hospitalCode,
    required List<int> resourceIds,
    required DateTime startUtc,
    required DateTime endUtc,
    int? excludeAppointmentId,
  }) async {
    if (resourceIds.isEmpty) return [];

    final startStr = startUtc.toIso8601String().substring(0, 19).replaceAll('T', ' ');
    final endStr = endUtc.toIso8601String().substring(0, 19).replaceAll('T', ' ');

    final inClause = resourceIds.join(',');
    var sql = '''
      SELECT a.*, r.name AS resource_name, r.resource_code, r.resource_type
      FROM mc_appointment_resource_allocations a
      JOIN mc_scheduling_resources r ON a.resource_id = r.id
      WHERE a.hospital_code = :hosp
        AND a.resource_id IN ($inClause)
        AND a.status IN ('CONFIRMED', 'HELD')
        AND a.allocated_start < :end_time
        AND a.allocated_end > :start_time
    ''';
    final params = <String, dynamic>{
      'hosp': hospitalCode,
      'start_time': startStr,
      'end_time': endStr,
    };

    if (excludeAppointmentId != null) {
      sql += ' AND a.appointment_id != :ex_apt';
      params['ex_apt'] = excludeAppointmentId;
    }

    final rows = await db.execute(sql, params);
    return rows.rows.map((r) => r.assoc()).toList();
  }

  Future<List<ResourceAllocationRecord>> allocateResourcesTransaction({
    required String hospitalCode,
    required int appointmentId,
    required List<int> resourceIds,
    required DateTime requestedStartUtc,
    required int durationMinutes,
    int bufferBeforeMinutes = 0,
    int bufferAfterMinutes = 0,
  }) async {
    final effectiveStart = requestedStartUtc.subtract(Duration(minutes: bufferBeforeMinutes));
    final effectiveEnd = requestedStartUtc.add(Duration(minutes: durationMinutes + bufferAfterMinutes));

    // 1. Strict Conflict Verification: ensure no overlapping allocations
    final conflicts = await checkConflicts(
      hospitalCode: hospitalCode,
      resourceIds: resourceIds,
      startUtc: effectiveStart,
      endUtc: effectiveEnd,
      excludeAppointmentId: appointmentId,
    );

    if (conflicts.isNotEmpty) {
      final conflictNames = conflicts.map((c) => "${c['resource_name']} (${c['resource_code']})").join(', ');
      throw StateError('RESOURCE_CONFLICT: One or more requested resources are already booked for this time window: $conflictNames');
    }

    // 2. Perform allocations
    final allocations = <ResourceAllocationRecord>[];
    final startStr = effectiveStart.toIso8601String().substring(0, 19).replaceAll('T', ' ');
    final endStr = effectiveEnd.toIso8601String().substring(0, 19).replaceAll('T', ' ');

    for (final resId in resourceIds) {
      final pubId = _uuid.v4();
      final res = await db.execute(
        '''
        INSERT INTO mc_appointment_resource_allocations (
          hospital_code, public_id, appointment_id, resource_id,
          allocated_start, allocated_end, status, created_at, updated_at
        ) VALUES (
          :hosp, :pub_id, :apt_id, :res_id,
          :start_time, :end_time, 'CONFIRMED', NOW(), NOW()
        )
        ''',
        {
          'hosp': hospitalCode,
          'pub_id': pubId,
          'apt_id': appointmentId,
          'res_id': resId,
          'start_time': startStr,
          'end_time': endStr,
        },
      );
      final id = res.lastInsertID.toInt();
      final row = await db.execute(
        'SELECT * FROM mc_appointment_resource_allocations WHERE id = :id AND hospital_code = :hosp',
        {'id': id, 'hosp': hospitalCode},
      );
      allocations.add(ResourceAllocationRecord.fromRow(row.rows.first.assoc()));
    }

    return allocations;
  }

  Future<void> releaseAllocationsForAppointment(String hospitalCode, int appointmentId) async {
    await db.execute(
      '''
      UPDATE mc_appointment_resource_allocations
      SET status = 'RELEASED', updated_at = NOW()
      WHERE hospital_code = :hosp AND appointment_id = :apt_id
      ''',
      {'hosp': hospitalCode, 'apt_id': appointmentId},
    );
  }

  Future<List<ResourceAllocationRecord>> listAllocationsForAppointment(String hospitalCode, int appointmentId) async {
    final rows = await db.execute(
      'SELECT * FROM mc_appointment_resource_allocations WHERE hospital_code = :hosp AND appointment_id = :apt_id',
      {'hosp': hospitalCode, 'apt_id': appointmentId},
    );
    return rows.rows.map((r) => ResourceAllocationRecord.fromRow(r.assoc())).toList();
  }
}
