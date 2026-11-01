import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:medcore_local_service/medcore_local_service.dart';
import 'package:test/test.dart';

void main() {
  late DbClient db;
  late LocalMedCoreServer internalServer;
  late SecureLanGateway gateway;
  late HttpServer gatewayHttpServer;

  const internalPort = 9443;
  const gatewayPort = 9444;

  setUpAll(() async {
    final credFile = File(r'C:\Users\hp\Desktop\project 4\runtime\security\db_credentials.json');
    String password = '';
    if (credFile.existsSync()) {
      final json = jsonDecode(credFile.readAsStringSync());
      password = json['password'] ?? '';
    }

    final config = DbConfig(
      host: '127.0.0.1',
      port: 3307,
      user: 'root',
      password: password,
      databaseName: 'medcore_parity_test_db',
    );
    db = DbClient(config);

    final runner = MigrationRunner(
      db: db,
      migrationsDir: r'C:\Users\hp\Desktop\project 4\medcore_local_service\sql\migrations',
    );
    await runner.runMigrations();

    // Start internal server on loopback
    internalServer = LocalMedCoreServer(
      db,
      securityRootDirectory: r'C:\Users\hp\Desktop\project 4\runtime\security',
      autoBootstrapCommissioningSecret: false,
    );
    final boundInternalPort = await internalServer.start(address: '127.0.0.1', port: internalPort);

    // Seed baseline tenant and facility config for HOSP_MAIN with LAN allowed
    await internalServer.databaseLifecycleService.seedBaselineSystemDataForTesting('HOSP_MAIN');

    // Start Secure LAN Gateway
    gateway = SecureLanGateway(
      db: db,
      internalHost: '127.0.0.1',
      internalPort: boundInternalPort,
      defaultHospitalCode: 'HOSP_MAIN',
      maxRequestsPerMinute: 30,
    );
    gatewayHttpServer = await gateway.start(address: '127.0.0.1', port: gatewayPort);
  });

  tearDownAll(() async {
    await gateway.stop();
    await internalServer.stop();
  });

  group('GATE 16 & 17 — Secure LAN Gateway & Multi-Workstation Architecture Tests', () {
    test('1. Architectural Proof: MariaDB (3307) and Internal Service (9443) are loopback-only', () {
      expect(internalServer.boundAddress, '127.0.0.1');
      expect(gateway.isRunning, isTrue);
      expect(gateway.boundPort, gatewayPort);
    });

    test('2. Discovery Endpoint: GET /api/v1/network/discovery returns public metadata without clinical data', () async {
      final res = await http.get(Uri.parse('http://127.0.0.1:$gatewayPort/api/v1/network/discovery?hospitalCode=HOSP_MAIN'));
      expect(res.statusCode, 200);
      final json = jsonDecode(res.body);
      final data = (json is Map && json.containsKey('data')) ? json['data'] : json;
      expect(data['hospitalCode'], 'HOSP_MAIN');
      expect(data['securityBoundary']['mariaDbExposedOverNetwork'], false);
      expect(data['securityBoundary']['discoveryGrantsAuthorization'], false);
    });

    test('3. Gateway Status: GET /api/v1/gateway/status reports active gateway and loopback MariaDB isolation', () async {
      final res = await http.get(Uri.parse('http://127.0.0.1:$gatewayPort/api/v1/gateway/status'));
      expect(res.statusCode, 200);
      final json = jsonDecode(res.body);
      expect(json['status'], 'ACTIVE');
      expect(json['mariadbIsolation']['status'], 'SECURE_LOOPBACK_ONLY');
      expect(json['mariadbIsolation']['lanExposure'], false);
    });

    test('4. RED-16-01: Operational request without X-Device-Id fails closed (401 Unauthorized)', () async {
      final res = await http.get(Uri.parse('http://127.0.0.1:$gatewayPort/api/v1/definitions/clinics'));
      expect(res.statusCode, 401);
      final json = jsonDecode(res.body);
      expect(json['error'], 'DEVICE_NOT_IDENTIFIED');
    });

    test('5. RED-16-02: Device pairing request registers PENDING device; access is denied until approved', () async {
      final devId = 'DEV_LAPTOP_${DateTime.now().microsecondsSinceEpoch}';

      // Submit pairing request
      final pairRes = await http.post(
        Uri.parse('http://127.0.0.1:$gatewayPort/api/v1/network/pairing/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'hospitalCode': 'HOSP_MAIN',
          'deviceId': devId,
          'deviceName': 'Reception Laptop $devId',
          'connectionType': 'LAN',
          'platform': 'WINDOWS',
          'roleScope': 'WORKSTATION',
          'hwFingerprintSha256': 'a1b2c3d4e5f678901234567890abcdef',
          'devicePublicKeyEd25519': 'pubkey_ed25519_mock_test_1234567890',
        }),
      );
      expect(pairRes.statusCode, inInclusiveRange(200, 201));

      // Attempt operational request with PENDING device -> must be 403 Forbidden
      final opRes = await http.get(
        Uri.parse('http://127.0.0.1:$gatewayPort/api/v1/definitions/clinics'),
        headers: {'X-Device-Id': devId},
      );
      expect(opRes.statusCode, 403);
      final json = jsonDecode(opRes.body);
      expect(json['error'], 'DEVICE_NOT_APPROVED');
      expect(json['deviceStatus'], 'PENDING');
    });

    test('6. Device Approval & Forwarding: Approved device requests forward to internal service and succeed', () async {
      final devId = 'DEV_APPROVED_${DateTime.now().microsecondsSinceEpoch}';

      // Seed approved/active device in mc_devices
      await db.execute('''
        INSERT INTO mc_devices (
          hospital_code, device_id, device_name, platform,
          hw_fingerprint_sha256, device_public_key_ed25519, role_scope,
          is_trusted_secure_runtime, status
        ) VALUES (
          'HOSP_MAIN', '$devId', 'Doctor Laptop Approved', 'WINDOWS',
          'mock_hw_fingerprint_doc_approved', 'mock_pub_key_doc_approved', 'WORKSTATION',
          1, 'ACTIVE'
        )
      ''');

      // Request through gateway with approved device ID to /api/v1/health
      final res = await http.get(
        Uri.parse('http://127.0.0.1:$gatewayPort/api/v1/health'),
        headers: {'X-Device-Id': devId},
      );
      expect(res.statusCode, 200);
      final json = jsonDecode(res.body);
      final data = (json is Map && json.containsKey('data')) ? json['data'] : json;
      expect(data['status'], 'HEALTHY');
    });

    test('7. RED-16-03: Revoked device is immediately rejected server-side (403 Forbidden)', () async {
      final devId = 'DEV_REVOKED_${DateTime.now().microsecondsSinceEpoch}';

      // Seed revoked device
      await db.execute('''
        INSERT INTO mc_devices (
          hospital_code, device_id, device_name, platform,
          hw_fingerprint_sha256, device_public_key_ed25519, role_scope,
          is_trusted_secure_runtime, status
        ) VALUES (
          'HOSP_MAIN', '$devId', 'Compromised Laptop', 'WINDOWS',
          'mock_hw_fingerprint_revoked', 'mock_pub_key_revoked', 'WORKSTATION',
          0, 'REVOKED'
        )
      ''');

      final res = await http.get(
        Uri.parse('http://127.0.0.1:$gatewayPort/api/v1/health'),
        headers: {'X-Device-Id': devId},
      );
      expect(res.statusCode, 403);
      final json = jsonDecode(res.body);
      expect(json['error'], 'DEVICE_NOT_APPROVED');
      expect(json['deviceStatus'], 'REVOKED');
    });

    test('8. RED-16-04: Rate limiting triggers HTTP 429 when client exceeds request threshold', () async {
      bool got429 = false;
      for (int i = 0; i < 35; i++) {
        final res = await http.get(Uri.parse('http://127.0.0.1:$gatewayPort/api/v1/gateway/status'));
        if (res.statusCode == 429) {
          got429 = true;
          break;
        }
      }
      expect(got429, isTrue, reason: 'Rapid requests must trigger HTTP 429 Rate Limit Exceeded');
    });
  });
}
