import 'dart:convert';
import 'package:http/http.dart' as http;

class MedCoreApiException implements Exception {
  final int statusCode;
  final String code;
  final String message;

  const MedCoreApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isModuleNotEntitled => code == 'MODULE_NOT_ENTITLED';
  bool get isClockRollback => code == 'CLOCK_ROLLBACK_DETECTED' || code == 'CLOCK_TAMPER_DETECTED';
  bool get isDeviceUnverified => code == 'DEVICE_NOT_VERIFIED';

  @override
  String toString() => '[$statusCode $code] $message';
}

/// Strictly HTTP-only client to Local MedCore Service.
/// Hard Invariant: Flutter Desktop NEVER connects directly to MariaDB.
class MedCoreApiClient {
  String baseUrl;
  String hospitalCode;
  String deviceId;
  String? _staffBearerToken;
  String? _technicianToken;
  final http.Client _http;

  MedCoreApiClient({
    this.baseUrl = 'http://127.0.0.1:8443',
    this.hospitalCode = 'HOSP_MAIN',
    this.deviceId = 'DEV-MAIN-HOST',
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  void configureConnection({
    required String baseUrl,
    required String hospitalCode,
    required String deviceId,
  }) {
    final trimmed = baseUrl.trim();
    this.baseUrl = trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
    this.hospitalCode = hospitalCode.trim();
    this.deviceId = deviceId.trim();
  }

  void setStaffBearerToken(String? token) {
    _staffBearerToken = (token != null && token.trim().isNotEmpty) ? token.trim() : null;
  }

  void setTechnicianToken(String? token) {
    _technicianToken = (token != null && token.trim().isNotEmpty) ? token.trim() : null;
  }

  bool get hasStaffToken => _staffBearerToken != null;
  bool get hasTechnicianToken => _technicianToken != null;

  Uri _buildUri(String path, [Map<String, String>? query]) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$baseUrl$normalizedPath');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: {...uri.queryParameters, ...query});
  }

  Map<String, String> _buildHeaders({
    bool useTechnicianAuth = false,
    bool includeAuth = true,
  }) {
    final headers = <String, String>{
      'content-type': 'application/json; charset=utf-8',
      'accept': 'application/json',
      if (hospitalCode.isNotEmpty) 'x-tenant-id': hospitalCode,
      if (deviceId.isNotEmpty) 'x-medcore-device-id': deviceId,
    };
    if (includeAuth) {
      if (useTechnicianAuth && _technicianToken != null) {
        headers['x-medcore-tech-token'] = _technicianToken!;
      } else if (!useTechnicianAuth && _staffBearerToken != null) {
        headers['authorization'] = 'Bearer $_staffBearerToken';
      }
    }
    return headers;
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
    bool useTechnicianAuth = false,
    bool includeAuth = true,
  }) async {
    try {
      final resp = await _http.get(
        _buildUri(path, query),
        headers: _buildHeaders(useTechnicianAuth: useTechnicianAuth, includeAuth: includeAuth),
      );
      return _decodeEnvelope(resp);
    } on MedCoreApiException {
      rethrow;
    } catch (e) {
      throw MedCoreApiException(
        statusCode: 0,
        code: 'SERVICE_UNREACHABLE',
        message: 'Cannot reach Local MedCore Service at $baseUrl: $e',
      );
    }
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    bool useTechnicianAuth = false,
    bool includeAuth = true,
  }) async {
    try {
      final resp = await _http.post(
        _buildUri(path),
        headers: _buildHeaders(useTechnicianAuth: useTechnicianAuth, includeAuth: includeAuth),
        body: jsonEncode(body),
      );
      return _decodeEnvelope(resp);
    } on MedCoreApiException {
      rethrow;
    } catch (e) {
      throw MedCoreApiException(
        statusCode: 0,
        code: 'SERVICE_UNREACHABLE',
        message: 'Cannot reach Local MedCore Service at $baseUrl: $e',
      );
    }
  }

  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> body, {
    bool useTechnicianAuth = false,
  }) async {
    try {
      final resp = await _http.put(
        _buildUri(path),
        headers: _buildHeaders(useTechnicianAuth: useTechnicianAuth, includeAuth: true),
        body: jsonEncode(body),
      );
      return _decodeEnvelope(resp);
    } on MedCoreApiException {
      rethrow;
    } catch (e) {
      throw MedCoreApiException(
        statusCode: 0,
        code: 'SERVICE_UNREACHABLE',
        message: 'Cannot reach Local MedCore Service at $baseUrl: $e',
      );
    }
  }

  Map<String, dynamic> _decodeEnvelope(http.Response resp) {
    Map<String, dynamic> decoded;
    try {
      final raw = jsonDecode(resp.body);
      decoded = raw is Map<String, dynamic> ? raw : Map<String, dynamic>.from(raw as Map);
    } catch (_) {
      throw MedCoreApiException(
        statusCode: resp.statusCode,
        code: 'NON_JSON_RESPONSE',
        message: 'Unexpected response (HTTP ${resp.statusCode}) from Local MedCore Service.',
      );
    }

    if (resp.statusCode >= 200 && resp.statusCode < 300 && decoded['ok'] == true) {
      final data = decoded['data'];
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return {'value': data};
    }

    final err = decoded['error'];
    if (err is Map) {
      throw MedCoreApiException(
        statusCode: resp.statusCode,
        code: (err['code'] ?? 'API_ERROR').toString(),
        message: (err['message'] ?? 'Request rejected by Local MedCore Service.').toString(),
      );
    }

    throw MedCoreApiException(
      statusCode: resp.statusCode,
      code: 'HTTP_${resp.statusCode}',
      message: 'Local MedCore Service returned HTTP ${resp.statusCode}.',
    );
  }
}
