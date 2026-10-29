import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../db/db_client.dart';
import '../db/transaction_manager.dart';
import '../repositories/clock_guard_repository.dart';
import '../repositories/tenant_governance_repository.dart';
import '../security/auth_service.dart';
import '../security/maintenance_token_service.dart';
import '../security/password_hasher.dart';
import '../security/trusted_time_evidence.dart';
import 'facility_config_service.dart';

class TechnicianSessionContext {
  final String sessionUuid;
  final String hospitalCode;
  final String authMethod;
  final String deviceId;
  final DateTime issuedAt;
  final DateTime expiresAt;

  const TechnicianSessionContext({
    required this.sessionUuid,
    required this.hospitalCode,
    required this.authMethod,
    required this.deviceId,
    required this.issuedAt,
    required this.expiresAt,
  });

  Map<String, dynamic> toJson() => {
        'sessionUuid': sessionUuid,
        'hospitalCode': hospitalCode,
        'authMethod': authMethod,
        'deviceId': deviceId,
        'issuedAt': issuedAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
      };
}

/// Protected Technician / Service Mode Engine.
///
/// Security Invariants:
/// 1. Strictly separated from ordinary hospital roles (`SuperAdmin`..`Employee` Bearer tokens
///    from `/api/v1/auth/login` are NEVER accepted as Technician sessions).
/// 2. Zero hardcoded secrets in source code. Technician sessions can ONLY be opened via:
///    - Cryptographically signed RSA-2048 `MC_MAINT_V1` authority token (`act: TECHNICIAN_SERVICE_MODE`)
///      bound to `(hospitalCode, installationIdentity, trustedTimeEvidence)` with one-time replay prevention, OR
///    - Installation-provisioned secret (`MEDCORE_TECHNICIAN_SECRET` env var or injected runtime secret hash)
///      verified in constant time. If unconfigured, fails closed (`403 TECHNICIAN_AUTH_NOT_CONFIGURED`).
/// 3. Enforces monotonic clock guard and strict fail-closed expiration (`exp <= now` is EXPIRED).
class TechnicianService {
  final DbClient db;
  final TransactionManager txManager;
  final FacilityConfigService facilityConfigService;
  final DateTime Function() clock;
  final Duration clockDriftTolerance;
  final String? securityRootDirectory;
  final String? installationSecretHashOverride;
  final MaintenanceTokenService maintenanceTokenService;
  final TrustedTimeVerifier trustedTimeVerifier;

  final Map<String, TrustedTimeChallenge> _pendingChallenges = <String, TrustedTimeChallenge>{};
  static const _uuid = Uuid();

  TechnicianService(
    this.db, {
    required this.facilityConfigService,
    DateTime Function()? clock,
    this.clockDriftTolerance = const Duration(seconds: 5),
    this.securityRootDirectory,
    this.installationSecretHashOverride,
    MaintenanceTokenService? maintenanceTokenService,
    TrustedTimeVerifier? trustedTimeVerifier,
  })  : txManager = TransactionManager(db),
        clock = clock ?? (() => DateTime.now().toUtc()),
        maintenanceTokenService = maintenanceTokenService ?? MaintenanceTokenService(),
        trustedTimeVerifier = trustedTimeVerifier ?? TrustedTimeVerifier.production();

  /// Issues a cryptographic Trusted-Time Challenge for offline RSA authority verification
  /// (used for Clock Rollback Recovery or RSA-signed Technician Session tokens).
  Future<Map<String, dynamic>> createTrustedTimeChallenge({
    required String hospitalCode,
  }) async {
    final config = await facilityConfigService.getConfiguration(hospitalCode);
    final challenge = trustedTimeVerifier.createChallenge(
      hospitalCode: hospitalCode,
      installationId: config.installationIdentity,
    );
    final challengeId = 'TTC-${_uuid.v4()}';
    if (_pendingChallenges.length > 100) {
      _pendingChallenges.remove(_pendingChallenges.keys.first);
    }
    _pendingChallenges[challengeId] = challenge;
    return {
      'challengeId': challengeId,
      'authorityRequest': challenge.toAuthorityRequest(),
    };
  }

