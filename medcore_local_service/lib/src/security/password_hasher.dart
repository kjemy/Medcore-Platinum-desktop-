import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Native Offline Password Hasher for MedCore Desktop (Zero WordPress wp_users dependency)
/// Uses PBKDF2-HMAC-SHA256 with 20,000 iterations and 16-byte cryptographic random salt,
/// plus constant-time comparison to prevent timing side-channel attacks.
class PasswordHasher {
  static const int defaultIterations = 20000;
  static const int keyLength = 32;

  static String hashPassword(String plainPassword, {int iterations = defaultIterations}) {
    final rng = Random.secure();
    final saltBytes = Uint8List.fromList(List<int>.generate(16, (_) => rng.nextInt(256)));
    final derived = _pbkdf2Sha256(utf8.encode(plainPassword), saltBytes, iterations, keyLength);
    final saltB64 = base64UrlEncode(saltBytes);
    final hashB64 = base64UrlEncode(derived);
    return 'pbkdf2_sha256\$$iterations\$$saltB64\$$hashB64';
  }

  static bool verifyPassword(String plainPassword, String storedHash) {
    final parts = storedHash.split('\$');
    if (parts.length != 4 || parts[0] != 'pbkdf2_sha256') {
      return false;
    }
    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations < 1000) return false;
    try {
      final saltBytes = base64Url.decode(parts[2]);
      final expectedBytes = base64Url.decode(parts[3]);
      final actualBytes = _pbkdf2Sha256(
        utf8.encode(plainPassword),
        saltBytes,
        iterations,
        expectedBytes.length,
      );
      return _constantTimeEquals(actualBytes, expectedBytes);
    } catch (_) {
      return false;
    }
  }

  static Uint8List _pbkdf2Sha256(
    List<int> password,
    List<int> salt,
    int iterations,
    int dkLen,
  ) {
    final hmac = Hmac(sha256, password);
    final numBlocks = (dkLen / 32).ceil();
    final output = BytesBuilder();

    for (var blockIndex = 1; blockIndex <= numBlocks; blockIndex++) {
      final blockSalt = Uint8List(salt.length + 4);
      blockSalt.setRange(0, salt.length, salt);
      blockSalt[salt.length] = (blockIndex >> 24) & 0xff;
      blockSalt[salt.length + 1] = (blockIndex >> 16) & 0xff;
      blockSalt[salt.length + 2] = (blockIndex >> 8) & 0xff;
      blockSalt[salt.length + 3] = blockIndex & 0xff;

      var u = hmac.convert(blockSalt).bytes;
      final t = Uint8List.fromList(u);

      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      output.add(t);
    }

    return Uint8List.sublistView(output.toBytes(), 0, dkLen);
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static String sha256Hex(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }

  static String generateSecureToken([int byteLength = 32]) {
    final rng = Random.secure();
    final bytes = List<int>.generate(byteLength, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
