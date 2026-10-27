import 'package:uuid/uuid.dart';
import '../db/transaction_manager.dart';
import '../repositories/clock_guard_repository.dart';
import '../repositories/scope_context.dart';
import '../repositories/staff_auth_repository.dart';
import '../repositories/tenant_governance_repository.dart';
import 'password_hasher.dart';
import 'rbac_evaluator.dart';

class AuthException implements Exception {
  final String code;
  final String message;
  final int statusCode;

  AuthException(this.code, this.message, [this.statusCode = 401]);

  @override
  String toString() => 'AuthException($code, HTTP $statusCode): $message';
}

class AuthenticatedRequestContext {
  final AuthSessionRecord session;
  final StaffIdentity staff;
  final DeviceRecord device;
  final Set<String> effectivePermissions;

  const AuthenticatedRequestContext({
    required this.session,
    required this.staff,
    required this.device,
    required this.effectivePermissions,
  });
}

class AuthService {
  final TransactionManager txManager;
  final DateTime Function() clock;
  final Duration clockDriftTolerance;
  final String? securityRootDirectory;
  static const _uuid = Uuid();

  AuthService(
    this.txManager, {
    DateTime Function()? clock,
    this.clockDriftTolerance = const Duration(seconds: 5),
    this.securityRootDirectory,
  }) : clock = clock ?? (() => DateTime.now().toUtc());

