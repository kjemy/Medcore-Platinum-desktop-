import 'dart:async';
import 'package:mysql_client/mysql_client.dart';
import 'db_config.dart';

abstract class SqlExecutor {
  Future<IResultSet> execute(String sql, [Map<String, dynamic>? params]);
}

class DbConnectionWrapper implements SqlExecutor {
  final MySQLConnection connection;
  DbConnectionWrapper(this.connection);

  @override
  Future<IResultSet> execute(String sql, [Map<String, dynamic>? params]) async {
    return await connection.execute(sql, params ?? const {});
  }
}

class DbClient implements SqlExecutor {
  final DbConfig config;
  MySQLConnectionPool? _pool;

  DbClient(this.config);

  MySQLConnectionPool get pool {
    _pool ??= MySQLConnectionPool(
      host: config.host,
      port: config.port,
      userName: config.user,
      password: config.password,
      databaseName: config.databaseName,
      maxConnections: config.maxConnections,
      secure: false,
    );
    return _pool!;
  }

  /// Opens a single dedicated MySQLConnection (used for transactions, FOR UPDATE locks, and multi-statement DDL)
  Future<MySQLConnection> openDedicatedConnection({bool useDatabase = true}) async {
    final conn = await MySQLConnection.createConnection(
      host: config.host,
      port: config.port,
      userName: config.user,
      password: config.password,
      databaseName: useDatabase ? config.databaseName : null,
      secure: false,
    );
    await conn.connect();
    await conn.execute("SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci");
    await conn.execute("SET SESSION sql_mode = 'STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION'");
    return conn;
  }

  Future<void> ensureDatabaseExists() async {
    final conn = await openDedicatedConnection(useDatabase: false);
    try {
      await conn.execute(
        "CREATE DATABASE IF NOT EXISTS `${config.databaseName}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci",
      );
    } finally {
      await conn.close();
    }
  }

  @override
  Future<IResultSet> execute(String sql, [Map<String, dynamic>? params]) async {
    return await pool.execute(sql, params ?? const {});
  }

  Future<void> close() async {
    if (_pool != null) {
      await _pool!.close();
      _pool = null;
    }
  }
}
