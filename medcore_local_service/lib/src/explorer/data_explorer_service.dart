import 'package:mysql_client/mysql_client.dart';
import '../db/db_client.dart';
import '../repositories/scope_context.dart';

/// Truth & Data Explorer Service for MedCore Desktop (Authoritative View & Inspection Layer)
/// Follows the strict MedCore Constitution:
/// Flutter Client -> Local MedCore Service -> Repositories / Data Explorer -> MariaDB
/// Flutter NEVER connects directly to MariaDB.
class DataExplorerService {
  final DbClient db;

  DataExplorerService(this.db);

  /// 1. Introspects complete database structure, columns, types, keys, and foreign keys
  Future<Map<String, dynamic>> getDatabaseStructure() async {
    final dbName = db.config.databaseName;

    // Tables
    final tablesRes = await db.execute(
      '''
      SELECT TABLE_NAME, ENGINE, TABLE_COLLATION, TABLE_ROWS
      FROM INFORMATION_SCHEMA.TABLES
      WHERE TABLE_SCHEMA = :db
      ORDER BY TABLE_NAME ASC
      ''',
      {'db': dbName},
    );

    // Columns
    final columnsRes = await db.execute(
      '''
      SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, COLUMN_TYPE, IS_NULLABLE, COLUMN_KEY, COLUMN_DEFAULT
      FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_SCHEMA = :db
      ORDER BY TABLE_NAME, ORDINAL_POSITION
      ''',
      {'db': dbName},
    );

    // Foreign Keys
    final fkRes = await db.execute(
      '''
      SELECT CONSTRAINT_NAME, TABLE_NAME, COLUMN_NAME, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME
      FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
      WHERE TABLE_SCHEMA = :db AND REFERENCED_TABLE_NAME IS NOT NULL
      ORDER BY TABLE_NAME, CONSTRAINT_NAME
      ''',
      {'db': dbName},
    );

    // Migrations
    final migRes = await db.execute(
      'SELECT version, description, checksum_sha256, applied_at FROM mc_schema_migrations ORDER BY version ASC',
    );

    final tablesList = tablesRes.rows.map((r) {
      final tname = r.colByName('TABLE_NAME') ?? '';
      final cols = columnsRes.rows
          .where((c) => c.colByName('TABLE_NAME') == tname)
          .map((c) => {
                'name': c.colByName('COLUMN_NAME'),
                'type': c.colByName('COLUMN_TYPE'),
                'isNullable': c.colByName('IS_NULLABLE') == 'YES',
                'key': c.colByName('COLUMN_KEY'),
                'default': c.colByName('COLUMN_DEFAULT'),
              })
          .toList();

      final fks = fkRes.rows
          .where((k) => k.colByName('TABLE_NAME') == tname)
          .map((k) => {
                'constraint': k.colByName('CONSTRAINT_NAME'),
                'column': k.colByName('COLUMN_NAME'),
                'refTable': k.colByName('REFERENCED_TABLE_NAME'),
                'refColumn': k.colByName('REFERENCED_COLUMN_NAME'),
              })
          .toList();

      return {
        'tableName': tname,
        'engine': r.colByName('ENGINE'),
        'collation': r.colByName('TABLE_COLLATION'),
        'columns': cols,
        'foreignKeys': fks,
      };
    }).toList();

    return {
      'database': dbName,
      'tableCount': tablesList.length,
      'tables': tablesList,
      'migrations': migRes.rows
          .map((m) => {
                'version': m.colByName('version'),
                'description': m.colByName('description'),
                'checksumSha256': m.colByName('checksum_sha256'),
                'appliedAt': m.colByName('applied_at'),
              })
          .toList(),
    };
  }

  /// 2. Data Inspection with mandatory Tenant Isolation and Privacy PII Redaction
  Future<Map<String, dynamic>> queryTableRecords({
    required String tableName,
    required ScopeContext scope,
    int limit = 50,
    int offset = 0,
    String? search,
    bool privacyFilter = true,
  }) async {
    final cleanTable = tableName.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(cleanTable)) {
      throw ArgumentError('Invalid table name: $tableName');
    }