  Future<Map<String, dynamic>> login({
    required String hospitalCode,
    required String identifier,
    required String password,
    required String deviceId,
    String? ipAddress,
  }) async {
    return await txManager.runInTransaction((tx) async {
      final govRepo = TenantGovernanceRepository(tx);
      final staffRepo = StaffIdentityRepository(tx);
      final sessionRepo = AuthSessionRepository(tx);

      // 1. Verify Tenant
      final tenant = await govRepo.findTenant(hospitalCode);
      if (tenant == null || tenant['status'] != 'active') {
        await govRepo.logSecurityEvent(
          hospitalCode: hospitalCode,
          deviceId: deviceId,
          eventType: 'auth.login.invalid_tenant',
          severity: 'WARNING',
          ipAddress: ipAddress,
        );
        throw AuthException('INVALID_TENANT', 'Hospital tenant $hospitalCode is invalid or inactive.', 403);
      }

      // 2. Verify Enrolled Device (Closes SEC-FLAW-05)
      final device = await govRepo.findDeviceById(deviceId);
      if (device == null || !device.isActive || device.hospitalCode != hospitalCode) {
        await govRepo.logSecurityEvent(
          hospitalCode: hospitalCode,
          deviceId: deviceId,
          eventType: 'auth.login.unverified_device',
          severity: 'HIGH',
          details: {'reason': device == null ? 'not_enrolled' : 'status=${device.status}, hosp=${device.hospitalCode}'},
          ipAddress: ipAddress,
        );
        throw AuthException(
          'DEVICE_NOT_VERIFIED',
          'Device $deviceId is not enrolled or not active for hospital $hospitalCode.',
          403,
        );
      }

      // 3. Verify Employee Identity in mc_staff
      final staffRec = await staffRepo.findByEmailOrCode(hospitalCode, identifier);
      if (staffRec == null || !staffRec.identity.isActive) {
        await govRepo.logSecurityEvent(
          hospitalCode: hospitalCode,
          deviceId: deviceId,
          eventType: 'auth.login.unknown_or_inactive_user',
          severity: 'WARNING',
          details: {'identifier': identifier},
          ipAddress: ipAddress,
        );
        throw AuthException('INVALID_CREDENTIALS', 'Invalid employee credentials.', 401);
      }

      // 4. Verify Password Hash (PBKDF2-HMAC-SHA256)
      if (!PasswordHasher.verifyPassword(password, staffRec.passwordHash)) {
        await govRepo.logSecurityEvent(
          hospitalCode: hospitalCode,
          staffId: staffRec.identity.id,
          deviceId: deviceId,
          eventType: 'auth.login.bad_password',
          severity: 'WARNING',
          ipAddress: ipAddress,
        );
        throw AuthException('INVALID_CREDENTIALS', 'Invalid employee credentials.', 401);
      }

      // Evaluate Monotonic Clock Guard inside the login transaction
      final clockRepo = ClockGuardRepository(tx, securityRootDirectory: securityRootDirectory);
      final ClockEvaluationResult clockEval;
      try {
        clockEval = await clockRepo.evaluateAndUpdateClock(
          hospitalCode: hospitalCode,
          currentWallClock: clock(),
          driftTolerance: clockDriftTolerance,
        );
      } on ClockTamperException catch (e) {
        await govRepo.logSecurityEvent(
          hospitalCode: hospitalCode,
          deviceId: deviceId,
          eventType: 'security.clock_guard_tamper_detected',
          severity: 'CRITICAL',
          details: {
            'error': e.message,
            'currentWallClock': clock().toIso8601String(),
          },
          ipAddress: ipAddress,
        );
        throw AuthException(
          'CLOCK_TAMPER_DETECTED',
          'System clock guard integrity violated: ${e.message}',
          403,
        );
      }

      if (clockEval.rollbackDetected) {
        await govRepo.logSecurityEvent(
          hospitalCode: hospitalCode,
          deviceId: deviceId,
          eventType: 'auth.login.clock_rollback_detected',
          severity: 'CRITICAL',
          details: {
            'effectiveTime': clockEval.effectiveTime.toIso8601String(),
            'currentWallClock': clock().toIso8601String(),
            'rollbackDeltaSeconds': clockEval.rollbackDeltaSeconds,
          },
          ipAddress: ipAddress,
        );
        throw AuthException(
          'CLOCK_ROLLBACK_DETECTED',
          'System clock rollback detected: host clock is behind high-water mark (${clockEval.rollbackDeltaSeconds}s delta).',
          403,
        );
      }

      // 5. Issue Tenant- & Device-Bound Session Token (Closes SEC-FLAW-03)
      final rawToken = ' mcd_${PasswordHasher.generateSecureToken(32)}'.trim();
      final tokenSha256 = PasswordHasher.sha256Hex(rawToken);
      final sessionUuid = 'SES-${_uuid.v4()}';

      final session = await sessionRepo.createSession(
        sessionUuid: sessionUuid,
        tokenSha256: tokenSha256,
        hospitalCode: hospitalCode,
        staffId: staffRec.identity.id,
        deviceId: deviceId,
        roleSnapshot: staffRec.identity.role.name,
        ipAddress: ipAddress,
        nowUtc: clockEval.effectiveTime,
      );

      await tx.execute(
        'UPDATE mc_staff SET last_login_at = CURRENT_TIMESTAMP WHERE id = :id',
        {'id': staffRec.identity.id},
      );

      final effectivePerms = RbacEvaluator.resolveEffectivePermissions(staffRec.identity);

      await tx.writeAuditLog(
        hospitalCode: hospitalCode,
        actorStaffId: staffRec.identity.id,
        actorRole: staffRec.identity.role.name,
        deviceId: deviceId,
        action: 'auth.login',
        entityType: 'mc_auth_sessions',
        entityId: session.sessionUuid,
        afterState: {
          'staffCode': staffRec.identity.staffCode,
          'role': staffRec.identity.role.name,
          'permissionsMode': staffRec.identity.permissionsMode,
          'deviceId': deviceId,
        },
        ipAddress: ipAddress,
      );

      return {
        'token': rawToken,
        'sessionUuid': session.sessionUuid,
        'expiresAt': session.expiresAt.toIso8601String(),
        'device': {
          'deviceId': device.deviceId,
          'platform': device.platform,
          'isTrustedSecureRuntime': device.isTrustedSecureRuntime,
        },
        'user': staffRec.identity.toPublicJson(effectivePerms),
      };
    });
  }

