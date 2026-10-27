import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'trusted_time_evidence.dart';

class MaintenanceTokenException implements Exception {
  final String code;
  final String message;
  MaintenanceTokenException(this.code, this.message);
  @override
  String toString() => 'MaintenanceTokenException($code): $message';
}

class MaintenanceUnlockToken {
  final String version;
  final String hospitalCode;
  final String installationId;
  final String action;
  final String nonce;
  final String tokenId;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final String rawToken;

  const MaintenanceUnlockToken({
    required this.version,
    required this.hospitalCode,
    required this.installationId,
    required this.action,
    required this.nonce,
    required this.tokenId,
    required this.issuedAt,
    required this.expiresAt,
    required this.rawToken,
  });
}

/// Asymmetric RSA-2048 PKCS#1 v1.5 Verification Service for Maintenance Tokens.
/// The MedCore Installation holds ONLY the public key (n, e).
/// The private key (d) is held exclusively by the Maintenance Authority / Control Plane.
class MaintenanceTokenService {
  final BigInt modulus;
  final BigInt publicExponent;

  // Canonical Authority Public Key (RSA-2048, e=65537)
  static const String defaultModulusB64 =
      'wNwJHEVkppX9s2OjwXejCIBgVOO+46HHGVh32EZpASzKoQgcefVBoenHv2wHckGItITcB0NdE92uXuC46j6GjyGJP6JO9PrzwvOy+3VabOaiLJghWN88zFOgJniwgi0ALvBjShdCX5COy9Eu5FJt3NY8Ycy9hIHWlmpBZFJRfVpmFy6T8ihH4XJwOt0oAa+B0sqoIiCGGUP7EO0V/fHYj+Z/V57x44ARMB2BUAH7850B4c1ljsKdDyUAAa/BQFWywrnuQezofHcaeX5+v/hGPIISORpJfGx0ftRoMSXJvlmQ/6EQA0gjnQYgOL2WtwdLkYdRtkK1XDwg+EYdKdGH1Q==';
  static const String defaultExponentB64 = 'AQAB';

  MaintenanceTokenService({
    BigInt? modulus,
    BigInt? publicExponent,
  })  : modulus = modulus ?? _decodeBase64BigInt(defaultModulusB64),
        publicExponent = publicExponent ?? _decodeBase64BigInt(defaultExponentB64);