  /// Opens an isolated Technician Service session (`mc_technician_sessions`).
  Future<Map<String, dynamic>> openSession({
    required String hospitalCode,
    required String deviceId,
    String? installationTechnicianSecret,
    String? rawAuthorityToken,
    String? challengeId,
    String? rawTrustedTimeResponse,
    String? ipAddress,
  }) async {
    return await txManager.runInTransaction((tx) async {
      final govRepo = TenantGovernanceRepository(tx);
      final tenant = await govRepo.findTenant(hospitalCode);
      if (tenant == null || tenant['status'] != 'active') {
        throw AuthException('INVALID_TENANT', 'Hospital tenant $hospitalCode is invalid or inactive.', 403);
      }

      // Evaluate monotonic clock guard
      final clockRepo = ClockGuardRepository(tx, securityRootDirectory: securityRootDirectory);
      final ClockEvaluationResult? clockEval;
      if (rawAuthorityToken != null && rawAuthorityToken.trim().isNotEmpty) {
        // RSA Authority token carries cryptographic trusted-time evidence and recovery authorization
        clockEval = null;
      } else {
        try {
          clockEval = await clockRepo.evaluateAndUpdateClock(
            hospitalCode: hospitalCode,
            currentWallClock: clock(),
            driftTolerance: clockDriftTolerance,
          );
        } on ClockTamperException catch (e) {
          throw AuthException('CLOCK_TAMPER_DETECTED', 'Clock guard integrity violated: ${e.message}', 403);
        }
        if (clockEval.rollbackDetected) {
          throw AuthException(
            'CLOCK_ROLLBACK_DETECTED',
            'Clock rollback active (${clockEval.rollbackDeltaSeconds}s). Execute clock recovery before opening standard technician config session.',
            403,
          );
        }
      }

      final facilityCfg = await facilityConfigService.getConfiguration(hospitalCode, executor: tx);
      late final String authMethod;
      String? consumedNonce;

      if (rawAuthorityToken != null && rawAuthorityToken.trim().isNotEmpty) {
        if (challengeId == null ||
            rawTrustedTimeResponse == null ||
            !_pendingChallenges.containsKey(challengeId)) {
          throw AuthException(
            'TRUSTED_TIME_CHALLENGE_REQUIRED',
            'RSA authority technician token requires a valid challengeId and signed MC_TIME_V1 response.',
            403,
          );
        }
        final challenge = _pendingChallenges.remove(challengeId)!;
        final TrustedTimeEvidence evidence;
        try {
          evidence = trustedTimeVerifier.verifyResponse(
            challenge: challenge,
            rawResponse: rawTrustedTimeResponse,
          );
        } on TrustedTimeEvidenceException catch (e) {
          throw AuthException(e.code, e.message, 403);
        }

        final MaintenanceUnlockToken parsed;
        try {
          parsed = maintenanceTokenService.verifyAndParseToken(
            rawToken: rawAuthorityToken,
            expectedHospitalCode: hospitalCode,
            expectedInstallationId: facilityCfg.installationIdentity,
            trustedTimeEvidence: evidence,
            trustedTimeVerifier: trustedTimeVerifier,
            allowedActions: const {'TECHNICIAN_SERVICE_MODE', 'TECHNICIAN_RECOVERY'},
          );
        } on MaintenanceTokenException catch (e) {
          await govRepo.logSecurityEvent(
            hospitalCode: hospitalCode,
            deviceId: deviceId,
            eventType: 'technician.auth.rsa_token_rejected',
            severity: 'CRITICAL',
            details: {'code': e.code, 'message': e.message},
            ipAddress: ipAddress,
          );
          throw AuthException(e.code, e.message, 403);
        }

        // Prevent replay of technician authority token in mc_consumed_maintenance_tokens
        final replayCheck = await tx.execute(
          '''
          SELECT id FROM mc_consumed_maintenance_tokens
          WHERE hospital_code = :hosp AND nonce = :nonce
          LIMIT 1
          ''',
          {'hosp': hospitalCode, 'nonce': parsed.nonce},
        );
        if (replayCheck.rows.isNotEmpty) {
          throw AuthException(
            'TECHNICIAN_TOKEN_REPLAYED',
            'Authority technician token nonce has already been consumed.',
            403,
          );
        }

        await tx.execute(
          '''
          INSERT INTO mc_consumed_maintenance_tokens (
            hospital_code, installation_id, nonce, action, consumed_at_utc
          ) VALUES (
            :hosp, :inst, :nonce, :act, :now_utc
          )
          ''',
          {
            'hosp': hospitalCode,
            'inst': facilityCfg.installationIdentity,
            'nonce': parsed.nonce,
            'act': parsed.action,
            'now_utc': _fmtUtcMillis(evidence.trustedUtc),
          },
        );
        authMethod = 'AUTHORITY_RSA_TOKEN';
        consumedNonce = parsed.nonce;
      } else if (installationTechnicianSecret != null &&
          installationTechnicianSecret.trim().isNotEmpty) {
        final expectedHash = _resolveExpectedInstallationSecretHash();
        if (expectedHash == null || expectedHash.isEmpty) {
          await govRepo.logSecurityEvent(
            hospitalCode: hospitalCode,
            deviceId: deviceId,
            eventType: 'technician.auth.unconfigured_installation_secret',
            severity: 'HIGH',
            ipAddress: ipAddress,
          );
          throw AuthException(
            'TECHNICIAN_AUTH_NOT_CONFIGURED',
            'Technician installation secret is not provisioned in MEDCORE_TECHNICIAN_SECRET. Use a signed MC_MAINT_V1 authority token or provision installation secret.',
            403,
          );
        }

        final verified = PasswordHasher.verifyPassword(
          installationTechnicianSecret,
          expectedHash,
        );
        if (!verified) {
          await govRepo.logSecurityEvent(
            hospitalCode: hospitalCode,
            deviceId: deviceId,
            eventType: 'technician.auth.invalid_secret',
            severity: 'CRITICAL',
            ipAddress: ipAddress,
          );
          throw AuthException(
            'INVALID_TECHNICIAN_CREDENTIALS',
            'Invalid Technician Service credentials.',
            403,
          );
        }
        authMethod = 'INSTALLATION_TECH_SECRET';
        if (_firstRunSecretSlipFile.existsSync()) {
          try {
            _firstRunSecretSlipFile.deleteSync();
          } catch (_) {}
        }
      } else {
        throw AuthException(
          'MISSING_TECHNICIAN_CREDENTIALS',
          'Provide either a signed MC_MAINT_V1 technician authority token or installation technician secret.',
          401,
        );
      }

      final rawTechToken = 'mct_${PasswordHasher.generateSecureToken(32)}';
      final tokenSha256 = PasswordHasher.sha256Hex(rawTechToken);
      final sessionUuid = 'TECH-SES-${_uuid.v4()}';
      final issuedAt = (clockEval?.effectiveTime ?? clock()).toUtc();
      final expiresAt = issuedAt.add(const Duration(minutes: 45));

      await tx.execute(
        '''
        INSERT INTO mc_technician_sessions (
          session_uuid, token_sha256, hospital_code, auth_method,
          authority_token_nonce, device_id, ip_address,
          issued_at, expires_at, is_active
        ) VALUES (
          :uuid, :sha, :hosp, :method,
          :nonce, :dev, :ip,
          :iat, :exp, 1
        )
        ''',
        {
          'uuid': sessionUuid,
          'sha': tokenSha256,
          'hosp': hospitalCode,
          'method': authMethod,
          'nonce': consumedNonce,
          'dev': deviceId,
          'ip': ipAddress,
          'iat': _fmtUtcMillis(issuedAt),
          'exp': _fmtUtcMillis(expiresAt),
        },
      );

      await tx.writeAuditLog(
        hospitalCode: hospitalCode,
        actorRole: 'TECHNICIAN_SERVICE',
        deviceId: deviceId,
        action: 'technician.session.opened',
        entityType: 'mc_technician_sessions',
        entityId: sessionUuid,
        afterState: {
          'authMethod': authMethod,
          'expiresAt': expiresAt.toIso8601String(),
          'deviceId': deviceId,
        },
        ipAddress: ipAddress,
      );

      return {
        'technicianToken': rawTechToken,
        'session': TechnicianSessionContext(
          sessionUuid: sessionUuid,
          hospitalCode: hospitalCode,
          authMethod: authMethod,
          deviceId: deviceId,
          issuedAt: issuedAt,
          expiresAt: expiresAt,
        ).toJson(),
      };
    });
  }