  Future<AuthenticatedRequestContext> verifySession({
    required String rawToken,
    required String requestedHospitalCode,
    required String requestedDeviceId,
    String? routePath,
    String? ipAddress,
  }) async {
    // 1. Evaluate Monotonic Clock Guard for the requested tenant first
    final ClockEvaluationResult clockEval;
    try {
      clockEval = await txManager.runInTransaction((tx) async {
        final clockRepo = ClockGuardRepository(tx, securityRootDirectory: securityRootDirectory);
        return await clockRepo.evaluateAndUpdateClock(
          hospitalCode: requestedHospitalCode,
          currentWallClock: clock(),
          driftTolerance: clockDriftTolerance,
        );
      });
    } on ClockTamperException catch (e) {
      final govRepo = TenantGovernanceRepository(txManager.db);
      await govRepo.logSecurityEvent(
        hospitalCode: requestedHospitalCode,
        deviceId: requestedDeviceId,
        eventType: 'security.clock_guard_tamper_detected',
        severity: 'CRITICAL',
        details: {
          'error': e.message,
          'currentWallClock': clock().toIso8601String(),
        },
        ipAddress: ipAddress,
      );
      throw AuthException(
        'CLOCK_TAMPER_DETECTED',
        'System clock guard integrity violated: ${e.message}',
        403,
      );
    }

    final tokenSha256 = PasswordHasher.sha256Hex(rawToken.trim());
    final sessionRepo = AuthSessionRepository(txManager.db);
    final staffRepo = StaffIdentityRepository(txManager.db);
    final govRepo = TenantGovernanceRepository(txManager.db);

    final session = await sessionRepo.findByTokenSha256(tokenSha256);
    if (session == null || !session.isActive) {
      throw AuthException('INVALID_SESSION', 'Session token is invalid or revoked.', 401);
    }

    // Monotonic Expiration Invariant:
    // If effective monotonic time is at or after session expiration, session is permanently expired.
    // Backward host clock movement CANNOT reduce effective time!
    if (clockEval.effectiveTime.isAfter(session.expiresAt) ||
        clockEval.effectiveTime.isAtSameMomentAs(session.expiresAt)) {
      await sessionRepo.revokeSessionByTokenSha256(tokenSha256, 'EXPIRED');
      throw AuthException('SESSION_EXPIRED', 'Session token has expired.', 401);
    }

    // Enforce Clock Tamper Invariant:
    // If wall clock rollback exceeds drift tolerance, reject request and log critical tamper event
    if (clockEval.rollbackDetected) {
      await govRepo.logSecurityEvent(
        hospitalCode: requestedHospitalCode,
        staffId: session.staffId,
        deviceId: requestedDeviceId,
        eventType: 'security.clock_rollback_detected',
        severity: 'CRITICAL',
        routePath: routePath,
        details: {
          'effectiveTime': clockEval.effectiveTime.toIso8601String(),
          'currentWallClock': clock().toIso8601String(),
          'rollbackDeltaSeconds': clockEval.rollbackDeltaSeconds,
        },
        ipAddress: ipAddress,
      );
      throw AuthException(
        'CLOCK_ROLLBACK_DETECTED',
        'System clock rollback detected: host clock is behind high-water mark (${clockEval.rollbackDeltaSeconds}s delta).',
        403,
      );
    }

    // Strict Tenant Binding Check (Closes SEC-FLAW-03)
    if (session.hospitalCode != requestedHospitalCode) {
      await govRepo.logSecurityEvent(
        hospitalCode: requestedHospitalCode,
        staffId: session.staffId,
        deviceId: requestedDeviceId,
        eventType: 'auth.cross_tenant_token_replay',
        severity: 'CRITICAL',
        routePath: routePath,
        details: {
          'tokenHospitalCode': session.hospitalCode,
          'requestedHospitalCode': requestedHospitalCode,
        },
        ipAddress: ipAddress,
      );
      throw AuthException(
        'TENANT_BINDING_MISMATCH',
        'Session token is bound to ${session.hospitalCode}, cannot access $requestedHospitalCode.',
        403,
      );
    }

    // Strict Device Binding Check (Closes SEC-FLAW-03 & SEC-FLAW-05)
    if (session.deviceId != requestedDeviceId) {
      await govRepo.logSecurityEvent(
        hospitalCode: requestedHospitalCode,
        staffId: session.staffId,
        deviceId: requestedDeviceId,
        eventType: 'auth.cross_device_token_replay',
        severity: 'HIGH',
        routePath: routePath,
        details: {
          'tokenDeviceId': session.deviceId,
          'requestedDeviceId': requestedDeviceId,
        },
        ipAddress: ipAddress,
      );
      throw AuthException(
        'DEVICE_BINDING_MISMATCH',
        'Session token is bound to device ${session.deviceId}, rejected on $requestedDeviceId.',
        403,
      );
    }

    final device = await govRepo.findDeviceById(requestedDeviceId);
    if (device == null || !device.isActive || device.hospitalCode != requestedHospitalCode) {
      throw AuthException('DEVICE_REVOKED', 'Device $requestedDeviceId is no longer active.', 403);
    }

    final staffRec = await staffRepo.findById(requestedHospitalCode, session.staffId);
    if (staffRec == null || !staffRec.identity.isActive) {
      throw AuthException('USER_INACTIVE', 'Employee account is inactive.', 403);
    }

    final effectivePerms = RbacEvaluator.resolveEffectivePermissions(staffRec.identity);
    return AuthenticatedRequestContext(
      session: session,
      staff: staffRec.identity,
      device: device,
      effectivePermissions: effectivePerms,
    );
  }

  Future<void> logout(String rawToken) async {
    final tokenSha256 = PasswordHasher.sha256Hex(rawToken.trim());
    final sessionRepo = AuthSessionRepository(txManager.db);
    await sessionRepo.revokeSessionByTokenSha256(tokenSha256, 'USER_LOGOUT');
  }
}