  factory MaintenanceTokenService.fromPublicKeyFile(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      return MaintenanceTokenService();
    }
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return MaintenanceTokenService(
      modulus: _decodeBase64BigInt(json['n'] as String),
      publicExponent: _decodeBase64BigInt(json['e'] as String),
    );
  }

  /// Verifies cryptographic RSA signature, format, expiration, tenant, installation, and action.
  /// Enforces:
  /// - Mandatory installation binding (expectedInstallationId must be non-empty and match token claim)
  /// - Trusted monotonic effective time expiration (exp <= effectiveTime is strictly EXPIRED)
  /// - Fail-closed downtime restart verification (rejects unverified local wall clocks across restarts)
  MaintenanceUnlockToken verifyAndParseToken({
    required String rawToken,
    required String expectedHospitalCode,
    required String expectedInstallationId,
    TrustedTimeEvidence? trustedTimeEvidence,
    TrustedTimeVerifier? trustedTimeVerifier,
    @Deprecated('Ignored; this value is not trusted time.') DateTime? effectiveTime,
  }) {
    final clean = rawToken.trim();
    if (!clean.startsWith('MC_MAINT_V1.')) {
      throw MaintenanceTokenException(
        'INVALID_FORMAT',
        'Maintenance token must have valid MC_MAINT_V1 prefix and format.',
      );
    }

    final parts = clean.split('.');
    if (parts.length != 3) {
      throw MaintenanceTokenException('MALFORMED_TOKEN', 'Token parts structure is invalid.');
    }

    final payloadB64 = parts[1];
    final signatureB64 = parts[2];

    Map<String, dynamic> payload;
    String canonicalJson;
    try {
      final normalizedB64 = base64Url.normalize(payloadB64);
      final decodedBytes = base64Url.decode(normalizedB64);
      canonicalJson = utf8.decode(decodedBytes);
      payload = jsonDecode(canonicalJson) as Map<String, dynamic>;
    } catch (_) {
      throw MaintenanceTokenException('CORRUPT_PAYLOAD', 'Unable to decode token payload.');
    }

    // 1. Verify Asymmetric RSA-2048 PKCS#1 v1.5 Signature
    List<int> signatureBytes;
    try {
      final normalizedSig = base64Url.normalize(signatureB64);
      signatureBytes = base64Url.decode(normalizedSig);
    } catch (_) {
      throw MaintenanceTokenException('INVALID_SIGNATURE_ENCODING', 'Signature encoding is invalid.');
    }

    final messageBytes = utf8.encode(canonicalJson);
    final isValidSignature = _verifyRsaSha256(
      messageBytes: messageBytes,
      signatureBytes: signatureBytes,
      modulus: modulus,
      publicExponent: publicExponent,
    );

    if (!isValidSignature) {
      throw MaintenanceTokenException(
        'INVALID_SIGNATURE',
        'Cryptographic RSA signature verification failed. Token is forged or corrupted.',
      );
    }


    // 2. Verify Action
    final action = payload['act']?.toString().trim() ?? '';
    if (action != 'UNLOCK_CLOCK_ROLLBACK') {
      throw MaintenanceTokenException(
        'INVALID_ACTION',
        'Token action "$action" is unauthorized for clock recovery (expected UNLOCK_CLOCK_ROLLBACK).',
      );
    }

    // 3. Verify Hospital Tenant Binding
    final hosp = payload['hosp']?.toString().trim() ?? '';
    if (hosp != expectedHospitalCode) {
      throw MaintenanceTokenException(
        'TENANT_MISMATCH',
        'Token was issued for hospital tenant "$hosp", cannot be used for "$expectedHospitalCode".',
      );
    }

    // 4. Verify Mandatory Installation Binding (Phase 5)
    final cleanExpectedInst = expectedInstallationId.trim();
    if (cleanExpectedInst.isEmpty) {
      throw MaintenanceTokenException(
        'MISSING_EXPECTED_INSTALLATION',
        'Local installation identifier is not configured or empty.',
      );
    }

    final inst = payload['inst']?.toString().trim() ?? '';
    if (inst.isEmpty) {
      throw MaintenanceTokenException(
        'EMPTY_INSTALLATION_CLAIM',
        'Maintenance token is missing mandatory installation binding claim (inst).',
      );
    }

    if (inst != cleanExpectedInst) {
      throw MaintenanceTokenException(
        'INSTALLATION_MISMATCH',
        'Token was issued for installation "$inst", rejected on "$cleanExpectedInst".',
      );
    }

    // 5. Verify expiration against cryptographically verified authority time.
    // Rule: exp <= now is EXPIRED (strict fail-closed, exp == now must fail)
    if (payload['v'] != 1) {
      throw MaintenanceTokenException('INVALID_VERSION', 'Token payload version must be integer 1.');
    }
    final expUtc = _strictUtcClaim(payload['exp'], 'exp');
    final iatUtc = _strictUtcClaim(payload['iat'], 'iat');
    final tokenId = payload['tid'] is String ? (payload['tid'] as String).trim() : '';
    if (tokenId.isEmpty || tokenId.length > 128) {
      throw MaintenanceTokenException('INVALID_TOKEN_ID', 'Token id is missing or invalid.');
    }
    if (trustedTimeEvidence == null || trustedTimeVerifier == null) {
      throw MaintenanceTokenException('UNTRUSTED_DOWNTIME_CLOCK', 'Verified trusted-time evidence is required for maintenance recovery.');
    }
    final effectiveUtc = trustedTimeVerifier.currentTrustedTime(
      evidence: trustedTimeEvidence,
      hospitalCode: expectedHospitalCode,
      installationId: expectedInstallationId,
    ).toUtc();

    if (effectiveUtc.isAfter(expUtc) || effectiveUtc.isAtSameMomentAs(expUtc)) {
      throw MaintenanceTokenException(
        'TOKEN_EXPIRED',
        'Maintenance token expired at ${expUtc.toIso8601String()} (effective security time: ${effectiveUtc.toIso8601String()}).',
      );
    }

    if (!expUtc.isAfter(iatUtc) || expUtc.difference(iatUtc) > const Duration(hours: 24)) {
      throw MaintenanceTokenException('INVALID_TOKEN_VALIDITY', 'Token validity interval is invalid.');
    }

    if (iatUtc.isAfter(effectiveUtc.add(const Duration(seconds: 5)))) {
      throw MaintenanceTokenException(
        'FUTURE_TOKEN',
        'Token claims to be issued in the future: ${iatUtc.toIso8601String()}.',
      );
    }

    final nonce = payload['nonce']?.toString().trim() ?? '';
    if (nonce.isEmpty) {
      throw MaintenanceTokenException('MISSING_NONCE', 'Token nonce is missing.');
    }

    return MaintenanceUnlockToken(
      version: '1',
      hospitalCode: hosp,
      installationId: inst,
      action: action,
      nonce: nonce,
      tokenId: tokenId,
      issuedAt: iatUtc,
      expiresAt: expUtc,
      rawToken: clean,
    );
  }

  // --- RSA PKCS#1 v1.5 Engine (Pure Dart, Zero Native Dependencies) ---

  static const List<int> _sha256DigestInfoPrefix = [
    0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20
  ];

  static bool _verifyRsaSha256({
    required List<int> messageBytes,
    required List<int> signatureBytes,
    required BigInt modulus,
    required BigInt publicExponent,
  }) {
    final k = (modulus.bitLength + 7) ~/ 8;
    if (signatureBytes.length != k) return false;
    final s = _bytesToBigInt(signatureBytes);
    if (s >= modulus) return false;

    final m = s.modPow(publicExponent, modulus);
    final emActual = _bigIntToBytes(m, k);
    final emExpected = encodePkcs1Sha256(messageBytes, k);

    var diff = 0;
    for (var i = 0; i < k; i++) {
      diff |= emActual[i] ^ emExpected[i];
    }
    return diff == 0;
  }

  static bool verifyRsaSha256Signature({
    required List<int> messageBytes,
    required List<int> signatureBytes,
    required BigInt modulus,
    required BigInt publicExponent,
  }) => _verifyRsaSha256(
        messageBytes: messageBytes,
        signatureBytes: signatureBytes,
        modulus: modulus,
        publicExponent: publicExponent,
      );

  static DateTime _strictUtcClaim(dynamic value, String claim) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$').hasMatch(value)) {
      throw MaintenanceTokenException('INVALID_$claim'.toUpperCase(), 'Token claim $claim must be strict UTC ISO-8601.');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw MaintenanceTokenException('INVALID_$claim'.toUpperCase(), 'Token claim $claim is invalid.');
    return parsed.toUtc();
  }

  static List<int> encodePkcs1Sha256(List<int> messageBytes, int k) {
    final hash = sha256.convert(messageBytes).bytes;
    final t = <int>[..._sha256DigestInfoPrefix, ...hash];
    final psLen = k - t.length - 3;
    if (psLen < 8) {
      throw StateError('Modulus too short for PKCS#1 v1.5 padding');
    }
    final em = List<int>.filled(k, 0);
    em[0] = 0x00;
    em[1] = 0x01;
    for (var i = 2; i < 2 + psLen; i++) {
      em[i] = 0xff;
    }
    em[2 + psLen] = 0x00;
    for (var i = 0; i < t.length; i++) {
      em[3 + psLen + i] = t[i];
    }
    return em;
  }

  static BigInt _bytesToBigInt(List<int> bytes) {
    var result = BigInt.zero;
    for (final b in bytes) {
      result = (result << 8) | BigInt.from(b & 0xff);
    }
    return result;
  }

  static List<int> _bigIntToBytes(BigInt number, int length) {
    final bytes = List<int>.filled(length, 0);
    var temp = number;
    for (var i = length - 1; i >= 0; i--) {
      bytes[i] = (temp & BigInt.from(0xff)).toInt();
      temp = temp >> 8;
    }
    return bytes;
  }

  static BigInt _decodeBase64BigInt(String b64) {
    final bytes = base64Decode(b64);
    return _bytesToBigInt(bytes);
  }
}
