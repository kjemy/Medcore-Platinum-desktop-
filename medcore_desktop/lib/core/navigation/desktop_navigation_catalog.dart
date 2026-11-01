import 'package:flutter/material.dart';
import '../models/product_models.dart';
import '../localization/medcore_strings_ar.dart';

class DesktopRouteEntry {
  final String routeId;
  final String label;
  final String? arLabel;
  final IconData icon;
  final String? requiredModule;
  final List<String> anyOfPermissions;

  const DesktopRouteEntry({
    required this.routeId,
    required this.label,
    this.arLabel,
    required this.icon,
    this.requiredModule,
    this.anyOfPermissions = const <String>[],
  });

  String getDisplayLabel(bool isRtl) {
    if (isRtl && arLabel != null && arLabel!.isNotEmpty) {
      return arLabel!;
    }
    return label;
  }

  bool isVisibleTo({
    required FacilityConfigModel config,
    required AuthenticatedStaffUser user,
  }) {
    if (requiredModule != null && !config.isModuleEnabled(requiredModule!)) {
      return false;
    }
    return user.hasAnyPermission(anyOfPermissions);
  }
}

/// Canonical Hospital Staff Desktop Navigation Catalog.
/// Note: Protected Technician / Service Mode is intentionally EXCLUDED from
/// ordinary hospital user navigation so hospital roles never see Technician controls.
class DesktopNavigationCatalog {
  static const List<DesktopRouteEntry> staffRoutes = [
    DesktopRouteEntry(
      routeId: 'dashboard',
      label: 'Executive Overview',
      arLabel: MedCoreStringsAr.navDashboard,
      icon: Icons.dashboard_outlined,
      anyOfPermissions: ['dashboard'],
    ),
    DesktopRouteEntry(
      routeId: 'patients',
      label: 'Patients & Registration',
      arLabel: MedCoreStringsAr.navPatients,
      icon: Icons.people_alt_outlined,
      requiredModule: 'Patients',
      anyOfPermissions: ['patients', 'reception_PatientRegistration'],
    ),
    DesktopRouteEntry(
      routeId: 'reception_visits',
      label: 'Shifts & Visit Billing',
      arLabel: MedCoreStringsAr.navReceptionVisits,
      icon: Icons.point_of_sale_outlined,
      requiredModule: 'Reception',
      anyOfPermissions: ['reception_QuickCheckIn', 'shifts'],
    ),
    DesktopRouteEntry(
      routeId: 'finance_ledger',
      label: 'Financial Ledger & Reports',
      arLabel: MedCoreStringsAr.navFinanceLedger,
      icon: Icons.account_balance_wallet_outlined,
      requiredModule: 'Finance',
      anyOfPermissions: ['finance', 'finance_Invoices', 'finance_Revenue'],
    ),
    DesktopRouteEntry(
      routeId: 'appointments',
      label: 'Appointments',
      arLabel: MedCoreStringsAr.navAppointments,
      icon: Icons.event_note_outlined,
      requiredModule: 'Appointments',
      anyOfPermissions: ['appointments', 'reception_Appointments', 'clinic_Appointments'],
    ),
    DesktopRouteEntry(
      routeId: 'doctors',
      label: 'Doctors & Outpatient',
      arLabel: MedCoreStringsAr.navDoctors,
      icon: Icons.medical_services_outlined,
      requiredModule: 'Doctors',
      anyOfPermissions: ['doctor', 'clinic', 'clinic_DoctorQueue', 'doctor_ClinicalWorkspace'],
    ),
    DesktopRouteEntry(
      routeId: 'laboratory',
      label: 'Laboratory (LIS)',
      arLabel: MedCoreStringsAr.navLaboratory,
      icon: Icons.biotech_outlined,
      requiredModule: 'Laboratory',
      anyOfPermissions: ['lab', 'lab_Dashboard', 'lab_ResultsEntry'],
    ),
    DesktopRouteEntry(
      routeId: 'radiology',
      label: 'Radiology (RIS)',
      arLabel: MedCoreStringsAr.navRadiology,
      icon: Icons.monitor_heart_outlined,
      requiredModule: 'Radiology',
      anyOfPermissions: ['rad', 'rad_Worklist', 'rad_Reporting'],
    ),
    DesktopRouteEntry(
      routeId: 'pharmacy',
      label: 'Pharmacy & Inventory',
      arLabel: MedCoreStringsAr.navPharmacy,
      icon: Icons.medication_outlined,
      requiredModule: 'Pharmacy',
      anyOfPermissions: ['pharmacy_inventory', 'pharmacy_Dispensing', 'inventory_ItemsCatalog'],
    ),
    DesktopRouteEntry(
      routeId: 'inpatient',
      label: 'Inpatient & Beds',
      arLabel: MedCoreStringsAr.navInpatient,
      icon: Icons.bed_outlined,
      requiredModule: 'Inpatient',
      anyOfPermissions: ['inpatient', 'inpatient_BedMap', 'inpatient_Admissions'],
    ),
    DesktopRouteEntry(
      routeId: 'specialty_units',
      label: 'Nursing / ICU / OR / Dialysis',
      arLabel: MedCoreStringsAr.navSpecialtyUnits,
      icon: Icons.local_hospital_outlined,
      anyOfPermissions: ['nurse', 'icu_nicu', 'surgery', 'dialysis', 'CommandCenter'],
    ),
    DesktopRouteEntry(
      routeId: 'definitions_workspace',
      label: 'Master Definitions',
      arLabel: MedCoreStringsAr.navDefinitions,
      icon: Icons.folder_special_outlined,
      anyOfPermissions: ['admin', 'definitions', 'settings_MasterDefinitions'],
    ),
    DesktopRouteEntry(
      routeId: 'commissions',
      label: 'Commissions & Settlements',
      arLabel: MedCoreStringsAr.navCommissions,
      icon: Icons.payments_outlined,
      requiredModule: 'Finance',
      anyOfPermissions: ['finance', 'finance_Commissions', 'doctor_Commissions', 'admin'],
    ),
    DesktopRouteEntry(
      routeId: 'hr_payroll',
      label: 'HR & Payroll',
      arLabel: MedCoreStringsAr.navHrPayroll,
      icon: Icons.badge_outlined,
      anyOfPermissions: ['admin', 'hr_Employees', 'hr_Payroll'],
    ),
    DesktopRouteEntry(
      routeId: 'clinical_templates',
      label: 'Clinical Templates',
      arLabel: MedCoreStringsAr.navClinicalTemplates,
      icon: Icons.description_outlined,
      requiredModule: 'Doctors',
      anyOfPermissions: ['doctor', 'clinic', 'doctor_ClinicalWorkspace', 'admin'],
    ),
    DesktopRouteEntry(
      routeId: 'resource_scheduling',
      label: 'Resource Scheduling',
      arLabel: MedCoreStringsAr.navResourceScheduling,
      icon: Icons.meeting_room_outlined,
      requiredModule: 'Appointments',
      anyOfPermissions: ['appointments', 'reception_Appointments', 'admin'],
    ),
    DesktopRouteEntry(
      routeId: 'staff_admin',
      label: 'Staff & Employee Accounts',
      arLabel: MedCoreStringsAr.navStaffAdmin,
      icon: Icons.people_outline,
      anyOfPermissions: ['admin', 'hr_Employees', 'security_Center'],
    ),
    DesktopRouteEntry(
      routeId: 'network_devices',
      label: 'LAN / Wi-Fi Devices',
      arLabel: MedCoreStringsAr.navNetworkDevices,
      icon: Icons.lan_outlined,
      anyOfPermissions: ['settings_Devices'],
    ),
    DesktopRouteEntry(
      routeId: 'maintenance_center',
      label: 'Maintenance & Backups',
      arLabel: MedCoreStringsAr.navMaintenanceCenter,
      icon: Icons.build_circle_outlined,
      anyOfPermissions: ['security_Center', 'settings_Backups'],
    ),
  ];

  static DesktopRouteEntry? findById(String routeId) {
    for (final entry in staffRoutes) {
      if (entry.routeId == routeId) return entry;
    }
    return null;
  }
}
