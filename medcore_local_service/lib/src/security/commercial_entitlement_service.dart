import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import '../db/db_client.dart';
import 'hardware_binding_service.dart';
import 'maintenance_token_service.dart';

enum EntitlementStatus {
  valid,
  gracePeriod,
  expiredReadOnly,
  tamperLocked,
  unlicensed;

  String toWire() {
    switch (this) {
      case EntitlementStatus.valid:
        return 'VALID';
      case EntitlementStatus.gracePeriod:
        return 'GRACE_PERIOD';
      case EntitlementStatus.expiredReadOnly:
        return 'EXPIRED_READ_ONLY';
      case EntitlementStatus.tamperLocked:
        return 'TAMPER_LOCKED';
      case EntitlementStatus.unlicensed:
        return 'UNLICENSED';
    }
  }

  static EntitlementStatus fromWire(String? raw) {
    switch ((raw ?? '').trim().toUpperCase()) {
      case 'VALID':
        return EntitlementStatus.valid;
      case 'GRACE_PERIOD':
        return EntitlementStatus.gracePeriod;
      case 'EXPIRED_READ_ONLY':
        return EntitlementStatus.expiredReadOnly;
      case 'TAMPER_LOCKED':
        return EntitlementStatus.tamperLocked;
      default:
        return EntitlementStatus.unlicensed;
    }
  }
}

class CommercialEntitlementException implements Exception {
  final String code;
  final String message;
  final int statusCode;

  const CommercialEntitlementException(this.code, this.message, {this.statusCode = 403});

  @override
  String toString() => 'CommercialEntitlementException($code): $message';
}

class CommercialEntitlement {
  final String licenseId;
  final String hospitalCode;
  final String installationId;
  final String hardwareFingerprintSha256;
  final String edition;
  final DateTime issuedAtUtc;
  final DateTime notBeforeUtc;
  final DateTime expiresAtUtc;
  final DateTime? graceUntilUtc;
  final DateTime maintenanceExpiresAtUtc;
  final int maxDevices;
  final int maxDoctors;
  final Map<String, bool> enabledModules;
  final bool isEmergencyReadOnlyPermitted;
  final EntitlementStatus status;
  final String? rawToken;
  final String? signature;
  final String? rejectionReason;

  const CommercialEntitlement({
    required this.licenseId,
    required this.hospitalCode,
    required this.installationId,
    required this.hardwareFingerprintSha256,
    required this.edition,
    required this.issuedAtUtc,
    required this.notBeforeUtc,
    required this.expiresAtUtc,
    this.graceUntilUtc,
    required this.maintenanceExpiresAtUtc,
    this.maxDevices = 25,
    this.maxDoctors = 50,
    required this.enabledModules,
    this.isEmergencyReadOnlyPermitted = true,
    required this.status,
    this.rawToken,
    this.signature,
    this.rejectionReason,
  });

  bool get isMutationAllowed =>
      status == EntitlementStatus.valid || status == EntitlementStatus.gracePeriod;

  bool get isReadOnlyAllowed => isEmergencyReadOnlyPermitted;

  bool isModuleEntitled(String moduleName) => enabledModules[moduleName] ?? false;

  Map<String, dynamic> toJson() => {
        'licenseId': licenseId,
        'hospitalCode': hospitalCode,
        'installationId': installationId,
        'hardwareFingerprintSha256': hardwareFingerprintSha256,
        'edition': edition,
        'issuedAtUtc': issuedAtUtc.toIso8601String(),
        'notBeforeUtc': notBeforeUtc.toIso8601String(),
        'expiresAtUtc': expiresAtUtc.toIso8601String(),
        'graceUntilUtc': graceUntilUtc?.toIso8601String(),
        'maintenanceExpiresAtUtc': maintenanceExpiresAtUtc.toIso8601String(),
        'maxDevices': maxDevices,
        'maxDoctors': maxDoctors,
        'enabledModules': enabledModules,
        'status': status.toWire(),
        'isMutationAllowed': isMutationAllowed,
        'isReadOnlyAllowed': isReadOnlyAllowed,
        if (rejectionReason != null) 'rejectionReason': rejectionReason,
      };

  factory CommercialEntitlement.unlicensed({
    required String hospitalCode,
    String? reason,
  }) {
    final now = DateTime.now().toUtc();
    return CommercialEntitlement(
      licenseId: 'UNLICENSED',
      hospitalCode: hospitalCode,
      installationId: 'UNBOUND',
      hardwareFingerprintSha256: 'UNBOUND',
      edition: 'UNLICENSED',
      issuedAtUtc: now,
      notBeforeUtc: now,
      expiresAtUtc: now,
      maintenanceExpiresAtUtc: now,
      enabledModules: const {},
      status: EntitlementStatus.unlicensed,
      rejectionReason: reason ?? 'No valid cryptographically signed license installed.',
    );
  }
}

