import 'dart:io';
import 'package:medcore_local_service/medcore_local_service.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final port = int.tryParse(Platform.environment['MEDCORE_PORT'] ?? '8443') ?? 8443;
  final dbHost = Platform.environment['MEDCORE_DB_HOST'] ?? '127.0.0.1';
  final dbPort = int.tryParse(Platform.environment['MEDCORE_DB_PORT'] ?? '3307') ?? 3307;
  final dbName = Platform.environment['MEDCORE_DB_NAME'] ?? 'medcore_local';
  final dbUser = _requiredEnvironment('MEDCORE_DB_USER');
  final dbPassword = _requiredEnvironment('MEDCORE_DB_PASSWORD');

  final config = DbConfig(
    host: dbHost,
    port: dbPort,
    user: dbUser,
    password: dbPassword,
    databaseName: dbName,
  );

  final db = DbClient(config);
  final migrationsDir = p.join(Directory.current.path, 'sql', 'migrations');
  final runner = MigrationRunner(db: db, migrationsDir: migrationsDir);

  stdout.writeln('[MedCore Local Service] Applying migrations from $migrationsDir to $dbName...');
  final applied = await runner.runMigrations();
  stdout.writeln('[MedCore Local Service] Applied/Verified ${applied.length} migrations.');

  final securityDir = Platform.environment['MEDCORE_SECURITY_DIR'] ?? p.join(Directory.current.path, 'runtime', 'security');
  final server = LocalMedCoreServer(
    db,
    securityRootDirectory: securityDir,
    autoBootstrapCommissioningSecret: true,
  );
  final bootstrap = server.technicianService.ensureCommissioningSecretProvisioned();
  if (bootstrap['isNewlyGenerated'] == true) {
    stdout.writeln('================================================================================');
    stdout.writeln('[MedCore Local Service] FRESH INSTALLATION DETECTED');
    stdout.writeln('[MedCore Local Service] One-time technician commissioning secret generated.');
    stdout.writeln('[MedCore Local Service] Secret written to: ${bootstrap['slipFile']}');
    stdout.writeln('================================================================================');
  }

  final boundPort = await server.start(address: '127.0.0.1', port: port);
  stdout.writeln('[MedCore Local Service] Listening on http://127.0.0.1:$boundPort/api/v1/health');
}

String _requiredEnvironment(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError('Required environment variable $name is not configured.');
  }
  return value;
}
