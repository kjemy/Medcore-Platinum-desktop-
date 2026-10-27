/// MedCore Canonical 10-Role & 261-Permission Catalog (Gate 2: TASK 2.4)
/// Unifies the 10 Backend Roles and the 3-Dimensional Permission Matrix:
/// - Dimension 1: Base Permission (<key>) -> 87 keys
/// - Dimension 2: Tenant-Wide Data Scope (<key>_all) -> 87 keys
/// - Dimension 3: Device / Page Security (<key>_secure) -> 87 keys
/// Total UI Permission Keys = 261, plus 43 Backend dot-notation keys and 4 Operational Action Flags.

enum MedCoreRole {
  SuperAdmin,
  HospitalAdmin,
  Doctor,
  Nurse,
  Receptionist,
  Cashier,
  Pharmacist,
  Lab,
  Radiology,
  Employee;

  static MedCoreRole fromString(String raw) {
    final clean = raw.trim().toLowerCase().replaceAll('_', '').replaceAll(' ', '');
    switch (clean) {
      case 'superadmin':
        return MedCoreRole.SuperAdmin;
      case 'hospitaladmin':
      case 'admin':
        return MedCoreRole.HospitalAdmin;
      case 'doctor':
      case 'physician':
        return MedCoreRole.Doctor;
      case 'nurse':
      case 'nursing':
        return MedCoreRole.Nurse;
      case 'receptionist':
      case 'reception':
        return MedCoreRole.Receptionist;
      case 'cashier':
      case 'accountant':
        return MedCoreRole.Cashier;
      case 'pharmacist':
      case 'pharmacy':
        return MedCoreRole.Pharmacist;
      case 'lab':
      case 'laboratory':
      case 'labtech':
        return MedCoreRole.Lab;
      case 'radiology':
      case 'rad':
      case 'radiologist':
        return MedCoreRole.Radiology;
      default:
        return MedCoreRole.Employee;
    }
  }
}

enum RefundPolicy {
  none,
  direct,
  approval;

  static RefundPolicy fromString(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'direct':
        return RefundPolicy.direct;
      case 'approval':
        return RefundPolicy.approval;
      default:
        return RefundPolicy.none;
    }
  }
}

class OperationalFlags {
  final bool canEdit;
  final bool canDelete;
  final bool canCollectMoney;
  final bool canMakeRefunds;
  final RefundPolicy refundPolicy;

  const OperationalFlags({
    required this.canEdit,
    required this.canDelete,
    required this.canCollectMoney,
    required this.canMakeRefunds,
    required this.refundPolicy,
  });

  Map<String, dynamic> toJson() => {
        'canEdit': canEdit,
        'canDelete': canDelete,
        'canCollectMoney': canCollectMoney,
        'canMakeRefunds': canMakeRefunds,
        'refundPolicy': refundPolicy.name,
      };
}

class PermissionsCatalog {
  /// All 87 Canonical Base Permission Keys (19 Sidebar Sections + 63 Subpages + 5 Operational/System Scopes)
  static const List<String> basePermissions = [
    // Standalone Top-Level (5)
    'dashboard',
    'patients',
    'appointments',
    'HMS_summary',
    'shifts',
    // Reception & ER (6)
    'reception',
    'reception_QuickCheckIn',
    'reception_PatientRegistration',
    'reception_Appointments',
    'reception_QueueManagement',
    'reception_Emergency',
    // Outpatient Clinics (6)
    'clinic',
    'clinic_DoctorQueue',
    'clinic_Appointments',
    'clinic_PatientsList',
    'clinic_Prescriptions',
    'clinic_ClinicReports',
    // Command Center (4)
    'CommandCenter',
    'CommandCenter_Overview',
    'CommandCenter_BedManagement',
    'CommandCenter_Alerts',
    // Doctor Portal (4)
    'doctor',
    'doctor_ClinicalWorkspace',
    'doctor_MyPatients',
    'doctor_Schedule',
    // Nursing Station (6)
    'nurse',
    'nurse_NursingStation',
    'nurse_Triage',
    'nurse_VitalsMonitoring',
    'nurse_MedicationAdmin',
    'nurse_ShiftHandover',
    // Inpatient & Wards (5)
    'inpatient',
    'inpatient_Admissions',
    'inpatient_BedMap',
    'inpatient_WardRounds',
    'inpatient_Discharge',
    // ICU & NICU (5)
    'icu_nicu',
    'icu_nicu_Dashboard',
    'icu_nicu_ICUMonitoring',
    'icu_nicu_NICUIncubators',
    'icu_nicu_Ventilators',
    // Surgery & OR (4)
    'surgery',
    'surgery_OTSchedule',
    'surgery_OperatingTheaters',
    'surgery_PostOpRecovery',
    // Dialysis Unit (5)
    'dialysis',
    'dialysis_Sessions',
    'dialysis_Machines',
    'dialysis_Patients',
    'dialysis_Consumables',
    // Laboratory (7)
    'lab',
    'lab_Dashboard',
    'lab_SampleTracking',
    'lab_ResultsEntry',
    'lab_Verification',
    'lab_BloodBank',
    'lab_Reagents',
    // Radiology (4)
    'rad',
    'rad_Worklist',
    'rad_Reporting',
    'rad_ContrastConsumables',
    // Pharmacy & Inventory (7)
    'pharmacy_inventory',
    'pharmacy_Dispensing',
    'inventory_ItemsCatalog',
    'inventory_StockBatches',
    'inventory_PurchaseReceipts',
    'inventory_Transfers',
    'inventory_Stocktake',
    // Finance & Accounting (6)
    'finance',
    'finance_Revenue',
    'finance_Invoices',
    'finance_Settlements',
    'finance_InsuranceClaims',
    'finance_TreasuryExpenses',
    // HR, Settings & Security (13)
    'hr_settings',
    'hr_Employees',
    'hr_Attendance',
    'hr_Payroll',
    'hr_Leaves',
    'hr_Evaluations',
    'settings_Definitions',
    'settings_CommissionRules',
    'settings_Permissions',
    'settings_HospitalProfile',
    'settings_Devices',
    'settings_Backups',
    'security_Center',
  ];

