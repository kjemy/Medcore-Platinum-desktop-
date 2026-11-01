import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import '../db/db_client.dart';
import '../repositories/tenant_governance_repository.dart';

/// Secure LAN Gateway for MedCore Platinum.
///
/// Implements the Gate 16 architectural requirement:
/// [Remote Workstations on LAN] -> [Secure LAN Gateway (0.0.0.0:8444)] -> [Internal Local Service (127.0.0.1:8443)] -> [MariaDB (127.0.0.1:3307)].
///
/// Invariants enforced:
/// 1. MariaDB (3307) remains strictly loopback-only and inaccessible to LAN.
/// 2. Discovery (!= Authorization): GET /api/v1/network/discovery is public metadata only.
/// 3. Device Pairing: POST /api/v1/network/pairing/request submits an untrusted PENDING device.
/// 4. Mandatory Pairing Approval: All operational endpoints (/api/v1/*) require X-Device-Id
///    which must resolve to status='APPROVED' in `mc_devices`.
/// 5. Revoked or Pending devices are blocked server-side (HTTP 403 Forbidden).
class SecureLanGateway {
  final DbClient db;
  final String internalHost;
  final int internalPort;
  final String defaultHospitalCode;

  HttpServer? _server;
  final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);

  // In-memory sliding window rate limiter: IP -> timestamps
  final Map<String, List<DateTime>> _rateLimitBuckets = {};
  final int maxRequestsPerMinute;

  SecureLanGateway({
    required this.db,
    this.internalHost = '127.0.0.1',
    this.internalPort = 8443,
    this.defaultHospitalCode = 'HOSP_MAIN',
    this.maxRequestsPerMinute = 120,
  });

  bool get isRunning => _server != null;
  int? get boundPort => _server?.port;
  String? get boundAddress => _server?.address.address;

  /// Starts the Secure LAN Gateway listener on the designated network address and port.
  Future<HttpServer> start({String address = '0.0.0.0', int port = 8444}) async {
    if (_server != null) return _server!;

    final pipeline = const Pipeline()
        .addMiddleware(_rateLimiterMiddleware())
        .addMiddleware(_securityBoundaryMiddleware())
        .addHandler(_handleGatewayRequest);

    _server = await shelf_io.serve(pipeline, address, port);
    return _server!;
  }

  /// Stops the gateway and frees the socket.
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _httpClient.close(force: true);
  }

  /// Middleware: Per-IP sliding-window rate limiting.
  Middleware _rateLimiterMiddleware() {
    return (Handler innerHandler) {
      return (Request req) async {
        final clientIp = _resolveClientIp(req);
        final now = DateTime.now();

        final bucket = _rateLimitBuckets.putIfAbsent(clientIp, () => []);
        bucket.removeWhere((ts) => now.difference(ts).inSeconds > 60);

        if (bucket.length >= maxRequestsPerMinute) {
          return Response(
            429,
            body: jsonEncode({
              'error': 'RATE_LIMIT_EXCEEDED',
              'message': 'Too many requests from $clientIp. Maximum allowed: $maxRequestsPerMinute/min.',
            }),
            headers: {'content-type': 'application/json'},
          );
        }

        bucket.add(now);
        return innerHandler(req);
      };
    };
  }

  /// Middleware: Enforces Device Pairing Approval on all non-discovery routes.
  Middleware _securityBoundaryMiddleware() {
    return (Handler innerHandler) {
      return (Request req) async {
        final path = req.url.path;

        // Discovery & status endpoints are public-safe
        if (path == 'api/v1/network/discovery' ||
            path == 'api/v1/gateway/status') {
          return innerHandler(req);
        }

        // Device pairing submission is permitted for untrusted enrollment
        if (path == 'api/v1/network/pairing/request' && req.method == 'POST') {
          return innerHandler(req);
        }

        // All clinical, financial, administrative, and inventory operations REQUIRE approved device
        final deviceId = req.headers['x-device-id']?.trim();
        if (deviceId == null || deviceId.isEmpty) {
          return Response(
            401,
            body: jsonEncode({
              'error': 'DEVICE_NOT_IDENTIFIED',
              'message': 'LAN Gateway requires X-Device-Id header on all operational requests.',
              'securityInvariant': 'Discovery != Authorization (Khaled Constitution)',
            }),
            headers: {'content-type': 'application/json'},
          );
        }

        final govRepo = TenantGovernanceRepository(db);
        final device = await govRepo.findDeviceById(deviceId);

        if (device == null) {
          return Response(
            403,
            body: jsonEncode({
              'error': 'DEVICE_UNKNOWN',
              'message': 'Device $deviceId is not registered. Request pairing first via /api/v1/network/pairing/request.',
            }),
            headers: {'content-type': 'application/json'},
          );
        }

        final isApproved = device.status.toUpperCase() == 'APPROVED' ||
            device.status.toUpperCase() == 'ACTIVE';
        if (!isApproved) {
          return Response(
            403,
            body: jsonEncode({
              'error': 'DEVICE_NOT_APPROVED',
              'deviceId': deviceId,
              'deviceStatus': device.status,
              'message': 'Device $deviceId status is ${device.status}. Explicit administrator approval is required.',
            }),
            headers: {'content-type': 'application/json'},
          );
        }

        // Device is approved: attach validated device identity header and proceed
        final updatedHeaders = Map<String, String>.from(req.headers);
        updatedHeaders['x-validated-lan-device'] = device.deviceId;
        updatedHeaders['x-device-role-scope'] = device.roleScope;

        return innerHandler(req.change(headers: updatedHeaders));
      };
    };
  }

  /// Gateway Request Handler: Forwards approved requests to internal loopback service.
  Future<Response> _handleGatewayRequest(Request req) async {
    final path = req.url.path;

    // Gateway Status report
    if (path == 'api/v1/gateway/status') {
      return Response.ok(
        jsonEncode({
          'gateway': 'MedCore Secure LAN Gateway',
          'status': 'ACTIVE',
          'boundAddress': boundAddress,
          'boundPort': boundPort,
          'targetInternalService': 'http://$internalHost:$internalPort',
          'mariadbIsolation': {
            'mariadbPort': 3307,
            'mariadbHost': '127.0.0.1',
            'lanExposure': false,
            'status': 'SECURE_LOOPBACK_ONLY',
          },
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    // Forward to internal service
    final rawPath = req.url.path;
    final normalizedPath = rawPath.startsWith('/') ? rawPath : '/$rawPath';
    final targetUri = Uri(
      scheme: 'http',
      host: internalHost,
      port: internalPort,
      path: normalizedPath,
      queryParameters: req.url.hasQuery ? req.url.queryParameters : null,
    );

    try {
      final clientReq = await _httpClient.openUrl(req.method, targetUri);

      // Copy headers, omitting hop-by-hop
      req.headers.forEach((key, val) {
        final lk = key.toLowerCase();
        if (lk != 'host' && lk != 'connection' && lk != 'content-length') {
          clientReq.headers.set(key, val);
        }
      });
      clientReq.headers.set('X-Forwarded-For', _resolveClientIp(req));
      clientReq.headers.set('X-Forwarded-Host', req.requestedUri.host);
      clientReq.headers.set('X-Gateway-Identity', 'MedCore-Secure-LAN-Gateway/1.0');

      // Forward body
      final bodyBytes = await req.read().toList();
      final flatBytes = bodyBytes.expand((e) => e).toList();
      if (flatBytes.isNotEmpty) {
        clientReq.add(flatBytes);
      }

      final clientResp = await clientReq.close();
      final respBytes = await clientResp.toList();
      final flatResp = respBytes.expand((e) => e).toList();

      final responseHeaders = <String, String>{};
      clientResp.headers.forEach((name, values) {
        final ln = name.toLowerCase();
        if (ln != 'transfer-encoding' && ln != 'connection') {
          responseHeaders[name] = values.join(', ');
        }
      });

      return Response(
        clientResp.statusCode,
        body: Stream.value(flatResp),
        headers: responseHeaders,
      );
    } catch (e) {
      return Response(
        502,
        body: jsonEncode({
          'error': 'BAD_GATEWAY',
          'message': 'Failed to reach internal MedCore service on $internalHost:$internalPort: $e',
        }),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  String _resolveClientIp(Request req) {
    final xff = req.headers['x-forwarded-for'];
    if (xff != null && xff.isNotEmpty) {
      return xff.split(',').first.trim();
    }
    final connectionInfo = req.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    return connectionInfo?.remoteAddress.address ?? '127.0.0.1';
  }
}
