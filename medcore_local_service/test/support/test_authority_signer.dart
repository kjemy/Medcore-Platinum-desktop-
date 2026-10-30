import 'dart:convert';
import 'dart:io';
import 'package:medcore_local_service/medcore_local_service.dart';
import 'package:path/path.dart' as p;

/// Test-Only Authority Signer (Lives strictly in test/support, NEVER in production distribution).
/// The private key (d) is kept outside the Desktop repository/distribution.
class TestAuthoritySigner {
  final BigInt modulus;
  final BigInt privateExponent;
  final BigInt publicExponent;

  TestAuthoritySigner({
    required this.modulus,
    required this.privateExponent,
    required this.publicExponent,
  });

  static String? findTestPrivateKeyPath() {
    final path = p.join(Directory.current.path, 'test', 'fixtures', 'maintenance_test_authority.json');
    return File(path).existsSync() ? path : null;
  }

  factory TestAuthoritySigner.loadDefault() {
    final path = findTestPrivateKeyPath();
    if (path == null) {
      throw StateError(
        'Test authority private key not found! '
        'Ensure test/fixtures/maintenance_test_authority.json exists.',
      );
    }
    return TestAuthoritySigner.fromPrivateKeyFile(path);
  }

  factory TestAuthoritySigner.fromPrivateKeyFile(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw StateError('Test authority private key file not found at: $path');
    }
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return TestAuthoritySigner(
      modulus: _decodeBase64BigInt(json['n'] as String),
      privateExponent: _decodeBase64BigInt(json['d'] as String),
      publicExponent: _decodeBase64BigInt(json['e'] as String),
    );
  }

  String signToken({
    required String hospitalCode,
    required String installationId,
    required String nonce,
    required DateTime issuedAt,
    required DateTime expiresAt,
    String action = 'UNLOCK_CLOCK_ROLLBACK',
  }) {
    final payloadMap = {
      'v': 1,
      'tid': 'TID-$nonce',
      'hosp': hospitalCode,
      'inst': installationId,
      'act': action,
      'nonce': nonce,
      'iat': issuedAt.toUtc().toIso8601String(),
      'exp': expiresAt.toUtc().toIso8601String(),
    };

    return signPayload(payloadMap);
  }

  String signPayload(Map<String, dynamic> payloadMap) {
    final canonicalJson = jsonEncode(payloadMap);
    final payloadB64 = base64UrlEncode(utf8.encode(canonicalJson)).replaceAll('=', '');

    final k = (modulus.bitLength + 7) ~/ 8;
    final em = MaintenanceTokenService.encodePkcs1Sha256(utf8.encode(canonicalJson), k);
    final m = _bytesToBigInt(em);
    final s = m.modPow(privateExponent, modulus);
    final sigBytes = _bigIntToBytes(s, k);
    final sigB64 = base64UrlEncode(sigBytes).replaceAll('=', '');

    return 'MC_MAINT_V1.$payloadB64.$sigB64';
  }

  String signLicenseLease(Map<String, dynamic> payloadMap) {
    final canonicalJson = jsonEncode(payloadMap);
    final payloadB64 = base64UrlEncode(utf8.encode(canonicalJson)).replaceAll('=', '');
    final signingText = 'MEDCORE_LIC_V1.$payloadB64';

    final k = (modulus.bitLength + 7) ~/ 8;
    final em = MaintenanceTokenService.encodePkcs1Sha256(utf8.encode(signingText), k);
    final m = _bytesToBigInt(em);
    final s = m.modPow(privateExponent, modulus);
    final sigBytes = _bigIntToBytes(s, k);
    final sigB64 = base64UrlEncode(sigBytes).replaceAll('=', '');

    return '$signingText.$sigB64';
  }

  String signTimeResponse({
    required String authorityId,
    required String hospitalCode,
    required String installationId,
    required String nonce,
    required DateTime trustedUtc,
  }) {
    final payload = <String, dynamic>{
      'v': 1,
      'authority': authorityId,
      'hosp': hospitalCode,
      'inst': installationId,
      'nonce': nonce,
      'time_utc': trustedUtc.toUtc().toIso8601String(),
      'valid_until_utc': trustedUtc.toUtc().add(const Duration(minutes: 1)).toIso8601String(),
    };
    final text = jsonEncode(payload);
    final k = (modulus.bitLength + 7) ~/ 8;
    final encoded = MaintenanceTokenService.encodePkcs1Sha256(utf8.encode(text), k);
    final signature = _bigIntToBytes(_bytesToBigInt(encoded).modPow(privateExponent, modulus), k);
    return 'MC_TIME_V1.${base64UrlEncode(utf8.encode(text)).replaceAll('=', '')}.${base64UrlEncode(signature).replaceAll('=', '')}';
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
