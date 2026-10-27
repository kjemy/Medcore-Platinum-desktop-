import 'dart:convert';
import '../db/db_client.dart';
import '../security/permissions_catalog.dart';
import 'scope_context.dart';

class StaffRecord {
  final StaffIdentity identity;
  final String passwordHash;

  const StaffRecord({
    required this.identity,
    required this.passwordHash,
  });
}

class AuthSessionRecord {
  final int id;
  final String sessionUuid;
  final String tokenSha256;
  final String hospitalCode;
  final int staffId;
  final String deviceId;
  final String roleSnapshot;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final bool isActive;

  const AuthSessionRecord({
    required this.id,
    required this.sessionUuid,
    required this.tokenSha256,
    required this.hospitalCode,
    required this.staffId,
    required this.deviceId,
    required this.roleSnapshot,
    required this.issuedAt,
    required this.expiresAt,
    required this.isActive,
  });
}

class StaffIdentityRepository {
  final SqlExecutor db;

  StaffIdentityRepository(this.db);

  Future<StaffIdentity> createStaff({
    required String hospitalCode,
    required String staffCode,
    required String fullName,
    required String email,
    String? phone,
    String? nationalId,
    required String passwordHash,
    required MedCoreRole role,
    String? departmentId,
    String? clinicId,
    String? doctorDefinitionCode,
    String? specialty,
    String permissionsMode = 'default',
    Set<String>? customPermissions,
    Set<String>? securePageLocks,
    OperationalFlags? operationalFlags,
    String baseSalaryDecimal = '0.0000',
    bool isActive = true,
  }) async {
    final flags = operationalFlags ?? PermissionsCatalog.defaultFlagsForRole(role);
    final res = await db.execute(
      '''
      INSERT INTO mc_staff (
        hospital_code, staff_code, full_name, email, phone, national_id,
        password_hash, role, department_id, clinic_id, doctor_definition_code,
        specialty, permissions_mode, custom_permissions_json, secure_permissions_json,
        can_edit, can_delete, can_collect_money, can_make_refunds, refund_policy,
        base_salary, status, is_active
      ) VALUES (
        :hosp, :code, :name, :email, :phone, :nid,
        :pwd, :role, :dept, :clinic, :doc_code,
        :spec, :pmode, :cperms, :sperms,
        :cedit, :cdel, :ccollect, :crefund, :rpolicy,
        :salary, :status, :active
      )
      ''',
      {
        'hosp': hospitalCode,
        'code': staffCode,
        'name': fullName,
        'email': email.toLowerCase().trim(),
        'phone': phone,
        'nid': nationalId,
        'pwd': passwordHash,
        'role': role.name,
        'dept': departmentId,
        'clinic': clinicId,
        'doc_code': doctorDefinitionCode,
        'spec': specialty,
        'pmode': permissionsMode == 'custom' ? 'custom' : 'default',
        'cperms': customPermissions != null ? jsonEncode(customPermissions.toList()) : null,
        'sperms': securePageLocks != null ? jsonEncode(securePageLocks.toList()) : null,
        'cedit': flags.canEdit ? 1 : 0,
        'cdel': flags.canDelete ? 1 : 0,
        'ccollect': flags.canCollectMoney ? 1 : 0,
        'crefund': flags.canMakeRefunds ? 1 : 0,
        'rpolicy': flags.refundPolicy.name,
        'salary': baseSalaryDecimal,
        'status': isActive ? 'active' : 'inactive',
        'active': isActive ? 1 : 0,
      },
    );
    final id = res.lastInsertID.toInt();
    return (await findById(hospitalCode, id))!.identity;
  }

  Future<StaffRecord?> findById(String hospitalCode, int id) async {
    final res = await db.execute(
      'SELECT * FROM mc_staff WHERE hospital_code = :hosp AND id = :id LIMIT 1',
      {'hosp': hospitalCode, 'id': id},
    );
    if (res.rows.isEmpty) return null;
    return _mapRow(res.rows.first);
  }

  Future<StaffRecord?> findByEmailOrCode(String hospitalCode, String identifier) async {
    final clean = identifier.trim();
    final res = await db.execute(
      '''
      SELECT * FROM mc_staff
      WHERE hospital_code = :hosp AND (LOWER(email) = LOWER(:id) OR staff_code = :id)
      LIMIT 1
      ''',
      {'hosp': hospitalCode, 'id': clean},
    );
    if (res.rows.isEmpty) return null;
    return _mapRow(res.rows.first);
  }

  Future<List<StaffIdentity>> listByTenant(String hospitalCode) async {
    final res = await db.execute(
      'SELECT * FROM mc_staff WHERE hospital_code = :hosp ORDER BY id ASC',
      {'hosp': hospitalCode},
    );
    return res.rows.map((r) => _mapRow(r).identity).toList();
  }

  Future<StaffIdentity> updatePermissionsAndFlags({
    required String hospitalCode,
    required int staffId,
    required String permissionsMode,
    Set<String>? customPermissions,
    Set<String>? securePageLocks,
    OperationalFlags? operationalFlags,
  }) async {
    final current = await findById(hospitalCode, staffId);
    if (current == null) {
      throw StateError('Staff $staffId not found in tenant $hospitalCode');
    }
    final flags = operationalFlags ?? current.identity.operationalFlags;
    await db.execute(
      '''
      UPDATE mc_staff
      SET permissions_mode = :pmode,
          custom_permissions_json = :cperms,
          secure_permissions_json = :sperms,
          can_edit = :cedit,
          can_delete = :cdel,
          can_collect_money = :ccollect,
          can_make_refunds = :crefund,
          refund_policy = :rpolicy
      WHERE hospital_code = :hosp AND id = :id
      ''',
      {
        'pmode': permissionsMode == 'custom' ? 'custom' : 'default',
        'cperms': customPermissions != null ? jsonEncode(customPermissions.toList()) : null,
        'sperms': securePageLocks != null ? jsonEncode(securePageLocks.toList()) : null,
        'cedit': flags.canEdit ? 1 : 0,
        'cdel': flags.canDelete ? 1 : 0,
        'ccollect': flags.canCollectMoney ? 1 : 0,
        'crefund': flags.canMakeRefunds ? 1 : 0,
        'rpolicy': flags.refundPolicy.name,
        'hosp': hospitalCode,
        'id': staffId,
      },
    );
    return (await findById(hospitalCode, staffId))!.identity;
  }

