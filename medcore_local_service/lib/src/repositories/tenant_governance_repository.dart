import 'dart:convert';
import '../db/db_client.dart';
import 'clock_guard_repository.dart';
import '../security/trusted_time_evidence.dart';

class DeviceRecord {
  final int id;
  final String hospitalCode;
  final String deviceId;
  final String deviceName;
  final String platform;
  final String hwFingerprintSha256;
  final String devicePublicKeyEd25519;
  final String roleScope;
  final bool isTrustedSecureRuntime;
  final String status;

  const DeviceRecord({
    required this.id,
    required this.hospitalCode,
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.hwFingerprintSha256,
    required this.devicePublicKeyEd25519,
    required this.roleScope,
    required this.isTrustedSecureRuntime,
    required this.status,
  });

  bool get isActive => status.toUpperCase() == 'ACTIVE';
}

class TenantGovernanceRepository {
  final SqlExecutor db;

  TenantGovernanceRepository(this.db);

  Future<void> upsertTenant({
    required String hospitalCode,
    required String name,
    String defaultCurrency = 'EGP',
    bool enforceScreenProtection = true,
    bool requireOpenShift = true,
    Map<String, dynamic>? settings,
  }) async {
    await db.execute(
      '''
      INSERT INTO mc_tenants (
        hospital_code, name, default_currency,
        enforce_screen_protection, require_open_shift, status, settings_json
      ) VALUES (
        :code, :name, :curr, :esp, :ros, 'active', :settings
      )
      ON DUPLICATE KEY UPDATE
        name = VALUES(name),
        default_currency = VALUES(default_currency),
        enforce_screen_protection = VALUES(enforce_screen_protection),
        require_open_shift = VALUES(require_open_shift),
        settings_json = VALUES(settings_json)
      ''',
      {
        'code': hospitalCode,
        'name': name,
        'curr': defaultCurrency,
        'esp': enforceScreenProtection ? 1 : 0,
        'ros': requireOpenShift ? 1 : 0,
        'settings': settings != null ? jsonEncode(settings) : null,
      },
    );
  }

  Future<Map<String, dynamic>?> findTenant(String hospitalCode) async {
    final res = await db.execute(
      'SELECT * FROM mc_tenants WHERE hospital_code = :code LIMIT 1',
      {'code': hospitalCode},
    );
    if (res.rows.isEmpty) return null;
    final r = res.rows.first;
    return {
      'id': int.parse(r.colByName('id') ?? '0'),
      'hospitalCode': r.colByName('hospital_code'),
      'name': r.colByName('name'),
      'defaultCurrency': r.colByName('default_currency') ?? 'EGP',
      'enforceScreenProtection': (r.colByName('enforce_screen_protection') ?? '1') == '1',
      'requireOpenShift': (r.colByName('require_open_shift') ?? '1') == '1',
      'status': r.colByName('status') ?? 'active',
    };
  }

  Future<DeviceRecord> enrollOrUpdateDevice({
    required String hospitalCode,
    required String deviceId,
    required String deviceName,
    String platform = 'WINDOWS',
    required String hwFingerprintSha256,
    required String devicePublicKeyEd25519,
    String roleScope = 'WORKSTATION',
    bool isTrustedSecureRuntime = true,
    String status = 'ACTIVE',
  }) async {
    await db.execute(
      '''
      INSERT INTO mc_devices (
        hospital_code, device_id, device_name, platform,
        hw_fingerprint_sha256, device_public_key_ed25519,
        role_scope, is_trusted_secure_runtime, status, last_seen_at
      ) VALUES (
        :hosp, :dev_id, :name, :platform,
        :fp, :pubkey,
        :scope, :trusted, :status, CURRENT_TIMESTAMP
      )
      ON DUPLICATE KEY UPDATE
        device_name = VALUES(device_name),
        hw_fingerprint_sha256 = VALUES(hw_fingerprint_sha256),
        is_trusted_secure_runtime = VALUES(is_trusted_secure_runtime),
        status = VALUES(status),
        last_seen_at = CURRENT_TIMESTAMP
      ''',
      {
        'hosp': hospitalCode,
        'dev_id': deviceId,
        'name': deviceName,
        'platform': platform,
        'fp': hwFingerprintSha256,
        'pubkey': devicePublicKeyEd25519,
        'scope': roleScope,
        'trusted': isTrustedSecureRuntime ? 1 : 0,
        'status': status,
      },
    );
    return (await findDeviceById(deviceId))!;
  }