  /// 87 `_all` Tenant-Wide Scope Keys
  static final List<String> allScopePermissions =
      basePermissions.map((p) => '${p}_all').toList(growable: false);

  /// 87 `_secure` Device/Page Security Keys
  static final List<String> securePagePermissions =
      basePermissions.map((p) => '${p}_secure').toList(growable: false);

  /// All 261 Canonical UI Permission Keys
  static final List<String> all261Permissions = [
    ...basePermissions,
    ...allScopePermissions,
    ...securePagePermissions,
  ];

  /// Administrative permissions that must never be implicitly granted to clinical/operational staff
  static const Set<String> administrativePermissions = {
    'HMS_summary',
    'CommandCenter',
    'CommandCenter_Overview',
    'CommandCenter_BedManagement',
    'CommandCenter_Alerts',
    'finance',
    'finance_Revenue',
    'finance_Invoices',
    'finance_Settlements',
    'finance_InsuranceClaims',
    'finance_TreasuryExpenses',
    'hr_settings',
    'hr_Employees',
    'hr_Attendance',
    'hr_Payroll',
    'hr_Leaves',
    'hr_Evaluations',
    'settings_Definitions',
    'settings_CommissionRules',
    'settings_Permissions',
    'settings_HospitalProfile',
    'settings_Devices',
    'settings_Backups',
    'security_Center',
  };