  StaffRecord _mapRow(dynamic r) {
    final role = MedCoreRole.fromString(r.colByName('role') ?? 'Employee');
    final customRaw = r.colByName('custom_permissions_json');
    final secureRaw = r.colByName('secure_permissions_json');

    Set<String> parseSet(String? raw) {
      if (raw == null || raw.trim().isEmpty) return <String>{};
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toSet();
        }
      } catch (_) {}
      return <String>{};
    }

    final flags = OperationalFlags(
      canEdit: (r.colByName('can_edit') ?? '1') == '1',
      canDelete: (r.colByName('can_delete') ?? '0') == '1',
      canCollectMoney: (r.colByName('can_collect_money') ?? '0') == '1',
      canMakeRefunds: (r.colByName('can_make_refunds') ?? '0') == '1',
      refundPolicy: RefundPolicy.fromString(r.colByName('refund_policy')),
    );

    final identity = StaffIdentity(
      id: int.parse(r.colByName('id') ?? '0'),
      hospitalCode: r.colByName('hospital_code') ?? '',
      staffCode: r.colByName('staff_code') ?? '',
      fullName: r.colByName('full_name') ?? '',
      email: r.colByName('email') ?? '',
      phone: r.colByName('phone'),
      nationalId: r.colByName('national_id'),
      role: role,
      departmentId: r.colByName('department_id'),
      clinicId: r.colByName('clinic_id'),
      doctorDefinitionCode: r.colByName('doctor_definition_code'),
      specialty: r.colByName('specialty'),
      permissionsMode: r.colByName('permissions_mode') ?? 'default',
      customPermissions: parseSet(customRaw),
      securePageLocks: parseSet(secureRaw),
      operationalFlags: flags,
      isActive: (r.colByName('is_active') ?? '1') == '1',
    );

    return StaffRecord(
      identity: identity,
      passwordHash: r.colByName('password_hash') ?? '',
    );
  }
}

class AuthSessionRepository {
  final SqlExecutor db;

  AuthSessionRepository(this.db);

  Future<AuthSessionRecord> createSession({
    required String sessionUuid,
    required String tokenSha256,
    required String hospitalCode,
    required int staffId,
    required String deviceId,
    required String roleSnapshot,
    String? ipAddress,
    Duration ttl = const Duration(hours: 12),
    DateTime? nowUtc,
  }) async {
    final now = nowUtc ?? DateTime.now().toUtc();
    final expires = now.add(ttl);
    final fmtNow = _fmtDt(now);
    final fmtExp = _fmtDt(expires);

    await db.execute(
      '''
      INSERT INTO mc_auth_sessions (
        session_uuid, token_sha256, hospital_code, staff_id,
        device_id, role_snapshot, ip_address, issued_at, expires_at,
        last_activity_at, is_active
      ) VALUES (
        :uuid, :tsha, :hosp, :staff_id,
        :dev_id, :role, :ip, :now, :exp,
        :now, 1
      )
      ''',
      {
        'uuid': sessionUuid,
        'tsha': tokenSha256,
        'hosp': hospitalCode,
        'staff_id': staffId,
        'dev_id': deviceId,
        'role': roleSnapshot,
        'ip': ipAddress,
        'now': fmtNow,
        'exp': fmtExp,
      },
    );
    return (await findByTokenSha256(tokenSha256))!;
  }

  Future<AuthSessionRecord?> findByTokenSha256(String tokenSha256) async {
    final res = await db.execute(
      'SELECT * FROM mc_auth_sessions WHERE token_sha256 = :tsha LIMIT 1',
      {'tsha': tokenSha256},
    );
    if (res.rows.isEmpty) return null;
    final r = res.rows.first;
    return AuthSessionRecord(
      id: int.parse(r.colByName('id') ?? '0'),
      sessionUuid: r.colByName('session_uuid') ?? '',
      tokenSha256: r.colByName('token_sha256') ?? '',
      hospitalCode: r.colByName('hospital_code') ?? '',
      staffId: int.parse(r.colByName('staff_id') ?? '0'),
      deviceId: r.colByName('device_id') ?? '',
      roleSnapshot: r.colByName('role_snapshot') ?? '',
      issuedAt: DateTime.tryParse('${r.colByName('issued_at')}Z') ?? DateTime.now().toUtc(),
      expiresAt: DateTime.tryParse('${r.colByName('expires_at')}Z') ?? DateTime.now().toUtc(),
      isActive: (r.colByName('is_active') ?? '0') == '1',
    );
  }

  Future<void> revokeSessionByTokenSha256(String tokenSha256, String reason) async {
    await db.execute(
      '''
      UPDATE mc_auth_sessions
      SET is_active = 0, revoked_at = CURRENT_TIMESTAMP, revoke_reason = :reason
      WHERE token_sha256 = :tsha
      ''',
      {'tsha': tokenSha256, 'reason': reason},
    );
  }

  static String _fmtDt(DateTime dt) {
    final u = dt.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year}-${two(u.month)}-${two(u.day)} ${two(u.hour)}:${two(u.minute)}:${two(u.second)}';
  }
}