/// Cryptographically Signed Offline License Token Parser and Verifier (Gate 2)
class SignedLicenseToken {
  final Map<String, dynamic> header;
  final Map<String, dynamic> payload;
  final List<int> signatureBytes;
  final String rawToken;

  SignedLicenseToken({
    required this.header,
    required this.payload,
    required this.signatureBytes,
    required this.rawToken,
  });

  static SignedLicenseToken parse(String raw) {
    final clean = raw.trim();
    final parts = clean.split('.');
    if (parts.length != 3) {
      throw const CommercialEntitlementException(
        'INVALID_LICENSE_FORMAT',
        'Expected 3 dot-delimited segments: MEDCORE_LIC_V1.<payload>.<signature>.',
      );
    }

    if (parts[0] != 'MEDCORE_LIC_V1') {
      throw const CommercialEntitlementException(
        'UNSUPPORTED_LICENSE_VERSION',
        'Unsupported license prefix. Expected MEDCORE_LIC_V1.',
      );
    }

    Map<String, dynamic> payload;
    try {
      final decodedPayload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      payload = jsonDecode(decodedPayload) as Map<String, dynamic>;
    } catch (_) {
      throw const CommercialEntitlementException(
        'MALFORMED_LICENSE_PAYLOAD',
        'License payload is not valid base64url JSON.',
      );
    }

    List<int> sigBytes;
    try {
      sigBytes = base64Url.decode(base64Url.normalize(parts[2]));
    } catch (_) {
      throw const CommercialEntitlementException(
        'MALFORMED_LICENSE_SIGNATURE',
        'License signature encoding is invalid.',
      );
    }

    return SignedLicenseToken(
      header: {'typ': 'MEDCORE_LIC_V1', 'alg': 'RS256'},
      payload: payload,
      signatureBytes: sigBytes,
      rawToken: clean,
    );
  }

  /// Verifies the digital signature using the authority RSA-2048 public key.
  bool verifySignature({
    required BigInt modulus,
    required BigInt publicExponent,
  }) {
    final messageBytes = utf8.encode(rawToken.substring(0, rawToken.lastIndexOf('.')));
    return MaintenanceTokenService.verifyRsaSha256Signature(
      messageBytes: messageBytes,
      signatureBytes: signatureBytes,
      modulus: modulus,
      publicExponent: publicExponent,
    );
  }
}

/// Authoritative Commercial Entitlement & Offline Licensing Service (Gates 1, 2, 5, 6)
class CommercialEntitlementService {
  final DbClient db;
  final String securityRootDirectory;
  final HardwareBindingService hardwareService;
  final BigInt? authorityModulusOverride;
  final BigInt? authorityExponentOverride;

  CommercialEntitlementService({
    required this.db,
    required this.securityRootDirectory,
    HardwareBindingService? hardwareService,
    this.authorityModulusOverride,
    this.authorityExponentOverride,
  }) : hardwareService = hardwareService ?? HardwareBindingService();

  BigInt get _authorityModulus =>
      authorityModulusOverride ?? MaintenanceTokenService.defaultModulus;

  BigInt get _authorityExponent =>
      authorityExponentOverride ?? MaintenanceTokenService.defaultExponent;

  File get _licenseFile => File(p.join(securityRootDirectory, 'license.mclic'));

  File get _clockKeyFile => File(p.join(securityRootDirectory, 'clock_guard.key'));

