import '../db/db_client.dart';
import '../db/transaction_manager.dart';
import '../repositories/tenant_governance_repository.dart';
import '../security/password_hasher.dart';
import 'facility_config_service.dart';

class NetworkDeviceService {
  static const List<String> allowedConnectionTypes = ['LOOPBACK', 'LAN', 'WIFI'];
  static const List<String> allowedRoleScopes = [
    'SERVER_HOST',
    'WORKSTATION',
    'TABLET_CLINICAL',
    'KIOSK',
  ];
  static const List<String> allowedPlatforms = ['WINDOWS', 'ANDROID', 'IPAD'];

  final DbClient db;
  final TransactionManager txManager;
  final FacilityConfigService facilityConfigService;

  NetworkDeviceService(
    this.db, {
    required this.facilityConfigService,
  }) : txManager = TransactionManager(db);

  /// Public-safe LAN/Wi-Fi Discovery Handshake Metadata (does NOT expose clinical/financial data
  /// and grants ZERO authorization — strictly satisfies `Discovery != Authorization`).
  Future<Map<String, dynamic>> getDiscoveryDescriptor({
    required String hospitalCode,
  }) async {
    final cfg = await facilityConfigService.getConfiguration(hospitalCode);
    final allowLan = cfg.networkConfig['allowLanConnections'] == true;
    final allowWifi = cfg.networkConfig['allowWifiConnections'] == true;

    return {
      'hospitalCode': cfg.hospitalCode,
      'facilityName': cfg.facilityName,
      'edition': cfg.edition,
      'medcoreServiceVersion': '1.0.0-rc.1',
      'supportedModes': [
        'LOOPBACK',
        if (allowLan) 'CONNECT_VIA_LAN',
        if (allowWifi) 'CONNECT_VIA_WIFI',
      ],
      'securityBoundary': {
        'discoveryGrantsAuthorization': false,
        'explicitPairingRequired': true,
        'unauthenticatedEndpointsExposed': false,
        'mariaDbExposedOverNetwork': false,
        'tlsCertificateInfrastructure': 'TLS_CERT_INFRASTRUCTURE_PENDING',
      },
    };
  }