  /// Bidirectional mapping between 43 Backend dot-notation permissions and UI base permissions
  static const Map<String, List<String>> backendToUiPermissions = {
    'patients.read': ['patients', 'reception_PatientRegistration', 'clinic_PatientsList', 'doctor_MyPatients'],
    'patients.write': ['patients', 'reception_PatientRegistration', 'reception_QuickCheckIn'],
    'appointments.read': ['appointments', 'reception_Appointments', 'clinic_Appointments', 'doctor_Schedule'],
    'appointments.write': ['appointments', 'reception_Appointments', 'clinic_Appointments'],
    'visits.read': ['reception_QueueManagement', 'clinic_DoctorQueue', 'doctor_ClinicalWorkspace'],
    'visits.write': ['reception_QuickCheckIn', 'doctor_ClinicalWorkspace'],
    'visits.cancel': ['reception_QueueManagement', 'finance_Invoices'],
    'clinical.read': ['doctor_ClinicalWorkspace', 'clinic_DoctorQueue', 'nurse_NursingStation'],
    'clinical.write': ['doctor_ClinicalWorkspace', 'clinic_Prescriptions'],
    'nursing.read': ['nurse', 'nurse_NursingStation', 'nurse_Triage', 'nurse_VitalsMonitoring', 'nurse_MedicationAdmin', 'nurse_ShiftHandover'],
    'nursing.write': ['nurse_Triage', 'nurse_VitalsMonitoring', 'nurse_MedicationAdmin', 'nurse_ShiftHandover'],
    'admissions.read': ['inpatient', 'inpatient_Admissions', 'inpatient_BedMap', 'inpatient_WardRounds', 'inpatient_Discharge'],
    'admissions.write': ['inpatient_Admissions', 'inpatient_BedMap', 'inpatient_WardRounds', 'inpatient_Discharge'],
    'icu.read': ['icu_nicu', 'icu_nicu_Dashboard', 'icu_nicu_ICUMonitoring', 'icu_nicu_NICUIncubators', 'icu_nicu_Ventilators'],
    'icu.write': ['icu_nicu_ICUMonitoring', 'icu_nicu_NICUIncubators', 'icu_nicu_Ventilators'],
    'surgery.read': ['surgery', 'surgery_OTSchedule', 'surgery_OperatingTheaters', 'surgery_PostOpRecovery'],
    'surgery.write': ['surgery_OTSchedule', 'surgery_OperatingTheaters', 'surgery_PostOpRecovery'],
    'dialysis.read': ['dialysis', 'dialysis_Sessions', 'dialysis_Machines', 'dialysis_Patients', 'dialysis_Consumables'],
    'dialysis.write': ['dialysis_Sessions', 'dialysis_Machines', 'dialysis_Consumables'],
    'lab.read': ['lab', 'lab_Dashboard', 'lab_SampleTracking', 'lab_ResultsEntry', 'lab_Verification', 'lab_BloodBank', 'lab_Reagents'],
    'lab.write': ['lab_SampleTracking', 'lab_ResultsEntry', 'lab_BloodBank', 'lab_Reagents'],
    'lab.verify': ['lab_Verification'],
    'rad.read': ['rad', 'rad_Worklist', 'rad_Reporting', 'rad_ContrastConsumables'],
    'rad.write': ['rad_Worklist', 'rad_Reporting', 'rad_ContrastConsumables'],
    'pharmacy.read': ['pharmacy_inventory', 'pharmacy_Dispensing'],
    'pharmacy.write': ['pharmacy_Dispensing'],
    'inventory.read': ['inventory_ItemsCatalog', 'inventory_StockBatches', 'inventory_PurchaseReceipts', 'inventory_Transfers', 'inventory_Stocktake'],
    'inventory.write': ['inventory_ItemsCatalog', 'inventory_StockBatches', 'inventory_PurchaseReceipts', 'inventory_Transfers', 'inventory_Stocktake'],
    'shifts.read': ['shifts'],
    'shifts.open': ['shifts'],
    'shifts.close': ['shifts'],
    'finance.read': ['finance', 'finance_Revenue', 'finance_Invoices', 'finance_InsuranceClaims', 'finance_TreasuryExpenses'],
    'finance.write': ['finance_Invoices', 'finance_InsuranceClaims', 'finance_TreasuryExpenses'],
    'finance.settle': ['finance_Settlements'],
    'hr.read': ['hr_settings', 'hr_Employees', 'hr_Attendance', 'hr_Payroll', 'hr_Leaves', 'hr_Evaluations'],
    'hr.write': ['hr_Employees', 'hr_Attendance', 'hr_Payroll', 'hr_Leaves', 'hr_Evaluations'],
    'definitions.read': ['settings_Definitions', 'settings_CommissionRules'],
    'definitions.write': ['settings_Definitions', 'settings_CommissionRules'],
    'permissions.manage': ['settings_Permissions'],
    'settings.manage': ['settings_HospitalProfile', 'settings_Devices', 'settings_Backups'],
    'security.read': ['security_Center'],
    'security.manage': ['security_Center', 'settings_Devices'],
    'audit.read': ['security_Center'],
  };

