import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import 'maintenance_token_service.dart';

class TrustedTimeChallenge {
  final String hospitalCode;
  final String installationId;
  final String nonce;
  final int _createdMonotonicMs;
  final String _ownerId;

  const TrustedTimeChallenge._({
    required this.hospitalCode,
    required this.installationId,
    required this.nonce,
    required int createdMonotonicMs,
    required String ownerId,
  }) : _createdMonotonicMs = createdMonotonicMs,
       _ownerId = ownerId;

  Map<String, String> toAuthorityRequest() => {
        'v': '1',
        'hosp': hospitalCode,
        'inst': installationId,
        'nonce': nonce,
      };
}

/// Evidence can only be created by [TrustedTimeVerifier.verifyResponse].
/// It is bound to the challenge and verifier instance that created it.
class TrustedTimeEvidence {
  final String authorityId;
  final String hospitalCode;
  final String installationId;
  final String challengeNonce;
  final DateTime trustedUtc;
  final DateTime validUntilUtc;
  final String _verifierOwnerId;
  final int _verifiedAtMonotonicMs;

  const TrustedTimeEvidence._({
    required this.authorityId,
    required this.hospitalCode,
    required this.installationId,
    required this.challengeNonce,
    required this.trustedUtc,
    required this.validUntilUtc,
    required String verifierOwnerId,
    required int verifiedAtMonotonicMs,
  }) : _verifierOwnerId = verifierOwnerId,
       _verifiedAtMonotonicMs = verifiedAtMonotonicMs;

  DateTime trustedNow(int currentMonotonicMs) =>
      trustedUtc.add(Duration(milliseconds: currentMonotonicMs - _verifiedAtMonotonicMs));
}

class TrustedTimeEvidenceException implements Exception {
  final String code;
  final String message;
  const TrustedTimeEvidenceException(this.code, this.message);
  @override
  String toString() => 'TrustedTimeEvidenceException($code): $message';
}

/// Verifies signed time responses from the pinned production authority.
/// The production private key is never present in this application.
class TrustedTimeVerifier {
  static const String productionAuthorityId = 'MEDCORE-TIME-AUTHORITY-01';
  static const String _productionModulusB64 =
      '2CyHenQ/BVEfW0dpv+m6Hkglqj89PHds1tU1NsS/pbn4FMzAK0dAvvrgLiIIQ+iM45W7OCzdkaCJl/iXkwQxJO72tHo/Kvl7CZzmh6ReG1GyaYnVjFVjegHVSTV8C6uj0/b3lNuiVHJGI9aYx1X0N+pDaxIOlU/SrBYi89ZrEY9NVwrdllIfrsuFPToApwX7Cx7M0SbjAGyZkhOwF570CisHH5ch0vuCwgA/2UttopcyL0oVVFH27nOqD9ldoviTp7OenUqu+lphVioLVhRX9YMk1RbSyC/IqkX75NJviICxpAN+MtvsSXZTxFosUiFLqci9cstTyoSbXeVe0aQb/Q==';
  static const String _productionExponentB64 = 'AQAB';
  static final Stopwatch _processMonotonic = Stopwatch()..start();
  static final String _processId = const Uuid().v4();

  final String authorityId;
  final BigInt modulus;
  final BigInt exponent;
  final String _ownerId = const Uuid().v4();
  final Set<String> _issuedNonces = <String>{};

  TrustedTimeVerifier.production()
      : authorityId = productionAuthorityId,
        modulus = _decodeBigInt(_productionModulusB64),
        exponent = _decodeBigInt(_productionExponentB64);

  /// Test-only injection point. Test keys must be distinct from production keys.
  @Deprecated('For isolated tests only. Production uses TrustedTimeVerifier.production().')
  TrustedTimeVerifier.forTesting({required this.authorityId, required this.modulus, required this.exponent});