  /// Registers an untrusted device pairing request (`status = 'PENDING'`).
  /// Grants ZERO API or login access until explicitly approved by an authorized admin/technician.
  Future<Map<String, dynamic>> requestDevicePairing({
    required String hospitalCode,
    required String deviceId,
    required String deviceName,
    required String connectionType, // 'LAN' | 'WIFI' | 'LOOPBACK'
    String platform = 'WINDOWS',
    String roleScope = 'WORKSTATION',
    String medcoreVersion = '1.0.0-rc.1',
    required String hwFingerprintSha256,
    required String devicePublicKeyEd25519,
    String? ipAddress,
  }) async {
    final cleanHosp = hospitalCode.trim();
    final cleanDevId = deviceId.trim();
    final cleanName = deviceName.trim();
    final cleanConn = connectionType.trim().toUpperCase();
    final cleanPlat = platform.trim().toUpperCase();
    final cleanRole = roleScope.trim().toUpperCase();

    if (cleanHosp.isEmpty || cleanDevId.isEmpty || cleanName.isEmpty) {
      throw ArgumentError('hospitalCode, deviceId, and deviceName are required.');
    }
    if (!allowedConnectionTypes.contains(cleanConn)) {
      throw ArgumentError('Invalid connectionType "$cleanConn". Allowed: ${allowedConnectionTypes.join(', ')}');
    }
    if (!allowedPlatforms.contains(cleanPlat)) {
      throw ArgumentError('Invalid platform "$cleanPlat". Allowed: ${allowedPlatforms.join(', ')}');
    }
    if (!allowedRoleScopes.contains(cleanRole)) {
      throw ArgumentError('Invalid roleScope "$cleanRole". Allowed: ${allowedRoleScopes.join(', ')}');
    }
    if (hwFingerprintSha256.trim().length < 16 || devicePublicKeyEd25519.trim().isEmpty) {
      throw ArgumentError('Hardware fingerprint (SHA-256) and device Ed25519 public key are required.');
    }

    return await txManager.runInTransaction((tx) async {
      final govRepo = TenantGovernanceRepository(tx);
      final tenant = await govRepo.findTenant(cleanHosp);
      if (tenant == null || tenant['status'] != 'active') {
        throw StateError('Hospital tenant $cleanHosp is invalid or inactive.');
      }

      final cfg = await facilityConfigService.getConfiguration(cleanHosp, executor: tx);
      if (cleanConn == 'LAN' && cfg.networkConfig['allowLanConnections'] != true) {
        throw StateError('CONNECT VIA LAN is disabled by facility network policy.');
      }
      if (cleanConn == 'WIFI' && cfg.networkConfig['allowWifiConnections'] != true) {
        throw StateError('CONNECT VIA WI-FI is disabled by facility network policy.');
      }

      final existing = await govRepo.findDeviceById(cleanDevId);
      if (existing != null && existing.hospitalCode != cleanHosp) {
        throw StateError('Device identifier $cleanDevId is already bound to another tenant.');
      }
      if (existing != null && existing.status.toUpperCase() == 'REVOKED') {
        await govRepo.logSecurityEvent(
          hospitalCode: cleanHosp,
          deviceId: cleanDevId,
          eventType: 'network.pairing.rejected_revoked_device',
          severity: 'CRITICAL',
          ipAddress: ipAddress,
        );
        throw StateError('Device $cleanDevId has been REVOKED and cannot self-re-enroll.');
      }
      if (existing != null && existing.isActive) {
        return {
          'deviceId': existing.deviceId,
          'status': existing.status,
          'alreadyActive': true,
          'authorizationGranted': true,
        };
      }

      // Generate a 6-character alphanumeric pairing verification code; store ONLY its SHA-256 hash
      final rawToken = PasswordHasher.generateSecureToken(6).toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), 'A');
      final pairingCode = rawToken.substring(0, 6);
      final pairingCodeSha = PasswordHasher.sha256Hex(pairingCode);

      await tx.execute(
        '''
        INSERT INTO mc_devices (
          hospital_code, device_id, device_name, platform, connection_type,
          hw_fingerprint_sha256, device_public_key_ed25519,
          role_scope, medcore_version, is_trusted_secure_runtime,
          status, last_seen_at, last_ip, pairing_code_sha256, pairing_requested_at
        ) VALUES (
          :hosp, :dev_id, :name, :plat, :conn,
          :fp, :pub,
          :role, :ver, :trusted,
          'PENDING', CURRENT_TIMESTAMP, :ip, :code_sha, CURRENT_TIMESTAMP
        )
        ON DUPLICATE KEY UPDATE
          device_name = VALUES(device_name),
          platform = VALUES(platform),
          connection_type = VALUES(connection_type),
          hw_fingerprint_sha256 = VALUES(hw_fingerprint_sha256),
          device_public_key_ed25519 = VALUES(device_public_key_ed25519),
          role_scope = VALUES(role_scope),
          medcore_version = VALUES(medcore_version),
          status = 'PENDING',
          last_seen_at = CURRENT_TIMESTAMP,
          last_ip = VALUES(last_ip),
          pairing_code_sha256 = VALUES(pairing_code_sha256),
          pairing_requested_at = CURRENT_TIMESTAMP
        ''',
        {
          'hosp': cleanHosp,
          'dev_id': cleanDevId,
          'name': cleanName,
          'plat': cleanPlat,
          'conn': cleanConn,
          'fp': hwFingerprintSha256.trim(),
          'pub': devicePublicKeyEd25519.trim(),
          'role': cleanRole,
          'ver': medcoreVersion.trim(),
          'trusted': cleanRole == 'KIOSK' ? 0 : 1,
          'ip': ipAddress ?? '127.0.0.1',
          'code_sha': pairingCodeSha,
        },
      );

      await govRepo.logSecurityEvent(
        hospitalCode: cleanHosp,
        deviceId: cleanDevId,
        eventType: 'network.pairing.requested',
        severity: 'INFO',
        details: {
          'deviceName': cleanName,
          'connectionType': cleanConn,
          'roleScope': cleanRole,
          'medcoreVersion': medcoreVersion,
        },
        ipAddress: ipAddress,
      );

      return {
        'deviceId': cleanDevId,
        'deviceName': cleanName,
        'connectionType': cleanConn,
        'status': 'PENDING',
        'authorizationGranted': false,
        'pairingVerificationCode': pairingCode,
        'instructions':
            'Present this pairing code to an authorized Hospital Admin or MedCore Technician on the Main Host to approve device enrollment.',
      };
    });
  }

  /// Returns full network topology and device table for authorized viewers.
  Future<Map<String, dynamic>> getTopologyAndDevices({
    required String hospitalCode,
  }) async {
    final cfg = await facilityConfigService.getConfiguration(hospitalCode);
    final res = await db.execute(
      '''
      SELECT id, hospital_code, device_id, device_name, platform, connection_type,
             hw_fingerprint_sha256, device_public_key_ed25519, role_scope, medcore_version,
             is_trusted_secure_runtime, status, last_seen_at, last_ip, approved_by,
             pairing_code_sha256, pairing_requested_at
      FROM mc_devices
      WHERE hospital_code = :hosp
      ORDER BY FIELD(status, 'PENDING', 'ACTIVE', 'SUSPENDED', 'REVOKED'), id ASC
      ''',
      {'hosp': hospitalCode},
    );

    final devices = res.rows
        .map((r) => {
              'id': int.tryParse(r.colByName('id') ?? '0') ?? 0,
              'hospitalCode': r.colByName('hospital_code'),
              'deviceId': r.colByName('device_id'),
              'deviceName': r.colByName('device_name'),
              'ip': r.colByName('last_ip') ?? '127.0.0.1',
              'platform': r.colByName('platform'),
              'connectionType': r.colByName('connection_type') ?? 'LOOPBACK',
              'status': r.colByName('status'),
              'medcoreVersion': r.colByName('medcore_version') ?? '1.0.0-rc.1',
              'role': r.colByName('role_scope'),
              'isTrustedSecureRuntime':
                  (r.colByName('is_trusted_secure_runtime') ?? '0') == '1',
              'lastSeen': r.colByName('last_seen_at'),
              'approvedByStaffId': r.colByName('approved_by') != null
                  ? int.tryParse(r.colByName('approved_by')!)
                  : null,
              'requiresPairingCodeVerification':
                  r.colByName('status') == 'PENDING' &&
                      (r.colByName('pairing_code_sha256') ?? '').isNotEmpty,
              'pairingRequestedAt': r.colByName('pairing_requested_at'),
            })
        .toList();

    final dbLoopback =
        db.config.host == '127.0.0.1' || db.config.host.toLowerCase() == 'localhost';

    return {
      'hospitalCode': hospitalCode,
      'connectionModes': {
        'connectViaLanEnabled': cfg.networkConfig['allowLanConnections'] == true,
        'connectViaWifiEnabled': cfg.networkConfig['allowWifiConnections'] == true,
        'maxAuthorizedDevices': cfg.networkConfig['maxAuthorizedDevices'] ?? 25,
      },
      'securityPosture': {
        'discoveryEqualsAuthorization': false,
        'mariaDbHost': db.config.host,
        'mariaDbPort': db.config.port,
        'mariaDbLoopbackOnlyEnforced': dbLoopback,
        'unauthenticatedServiceAccessAllowed': false,
        'tlsCertificateRuntimeStatus': 'TLS_CERT_INFRASTRUCTURE_PENDING',
        'tlsNotice':
            'mTLS / TLS X.509 certificate authority runtime provisioning is pending. Do not bind service over untrusted networks without TLS termination.',
      },
      'summary': {
        'totalDevices': devices.length,
        'activeCount': devices.where((d) => d['status'] == 'ACTIVE').length,
        'pendingCount': devices.where((d) => d['status'] == 'PENDING').length,
        'revokedCount': devices.where((d) => d['status'] == 'REVOKED').length,
      },
      'devices': devices,
    };
  }

  /// Approves a `PENDING` (or `SUSPENDED`) device into `ACTIVE` status.
  Future<Map<String, dynamic>> approveDevice({
    required String hospitalCode,
    required String targetDeviceId,
    String? pairingVerificationCode,
    bool isTrustedSecureRuntime = true,
    String? roleScopeOverride,
    int? approvedByStaffId,
    required String actorRoleLabel,
    String? actorDeviceId,
    String? ipAddress,
  }) async {
    return await txManager.runInTransaction((tx) async {
      final cfg = await facilityConfigService.getConfiguration(hospitalCode, executor: tx);
      final maxDevices = (cfg.networkConfig['maxAuthorizedDevices'] is int)
          ? cfg.networkConfig['maxAuthorizedDevices'] as int
          : 25;

      final activeCountRes = await tx.execute(
        '''
        SELECT COUNT(*) AS cnt FROM mc_devices
        WHERE hospital_code = :hosp AND status = 'ACTIVE' AND device_id != :dev
        ''',
        {'hosp': hospitalCode, 'dev': targetDeviceId},
      );
      final activeCount =
          int.tryParse(activeCountRes.rows.first.colByName('cnt') ?? '0') ?? 0;
      if (activeCount >= maxDevices) {
        throw StateError(
          'Maximum authorized device limit ($maxDevices) reached for facility $hospitalCode.',
        );
      }

      final devRes = await tx.execute(
        '''
        SELECT * FROM mc_devices
        WHERE hospital_code = :hosp AND device_id = :dev
        FOR UPDATE
        ''',
        {'hosp': hospitalCode, 'dev': targetDeviceId},
      );
      if (devRes.rows.isEmpty) {
        throw StateError('Device $targetDeviceId not found for tenant $hospitalCode.');
      }

      final row = devRes.rows.first;
      final expectedCodeSha = row.colByName('pairing_code_sha256');
      if (expectedCodeSha != null && expectedCodeSha.trim().isNotEmpty) {
        final provided = (pairingVerificationCode ?? '').trim().toUpperCase();
        if (provided.isEmpty ||
            !_constantTimeHexEquals(PasswordHasher.sha256Hex(provided), expectedCodeSha)) {
          throw ArgumentError(
            'INVALID_PAIRING_CODE: Valid 6-character pairing verification code from the target device is required to approve pairing.',
          );
        }
      }

      final nextRole = (roleScopeOverride != null &&
              allowedRoleScopes.contains(roleScopeOverride.trim().toUpperCase()))
          ? roleScopeOverride.trim().toUpperCase()
          : (row.colByName('role_scope') ?? 'WORKSTATION');

      await tx.execute(
        '''
        UPDATE mc_devices
        SET status = 'ACTIVE',
            role_scope = :role,
            is_trusted_secure_runtime = :trusted,
            approved_by = :approver,
            pairing_code_sha256 = NULL
        WHERE hospital_code = :hosp AND device_id = :dev
        ''',
        {
          'role': nextRole,
          'trusted': (nextRole == 'KIOSK' ? false : isTrustedSecureRuntime) ? 1 : 0,
          'approver': approvedByStaffId,
          'hosp': hospitalCode,
          'dev': targetDeviceId,
        },
      );

      await tx.writeAuditLog(
        hospitalCode: hospitalCode,
        actorStaffId: approvedByStaffId,
        actorRole: actorRoleLabel,
        deviceId: actorDeviceId,
        action: 'network.device.approved',
        entityType: 'mc_devices',
        entityId: targetDeviceId,
        afterState: {
          'status': 'ACTIVE',
          'roleScope': nextRole,
          'connectionType': row.colByName('connection_type'),
        },
        ipAddress: ipAddress,
      );

      final updated = await TenantGovernanceRepository(tx).findDeviceById(targetDeviceId);
      return updated!.toJson();
    });
  }

  /// Revokes a device (`status = 'REVOKED'`) and immediately terminates all active
  /// staff and technician sessions bound to that device.
  Future<Map<String, dynamic>> revokeDevice({
    required String hospitalCode,
    required String targetDeviceId,
    int? revokedByStaffId,
    required String actorRoleLabel,
    String? actorDeviceId,
    String? reason,
    String? ipAddress,
  }) async {
    return await txManager.runInTransaction((tx) async {
      final devRes = await tx.execute(
        '''
        SELECT status FROM mc_devices
        WHERE hospital_code = :hosp AND device_id = :dev
        FOR UPDATE
        ''',
        {'hosp': hospitalCode, 'dev': targetDeviceId},
      );
      if (devRes.rows.isEmpty) {
        throw StateError('Device $targetDeviceId not found for tenant $hospitalCode.');
      }

      await tx.execute(
        '''
        UPDATE mc_devices
        SET status = 'REVOKED', pairing_code_sha256 = NULL
        WHERE hospital_code = :hosp AND device_id = :dev
        ''',
        {'hosp': hospitalCode, 'dev': targetDeviceId},
      );

      // Immediately kill active staff sessions for this device
      await tx.execute(
        '''
        UPDATE mc_auth_sessions
        SET is_active = 0, revoked_at = CURRENT_TIMESTAMP
        WHERE hospital_code = :hosp AND device_id = :dev AND is_active = 1
        ''',
        {'hosp': hospitalCode, 'dev': targetDeviceId},
      );

      // Immediately kill active technician sessions for this device
      await tx.execute(
        '''
        UPDATE mc_technician_sessions
        SET is_active = 0, revoked_at = CURRENT_TIMESTAMP(3)
        WHERE hospital_code = :hosp AND device_id = :dev AND is_active = 1
        ''',
        {'hosp': hospitalCode, 'dev': targetDeviceId},
      );

      await tx.writeAuditLog(
        hospitalCode: hospitalCode,
        actorStaffId: revokedByStaffId,
        actorRole: actorRoleLabel,
        deviceId: actorDeviceId,
        action: 'network.device.revoked',
        entityType: 'mc_devices',
        entityId: targetDeviceId,
        afterState: {
          'status': 'REVOKED',
          if (reason != null) 'reason': reason,
        },
        ipAddress: ipAddress,
      );

      return {
        'deviceId': targetDeviceId,
        'status': 'REVOKED',
        'sessionsTerminated': true,
      };
    });
  }

  static bool _constantTimeHexEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
