import 'dart:convert';
import 'dart:io';
import 'package:medcore_local_service/medcore_local_service.dart';
import 'package:path/path.dart' as p;

String _resolveMigrationsDir() {
  final envCustom = Platform.environment['MEDCORE_MIGRATIONS_DIR']?.trim();
  if (envCustom != null && envCustom.isNotEmpty && Directory(envCustom).existsSync()) {
    return envCustom;
  }

  final cwdDirect = p.join(Directory.current.path, 'sql', 'migrations');
  if (Directory(cwdDirect).existsSync()) {
    return cwdDirect;
  }

  final cwdService = p.join(Directory.current.path, 'service', 'sql', 'migrations');
  if (Directory(cwdService).existsSync()) {
    return cwdService;
  }

  final cwdServicePkg = p.join(Directory.current.path, 'medcore_local_service', 'sql', 'migrations');
  if (Directory(cwdServicePkg).existsSync()) {
    return cwdServicePkg;
  }

  final exeDir = p.dirname(Platform.resolvedExecutable);
  final exeDirect = p.join(exeDir, 'sql', 'migrations');
  if (Directory(exeDirect).existsSync()) {
    return exeDirect;
  }

  final exeSibling = p.join(exeDir, 'service', 'sql', 'migrations');
  if (Directory(exeSibling).existsSync()) {
    return exeSibling;
  }

  return cwdDirect;
}

String _resolveSecurityDir() {
  final envCustom = Platform.environment['MEDCORE_SECURITY_DIR']?.trim();
  if (envCustom != null && envCustom.isNotEmpty) {
    return envCustom;
  }

  final exeDir = p.dirname(Platform.resolvedExecutable);
  if (Directory(p.join(exeDir, 'sql', 'migrations')).existsSync()) {
    return p.join(exeDir, 'runtime', 'security');
  }

  if (Directory(p.join(Directory.current.path, 'service', 'sql', 'migrations')).existsSync()) {
    return p.join(Directory.current.path, 'service', 'runtime', 'security');
  }

  return p.join(Directory.current.path, 'runtime', 'security');
}

String _resolveDbPassword(String securityDir) {
  final envPass = Platform.environment['MEDCORE_DB_PASSWORD']?.trim();
  if (envPass != null && envPass.isNotEmpty) return envPass;

  final credFile = File(p.join(securityDir, 'db_credentials.json'));
  if (credFile.existsSync()) {
    try {
      final json = jsonDecode(credFile.readAsStringSync()) as Map<String, dynamic>;
      final pass = json['password']?.toString().trim();
      if (pass != null && pass.isNotEmpty) return pass;
    } catch (_) {}
  }

  throw StateError(
    'CRITICAL: Dynamic database credential not configured in environment '
    '(MEDCORE_DB_PASSWORD) or in security file (${credFile.path}). '
    'Zero static fallback allowed under Khaled Constitution.',
  );
}

Future<void> main(List<String> args) async {
  final port = int.tryParse(Platform.environment['MEDCORE_PORT'] ?? '8443') ?? 8443;
  final dbHost = Platform.environment['MEDCORE_DB_HOST'] ?? '127.0.0.1';
  final dbPort = int.tryParse(Platform.environment['MEDCORE_DB_PORT'] ?? '3307') ?? 3307;
  final dbName = Platform.environment['MEDCORE_DB_NAME'] ?? 'medcore_local';
  final dbUser = Platform.environment['MEDCORE_DB_USER']?.trim().isNotEmpty == true
      ? Platform.environment['MEDCORE_DB_USER']!.trim()
      : 'root';
  final securityDir = _resolveSecurityDir();
  final dbPassword = _resolveDbPassword(securityDir);

  final config = DbConfig(
    host: dbHost,
    port: dbPort,
    user: dbUser,
    password: dbPassword,
    databaseName: dbName,
  );

  final db = DbClient(config);
  final migrationsDir = _resolveMigrationsDir();
  final runner = MigrationRunner(db: db, migrationsDir: migrationsDir);

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

  stdout.writeln('[MedCore Local Service] Applying migrations from $migrationsDir to $dbName...');
  final applied = await runner.runMigrations();
  stdout.writeln('[MedCore Local Service] Applied/Verified ${applied.length} migrations.');

  // Ensure baseline tenant is provisioned if fresh installation
  final tenantResult = await db.execute('SELECT COUNT(*) as cnt FROM mc_tenants');
  final rawCnt = tenantResult.rows.isNotEmpty ? tenantResult.rows.first.assoc()['cnt'] : null;
  final tenantCnt = (rawCnt is num) ? (rawCnt as num).toInt() : (int.tryParse(rawCnt?.toString() ?? '') ?? 0);
  if (tenantCnt == 0) {
    stdout.writeln('[MedCore Local Service] Seeding baseline tenant and device configuration for HOSP_MAIN...');
    await server.databaseLifecycleService.seedBaselineSystemDataForTesting('HOSP_MAIN');
  }

  final boundPort = await server.start(address: '127.0.0.1', port: port);
  stdout.writeln('[MedCore Local Service] Listening on http://127.0.0.1:$boundPort/api/v1/health');
}


