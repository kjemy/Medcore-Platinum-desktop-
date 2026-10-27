import '../security/permissions_catalog.dart';

/// Represents the authoritative employee identity loaded from `mc_staff` (TASK 2.3)
class StaffIdentity {
  final int id;
  final String hospitalCode;
  final String staffCode;
  final String fullName;
  final String email;
  final String? phone;
  final String? nationalId;
  final MedCoreRole role;
  final String? departmentId;
  final String? clinicId;
  final String? doctorDefinitionCode;
  final String? specialty;
  final String permissionsMode; // 'default' | 'custom'
  final Set<String> customPermissions;
  final Set<String> securePageLocks;
  final OperationalFlags operationalFlags;
  final bool isActive;

  const StaffIdentity({
    required this.id,
    required this.hospitalCode,
    required this.staffCode,
    required this.fullName,
    required this.email,
    this.phone,
    this.nationalId,
    required this.role,
    this.departmentId,
    this.clinicId,
    this.doctorDefinitionCode,
    this.specialty,
    required this.permissionsMode,
    required this.customPermissions,
    required this.securePageLocks,
    required this.operationalFlags,
    required this.isActive,
  });

  Map<String, dynamic> toPublicJson(Set<String> effectivePermissions) => {
        'id': id,
        'hospitalCode': hospitalCode,
        'staffCode': staffCode,
        'fullName': fullName,
        'email': email,
        'phone': phone,
        'nationalId': nationalId,
        'role': role.name,
        'departmentId': departmentId,
        'clinicId': clinicId,
        'doctorDefinitionCode': doctorDefinitionCode,
        'specialty': specialty,
        'permissionsMode': permissionsMode,
        'effectivePermissions': effectivePermissions.toList()..sort(),
        'securePageLocks': securePageLocks.toList()..sort(),
        'operationalFlags': operationalFlags.toJson(),
        'isActive': isActive,
      };
}

enum DataScopeMode {
  /// Employee holds `<perm>_all` (or is SuperAdmin/HospitalAdmin): can query all records in `hospital_code`
  tenantWide,

  /// Employee holds ONLY `<perm>` (Base): repository restricts SQL to records owned/assigned to this employee
  ownOnly,
}

/// Passed from Gate 2 Middleware/Service Layer down into Gate 1 Repositories
/// so data scoping (`_all` vs own-only) and tenant isolation (`hospital_code`) are enforced at the SQL layer!
class ScopeContext {
  final String hospitalCode;
  final StaffIdentity actor;
  final String deviceId;
  final bool isTrustedSecureDevice;
  final DataScopeMode dataScopeMode;
  final String? activePermission;
  final String? correlationId;
  final String? ipAddress;

  const ScopeContext({
    required this.hospitalCode,
    required this.actor,
    required this.deviceId,
    required this.isTrustedSecureDevice,
    required this.dataScopeMode,
    this.activePermission,
    this.correlationId,
    this.ipAddress,
  });

  bool get isTenantWide => dataScopeMode == DataScopeMode.tenantWide;
}