  /// Verifies an isolated Technician session (`X-MedCore-Tech-Token`).
  /// Rejects ordinary hospital user tokens (`mcd_...`) fail-closed!
  Future<TechnicianSessionContext> verifyTechnicianSession({
    required String? rawTechToken,
    required String requestedHospitalCode,
    required String requestedDeviceId,
    String? routePath,
    String? ipAddress,
  }) async {
    final cleanToken = (rawTechToken ?? '').trim();
    if (cleanToken.isEmpty || !cleanToken.startsWith('mct_')) {
      final govRepo = TenantGovernanceRepository(db);
      if (requestedHospitalCode.isNotEmpty) {
        await govRepo.logSecurityEvent(
          hospitalCode: requestedHospitalCode,
          deviceId: requestedDeviceId,
          eventType: 'technician.access.denied_non_technician_caller',
          severity: 'HIGH',
          routePath: routePath,
          details: {'hasToken': cleanToken.isNotEmpty},
          ipAddress: ipAddress,
        );
      }
      throw AuthException(
        'TECHNICIAN_SESSION_REQUIRED',
        'Protected Technician / Service Mode requires an isolated X-MedCore-Tech-Token. Ordinary hospital staff roles cannot access Technician endpoints.',
        403,
      );
    }

    final clockEval = await txManager.runInTransaction((tx) async {
      final clockRepo = ClockGuardRepository(tx, securityRootDirectory: securityRootDirectory);
      return await clockRepo.evaluateAndUpdateClock(
        hospitalCode: requestedHospitalCode,
        currentWallClock: clock(),
        driftTolerance: clockDriftTolerance,
      );
    });
    if (clockEval.rollbackDetected) {
      throw AuthException(
        'CLOCK_ROLLBACK_DETECTED',
        'Clock rollback detected; technician configuration session blocked until clock recovery.',
        403,
      );
    }

    final tokenSha = PasswordHasher.sha256Hex(cleanToken);
    final res = await db.execute(
      '''
      SELECT * FROM mc_technician_sessions
      WHERE token_sha256 = :sha LIMIT 1
      ''',
      {'sha': tokenSha},
    );
    if (res.rows.isEmpty) {
      throw AuthException('INVALID_TECHNICIAN_SESSION', 'Technician session is unknown or invalid.', 403);
    }

    final r = res.rows.first;
    final isActive = (r.colByName('is_active') ?? '0') == '1' && r.colByName('revoked_at') == null;
    final hosp = r.colByName('hospital_code') ?? '';
    final dev = r.colByName('device_id') ?? '';
    final issuedAt = _parseDbUtc(r.colByName('issued_at') ?? '');
    final expiresAt = _parseDbUtc(r.colByName('expires_at') ?? '');
    final nowUtc = clockEval.effectiveTime.toUtc();

    if (!isActive || hosp != requestedHospitalCode || dev != requestedDeviceId) {
      throw AuthException(
        'TECHNICIAN_SESSION_BINDING_MISMATCH',
        'Technician session is revoked or bound to a different tenant/device.',
        403,
      );
    }

    // Strict Trusted-Time boundary: exp <= now is EXPIRED
    if (nowUtc.isAfter(expiresAt) || nowUtc.isAtSameMomentAs(expiresAt)) {
      await db.execute(
        'UPDATE mc_technician_sessions SET is_active = 0 WHERE token_sha256 = :sha',
        {'sha': tokenSha},
      );
      throw AuthException('TECHNICIAN_SESSION_EXPIRED', 'Technician session has expired.', 403);
    }

    return TechnicianSessionContext(
      sessionUuid: r.colByName('session_uuid') ?? '',
      hospitalCode: hosp,
      authMethod: r.colByName('auth_method') ?? 'INSTALLATION_TECH_SECRET',
      deviceId: dev,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
    );
  }

