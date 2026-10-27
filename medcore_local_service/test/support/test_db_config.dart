import 'dart:io';

import 'package:medcore_local_service/medcore_local_service.dart';

DbConfig testDbConfig({required String databaseName, int maxConnections = 10}) {
  final user = _requiredTestEnvironment('MEDCORE_TEST_DB_USER');
  final password = _requiredTestEnvironment('MEDCORE_TEST_DB_PASSWORD');
  final port = int.tryParse(Platform.environment['MEDCORE_TEST_DB_PORT'] ?? '3307');
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

String _requiredTestEnvironment(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError('Required test database environment variable $name is not configured.');
  }
  return value;
}
