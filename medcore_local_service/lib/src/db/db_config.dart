class DbConfig {
  final String host;
  final int port;
  final String user;
  final String password;
  final String databaseName;
  final int maxConnections;

  const DbConfig({
    this.host = '127.0.0.1',
    this.port = 3307,
    required this.user,
    required this.password,
    this.databaseName = 'medcore_local',
    this.maxConnections = 10,
  });

  DbConfig copyWith({
    String? host,
    int? port,
    String? user,
    String? password,
    String? databaseName,
    int? maxConnections,
  }) {
    return DbConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      user: user ?? this.user,
      password: password ?? this.password,
      databaseName: databaseName ?? this.databaseName,
      maxConnections: maxConnections ?? this.maxConnections,
    );
  }
}