  Future<void> closeSession(String? rawTechToken) async {
    final clean = (rawTechToken ?? '').trim();
    if (clean.isEmpty) return;
    final sha = PasswordHasher.sha256Hex(clean);
    await db.execute(
      '''
      UPDATE mc_technician_sessions
      SET is_active = 0, revoked_at = CURRENT_TIMESTAMP(3)
      WHERE token_sha256 = :sha
      ''',
      {'sha': sha},
    );
  }

  /// Executes cryptographic Clock Rollback Recovery using existing verified `ClockGuardRepository`.
  Future<Map<String, dynamic>> recoverClockRollback({
    required String hospitalCode,
    required String challengeId,
    required String rawTrustedTimeResponse,
    required String rawMaintenanceToken,
    String? expectedInstallationIdOverride,
  }) async {
    if (!_pendingChallenges.containsKey(challengeId)) {
      throw AuthException('INVALID_TIME_CHALLENGE', 'Unknown or expired challengeId.', 403);
    }
    final challenge = _pendingChallenges.remove(challengeId)!;
    final TrustedTimeEvidence evidence;
    try {
      evidence = trustedTimeVerifier.verifyResponse(
        challenge: challenge,
        rawResponse: rawTrustedTimeResponse,
      );
    } on TrustedTimeEvidenceException catch (e) {
      throw AuthException(e.code, e.message, 403);
    }

    final cfg = await facilityConfigService.getConfiguration(hospitalCode);
    final instId = (expectedInstallationIdOverride != null &&
            expectedInstallationIdOverride.trim().isNotEmpty)
        ? expectedInstallationIdOverride.trim()
        : cfg.installationIdentity;

    final record = await txManager.runInTransaction((tx) async {
      final repo = ClockGuardRepository(
        tx,
        maintenanceTokenService: maintenanceTokenService,
        trustedTimeVerifier: trustedTimeVerifier,
        securityRootDirectory: securityRootDirectory,
      );
      return await repo.unlockWithMaintenanceToken(
        hospitalCode: hospitalCode,
        rawMaintenanceToken: rawMaintenanceToken,
        expectedInstallationId: instId,
        trustedTimeEvidence: evidence,
      );
    });

    return {
      'recovered': true,
      'hospitalCode': record.hospitalCode,
      'maxObservedUtc': record.maxObservedUtc.toIso8601String(),
      'rollbackDetected': record.rollbackDetected,
      'unlockedByTokenId': record.unlockedByMaintenanceTokenId,
    };
  }

