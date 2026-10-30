import 'dart:convert';
import 'dart:io';

import 'package:medcore_local_service/medcore_local_service.dart';
import 'package:path/path.dart' as p;

DbConfig testDbConfig({required String databaseName, int maxConnections = 10}) {
  final user = _requiredTestEnvironment('MEDCORE_TEST_DB_USER');
  final password = _requiredTestEnvironment('MEDCORE_TEST_DB_PASSWORD');
  final port = int.tryParse(Platform.environment['MEDCORE_TEST_DB_PORT'] ?? _optionalTestCredentials('port') ?? '3307');
  if (port == null || port < 1 || port > 65535) {
    throw StateError('MEDCORE_TEST_DB_PORT must be a valid TCP port.');
  }

  return DbConfig(
    host: Platform.environment['MEDCORE_TEST_DB_HOST'] ?? '127.0.0.1',
    port: port,
    user: user,
    password: password,
    databaseName: databaseName,
    maxConnections: maxConnections,
  );
}

String? _optionalTestCredentials(String key) {
  final candidates = [
    File(p.join(Directory.current.path, 'runtime', 'security', 'db_credentials.json')),
    File(p.join(Directory.current.path, '..', 'runtime', 'security', 'db_credentials.json')),
    File(p.join(Directory.current.path, 'medcore_local_service', 'runtime', 'security', 'db_credentials.json')),
  ];
  for (final f in candidates) {
    if (f.existsSync()) {
      try {
        final data = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        if (data[key] != null) return data[key].toString();
      } catch (_) {}
    }
  }
  return null;
}

String _requiredTestEnvironment(String name) {
  final value = Platform.environment[name]?.trim();
  if (value != null && value.isNotEmpty) {
    return value;
  }
  if (name == 'MEDCORE_TEST_DB_USER') {
    final u = _optionalTestCredentials('user');
    if (u != null && u.isNotEmpty) return u;
  }
  if (name == 'MEDCORE_TEST_DB_PASSWORD') {
    final pw = _optionalTestCredentials('password');
    if (pw != null && pw.isNotEmpty) return pw;
  }
  throw StateError('Required test database environment variable $name is not configured.');
}
