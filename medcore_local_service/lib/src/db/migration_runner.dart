import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'db_client.dart';

class MigrationRecord {
  final String version;
  final String description;
  final String checksumSha256;
  final int executionMs;

  MigrationRecord({
    required this.version,
    required this.description,
    required this.checksumSha256,
    required this.executionMs,
  });
}

class MigrationTamperException implements Exception {
  final String version;
  final String expectedChecksum;
  final String actualChecksum;

  MigrationTamperException(this.version, this.expectedChecksum, this.actualChecksum);

  @override
  String toString() =>
      'MigrationTamperException: Migration $version checksum mismatch (expected $expectedChecksum, got $actualChecksum)';
}

class MigrationRunner {
  final DbClient db;
  final String migrationsDir;

  MigrationRunner({
    required this.db,
    required this.migrationsDir,
  });

  static String computeSha256(String content) {
    final normalized = content.replaceAll('\r\n', '\n').trim();
    return sha256.convert(utf8.encode(normalized)).toString();
  }

  /// Splits SQL script into individual executable statements
  static List<String> splitStatements(String sqlContent) {
    final lines = sqlContent.replaceAll('\r\n', '\n').split('\n');
    final cleanedLines = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('--')) continue;
      cleanedLines.add(line);
    }
    final joined = cleanedLines.join('\n');
    return joined
        .split(';')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<List<MigrationRecord>> runMigrations() async {
    await db.ensureDatabaseExists();
    final conn = await db.openDedicatedConnection(useDatabase: true);
    try {
      // Ensure mc_schema_migrations table exists first
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS mc_schema_migrations (
          version VARCHAR(64) NOT NULL PRIMARY KEY,
          description VARCHAR(255) NOT NULL,
          checksum_sha256 CHAR(64) NOT NULL,
          execution_ms INT UNSIGNED NOT NULL DEFAULT 0,
          applied_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
      ''');

      // Load already applied migrations
      final existingRes = await conn.execute(
        'SELECT version, description, checksum_sha256, execution_ms FROM mc_schema_migrations ORDER BY version ASC',
      );
      final appliedMap = <String, MigrationRecord>{};
      for (final row in existingRes.rows) {
        final v = row.colByName('version') ?? '';
        appliedMap[v] = MigrationRecord(
          version: v,
          description: row.colByName('description') ?? '',
          checksumSha256: row.colByName('checksum_sha256') ?? '',
          executionMs: int.tryParse(row.colByName('execution_ms') ?? '0') ?? 0,
        );
      }

      final dir = Directory(migrationsDir);
      if (!dir.existsSync()) {
        throw StateError('Migrations directory not found: $migrationsDir');
      }

      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('V') && f.path.endsWith('.sql'))
          .toList()
        ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

      final results = <MigrationRecord>[];

      for (final file in files) {
        final base = p.basenameWithoutExtension(file.path);
        final parts = base.split('__');
        final version = parts[0];
        final description = parts.length > 1 ? parts[1].replaceAll('_', ' ') : base;
        final content = file.readAsStringSync();
        final checksum = computeSha256(content);

        if (appliedMap.containsKey(version)) {
          final prev = appliedMap[version]!;
          if (prev.checksumSha256 != checksum) {
            throw MigrationTamperException(version, prev.checksumSha256, checksum);
          }
          results.add(prev);
          continue;
        }

        final sw = Stopwatch()..start();
        final statements = splitStatements(content);
        for (final stmt in statements) {
          try {
            await conn.execute(stmt);
          } catch (e) {
            // Ignore duplicate index errors on idempotent re-run
            final msg = e.toString().toLowerCase();
            if (msg.contains('duplicate key name') || msg.contains('already exists')) {
              continue;
            }
            rethrow;
          }
        }
        sw.stop();

        await conn.execute(
          '''
          INSERT INTO mc_schema_migrations (version, description, checksum_sha256, execution_ms)
          VALUES (:version, :description, :checksum, :ms)
          ''',
          {
            'version': version,
            'description': description,
            'checksum': checksum,
            'ms': sw.elapsedMilliseconds,
          },
        );

        results.add(
          MigrationRecord(
            version: version,
            description: description,
            checksumSha256: checksum,
            executionMs: sw.elapsedMilliseconds,
          ),
        );
      }

      return results;
    } finally {
      await conn.close();
    }
  }

  /// Introspects all tables in the current database via INFORMATION_SCHEMA.TABLES
  Future<List<Map<String, String>>> inspectTables() async {
    final res = await db.execute(
      '''
      SELECT TABLE_NAME, ENGINE, TABLE_COLLATION
      FROM INFORMATION_SCHEMA.TABLES
      WHERE TABLE_SCHEMA = :db
      ORDER BY TABLE_NAME ASC
      ''',
      {'db': db.config.databaseName},
    );
    return res.rows
        .map((r) => {
              'table_name': r.colByName('TABLE_NAME') ?? '',
              'engine': r.colByName('ENGINE') ?? '',
              'collation': r.colByName('TABLE_COLLATION') ?? '',
            })
        .toList();
  }

  /// Introspects all Foreign Keys via INFORMATION_SCHEMA.KEY_COLUMN_USAGE
  Future<List<Map<String, String>>> inspectForeignKeys() async {
    final res = await db.execute(
      '''
      SELECT CONSTRAINT_NAME, TABLE_NAME, COLUMN_NAME, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME
      FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
      WHERE TABLE_SCHEMA = :db AND REFERENCED_TABLE_NAME IS NOT NULL
      ORDER BY TABLE_NAME, CONSTRAINT_NAME
      ''',
      {'db': db.config.databaseName},
    );
    return res.rows
        .map((r) => {
              'constraint': r.colByName('CONSTRAINT_NAME') ?? '',
              'table': r.colByName('TABLE_NAME') ?? '',
              'column': r.colByName('COLUMN_NAME') ?? '',
              'ref_table': r.colByName('REFERENCED_TABLE_NAME') ?? '',
              'ref_column': r.colByName('REFERENCED_COLUMN_NAME') ?? '',
            })
        .toList();
  }

  /// Introspects all indexes via INFORMATION_SCHEMA.STATISTICS
  Future<List<Map<String, String>>> inspectIndexes() async {
    final res = await db.execute(
      '''
      SELECT TABLE_NAME, INDEX_NAME, COLUMN_NAME, SEQ_IN_INDEX, NON_UNIQUE
      FROM INFORMATION_SCHEMA.STATISTICS
      WHERE TABLE_SCHEMA = :db
      ORDER BY TABLE_NAME, INDEX_NAME, SEQ_IN_INDEX
      ''',
      {'db': db.config.databaseName},
    );
    return res.rows
        .map((r) => {
              'table': r.colByName('TABLE_NAME') ?? '',
              'index': r.colByName('INDEX_NAME') ?? '',
              'column': r.colByName('COLUMN_NAME') ?? '',
              'seq': r.colByName('SEQ_IN_INDEX') ?? '',
              'non_unique': r.colByName('NON_UNIQUE') ?? '',
            })
        .toList();
  }
}