    // Verify table exists
    final existsRes = await db.execute(
      '''
      SELECT COUNT(*) AS cnt
      FROM INFORMATION_SCHEMA.TABLES
      WHERE TABLE_SCHEMA = :db AND TABLE_NAME = :tname
      ''',
      {'db': db.config.databaseName, 'tname': cleanTable},
    );
    if ((int.tryParse(existsRes.rows.first.colByName('cnt') ?? '0') ?? 0) == 0) {
      throw ArgumentError('Table $cleanTable does not exist');
    }

    // Check if table has hospital_code column
    final colCheck = await db.execute(
      '''
      SELECT COLUMN_NAME
      FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_SCHEMA = :db AND TABLE_NAME = :tname
      ''',
      {'db': db.config.databaseName, 'tname': cleanTable},
    );
    final colNames = colCheck.rows.map((r) => r.colByName('COLUMN_NAME')!.toLowerCase()).toSet();

    final whereClauses = <String>[];
    final params = <String, dynamic>{};

    if (colNames.contains('hospital_code')) {
      whereClauses.add('hospital_code = :hospitalCode');
      params['hospitalCode'] = scope.hospitalCode;
    }

    if (scope.dataScopeMode == DataScopeMode.ownOnly) {
      if (colNames.contains('created_by')) {
        whereClauses.add('created_by = :actorStaffId');
        params['actorStaffId'] = scope.actor.id;
      } else if (colNames.contains('assigned_doctor_id')) {
        whereClauses.add('assigned_doctor_id = :actorStaffId');
        params['actorStaffId'] = scope.actor.id;
      }
    }

    if (search != null && search.trim().isNotEmpty) {
      final searchFields = colNames.intersection({'mrn', 'visit_number', 'staff_code', 'event_uuid', 'email'}).toList();
      if (searchFields.isNotEmpty) {
        final orParts = searchFields.map((f) => '$f LIKE :search').join(' OR ');
        whereClauses.add('($orParts)');
        params['search'] = '%${search.trim()}%';
      }
    }

    final whereSql = whereClauses.isNotEmpty ? 'WHERE ${whereClauses.join(' AND ')}' : '';
    final countSql = 'SELECT COUNT(*) AS total FROM `$cleanTable` $whereSql';
    final countRes = await db.execute(countSql, params);
    final totalRows = int.parse(countRes.rows.first.colByName('total') ?? '0');

    final dataSql = 'SELECT * FROM `$cleanTable` $whereSql LIMIT $limit OFFSET $offset';
    final dataRes = await db.execute(dataSql, params);

    final records = dataRes.rows.map((row) {
      final map = <String, dynamic>{};
      for (final col in colNames) {
        final val = row.colByName(col);
        map[col] = privacyFilter ? _redactField(col, val) : val;
      }
      return map;
    }).toList();

