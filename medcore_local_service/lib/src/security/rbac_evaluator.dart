import '../repositories/scope_context.dart';
import 'permissions_catalog.dart';

class RbacForbiddenException implements Exception {
  final String code;
  final String message;
  final String? requiredPermission;

  RbacForbiddenException({
    required this.code,
    required this.message,
    this.requiredPermission,
  });

  @override
  String toString() => 'RbacForbiddenException($code): $message';
}

class RbacEvaluator {
  /// Resolves the authoritative set of UI permissions for [staff].
  /// Closes SEC-FLAW-01: 'default' mode strictly returns `defaultRolePermissions[staff.role]`
  /// and NEVER synthesizes wildcard '*' for non-admin users.
  static Set<String> resolveEffectivePermissions(StaffIdentity staff) {
    if (!staff.isActive) return const <String>{};

    if (staff.role == MedCoreRole.SuperAdmin) {
      return {...PermissionsCatalog.all261Permissions};
    }

    if (staff.role == MedCoreRole.HospitalAdmin) {
      final baseAndAll = <String>{
        ...PermissionsCatalog.basePermissions,
        ...PermissionsCatalog.allScopePermissions,
        ...staff.securePageLocks,
      };
      return baseAndAll;
    }

    if (staff.permissionsMode.toLowerCase() == 'custom') {
      // Strip any accidental '*' wildcard from non-admin custom permissions
      return staff.customPermissions.where((p) => p != '*').toSet();
    }

    // Default mode: strictly evaluate role default permissions (NO wildcard bypass!)
    final defaults = PermissionsCatalog.defaultRolePermissions[staff.role] ?? const <String>{};
    return {...defaults, ...staff.securePageLocks};
  }

  /// Checks whether [staff] has access to [permission] (supports both UI keys and backend dot-notation keys).
  static bool hasPermission(StaffIdentity staff, String permission) {
    if (!staff.isActive) return false;
    if (staff.role == MedCoreRole.SuperAdmin || staff.role == MedCoreRole.HospitalAdmin) {
      return true;
    }

    final effective = resolveEffectivePermissions(staff);

    // Direct UI permission match (or _all implies base permission)
    if (effective.contains(permission) || effective.contains('${permission}_all')) {
      return true;
    }

    // Backend dot-notation permission translation (e.g., 'patients.read', 'lab.verify')
    final mappedUiKeys = PermissionsCatalog.backendToUiPermissions[permission];
    if (mappedUiKeys != null) {
      for (final uiKey in mappedUiKeys) {
        if (effective.contains(uiKey) || effective.contains('${uiKey}_all')) {
          return true;
        }
      }
    }

    return false;
  }

  /// Resolves Dimension 2 (`_all` vs Individual/Own Scope) for [basePermission].
  static DataScopeMode resolveDataScope(StaffIdentity staff, String basePermission) {
    if (staff.role == MedCoreRole.SuperAdmin || staff.role == MedCoreRole.HospitalAdmin) {
      return DataScopeMode.tenantWide;
    }
    final effective = resolveEffectivePermissions(staff);
    final cleanBase = basePermission.endsWith('_all')
        ? basePermission.substring(0, basePermission.length - 4)
        : (basePermission.endsWith('_secure')
            ? basePermission.substring(0, basePermission.length - 7)
            : basePermission);

    if (effective.contains('${cleanBase}_all')) {
      return DataScopeMode.tenantWide;
    }

    // If a backend dot-notation key was passed, check if any mapped UI key has `_all`
    final mappedUiKeys = PermissionsCatalog.backendToUiPermissions[cleanBase];
    if (mappedUiKeys != null) {
      for (final uiKey in mappedUiKeys) {
        if (effective.contains('${uiKey}_all')) {
          return DataScopeMode.tenantWide;
        }
      }
    }

    return DataScopeMode.ownOnly;
  }

