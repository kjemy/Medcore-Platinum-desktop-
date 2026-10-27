import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../repositories/clock_guard_repository.dart';

class ClockGuardKeyManager {
  final Uint8List _secretKey;

  ClockGuardKeyManager._(this._secretKey);

  /// Creates a key manager with an explicitly provided in-memory key (ideal for isolated testing)
  factory ClockGuardKeyManager.inMemory([List<int>? keyBytes]) {
    if (keyBytes != null) {
      return ClockGuardKeyManager._(Uint8List.fromList(keyBytes));
    }
    final rng = Random.secure();
    final generated = Uint8List.fromList(List<int>.generate(32, (_) => rng.nextInt(256)));
    return ClockGuardKeyManager._(generated);
  }

  /// Loads or generates the persistent installation secret key stored outside the database.
  factory ClockGuardKeyManager.fromFile({String? keyFilePath}) {
    final path = keyFilePath ?? _defaultKeyPath();
    final file = File(path);

    if (file.existsSync()) {
      final content = file.readAsStringSync().trim();
      if (content.length == 64) {
        // 64-char hex
        final bytes = _hexDecode(content);
        return ClockGuardKeyManager._(bytes);
      } else {
        final raw = file.readAsBytesSync();
        if (raw.length >= 32) {
          return ClockGuardKeyManager._(Uint8List.sublistView(raw, 0, 32));
        }
      }
      throw StateError('Existing clock guard key is malformed; refusing silent key regeneration.');
    }

    // Generate new 256-bit cryptographically secure key
    final rng = Random.secure();
    final newKey = Uint8List.fromList(List<int>.generate(32, (_) => rng.nextInt(256)));

    // Ensure directory exists
    file.parent.createSync(recursive: true);
    final hexString = _hexEncode(newKey);
    file.writeAsStringSync(hexString, flush: true);

    return ClockGuardKeyManager._(newKey);
  }

  Uint8List get keyBytes => Uint8List.fromList(_secretKey);

  String get installationId => sha256.convert(_secretKey).toString().substring(0, 32);

  String computeSecurityRootSeal({
    required String hospitalCode,
    required String installationId,
    required String initializationId,
    required DateTime initializedAtUtc,
    required String state,
  }) {
    final payload = 'MC_SECURITY_ROOT:v1:$hospitalCode:$installationId:$initializationId:'
        '${_fmtDt3(initializedAtUtc)}:$state';
    return Hmac(sha256, _secretKey).convert(utf8.encode(payload)).toString();
  }

  /// Computes a cryptographically keyed HMAC-SHA256 seal for mc_clock_guard.
  /// Authenticates every security-critical field:
  /// - hospitalCode (tenant binding)
  /// - maxObservedUtc (high-water mark)
  /// - lastBootMonotonicMs (monotonic progression anchor)
  /// - rollbackDetected (alarm state)
  /// - rollbackDeltaSeconds (tamper magnitude)
  /// - lockedAtUtc (tamper occurrence timestamp)
  /// - unlockedByMaintenanceTokenId (recovery audit link / consumed nonce)
  /// - lastEventUuid (audit trace correlation)
  String computeKeyedSeal({
    required String hospitalCode,
    required DateTime maxObservedUtc,
    required int lastBootMonotonicMs,
    String processBootId = 'LEGACY_UNKNOWN',
    required bool rollbackDetected,
    int? rollbackDeltaSeconds,
    DateTime? lockedAtUtc,
    String? unlockedByMaintenanceTokenId,
    String? lastEventUuid,
  }) {
    final dtStr = _fmtDt3(maxObservedUtc);
    final rbStr = rollbackDetected ? '1' : '0';
    final deltaStr = rollbackDeltaSeconds != null ? rollbackDeltaSeconds.toString() : 'none';
    final lockedStr = lockedAtUtc != null ? _fmtDt(lockedAtUtc) : 'none';
    final tokenStr = unlockedByMaintenanceTokenId != null && unlockedByMaintenanceTokenId.isNotEmpty
        ? unlockedByMaintenanceTokenId
        : 'none';
    final eventStr = lastEventUuid != null && lastEventUuid.isNotEmpty ? lastEventUuid : 'none';

    final message = 'MC_CLOCK_KEYED_SEAL:v3:'
        '$hospitalCode:'
        '$dtStr:'
        '$lastBootMonotonicMs:'
        '$processBootId:'
        '$rbStr:'
        '$deltaStr:'
        '$lockedStr:'
        '$tokenStr:'
        '$eventStr';

    final hmac = Hmac(sha256, _secretKey);
    return hmac.convert(utf8.encode(message)).toString();
  }

  /// Verifies the HMAC-SHA256 seal on a ClockGuardRecord using constant-time comparison
  bool verifySeal({required ClockGuardRecord record}) {
    final expected = computeKeyedSeal(
      hospitalCode: record.hospitalCode,
      maxObservedUtc: record.maxObservedUtc,
      lastBootMonotonicMs: record.lastBootMonotonicMs,
      processBootId: record.processBootId ?? 'LEGACY_UNKNOWN',
      rollbackDetected: record.rollbackDetected,
      rollbackDeltaSeconds: record.rollbackDeltaSeconds,
      lockedAtUtc: record.lockedAtUtc,
      unlockedByMaintenanceTokenId: record.unlockedByMaintenanceTokenId,
      lastEventUuid: record.lastEventUuid,
    );
    if (_constantTimeEquals(record.hmacSeal, expected)) return true;
    if (record.processBootId == 'LEGACY_UNKNOWN') {
      final legacy = _computeLegacySeal(record);
      return _constantTimeEquals(record.hmacSeal, legacy);
    }
    return false;
  }

  String _computeLegacySeal(ClockGuardRecord record) {
    final dt = _fmtDt3(record.maxObservedUtc);
    final delta = record.rollbackDeltaSeconds?.toString() ?? 'none';
    final locked = record.lockedAtUtc != null ? _fmtDt(record.lockedAtUtc!) : 'none';
    final token = record.unlockedByMaintenanceTokenId?.isNotEmpty == true ? record.unlockedByMaintenanceTokenId! : 'none';
    final event = record.lastEventUuid?.isNotEmpty == true ? record.lastEventUuid! : 'none';
    final message = 'MC_CLOCK_KEYED_SEAL:v2:${record.hospitalCode}:$dt:${record.lastBootMonotonicMs}:'
        '${record.rollbackDetected ? '1' : '0'}:$delta:$locked:$token:$event';
    return Hmac(sha256, _secretKey).convert(utf8.encode(message)).toString();
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  static String _defaultKeyPath() {
    return 'runtime/security/clock_guard.key';
  }

  static String _fmtDt3(DateTime dt) {
    final u = dt.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    return '${u.year}-${two(u.month)}-${two(u.day)} ${two(u.hour)}:${two(u.minute)}:${two(u.second)}.${three(u.millisecond)}';
  }

  static String _fmtDt(DateTime dt) {
    final u = dt.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year}-${two(u.month)}-${two(u.day)} ${two(u.hour)}:${two(u.minute)}:${two(u.second)}';
  }

  static String _hexEncode(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static Uint8List _hexDecode(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }
}