  /// Default Role Permissions Matrix across all 10 Canonical Roles.
  /// Notice: Non-admin roles NEVER receive '*' and only receive their explicit domain permissions!
  static Map<MedCoreRole, Set<String>> get defaultRolePermissions => {
        MedCoreRole.SuperAdmin: {...all261Permissions},
        MedCoreRole.HospitalAdmin: {
          ...basePermissions,
          ...allScopePermissions,
        },
        MedCoreRole.Doctor: {
          'dashboard',
          'patients',
          'appointments',
          'clinic',
          'clinic_DoctorQueue',
          'clinic_Appointments',
          'clinic_PatientsList',
          'clinic_Prescriptions',
          'doctor',
          'doctor_ClinicalWorkspace',
          'doctor_MyPatients',
          'doctor_Schedule',
          'inpatient',
          'inpatient_WardRounds',
          'inpatient_Discharge',
          'icu_nicu',
          'icu_nicu_Dashboard',
          'icu_nicu_ICUMonitoring',
          'icu_nicu_NICUIncubators',
          'surgery',
          'surgery_OTSchedule',
          'surgery_OperatingTheaters',
          'dialysis',
          'dialysis_Sessions',
          'dialysis_Patients',
        },
        MedCoreRole.Nurse: {
          'dashboard',
          'patients',
          'nurse',
          'nurse_NursingStation',
          'nurse_Triage',
          'nurse_VitalsMonitoring',
          'nurse_MedicationAdmin',
          'nurse_ShiftHandover',
          'inpatient',
          'inpatient_BedMap',
          'icu_nicu',
          'icu_nicu_Dashboard',
          'icu_nicu_ICUMonitoring',
          'icu_nicu_NICUIncubators',
          'icu_nicu_Ventilators',
          'surgery',
          'surgery_PostOpRecovery',
          'dialysis',
          'dialysis_Sessions',
        },
        MedCoreRole.Receptionist: {
          'dashboard',
          'patients',
          'patients_all',
          'appointments',
          'appointments_all',
          'reception',
          'reception_QuickCheckIn',
          'reception_QuickCheckIn_all',
          'reception_PatientRegistration',
          'reception_PatientRegistration_all',
          'reception_Appointments',
          'reception_Appointments_all',
          'reception_QueueManagement',
          'reception_QueueManagement_all',
          'reception_Emergency',
          'reception_Emergency_all',
          'inpatient_Admissions',
          'inpatient_BedMap',
        },
        MedCoreRole.Cashier: {
          'dashboard',
          'patients',
          'patients_all',
          'shifts',
          'reception_QuickCheckIn',
          'reception_QuickCheckIn_all',
          'finance_Invoices',
          'finance_Invoices_all',
          'finance_TreasuryExpenses',
        },
        MedCoreRole.Pharmacist: {
          'dashboard',
          'patients',
          'pharmacy_inventory',
          'pharmacy_Dispensing',
          'pharmacy_Dispensing_all',
          'inventory_ItemsCatalog',
          'inventory_ItemsCatalog_all',
          'inventory_StockBatches',
          'inventory_StockBatches_all',
          'inventory_PurchaseReceipts',
          'inventory_Transfers',
          'inventory_Stocktake',
        },
        MedCoreRole.Lab: {
          'dashboard',
          'patients',
          'lab',
          'lab_Dashboard',
          'lab_Dashboard_all',
          'lab_SampleTracking',
          'lab_SampleTracking_all',
          'lab_ResultsEntry',
          'lab_ResultsEntry_all',
          'lab_Verification',
          'lab_Verification_all',
          'lab_BloodBank',
          'lab_Reagents',
        },
        MedCoreRole.Radiology: {
          'dashboard',
          'patients',
          'rad',
          'rad_Worklist',
          'rad_Worklist_all',
          'rad_Reporting',
          'rad_Reporting_all',
          'rad_ContrastConsumables',
        },
        MedCoreRole.Employee: {
          'dashboard',
        },
      };

  static OperationalFlags defaultFlagsForRole(MedCoreRole role) {
    switch (role) {
      case MedCoreRole.SuperAdmin:
      case MedCoreRole.HospitalAdmin:
        return const OperationalFlags(
          canEdit: true,
          canDelete: true,
          canCollectMoney: true,
          canMakeRefunds: true,
          refundPolicy: RefundPolicy.direct,
        );
      case MedCoreRole.Cashier:
        return const OperationalFlags(
          canEdit: true,
          canDelete: false,
          canCollectMoney: true,
          canMakeRefunds: true,
          refundPolicy: RefundPolicy.approval,
        );
      case MedCoreRole.Receptionist:
        return const OperationalFlags(
          canEdit: true,
          canDelete: false,
          canCollectMoney: true,
          canMakeRefunds: false,
          refundPolicy: RefundPolicy.none,
        );
      case MedCoreRole.Doctor:
      case MedCoreRole.Nurse:
      case MedCoreRole.Pharmacist:
      case MedCoreRole.Lab:
      case MedCoreRole.Radiology:
        return const OperationalFlags(
          canEdit: true,
          canDelete: false,
          canCollectMoney: false,
          canMakeRefunds: false,
          refundPolicy: RefundPolicy.none,
        );
      case MedCoreRole.Employee:
        return const OperationalFlags(
          canEdit: false,
          canDelete: false,
          canCollectMoney: false,
          canMakeRefunds: false,
          refundPolicy: RefundPolicy.none,
        );
    }
  }
}