  /// Rotates or sets a new technician installation secret in `technician_secret.json`.
  /// Requires active technician session context or cryptographically verified recovery.
  Future<Map<String, dynamic>> rotateTechnicianSecret({
    required String hospitalCode,
    String? newSecret,
    required String actorRole,
    String? deviceId,
    String? ipAddress,
  }) async {
    final secretToHash = (newSecret != null && newSecret.trim().isNotEmpty)
        ? newSecret.trim()
        : 'TECH-COMM-${PasswordHasher.generateSecureToken(16)}';

    if (secretToHash.length < 12) {
      throw ArgumentError('Technician installation secret must be at least 12 characters.');
    }

    final hash = PasswordHasher.hashPassword(secretToHash);
    final secDir = Directory(_resolveSecurityDir());
    if (!secDir.existsSync()) {
      secDir.createSync(recursive: true);
    }

    final nowUtc = clock().toUtc();
    final jsonPayload = jsonEncode({
      'technicianSecretHash': hash,
      'authType': 'LOCAL_INSTALLATION_SECRET',
      'provisionedAtUtc': nowUtc.toIso8601String(),
      'isOneTimeBootstrap': false,
      'rotatedByRole': actorRole,
    });
    _technicianSecretFile.writeAsStringSync(jsonPayload);

    // Consume any pending one-time slip file
    if (_firstRunSecretSlipFile.existsSync()) {
      try {
        _firstRunSecretSlipFile.deleteSync();
      } catch (_) {}
    }

    // Immutable audit log
    final txManager = TransactionManager(db);
    await txManager.runInTransaction((tx) async {
      await tx.writeAuditLog(
        hospitalCode: hospitalCode,
        actorRole: actorRole,
        deviceId: deviceId,
        action: 'technician.secret.rotated',
        entityType: 'technician_credential',
        entityId: 'LOCAL_INSTALLATION_SECRET',
        afterState: {
          'rotatedAt': nowUtc.toIso8601String(),
          'authType': 'LOCAL_INSTALLATION_SECRET',
        },
        ipAddress: ipAddress,
      );
    });

    return {
      'status': 'ROTATED',
      'secretFile': _technicianSecretFile.path,
      'newSecret': secretToHash,
      'rotatedAtUtc': nowUtc.toIso8601String(),
    };
  }