  /// Resolves the canonical active entitlement for a facility.
  /// Follows strict truth hierarchy:
  /// Level 1: Cryptographically signed license file on disk (`license.mclic`)
  /// Level 2: Database verified cache (`mc_license_state` + HMAC seal)
  /// Level 3: Evaluated against monotonic time high-water mark
  Future<CommercialEntitlement> getActiveEntitlement(String hospitalCode) async {
    final cleanHosp = hospitalCode.trim();
    if (cleanHosp.isEmpty) {
      throw ArgumentError('hospitalCode is required.');
    }

    // 1. Try reading signed license file from disk
    if (_licenseFile.existsSync()) {
      try {
        final raw = _licenseFile.readAsStringSync().trim();
        final token = SignedLicenseToken.parse(raw);
        final entitlement = await _evaluateToken(token, cleanHosp);
        await _persistToLicenseState(entitlement, token.rawToken);
        return entitlement;
      } catch (e) {
        // Log corrupted license file and fall back to database cache
      }
    }

    // 2. Fall back to authoritative database cache in mc_license_state
    final dbRows = await db.execute(
      'SELECT * FROM mc_license_state WHERE hospital_code = :hosp LIMIT 1',
      {'hosp': cleanHosp},
    );

    if (dbRows.rows.isNotEmpty) {
      final row = dbRows.rows.first.assoc();
      final leaseTokenRaw = row['lease_payload_json']?.toString();
      if (leaseTokenRaw != null && leaseTokenRaw.startsWith('MEDCORE_LIC_V1.')) {
        try {
          final token = SignedLicenseToken.parse(leaseTokenRaw);
          final entitlement = await _evaluateToken(token, cleanHosp);
          return entitlement;
        } catch (_) {}
      }
    }

    // 3. No valid license -> Return UNLICENSED (fails closed)
    return CommercialEntitlement.unlicensed(
      hospitalCode: cleanHosp,
      reason: 'No cryptographically valid offline license installed.',
    );
  }

  /// Evaluates a parsed SignedLicenseToken against hardware, installation ID,
  /// hospital code, and monotonic security clock.
  Future<CommercialEntitlement> _evaluateToken(
    SignedLicenseToken token,
    String expectedHospitalCode,
  ) async {
    // 1. Verify Asymmetric Digital Signature
    final isValidSig = token.verifySignature(
      modulus: _authorityModulus,
      publicExponent: _authorityExponent,
    );

    if (!isValidSig) {
      return CommercialEntitlement.unlicensed(
        hospitalCode: expectedHospitalCode,
        reason: 'CRITICAL: Digital RSA signature verification failed. License is forged or corrupted.',
      );
    }

    final p = token.payload;

    // 2. Validate Hospital Code Binding
    final licHosp = (p['hosp'] ?? '').toString().trim();
    if (licHosp != expectedHospitalCode) {
      return CommercialEntitlement.unlicensed(
        hospitalCode: expectedHospitalCode,
        reason: 'LICENSE_TENANT_MISMATCH: License issued for facility "$licHosp", but requested by "$expectedHospitalCode".',
      );
    }

    // 3. Validate Hardware Binding
    final expectedHw = (p['hw'] ?? '').toString().trim();
    final actualHw = await hardwareService.getHardwareFingerprint();
    final hwValid = hardwareService.verifyHardwareBinding(
      expectedFingerprint: expectedHw,
      actualFingerprint: actualHw,
    );

    if (!hwValid) {
      return CommercialEntitlement(
        licenseId: (p['lid'] ?? 'UNKNOWN').toString(),
        hospitalCode: expectedHospitalCode,
        installationId: (p['inst'] ?? 'UNKNOWN').toString(),
        hardwareFingerprintSha256: actualHw,
        edition: (p['ed'] ?? 'PLATINUM').toString(),
        issuedAtUtc: DateTime.tryParse(p['iat']?.toString() ?? '')?.toUtc() ?? DateTime.now().toUtc(),
        notBeforeUtc: DateTime.tryParse(p['nbf']?.toString() ?? '')?.toUtc() ?? DateTime.now().toUtc(),
        expiresAtUtc: DateTime.tryParse(p['exp']?.toString() ?? '')?.toUtc() ?? DateTime.now().toUtc(),
        maintenanceExpiresAtUtc: DateTime.tryParse(p['maint_exp']?.toString() ?? '')?.toUtc() ?? DateTime.now().toUtc(),
        enabledModules: const {},
        status: EntitlementStatus.tamperLocked,
        rawToken: token.rawToken,
        rejectionReason: 'HARDWARE_BINDING_VIOLATION: License is bound to another physical machine.',
      );
    }

    // 4. Validate Timestamps & Anti-Clock-Rollback
    final iat = DateTime.parse(_strictUtcString(p['iat'], 'iat')).toUtc();
    final nbf = DateTime.parse(_strictUtcString(p['nbf'], 'nbf')).toUtc();
    final exp = DateTime.parse(_strictUtcString(p['exp'], 'exp')).toUtc();
    final grace = p['grace'] != null ? DateTime.tryParse(p['grace'].toString())?.toUtc() : null;
    final maintExp = p['maint_exp'] != null
        ? DateTime.parse(_strictUtcString(p['maint_exp'], 'maint_exp')).toUtc()
        : exp;

    final nowUtc = DateTime.now().toUtc();

    // Check monotonic high-water mark from MariaDB mc_clock_guard
    DateTime effectiveTime = nowUtc;
    final cgRes = await db.execute(
      'SELECT max_observed_utc, rollback_detected FROM mc_clock_guard WHERE hospital_code = :hosp LIMIT 1',
      {'hosp': expectedHospitalCode},
    );
    if (cgRes.rows.isNotEmpty) {
      final cgRow = cgRes.rows.first.assoc();
      if (cgRow['rollback_detected'] == 1 || cgRow['rollback_detected'] == '1') {
        return CommercialEntitlement(
          licenseId: (p['lid'] ?? 'UNKNOWN').toString(),
          hospitalCode: expectedHospitalCode,
          installationId: (p['inst'] ?? 'UNKNOWN').toString(),
          hardwareFingerprintSha256: actualHw,
          edition: (p['ed'] ?? 'PLATINUM').toString(),
          issuedAtUtc: iat,
          notBeforeUtc: nbf,
          expiresAtUtc: exp,
          graceUntilUtc: grace,
          maintenanceExpiresAtUtc: maintExp,
          enabledModules: const {},
          status: EntitlementStatus.tamperLocked,
          rawToken: token.rawToken,
          rejectionReason: 'CLOCK_ROLLBACK_LOCKED: Clock tampering detected on machine.',
        );
      }
      final rawMax = cgRow['max_observed_utc']?.toString();
      if (rawMax != null && rawMax.isNotEmpty) {
        final parsedMax = DateTime.tryParse(rawMax.endsWith('Z') ? rawMax : '${rawMax.replaceFirst(' ', 'T')}Z')?.toUtc();
        if (parsedMax != null && parsedMax.isAfter(effectiveTime)) {
          effectiveTime = parsedMax;
        }
      }
    }

    // Fail-Closed Entitlement Status Calculation:
    EntitlementStatus status = EntitlementStatus.valid;
    if (effectiveTime.isBefore(nbf)) {
      status = EntitlementStatus.unlicensed; // Not yet valid
    } else if (effectiveTime.isAfter(exp) || effectiveTime.isAtSameMomentAs(exp)) {
      if (grace != null && effectiveTime.isBefore(grace)) {
        status = EntitlementStatus.gracePeriod;
      } else {
        status = EntitlementStatus.expiredReadOnly;
      }
    }

    // 5. Extract Modules Map
    final modsRaw = p['mods'];
    final Map<String, bool> enabledModules = {};
    if (modsRaw is Map) {
      for (final entry in modsRaw.entries) {
        enabledModules[entry.key.toString()] = entry.value == true;
      }
    }

    return CommercialEntitlement(
      licenseId: (p['lid'] ?? 'LIC-DEFAULT').toString(),
      hospitalCode: expectedHospitalCode,
      installationId: (p['inst'] ?? 'INST-DEFAULT').toString(),
      hardwareFingerprintSha256: actualHw,
      edition: (p['ed'] ?? 'PLATINUM').toString().toUpperCase(),
      issuedAtUtc: iat,
      notBeforeUtc: nbf,
      expiresAtUtc: exp,
      graceUntilUtc: grace,
      maintenanceExpiresAtUtc: maintExp,
      maxDevices: (p['max_dev'] is num) ? (p['max_dev'] as num).toInt() : 25,
      maxDoctors: (p['max_doc'] is num) ? (p['max_doc'] as num).toInt() : 50,
      enabledModules: enabledModules,
      isEmergencyReadOnlyPermitted: p['allow_read_only'] != false,
      status: status,
      rawToken: token.rawToken,
    );
  }