  /// Resolves Dimension 3 (`_secure` Page / Device Lock) for [basePermission].
  static bool requiresSecureDevice(
    StaffIdentity staff,
    String basePermission, {
    Set<String> tenantSecureLocks = const <String>{},
  }) {
    final cleanBase = basePermission.endsWith('_all')
        ? basePermission.substring(0, basePermission.length - 4)
        : (basePermission.endsWith('_secure')
            ? basePermission.substring(0, basePermission.length - 7)
            : basePermission);
    final secureKey = '${cleanBase}_secure';

    if (staff.securePageLocks.contains(secureKey) ||
        staff.customPermissions.contains(secureKey) ||
        tenantSecureLocks.contains(secureKey)) {
      return true;
    }

    final mappedUiKeys = PermissionsCatalog.backendToUiPermissions[cleanBase];
    if (mappedUiKeys != null) {
      for (final uiKey in mappedUiKeys) {
        final mappedSecure = '${uiKey}_secure';
        if (staff.securePageLocks.contains(mappedSecure) ||
            staff.customPermissions.contains(mappedSecure) ||
            tenantSecureLocks.contains(mappedSecure)) {
          return true;
        }
      }
    }

    return false;
  }

  /// Enforces all 3 RBAC Dimensions + Operational Action Flags and returns an authoritative [ScopeContext].
  static ScopeContext enforceAndBuildScope({
    required StaffIdentity staff,
    required String deviceId,
    required bool isTrustedSecureDevice,
    required String requiredPermission,
    Set<String> tenantSecureLocks = const <String>{},
    bool requireCanEdit = false,
    bool requireCanDelete = false,
    bool requireCanCollectMoney = false,
    bool requireCanMakeRefunds = false,
    String? correlationId,
    String? ipAddress,
  }) {
    // 1. Dimension 1: Base Permission Check
    if (!hasPermission(staff, requiredPermission)) {
      throw RbacForbiddenException(
        code: 'PERMISSION_DENIED',
        message:
            'Role ${staff.role.name} (mode=${staff.permissionsMode}) lacks required permission: $requiredPermission',
        requiredPermission: requiredPermission,
      );
    }

    // 2. Dimension 3: Protected Screen / Device Security Check (`_secure`)
    if (requiresSecureDevice(staff, requiredPermission, tenantSecureLocks: tenantSecureLocks) &&
        !isTrustedSecureDevice) {
      throw RbacForbiddenException(
        code: 'SECURE_DEVICE_REQUIRED',
        message:
            'Permission ${requiredPermission}_secure requires an enrolled, hardware-verified Desktop/Tablet runtime.',
        requiredPermission: '${requiredPermission}_secure',
      );
    }

    // 3. Operational Action Flags Check
    if (requireCanEdit && !staff.operationalFlags.canEdit) {
      throw RbacForbiddenException(
        code: 'ACTION_FLAG_DENIED_EDIT',
        message: 'Employee ${staff.staffCode} has canEdit=false.',
        requiredPermission: 'canEdit',
      );
    }
    if (requireCanDelete && !staff.operationalFlags.canDelete) {
      throw RbacForbiddenException(
        code: 'ACTION_FLAG_DENIED_DELETE',
        message: 'Employee ${staff.staffCode} has canDelete=false.',
        requiredPermission: 'canDelete',
      );
    }
    if (requireCanCollectMoney && !staff.operationalFlags.canCollectMoney) {
      throw RbacForbiddenException(
        code: 'ACTION_FLAG_DENIED_COLLECT_MONEY',
        message: 'Employee ${staff.staffCode} has canCollectMoney=false.',
        requiredPermission: 'canCollectMoney',
      );
    }
    if (requireCanMakeRefunds &&
        (!staff.operationalFlags.canMakeRefunds ||
            staff.operationalFlags.refundPolicy == RefundPolicy.none)) {
      throw RbacForbiddenException(
        code: 'ACTION_FLAG_DENIED_REFUND',
        message:
            'Employee ${staff.staffCode} is not permitted to initiate refunds (canMakeRefunds=${staff.operationalFlags.canMakeRefunds}, policy=${staff.operationalFlags.refundPolicy.name}).',
        requiredPermission: 'canMakeRefunds',
      );
    }

    // 4. Dimension 2: Resolve Data Scope (`_all` vs ownOnly)
    final scopeMode = resolveDataScope(staff, requiredPermission);

    return ScopeContext(
      hospitalCode: staff.hospitalCode,
      actor: staff,
      deviceId: deviceId,
      isTrustedSecureDevice: isTrustedSecureDevice,
      dataScopeMode: scopeMode,
      activePermission: requiredPermission,
      correlationId: correlationId,
      ipAddress: ipAddress,
    );
  }
}