  /// Cryptographically authorizes technician credential recovery via signed RSA authority token.
  /// Enforces:
  /// - Trusted-time challenge-response verification
  /// - RSA-2048 signature verification under root authority public key
  /// - Installation and tenant binding
  /// - Nonce consumption and replay rejection
  /// - Invalidation of all prior technician sessions
  /// - Rotation of installation secret
  /// - Immutable audit record
  Future<Map<String, dynamic>> recoverTechnicianSecretWithAuthorityToken({
    required String hospitalCode,
    required String deviceId,
    required String challengeId,
    required String rawTrustedTimeResponse,
    required String rawAuthorityToken,
    String? newSecret,
    String? ipAddress,
  }) async {
    if (challengeId.isEmpty || !_pendingChallenges.containsKey(challengeId)) {
      throw AuthException(
        'TRUSTED_TIME_CHALLENGE_REQUIRED',
        'Valid challengeId is required for cryptographic recovery.',
        403,
      );
    }
    final challenge = _pendingChallenges.remove(challengeId)!;
    final TrustedTimeEvidence evidence;
    try {
      evidence = trustedTimeVerifier.verifyResponse(
        challenge: challenge,
        rawResponse: rawTrustedTimeResponse,
      );
    } on TrustedTimeEvidenceException catch (e) {
      throw AuthException(e.code, e.message, 403);
    }

    final facilityCfg = await facilityConfigService.getConfiguration(hospitalCode);
    final MaintenanceUnlockToken parsed;
    try {
      parsed = maintenanceTokenService.verifyAndParseToken(
        rawToken: rawAuthorityToken,
        expectedHospitalCode: hospitalCode,
        expectedInstallationId: facilityCfg.installationIdentity,
        trustedTimeEvidence: evidence,
        trustedTimeVerifier: trustedTimeVerifier,
        allowedActions: const {'TECHNICIAN_SERVICE_MODE', 'TECHNICIAN_RECOVERY'},
      );
    } on MaintenanceTokenException catch (e) {
      throw AuthException(e.code, e.message, 403);
    }

    // Atomic transaction for replay prevention, session invalidation, and audit log
    final txManager = TransactionManager(db);
    return await txManager.runInTransaction((tx) async {
      // Replay prevention
      final replayCheck = await tx.execute(
        'SELECT id FROM mc_consumed_maintenance_tokens WHERE hospital_code = :hosp AND nonce = :nonce LIMIT 1',
        {'hosp': hospitalCode, 'nonce': parsed.nonce},
      );
      if (replayCheck.rows.isNotEmpty) {
        throw AuthException(
          'TECHNICIAN_TOKEN_REPLAYED',
          'Authority recovery token nonce has already been consumed.',
          403,
        );
      }

      await tx.execute(
        '''
        INSERT INTO mc_consumed_maintenance_tokens (
          hospital_code, installation_id, nonce, action, consumed_at_utc
        ) VALUES (
          :hosp, :inst, :nonce, :act, :now_utc
        )
        ''',
        {
          'hosp': hospitalCode,
          'inst': facilityCfg.installationIdentity,
          'nonce': parsed.nonce,
          'act': parsed.action,
          'now_utc': _fmtUtcMillis(evidence.trustedUtc),
        },
      );

      // Invalidate all existing active technician sessions
      await tx.execute(
        'UPDATE mc_technician_sessions SET is_active = 0, revoked_at = CURRENT_TIMESTAMP WHERE hospital_code = :hosp AND is_active = 1',
        {'hosp': hospitalCode},
      );

      // Rotate technician secret
      final secretToHash = (newSecret != null && newSecret.trim().isNotEmpty)
          ? newSecret.trim()
          : 'TECH-COMM-${PasswordHasher.generateSecureToken(16)}';

      if (secretToHash.length < 12) {
        throw ArgumentError('Technician installation secret must be at least 12 characters.');
      }

      final hash = PasswordHasher.hashPassword(secretToHash);
      final secDir = Directory(_resolveSecurityDir());
      if (!secDir.existsSync()) {
        secDir.createSync(recursive: true);
      }

      final nowUtc = clock().toUtc();
      final jsonPayload = jsonEncode({
        'technicianSecretHash': hash,
        'authType': 'LOCAL_INSTALLATION_SECRET',
        'provisionedAtUtc': nowUtc.toIso8601String(),
        'isOneTimeBootstrap': false,
        'recoveredViaAuthorityToken': parsed.tokenId,
      });
      _technicianSecretFile.writeAsStringSync(jsonPayload);

      // Consume any old slip
      if (_firstRunSecretSlipFile.existsSync()) {
        try {
          _firstRunSecretSlipFile.deleteSync();
        } catch (_) {}
      }

      // Re-anchor security root if needed
      final clockRepo = ClockGuardRepository(
        tx,
        maintenanceTokenService: maintenanceTokenService,
        trustedTimeVerifier: trustedTimeVerifier,
        securityRootDirectory: securityRootDirectory,
      );
      await clockRepo.evaluateAndUpdateClock(
        hospitalCode: hospitalCode,
        currentWallClock: evidence.trustedUtc,
      );

      await tx.writeAuditLog(
        hospitalCode: hospitalCode,
        actorRole: 'TECHNICIAN_AUTHORITY_RECOVERY',
        deviceId: deviceId,
        action: 'technician.secret.recovered',
        entityType: 'technician_credential',
        entityId: parsed.tokenId,
        afterState: {
          'recoveredAt': nowUtc.toIso8601String(),
          'tokenId': parsed.tokenId,
          'nonce': parsed.nonce,
        },
        ipAddress: ipAddress,
      );

      return {
        'status': 'RECOVERED',
        'hospitalCode': hospitalCode,
        'newSecret': secretToHash,
        'temporarySecret': secretToHash,
        'temporaryTechnicianSecret': secretToHash,
        'tokenId': parsed.tokenId,
        'recoveredAtUtc': nowUtc.toIso8601String(),
      };
    });
  }

