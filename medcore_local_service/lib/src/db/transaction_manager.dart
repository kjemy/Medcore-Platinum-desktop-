import 'dart:convert';
import 'package:mysql_client/mysql_client.dart';
import 'db_client.dart';

class TxContext implements SqlExecutor {
  final MySQLConnection _conn;
  final String? databaseName;
  bool _isActive = true;

  TxContext(this._conn, {this.databaseName});

  bool get isActive => _isActive;

  @override
  Future<IResultSet> execute(String sql, [Map<String, dynamic>? params]) async {
    if (!_isActive) {
      throw StateError('Transaction is no longer active.');
    }
    return await _conn.execute(sql, params ?? const {});
  }

  /// Executes a SELECT ... FOR UPDATE row-level lock inside the active transaction boundary
  Future<IResultSet> selectForUpdate(String sql, [Map<String, dynamic>? params]) async {
    if (!_isActive) {
      throw StateError('Cannot acquire FOR UPDATE lock outside an active transaction.');
    }
    final normalized = sql.trim();
    final lockSql = normalized.toUpperCase().endsWith('FOR UPDATE')
        ? normalized
        : '$normalized FOR UPDATE';
    return await _conn.execute(lockSql, params ?? const {});
  }

  Future<void> createSavepoint(String name) async {
    await execute('SAVEPOINT `$name`');
  }

  Future<void> rollbackToSavepoint(String name) async {
    await execute('ROLLBACK TO SAVEPOINT `$name`');
  }

  Future<void> releaseSavepoint(String name) async {
    await execute('RELEASE SAVEPOINT `$name`');
  }

  /// Writes an immutable audit log entry inside the exact same ACID transaction boundary
  Future<int> writeAuditLog({
    required String hospitalCode,
    int? actorStaffId,
    String? actorRole,
    String? deviceId,
    required String action,
    required String entityType,
    String? entityId,
    String? correlationId,
    Map<String, dynamic>? beforeState,
    Map<String, dynamic>? afterState,
    String? ipAddress,
  }) async {
    final res = await execute(
      '''
      INSERT INTO mc_audit_logs (
        hospital_code, actor_staff_id, actor_role, device_id,
        action, entity_type, entity_id, correlation_id,
        before_json, after_json, ip_address
      ) VALUES (
        :hosp, :actor_id, :actor_role, :device_id,
        :action, :entity_type, :entity_id, :corr_id,
        :before_json, :after_json, :ip
      )
      ''',
      {
        'hosp': hospitalCode,
        'actor_id': actorStaffId,
        'actor_role': actorRole,
        'device_id': deviceId,
        'action': action,
        'entity_type': entityType,
        'entity_id': entityId,
        'corr_id': correlationId,
        'before_json': beforeState != null ? jsonEncode(beforeState) : null,
        'after_json': afterState != null ? jsonEncode(afterState) : null,
        'ip': ipAddress,
      },
    );
    return res.lastInsertID.toInt();
  }

  void _markClosed() {
    _isActive = false;
  }
}

class TransactionManager {
  final DbClient db;

  TransactionManager(this.db);

  /// Executes [action] inside an ACID transaction boundary (`START TRANSACTION` .. `COMMIT` / `ROLLBACK`).
  Future<T> runInTransaction<T>(
    Future<T> Function(TxContext tx) action, {
    bool serializable = false,
  }) async {
    final conn = await db.openDedicatedConnection(useDatabase: true);
    final tx = TxContext(conn, databaseName: db.config.databaseName);
    try {
      if (serializable) {
        await conn.execute('SET TRANSACTION ISOLATION LEVEL SERIALIZABLE');
      } else {
        await conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ');
      }
      await conn.execute('START TRANSACTION');
      final result = await action(tx);
      await conn.execute('COMMIT');
      tx._markClosed();
      return result;
    } catch (e) {
      try {
        await conn.execute('ROLLBACK');
      } catch (_) {}
      tx._markClosed();
      rethrow;
    } finally {
      await conn.close();
    }
  }
}
