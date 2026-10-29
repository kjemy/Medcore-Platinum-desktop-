import 'dart:io';
import 'package:medcore_local_service/medcore_local_service.dart';
import 'package:path/path.dart' as p;

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

Future<void> main(List<String> args) async {
  final command = args.isNotEmpty ? args[0].toLowerCase().trim() : 'help';
  final dbHost = Platform.environment['MEDCORE_DB_HOST'] ?? '127.0.0.1';
  final dbPort = int.tryParse(Platform.environment['MEDCORE_DB_PORT'] ?? '3307') ?? 3307;
  final dbName = Platform.environment['MEDCORE_DB_NAME'] ?? 'medcore_local';
  final dbUser = Platform.environment['MEDCORE_DB_USER'] ?? 'root';
  final dbPassword = Platform.environment['MEDCORE_DB_PASSWORD'] ?? 'MedCoreLocalDb#2026';
  final securityDir = _resolveSecurityDir();

  final config = DbConfig(
    host: dbHost,
    port: dbPort,
    user: dbUser,
    password: dbPassword,
    databaseName: dbName,
  );
  final db = DbClient(config);
  final facilityConfigService = FacilityConfigService(db);
  final techService = TechnicianService(
    db,
    facilityConfigService: facilityConfigService,
    securityRootDirectory: securityDir,
  );

  stdout.writeln('================================================================================');
  stdout.writeln('MEDCORE PLATINUM DESKTOP — FIELD TECHNICIAN COMMISSIONING UTILITY');
  stdout.writeln('================================================================================');

  try {
    switch (command) {
      case 'status':
        await _printStatus(db, techService, securityDir);
        break;

      case 'generate':
        final res = techService.ensureCommissioningSecretProvisioned(forceRotate: true);
        stdout.writeln('SUCCESS: New Technician Commissioning Secret generated.');
        stdout.writeln('--------------------------------------------------------------------------------');
        stdout.writeln('Commissioning Secret : ${res['secret']}');
        stdout.writeln('Secret Hash Storage  : ${res['secretFile']}');
        if (res['slipFile'] != null) {
          stdout.writeln('One-Time Slip File   : ${res['slipFile']}');
        }
        stdout.writeln('--------------------------------------------------------------------------------');
        stdout.writeln('Use this key in MedCore Desktop -> Technician / Service Installation Gate.');
        break;

      case 'set':
        if (args.length < 2 || args[1].trim().length < 12) {
          stderr.writeln('ERROR: You must provide a custom secret with minimum 12 characters.');
          stderr.writeln('Usage: dart run bin/commission.dart set <YourSecret#2026>');
          exitCode = 1;
          return;
        }
        final customSecret = args[1].trim();
        final res = techService.ensureCommissioningSecretProvisioned(
          explicitSecret: customSecret,
          forceRotate: true,
        );
        stdout.writeln('SUCCESS: Custom Technician Installation Secret provisioned.');
        stdout.writeln('Secret Hash Storage : ${res['secretFile']} (PBKDF2 hash stored, zero plaintext)');
        break;

      default:
        stdout.writeln('Available Commands:');
        stdout.writeln('  status               Inspect database and technician provisioning state');
        stdout.writeln('  generate             Generate a new high-entropy commissioning key');
        stdout.writeln('  set <secret>         Provision a custom installation technician secret');
        stdout.writeln('');
        stdout.writeln('Examples:');
        stdout.writeln('  dart run bin/commission.dart status');
        stdout.writeln('  dart run bin/commission.dart generate');
        stdout.writeln('  dart run bin/commission.dart set "CertifiedTech#2026"');
        break;
    }
  } catch (e, st) {
    stderr.writeln('COMMISSIONING ERROR: $e');
    stderr.writeln(st);
    exitCode = 1;
  } finally {
    await db.close();
  }
}

Future<void> _printStatus(DbClient db, TechnicianService techService, String securityDir) async {
  stdout.writeln('Inspecting Local MedCore Environment:');
  stdout.writeln('  Security Directory  : $securityDir');

  final secretFile = File(p.join(securityDir, 'technician_secret.json'));
  final slipFile = File(p.join(securityDir, 'FIRST_RUN_COMMISSIONING_SECRET.txt'));

  stdout.writeln('  Secret Hash File    : ${secretFile.existsSync() ? "PROVISIONED (${secretFile.path})" : "NOT FOUND"}');
  stdout.writeln('  One-Time Slip File  : ${slipFile.existsSync() ? "ACTIVE (${slipFile.path})" : "NONE (Already consumed or custom)"}');

  try {
    final conn = await db.openDedicatedConnection(useDatabase: true);
    try {
      final staffRes = await conn.execute(
        "SELECT id, staff_code, full_name, email, role, force_password_change, is_active FROM mc_staff WHERE role = 'HospitalAdmin' ORDER BY id ASC",
      );
      stdout.writeln('  Database Connection : ONLINE (port ${db.config.port}, db ${db.config.databaseName})');
      if (staffRes.rows.isEmpty) {
        stdout.writeln('  Hospital Admin      : NOT PROVISIONED (0 admins found in mc_staff)');
        stdout.writeln('  Action Required     : Authenticate in Technician Console (Tab 8) to provision first Admin.');
      } else {
        stdout.writeln('  Hospital Admin      : PROVISIONED (${staffRes.rows.length} active admin account(s))');
        for (final row in staffRes.rows) {
          stdout.writeln('    - ${row.colByName('full_name')} | Code: ${row.colByName('staff_code')} | Email: ${row.colByName('email')} | ForcePasswordChange: ${row.colByName('force_password_change')}');
        }
      }
    } finally {
      await conn.close();
    }
  } catch (e) {
    stdout.writeln('  Database Connection : OFFLINE / UNREACHABLE ($e)');
  }
}