  Future<DeviceRecord?> findDeviceById(String deviceId) async {
    final res = await db.execute(
      'SELECT * FROM mc_devices WHERE device_id = :dev_id LIMIT 1',
      {'dev_id': deviceId},
    );
    if (res.rows.isEmpty) return null;
    final r = res.rows.first;
    return DeviceRecord(
      id: int.parse(r.colByName('id') ?? '0'),
      hospitalCode: r.colByName('hospital_code') ?? '',
      deviceId: r.colByName('device_id') ?? '',
      deviceName: r.colByName('device_name') ?? '',
      platform: r.colByName('platform') ?? 'WINDOWS',
      hwFingerprintSha256: r.colByName('hw_fingerprint_sha256') ?? '',
      devicePublicKeyEd25519: r.colByName('device_public_key_ed25519') ?? '',
      roleScope: r.colByName('role_scope') ?? 'WORKSTATION',
      isTrustedSecureRuntime: (r.colByName('is_trusted_secure_runtime') ?? '0') == '1',
      status: r.colByName('status') ?? 'PENDING',
    );
  }

  Future<int> logSecurityEvent({
    required String hospitalCode,
    int? staffId,
    String? deviceId,
    required String eventType,
    String severity = 'WARNING',
    String? routePath,
    String? requiredPermission,
    Map<String, dynamic>? details,
    String? ipAddress,
  }) async {
    final res = await db.execute(
      '''
      INSERT INTO mc_security_logs (
        hospital_code, staff_id, device_id, event_type,
        severity, route_path, required_permission, details_json, ip_address
      ) VALUES (
        :hosp, :staff_id, :dev_id, :etype,
        :sev, :route, :perm, :details, :ip
      )
      ''',
      {
        'hosp': hospitalCode,
        'staff_id': staffId,
        'dev_id': deviceId,
        'etype': eventType,
        'sev': severity,
        'route': routePath,
        'perm': requiredPermission,
        'details': details != null ? jsonEncode(details) : null,
        'ip': ipAddress,
      },
    );
    return res.lastInsertID.toInt();
  }

  Future<int> createDualControlRequest({
    required String requestUuid,
    required String hospitalCode,
    required String actionType,
    required String targetEntityType,
    required String targetEntityId,
    required String requestedAmountDecimal,
    required Map<String, dynamic> payload,
    required int requesterStaffId,
    String? reason,
  }) async {
    final res = await db.execute(
      '''
      INSERT INTO mc_dual_control_request (
        request_uuid, hospital_code, action_type, target_entity_type,
        target_entity_id, requested_amount, payload_json,
        requester_staff_id, status, reason
      ) VALUES (
        :uuid, :hosp, :atype, :etype,
        :eid, :amt, :payload,
        :req_id, 'PENDING', :reason
      )
      ''',
      {
        'uuid': requestUuid,
        'hosp': hospitalCode,
        'atype': actionType,
        'etype': targetEntityType,
        'eid': targetEntityId,
        'amt': requestedAmountDecimal,
        'payload': jsonEncode(payload),
        'req_id': requesterStaffId,
        'reason': reason,
      },
    );
    return res.lastInsertID.toInt();
  }

  Future<ClockGuardRecord?> getClockGuard(String hospitalCode) async {
    return ClockGuardRepository(db).getClockGuard(hospitalCode);
  }

  Future<ClockGuardRecord> unlockClockWithMaintenanceToken({
    required String hospitalCode,
    required String rawMaintenanceToken,
    required String expectedInstallationId,
    required TrustedTimeEvidence trustedTimeEvidence,
  }) async {
    return ClockGuardRepository(db).unlockWithMaintenanceToken(
      hospitalCode: hospitalCode,
      rawMaintenanceToken: rawMaintenanceToken,
      expectedInstallationId: expectedInstallationId,
      trustedTimeEvidence: trustedTimeEvidence,
    );
  }
}