  /// Imports and validates a newly supplied signed offline license lease.
  /// Writes it to `runtime/security/license.mclic`, updates `mc_license_state`,
  /// updates `mc_facility_config`, and emits an immutable audit event.
  Future<CommercialEntitlement> importSignedLicense(
    String rawToken, {
    required String hospitalCode,
  }) async {
    final token = SignedLicenseToken.parse(rawToken);
    final entitlement = await _evaluateToken(token, hospitalCode);

    if (entitlement.status == EntitlementStatus.tamperLocked) {
      throw CommercialEntitlementException(
        'LICENSE_REJECTED',
        entitlement.rejectionReason ?? 'License validation failed.',
      );
    }

    // 1. Write to disk
    if (!_licenseFile.parent.existsSync()) {
      _licenseFile.parent.createSync(recursive: true);
    }
    _licenseFile.writeAsStringSync(rawToken.trim());

    // 2. Persist to mc_license_state
    await _persistToLicenseState(entitlement, rawToken);

    // 3. Update mc_facility_config authoritative subscription dates & edition
    await _syncToFacilityConfig(entitlement);

    // 4. Emit audit log
    await db.execute(
      '''
      INSERT INTO mc_commercial_audit_log (
        hospital_code, license_id, event_type, severity, details_json, created_at
      ) VALUES (
        :hosp, :lid, 'license.imported', 'INFO', :details, NOW(3)
      )
      ''',
      {
        'hosp': hospitalCode,
        'lid': entitlement.licenseId,
        'details': jsonEncode(entitlement.toJson()),
      },
    );

    return entitlement;
  }