    return {
      'table': cleanTable,
      'totalRecords': totalRows,
      'limit': limit,
      'offset': offset,
      'privacyFilterApplied': privacyFilter,
      'records': records,
    };
  }

  /// 3. Business Graph / Truth Trace: Relational inspection from Visit -> Patient -> Postings -> Ledger
  Future<Map<String, dynamic>> traceTruthGraph({
    required String hospitalCode,
    required String visitNumber,
    bool privacyFilter = true,
  }) async {
    // 1. Visit
    final visitRes = await db.execute(
      'SELECT * FROM mc_visits WHERE hospital_code = :hosp AND visit_number = :vnum LIMIT 1',
      {'hosp': hospitalCode, 'vnum': visitNumber},
    );
    if (visitRes.rows.isEmpty) {
      throw ArgumentError('Visit $visitNumber not found in hospital $hospitalCode');
    }
    final visitRow = visitRes.rows.first;
    final visitId = int.parse(visitRow.colByName('id')!);
    final patientId = int.parse(visitRow.colByName('patient_id')!);
    final shiftIdStr = visitRow.colByName('shift_id');
    final shiftId = shiftIdStr != null ? int.tryParse(shiftIdStr) : null;

    // 2. Patient
    final patRes = await db.execute(
      'SELECT * FROM mc_patients WHERE hospital_code = :hosp AND id = :pid LIMIT 1',
      {'hosp': hospitalCode, 'pid': patientId},
    );
    final patRow = patRes.rows.isNotEmpty ? _rowToMap(patRes, patRes.rows.first) : null;

    // 3. Visit Items
    final itemsRes = await db.execute(
      'SELECT * FROM mc_visit_items WHERE hospital_code = :hosp AND visit_id = :vid ORDER BY id ASC',
      {'hosp': hospitalCode, 'vid': visitId},
    );

    // 4. Cost lines per item
    final itemIds = itemsRes.rows.map((r) => int.parse(r.colByName('id')!)).toList();
    final costLines = <Map<String, dynamic>>[];
    if (itemIds.isNotEmpty) {
      final costRes = await db.execute(
        'SELECT * FROM mc_visit_item_cost_lines WHERE hospital_code = :hosp AND visit_item_id IN (${itemIds.join(",")}) ORDER BY id ASC',
        {'hosp': hospitalCode},
      );
      for (final r in costRes.rows) {
        costLines.add(_rowToMap(costRes, r));
      }
    }

    // 5. Financial Event & Postings
    final evRes = await db.execute(
      '''
      SELECT * FROM mc_financial_events
      WHERE hospital_code = :hosp AND source_entity_type = 'VISIT' AND source_entity_id = :vid
      ORDER BY id ASC
      ''',
      {'hosp': hospitalCode, 'vid': visitId},
    );
    final events = <Map<String, dynamic>>[];
    final postings = <Map<String, dynamic>>[];
    for (final evRow in evRes.rows) {
      final evId = int.parse(evRow.colByName('id')!);
      events.add(_rowToMap(evRes, evRow));

      final postRes = await db.execute(
        'SELECT * FROM mc_financial_postings WHERE hospital_code = :hosp AND event_id = :eid ORDER BY id ASC',
        {'hosp': hospitalCode, 'eid': evId},
      );
      for (final pRow in postRes.rows) {
        postings.add(_rowToMap(postRes, pRow));
      }
    }

    // 6. Shift
    Map<String, dynamic>? shiftData;
    if (shiftId != null) {
      final shiftRes = await db.execute(
        'SELECT * FROM mc_shifts WHERE hospital_code = :hosp AND id = :sid LIMIT 1',
        {'hosp': hospitalCode, 'sid': shiftId},
      );
      if (shiftRes.rows.isNotEmpty) {
        shiftData = _rowToMap(shiftRes, shiftRes.rows.first);
      }
    }

    // 7. Audit Trail
    final auditRes = await db.execute(
      '''
      SELECT * FROM mc_audit_logs
      WHERE hospital_code = :hosp AND entity_type = 'VISIT' AND entity_id = :vid
      ORDER BY id ASC
      ''',
      {'hosp': hospitalCode, 'vid': visitId},
    );
    final auditLogs = auditRes.rows.map((r) => _rowToMap(auditRes, r)).toList();

    return {
      'traceType': 'VISIT_TRUTH_GRAPH',
      'hospitalCode': hospitalCode,
      'visitNumber': visitNumber,
      'privacyFilterApplied': privacyFilter,
      'patient': patRow != null ? _redactMap(patRow, privacyFilter) : null,
      'visit': _redactMap(_rowToMap(visitRes, visitRow), privacyFilter),
      'items': itemsRes.rows.map((r) => _redactMap(_rowToMap(itemsRes, r), privacyFilter)).toList(),
      'costLines': costLines,
      'financialEvents': events,
      'financialPostings': postings,
      'shift': shiftData,
      'auditTrail': auditLogs,
    };
  }

  Map<String, dynamic> _rowToMap(IResultSet res, dynamic row) {
    final map = <String, dynamic>{};
    for (final col in res.cols) {
      map[col.name] = row.colByName(col.name);
    }
    return map;
  }

  /// 4. Structured CSV Export
  Future<String> exportTableDataCsv({
    required String tableName,
    required ScopeContext scope,
    bool privacyFilter = true,
  }) async {
    final result = await queryTableRecords(
      tableName: tableName,
      scope: scope,
      limit: 1000,
      privacyFilter: privacyFilter,
    );
    final records = (result['records'] as List).cast<Map<String, dynamic>>();
    if (records.isEmpty) {
      return 'No records found for table $tableName';
    }

    final headers = records.first.keys.toList();
    final buffer = StringBuffer();
    buffer.writeln(headers.map(_csvEscape).join(','));

    for (final r in records) {
      final row = headers.map((h) => _csvEscape(r[h]?.toString() ?? '')).join(',');
      buffer.writeln(row);
    }

    return buffer.toString();
  }

  /// 5. Structured Formatted TXT Export
  Future<String> exportTableDataTxt({
    required String tableName,
    required ScopeContext scope,
    bool privacyFilter = true,
  }) async {
    final result = await queryTableRecords(
      tableName: tableName,
      scope: scope,
      limit: 100,
      privacyFilter: privacyFilter,
    );
    final records = (result['records'] as List).cast<Map<String, dynamic>>();
    final buffer = StringBuffer();
    buffer.writeln('================================================================================');
    buffer.writeln('MEDCORE DESKTOP — AUTHORITATIVE DATA EXPORT');
    buffer.writeln('Table: $tableName | Tenant: ${scope.hospitalCode} | Privacy Mask: $privacyFilter');
    buffer.writeln('Export Timestamp: ${DateTime.now().toUtc().toIso8601String()}');
    buffer.writeln('================================================================================\n');

    if (records.isEmpty) {
      buffer.writeln('No records found.');
      return buffer.toString();
    }

    for (var i = 0; i < records.length; i++) {
      buffer.writeln('--- [Record #${i + 1}] ---');
      for (final entry in records[i].entries) {
        buffer.writeln('  ${entry.key.padRight(28)}: ${entry.value}');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// Privacy Masking / Redaction helper
  dynamic _redactField(String colName, dynamic val) {
    if (val == null) return null;
    final str = val.toString();
    final lower = colName.toLowerCase();

    if (lower.contains('password') || lower.contains('secret') || lower.contains('token')) {
      return '[REDACTED_SECRET]';
    }
    if (lower.contains('name') && (lower.contains('full') || lower.contains('patient') || lower.contains('staff'))) {
      if (str.length <= 2) return '***';
      return '${str[0]}*** ${str[str.length - 1]}***';
    }
    if (lower.contains('phone') || lower.contains('mobile')) {
      if (str.length < 7) return '****';
      return '${str.substring(0, 3)}****${str.substring(str.length - 4)}';
    }
    if (lower.contains('national_id') || lower.contains('ssn')) {
      if (str.length < 5) return '****';
      return '******${str.substring(str.length - 4)}';
    }
    if (lower.contains('notes') || lower.contains('complaint') || lower.contains('diagnosis') || lower.contains('history')) {
      return '[CONFIDENTIAL MEDICAL DATA REDACTED]';
    }
    return val;
  }

  Map<String, dynamic> _redactMap(Map<String, dynamic> input, bool privacyFilter) {
    if (!privacyFilter) return input;
    final out = <String, dynamic>{};
    for (final e in input.entries) {
      out[e.key] = _redactField(e.key, e.value);
    }
    return out;
  }

  String _csvEscape(String val) {
    if (val.contains(',') || val.contains('"') || val.contains('\n')) {
      return '"${val.replaceAll('"', '""')}"';
    }
    return val;
  }
}