  String _resolveSecurityDir() {
    if (securityRootDirectory != null && securityRootDirectory!.trim().isNotEmpty) {
      return securityRootDirectory!.trim();
    }
    final envCustom = Platform.environment['MEDCORE_SECURITY_DIR']?.trim();
    if (envCustom != null && envCustom.isNotEmpty) {
      return envCustom;
    }
    final exeDir = p.dirname(Platform.resolvedExecutable);
    if (Directory(p.join(exeDir, 'sql', 'migrations')).existsSync()) {
      return p.join(exeDir, 'runtime', 'security');
    }
    if (Directory(p.join(Directory.current.path, 'service', 'sql', 'migrations')).existsSync()) {
      return p.join(Directory.current.path, 'service', 'runtime', 'security');
    }
    return p.join(Directory.current.path, 'runtime', 'security');
  }

  File get _technicianSecretFile => File(p.join(_resolveSecurityDir(), 'technician_secret.json'));
  File get _firstRunSecretSlipFile => File(p.join(_resolveSecurityDir(), 'FIRST_RUN_COMMISSIONING_SECRET.txt'));

  String? _resolveExpectedInstallationSecretHash() {
    if (installationSecretHashOverride != null &&
        installationSecretHashOverride!.trim().isNotEmpty) {
      return installationSecretHashOverride!.trim();
    }
    final envHash = Platform.environment['MEDCORE_TECHNICIAN_SECRET_HASH']?.trim();
    if (envHash != null && envHash.isNotEmpty) {
      return envHash;
    }
    final envPlain = Platform.environment['MEDCORE_TECHNICIAN_SECRET']?.trim();
    if (envPlain != null && envPlain.isNotEmpty) {
      return PasswordHasher.hashPassword(envPlain);
    }
    // Check local provisioned security file
    try {
      final file = _technicianSecretFile;
      if (file.existsSync()) {
        final content = file.readAsStringSync().trim();
        if (content.isNotEmpty) {
          final decoded = jsonDecode(content);
          if (decoded is Map && decoded['technicianSecretHash'] != null) {
            return decoded['technicianSecretHash'].toString().trim();
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Ensures that a technician installation secret is provisioned.
  /// If neither env vars nor technician_secret.json exist, this creates a secure,
  /// high-entropy first-run commissioning secret and writes:
  /// 1. `technician_secret.json` (PBKDF2 hash ONLY)
  /// 2. `FIRST_RUN_COMMISSIONING_SECRET.txt` (one-time secret for physical technician)
  Map<String, dynamic> ensureCommissioningSecretProvisioned({
    String? explicitSecret,
    bool forceRotate = false,
  }) {
    final existingHash = _resolveExpectedInstallationSecretHash();
    if (existingHash != null && existingHash.isNotEmpty && !forceRotate) {
      return {
        'status': 'ALREADY_PROVISIONED',
        'secretFile': _technicianSecretFile.path,
        'isNewlyGenerated': false,
      };
    }

    final plainSecret = (explicitSecret != null && explicitSecret.trim().isNotEmpty)
        ? explicitSecret.trim()
        : 'TECH-COMM-${PasswordHasher.generateSecureToken(16)}';

    if (plainSecret.length < 12) {
      throw ArgumentError('Technician commissioning secret must be at least 12 characters.');
    }

    final hash = PasswordHasher.hashPassword(plainSecret);
    final secDir = Directory(_resolveSecurityDir());
    if (!secDir.existsSync()) {
      secDir.createSync(recursive: true);
    }

    final nowUtc = clock().toUtc();
    final jsonPayload = jsonEncode({
      'technicianSecretHash': hash,
      'authType': 'LOCAL_INSTALLATION_SECRET',
      'provisionedAtUtc': nowUtc.toIso8601String(),
      'isOneTimeBootstrap': explicitSecret == null,
    });
    _technicianSecretFile.writeAsStringSync(jsonPayload);

    if (explicitSecret == null) {
      final slipContent = '''
================================================================================
MEDCORE PLATINUM DESKTOP — ONE-TIME FIRST-RUN TECHNICIAN COMMISSIONING SECRET
================================================================================
Generated At (UTC)    : ${nowUtc.toIso8601String()}
Commissioning Secret  : $plainSecret

OPERATIONAL INSTRUCTIONS:
1. Launch MedCore Desktop on this workstation.
2. Click "Technician / Service Installation Gate" on the connection screen.
3. Enter the Commissioning Secret above into the Installation Technician Secret field.
4. Open the Technician Console to configure the facility and provision the
   initial Hospital Administrator account.
5. This physical one-time slip file is automatically consumed upon first successful authentication.
================================================================================
''';
      _firstRunSecretSlipFile.writeAsStringSync(slipContent);
    }

    return {
      'status': 'PROVISIONED',
      'secret': plainSecret,
      'secretFile': _technicianSecretFile.path,
      'slipFile': explicitSecret == null ? _firstRunSecretSlipFile.path : null,
      'isNewlyGenerated': true,
    };
  }

  static String _fmtUtcMillis(DateTime dt) {
    final u = dt.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    return '${u.year}-${two(u.month)}-${two(u.day)} ${two(u.hour)}:${two(u.minute)}:${two(u.second)}.${three(u.millisecond)}';
  }

  static DateTime _parseDbUtc(String raw) {
    final clean = raw.trim().replaceFirst(' ', 'T');
    return DateTime.parse(clean.endsWith('Z') ? clean : '${clean}Z').toUtc();
  }
}