  Future<void> _persistToLicenseState(CommercialEntitlement ent, String rawToken) async {
    final hmacSeal = _computeHmacSeal(ent);
    await db.execute(
      '''
      INSERT INTO mc_license_state (
        hospital_code, license_id, installation_id, hardware_fingerprint_sha256,
        edition, entitled_modules_json, max_devices, max_doctors,
        issued_at_utc, expires_at_utc, offline_grace_until_utc, maintenance_expires_at_utc,
        last_online_refresh_utc, lease_payload_json, ed25519_signature, hmac_seal, status
      ) VALUES (
        :hosp, :lid, :inst, :hw,
        :ed, :mods, :devs, :docs,
        :iat, :exp, :grace, :maint,
        NOW(), :raw, :sig, :seal, :status
      )
      ON DUPLICATE KEY UPDATE
        license_id = VALUES(license_id),
        installation_id = VALUES(installation_id),
        hardware_fingerprint_sha256 = VALUES(hardware_fingerprint_sha256),
        edition = VALUES(edition),
        entitled_modules_json = VALUES(entitled_modules_json),
        max_devices = VALUES(max_devices),
        max_doctors = VALUES(max_doctors),
        expires_at_utc = VALUES(expires_at_utc),
        maintenance_expires_at_utc = VALUES(maintenance_expires_at_utc),
        lease_payload_json = VALUES(lease_payload_json),
        hmac_seal = VALUES(hmac_seal),
        status = VALUES(status)
      ''',
      {
        'hosp': ent.hospitalCode,
        'lid': ent.licenseId,
        'inst': ent.installationId,
        'hw': ent.hardwareFingerprintSha256,
        'ed': ent.edition,
        'mods': jsonEncode(ent.enabledModules),
        'devs': ent.maxDevices,
        'docs': ent.maxDoctors,
        'iat': ent.issuedAtUtc.toIso8601String().replaceFirst('T', ' ').replaceAll('Z', ''),
        'exp': ent.expiresAtUtc.toIso8601String().replaceFirst('T', ' ').replaceAll('Z', ''),
        'grace': (ent.graceUntilUtc ?? ent.expiresAtUtc).toIso8601String().replaceFirst('T', ' ').replaceAll('Z', ''),
        'maint': ent.maintenanceExpiresAtUtc.toIso8601String().replaceFirst('T', ' ').replaceAll('Z', ''),
        'raw': rawToken,
        'sig': rawToken.split('.').last,
        'seal': hmacSeal,
        'status': ent.status.toWire(),
      },
    );
  }

  Future<void> _syncToFacilityConfig(CommercialEntitlement ent) async {
    final expStr = ent.expiresAtUtc.toIso8601String().replaceFirst('T', ' ').replaceAll('Z', '');
    await db.execute(
      '''
      UPDATE mc_facility_config
      SET license_id = :lid,
          edition = :ed,
          subscription_expires_utc = :exp,
          entitlement_status = :status,
          enabled_modules_json = :mods
      WHERE hospital_code = :hosp
      ''',
      {
        'hosp': ent.hospitalCode,
        'lid': ent.licenseId,
        'ed': ent.edition,
        'exp': expStr,
        'status': ent.status.toWire(),
        'mods': jsonEncode(ent.enabledModules),
      },
    );
  }

  String _computeHmacSeal(CommercialEntitlement ent) {
    List<int> keyBytes = utf8.encode('fallback_secret_key');
    if (_clockKeyFile.existsSync()) {
      keyBytes = _clockKeyFile.readAsBytesSync();
    }
    final canonical = '${ent.licenseId}:${ent.hospitalCode}:${ent.installationId}:${ent.edition}:${ent.expiresAtUtc.toIso8601String()}:${ent.status.toWire()}';
    return Hmac(sha256, keyBytes).convert(utf8.encode(canonical)).toString();
  }

  static String _strictUtcString(dynamic val, String claim) {
    final s = val?.toString().trim() ?? '';
    if (s.isEmpty) {
      throw CommercialEntitlementException('MISSING_CLAIM_$claim'.toUpperCase(), 'Claim $claim is missing.');
    }
    return s;
  }
}