  TrustedTimeChallenge createChallenge({required String hospitalCode, required String installationId}) {
    if (hospitalCode.trim().isEmpty || installationId.trim().isEmpty) {
      throw ArgumentError('Hospital and installation binding are required.');
    }
    final random = Random.secure();
    final bytes = Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256)));
    final nonce = base64UrlEncode(bytes).replaceAll('=', '');
    _issuedNonces.add(nonce);
    return TrustedTimeChallenge._(
      hospitalCode: hospitalCode,
      installationId: installationId,
      nonce: nonce,
      createdMonotonicMs: _processMonotonic.elapsedMilliseconds,
      ownerId: _ownerId,
    );
  }

  TrustedTimeEvidence verifyResponse({required TrustedTimeChallenge challenge, required String rawResponse}) {
    if (challenge._ownerId != _ownerId || !_issuedNonces.contains(challenge.nonce)) {
      throw const TrustedTimeEvidenceException('INVALID_CHALLENGE', 'Challenge was not issued by this verifier instance.');
    }
    final age = _processMonotonic.elapsedMilliseconds - challenge._createdMonotonicMs;
    if (_processId.isEmpty || age < 0 || age > const Duration(minutes: 2).inMilliseconds) {
      throw const TrustedTimeEvidenceException('STALE_CHALLENGE', 'Time challenge is stale or from another process.');
    }

    final parts = rawResponse.trim().split('.');
    if (parts.length != 3 || parts[0] != 'MC_TIME_V1') {
      throw const TrustedTimeEvidenceException('INVALID_TIME_RESPONSE', 'Expected MC_TIME_V1.<payload>.<signature>.');
    }
    late final String payloadText;
    late final Map<String, dynamic> payload;
    late final List<int> signature;
    try {
      payloadText = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      payload = jsonDecode(payloadText) as Map<String, dynamic>;
      signature = base64Url.decode(base64Url.normalize(parts[2]));
    } catch (_) {
      throw const TrustedTimeEvidenceException('MALFORMED_TIME_RESPONSE', 'Payload or signature encoding is invalid.');
    }
    if (jsonEncode(payload) != payloadText ||
        payload.keys.toSet().difference(const {'v', 'authority', 'hosp', 'inst', 'nonce', 'time_utc', 'valid_until_utc'}).isNotEmpty ||
        payload.keys.toSet().length != 7) {
      throw const TrustedTimeEvidenceException('NON_CANONICAL_TIME_RESPONSE', 'Time response claims are not canonical.');
    }
    if (payload['v'] != 1 || payload['authority'] != authorityId ||
        payload['hosp'] != challenge.hospitalCode || payload['inst'] != challenge.installationId ||
        payload['nonce'] != challenge.nonce) {
      throw const TrustedTimeEvidenceException('TIME_BINDING_MISMATCH', 'Authority, tenant, installation or challenge binding is invalid.');
    }
    if (!MaintenanceTokenService.verifyRsaSha256Signature(
      messageBytes: utf8.encode(payloadText),
      signatureBytes: signature,
      modulus: modulus,
      publicExponent: exponent,
    )) {
      throw const TrustedTimeEvidenceException('INVALID_TIME_SIGNATURE', 'Trusted time authority signature is invalid.');
    }
    final timestamp = _parseStrictUtc(payload['time_utc']);
    final validUntil = _parseStrictUtc(payload['valid_until_utc']);
    if (!validUntil.isAfter(timestamp) || validUntil.difference(timestamp) > const Duration(minutes: 2)) {
      throw const TrustedTimeEvidenceException('INVALID_TIME_VALIDITY', 'Authority response validity interval is invalid.');
    }
    _issuedNonces.remove(challenge.nonce);
    return TrustedTimeEvidence._(
      authorityId: authorityId,
      hospitalCode: challenge.hospitalCode,
      installationId: challenge.installationId,
      challengeNonce: challenge.nonce,
      trustedUtc: timestamp,
      validUntilUtc: validUntil,
      verifierOwnerId: _ownerId,
      verifiedAtMonotonicMs: _processMonotonic.elapsedMilliseconds,
    );
  }

  void requireEvidence({
    required TrustedTimeEvidence evidence,
    required String hospitalCode,
    required String installationId,
  }) {
    if (evidence._verifierOwnerId != _ownerId || evidence.authorityId != authorityId ||
        evidence.hospitalCode != hospitalCode || evidence.installationId != installationId ||
        evidence.challengeNonce.isEmpty || !evidence.validUntilUtc.isAfter(evidence.trustedUtc)) {
      throw const TrustedTimeEvidenceException('UNTRUSTED_DOWNTIME_CLOCK', 'Trusted time evidence is invalid or misbound.');
    }
    final trustedNow = evidence.trustedNow(_processMonotonic.elapsedMilliseconds);
    if (trustedNow.isBefore(evidence.trustedUtc) || !trustedNow.isBefore(evidence.validUntilUtc) ||
        trustedNow.difference(evidence.trustedUtc) > const Duration(minutes: 2)) {
      throw const TrustedTimeEvidenceException('UNTRUSTED_DOWNTIME_CLOCK', 'Trusted time evidence has expired or is stale.');
    }
  }

  DateTime currentTrustedTime({
    required TrustedTimeEvidence evidence,
    required String hospitalCode,
    required String installationId,
  }) {
    requireEvidence(evidence: evidence, hospitalCode: hospitalCode, installationId: installationId);
    return evidence.trustedNow(_processMonotonic.elapsedMilliseconds);
  }

  static DateTime _parseStrictUtc(dynamic value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$').hasMatch(value)) {
      throw const TrustedTimeEvidenceException('INVALID_AUTHORITY_TIMESTAMP', 'Timestamp must be strict UTC ISO-8601.');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw const TrustedTimeEvidenceException('INVALID_AUTHORITY_TIMESTAMP', 'Timestamp is invalid.');
    return parsed.toUtc();
  }

  static BigInt _decodeBigInt(String value) {
    var result = BigInt.zero;
    for (final byte in base64Decode(value)) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }
}
