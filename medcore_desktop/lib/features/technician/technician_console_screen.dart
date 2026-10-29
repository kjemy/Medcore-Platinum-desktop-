import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api/medcore_api_client.dart';
import '../../core/state/medcore_app_controller.dart';
import '../maintenance/maintenance_center_screen.dart';
import '../network/network_device_center_screen.dart';

/// Protected Technician / Service Installation Console.
/// Strictly isolated from ordinary hospital user sessions (`MedCoreDesktopShell`).
/// Requires an active device-bound `mc_technician_sessions` token (`X-MedCore-Tech-Token`).
class TechnicianConsoleScreen extends StatefulWidget {
  final MedCoreAppController controller;

  const TechnicianConsoleScreen({
    super.key,
    required this.controller,
  });

  @override
  State<TechnicianConsoleScreen> createState() => _TechnicianConsoleScreenState();
}

class _TechnicianConsoleScreenState extends State<TechnicianConsoleScreen>
    with SingleTickerProviderStateMixin {
  static const List<String> _allModules = [
    'Patients',
    'Appointments',
    'Reception',
    'Shifts',
    'Doctors',
    'Nursing',
    'Inpatient',
    'ICU',
    'Surgery',
    'Dialysis',
    'Laboratory',
    'Radiology',
    'Pharmacy',
    'Finance',
    'CommandCenter',
    'HR',
    'AI',
  ];

  static const List<String> _editions = [
    'SILVER',
    'GOLD',
    'PLATINUM',
    'ADVANCED',
    'ENTERPRISE_LAN',
  ];

  static const List<String> _facilityTypes = [
    'GENERAL_HOSPITAL',
    'SPECIALIZED_CLINIC',
    'DENTAL_CLINIC',
    'DAY_SURGERY_CENTER',
    'DIAGNOSTIC_CENTER',
  ];

  static const List<String> _patientFieldKeys = [
    'dateOfBirth',
    'age',
    'nationalId',
    'bloodGroup',
    'address',
    'insuranceCompanyId',
    'insurancePolicyNo',
    'emergencyContactName',
    'emergencyContactPhone',
    'allergies',
    'chronicConditions',
    'inpatientAdmissionNotes',
    'icuTriageNotes',
    'nursingIntakeAssessment',
  ];

  late final TabController _tabController;

  // Tab 1: Facility Identity & Edition
  late final TextEditingController _facilityNameCtrl;
  late final TextEditingController _branchCodeCtrl;
  late final TextEditingController _installIdCtrl;
  late final TextEditingController _subStartCtrl;
  late final TextEditingController _subEndCtrl;
  late String _facilityType;
  late String _edition;
  bool _applyEditionModulePreset = false;
  bool _applyFacilityPatientPreset = false;

  // Tab 2 & 3: Modules & Patient Fields
  late Map<String, bool> _enabledModules;
  late Map<String, String> _patientFields;

  // Tab 4: Centralized Branding & Appearance
  late final TextEditingController _appDisplayNameCtrl;
  late final TextEditingController _facDisplayNameCtrl;
  late final TextEditingController _logoCtrl;
  late final TextEditingController _editionLabelCtrl;
  late final TextEditingController _primaryColorCtrl;
  late String _themeMode;
  late double _fontScale;
  late String _uiDensity;

  // Tab 5: Network, Backup & Clock Recovery
  bool _allowLan = true;
  bool _allowWifi = true;
  late final TextEditingController _maxDevicesCtrl;
  String _backupProvider = 'LOCAL_STORAGE';
  late final TextEditingController _localBackupDirCtrl;
  String _s3VendorPreset = 'VENDOR_NEUTRAL_S3';
  late final TextEditingController _s3EndpointCtrl;
  late final TextEditingController _s3RegionCtrl;
  late final TextEditingController _s3BucketCtrl;
  late final TextEditingController _s3PrefixCtrl;
  bool _futureRemoteReportingReady = false;

  // Clock Recovery inputs
  final TextEditingController _clockChallengeCtrl = TextEditingController();
  final TextEditingController _clockTimeRespCtrl = TextEditingController();
  final TextEditingController _clockMaintTokenCtrl = TextEditingController();

  // Technician Secret Rotation inputs
  final TextEditingController _newTechSecretCtrl = TextEditingController();
  String? _rotatedSecretDisplay;

  // Tab 8: Initial Hospital Administrator Provisioning & Handover
  final TextEditingController _adminStaffCodeCtrl = TextEditingController(text: 'ADM-001');
  final TextEditingController _adminFullNameCtrl = TextEditingController(text: 'Hospital Director');
  final TextEditingController _adminEmailCtrl = TextEditingController(text: 'admin@hospital.org');
  final TextEditingController _adminPasswordCtrl = TextEditingController();
  final TextEditingController _adminPhoneCtrl = TextEditingController();
  final TextEditingController _adminNationalIdCtrl = TextEditingController();
  Map<String, dynamic>? _provisionedAdminResult;
  bool _isLoadingAdminStatus = false;
  Map<String, dynamic>? _adminStatusData;

  String? _statusMessage;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
    _fetchAdminStatus();
    final cfg = widget.controller.facilityConfig;
    final b = cfg.branding;

    _facilityNameCtrl = TextEditingController(text: cfg.facilityName);
    _branchCodeCtrl = TextEditingController(text: cfg.branchCode);
    _installIdCtrl = TextEditingController(text: cfg.installationIdentity);
    _subStartCtrl = TextEditingController(text: cfg.subscriptionStartsUtc ?? '');
    _subEndCtrl = TextEditingController(text: cfg.subscriptionExpiresUtc ?? '');
    _facilityType = _facilityTypes.contains(cfg.facilityType)
        ? cfg.facilityType
        : 'GENERAL_HOSPITAL';
    _edition = _editions.contains(cfg.edition) ? cfg.edition : 'PLATINUM';

    _enabledModules = {
      for (final m in _allModules) m: cfg.enabledModules[m] ?? true,
    };
    _patientFields = {
      for (final k in _patientFieldKeys) k: cfg.fieldRequirement(k),
    };

    _appDisplayNameCtrl = TextEditingController(text: b.appDisplayName);
    _facDisplayNameCtrl = TextEditingController(text: b.facilityDisplayName);
    _logoCtrl = TextEditingController(text: b.logoPathOrUrl ?? '');
    _editionLabelCtrl = TextEditingController(text: b.editionLabel);
    _primaryColorCtrl = TextEditingController(text: b.primaryColorHex);
    _themeMode = const ['LIGHT', 'DARK', 'SYSTEM'].contains(b.themeMode) ? b.themeMode : 'LIGHT';
    _fontScale = b.fontScale.clamp(0.85, 1.30);
    _uiDensity = const ['COMPACT', 'STANDARD', 'COMFORTABLE'].contains(b.uiDensity)
        ? b.uiDensity
        : 'STANDARD';

    _allowLan = cfg.networkConfig['allowLanConnections'] != false;
    _allowWifi = cfg.networkConfig['allowWifiConnections'] != false;
    _maxDevicesCtrl = TextEditingController(
      text: (cfg.networkConfig['maxAuthorizedDevices'] ?? 25).toString(),
    );

    _backupProvider = (cfg.backupConfig['activeProvider'] ?? 'LOCAL_STORAGE').toString();
    if (!const ['LOCAL_STORAGE', 'S3_COMPATIBLE', 'CLOUD_ADAPTER'].contains(_backupProvider)) {
      _backupProvider = 'LOCAL_STORAGE';
    }
    _localBackupDirCtrl = TextEditingController(
      text: (cfg.backupConfig['localBackupDirectory'] ?? 'backups/local').toString(),
    );
    final s3Map = cfg.backupConfig['s3Compatible'] is Map
        ? Map<String, dynamic>.from(cfg.backupConfig['s3Compatible'] as Map)
        : const <String, dynamic>{};
    _s3VendorPreset = (s3Map['vendorPreset'] ?? 'VENDOR_NEUTRAL_S3').toString();
    _s3EndpointCtrl = TextEditingController(text: (s3Map['endpointUrl'] ?? '').toString());
    _s3RegionCtrl = TextEditingController(text: (s3Map['region'] ?? 'auto').toString());
    _s3BucketCtrl = TextEditingController(text: (s3Map['bucket'] ?? '').toString());
    _s3PrefixCtrl = TextEditingController(
      text: (s3Map['keyPrefix'] ?? 'medcore-backups/').toString(),
    );
    _futureRemoteReportingReady =
        cfg.remoteHybridConfig['futureOptionalRemoteReportingReady'] == true;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _facilityNameCtrl.dispose();
    _branchCodeCtrl.dispose();
    _installIdCtrl.dispose();
    _subStartCtrl.dispose();
    _subEndCtrl.dispose();
    _appDisplayNameCtrl.dispose();
    _facDisplayNameCtrl.dispose();
    _logoCtrl.dispose();
    _editionLabelCtrl.dispose();
    _primaryColorCtrl.dispose();
    _maxDevicesCtrl.dispose();
    _localBackupDirCtrl.dispose();
    _s3EndpointCtrl.dispose();
    _s3RegionCtrl.dispose();
    _s3BucketCtrl.dispose();
    _s3PrefixCtrl.dispose();
    _clockChallengeCtrl.dispose();
    _clockTimeRespCtrl.dispose();
    _clockMaintTokenCtrl.dispose();
    _adminStaffCodeCtrl.dispose();
    _adminFullNameCtrl.dispose();
    _adminEmailCtrl.dispose();
    _adminPasswordCtrl.dispose();
    _adminPhoneCtrl.dispose();
    _adminNationalIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveConfigurationAtomically() async {
    setState(() {
      _statusMessage = null;
      _isError = false;
    });

    final payload = <String, dynamic>{
      'facilityName': _facilityNameCtrl.text.trim(),
      'facilityType': _facilityType,
      'branchCode': _branchCodeCtrl.text.trim(),
      'installationIdentity': _installIdCtrl.text.trim(),
      'edition': _edition,
      'subscriptionStartsUtc':
          _subStartCtrl.text.trim().isEmpty ? null : _subStartCtrl.text.trim(),
      'subscriptionExpiresUtc':
          _subEndCtrl.text.trim().isEmpty ? null : _subEndCtrl.text.trim(),
      'applyEditionModulePreset': _applyEditionModulePreset,
      if (!_applyEditionModulePreset) 'enabledModules': _enabledModules,
      'applyFacilityTypePatientPreset': _applyFacilityPatientPreset,
      if (!_applyFacilityPatientPreset) 'patientFields': _patientFields,
      'branding': {
        'appDisplayName': _appDisplayNameCtrl.text.trim(),
        'facilityDisplayName': _facDisplayNameCtrl.text.trim(),
        'logoPathOrUrl': _logoCtrl.text.trim().isEmpty ? null : _logoCtrl.text.trim(),
        'editionLabel': _editionLabelCtrl.text.trim(),
        'primaryColorHex': _primaryColorCtrl.text.trim(),
        'themeMode': _themeMode,
        'fontScale': _fontScale,
        'uiDensity': _uiDensity,
      },
      'networkConfig': {
        'allowLanConnections': _allowLan,
        'allowWifiConnections': _allowWifi,
        'maxAuthorizedDevices': int.tryParse(_maxDevicesCtrl.text.trim()) ?? 25,
      },
      'backupConfig': {
        'activeProvider': _backupProvider,
        'localBackupDirectory': _localBackupDirCtrl.text.trim(),
        's3Compatible': {
          'vendorPreset': _s3VendorPreset,
          'endpointUrl': _s3EndpointCtrl.text.trim(),
          'region': _s3RegionCtrl.text.trim(),
          'bucket': _s3BucketCtrl.text.trim(),
          'keyPrefix': _s3PrefixCtrl.text.trim(),
        },
      },
      'remoteHybridConfig': {
        'futureOptionalRemoteReportingReady': _futureRemoteReportingReady,
      },
    };

    try {
      await widget.controller.saveTechnicianConfiguration(payload);
      final updated = widget.controller.facilityConfig;
      if (!mounted) return;
      setState(() {
        _applyEditionModulePreset = false;
        _applyFacilityPatientPreset = false;
        _enabledModules = {
          for (final m in _allModules) m: updated.enabledModules[m] ?? true,
        };
        _patientFields = {
          for (final k in _patientFieldKeys) k: updated.fieldRequirement(k),
        };
        _statusMessage =
            'Committed Facility Configuration v${updated.configVersion} atomically to MariaDB (mc_facility_config + mc_tenants + mc_audit_logs).';
        _isError = false;
      });
    } on MedCoreApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = e.toString();
        _isError = true;
      });
    }
  }

  Future<void> _issueClockChallenge() async {
    try {
      final res = await widget.controller.api.postJson(
        '/api/v1/technician/time-challenge',
        {'hospitalCode': widget.controller.api.hospitalCode},
        includeAuth: false,
      );
      if (!mounted) return;
      setState(() {
        _clockChallengeCtrl.text = (res['challengeId'] ?? '').toString();
        _statusMessage =
            'Issued Trusted-Time Challenge ${res['challengeId']} (Nonce: ${res['nonce']}). Sign with authority offline tool.';
        _isError = false;
      });
    } on MedCoreApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = e.toString();
        _isError = true;
      });
    }
  }

  Future<void> _executeClockRecovery() async {
    try {
      final res = await widget.controller.api.postJson(
        '/api/v1/technician/clock-recovery',
        {
          'hospitalCode': widget.controller.api.hospitalCode,
          'challengeId': _clockChallengeCtrl.text.trim(),
          'trustedTimeResponse': _clockTimeRespCtrl.text.trim(),
          'maintenanceToken': _clockMaintTokenCtrl.text.trim(),
        },
        includeAuth: false,
      );
      if (!mounted) return;
      setState(() {
        _statusMessage =
            'Clock Rollback Guard Recovered: Status=${res['status']} • Trusted UTC=${res['recoveredMaxObservedUtc']}.';
        _isError = false;
      });
    } on MedCoreApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = e.toString();
        _isError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tech = widget.controller.technicianSession;

    return Scaffold(
      body: Column(
        children: [
          // Protected Technician Banner Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: cs.tertiaryContainer,
              border: Border(bottom: BorderSide(color: cs.outlineVariant)),
            ),
            child: Row(
              children: [
                Icon(Icons.engineering, color: cs.onTertiaryContainer, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PROTECTED TECHNICIAN / SERVICE INSTALLATION CONSOLE',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: cs.onTertiaryContainer,
                        ),
                      ),
                      Text(
                        'Session: ${tech?.sessionUuid ?? '-'} • Auth: ${tech?.authMethod ?? '-'} • Tenant: ${tech?.hospitalCode ?? '-'} • Device: ${tech?.deviceId ?? '-'} • Isolated from Hospital Staff Roles',
                        style: TextStyle(fontSize: 12, color: cs.onTertiaryContainer),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  key: const Key('btn_tech_save_config'),
                  onPressed: widget.controller.isBusy ? null : _saveConfigurationAtomically,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Commit Configuration to MariaDB'),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  key: const Key('btn_tech_exit'),
                  onPressed: widget.controller.exitTechnicianMode,
                  icon: const Icon(Icons.exit_to_app, size: 18),
                  label: const Text('Exit Service Mode'),
                ),
              ],
            ),
          ),

          if (_statusMessage != null)
            Container(
              width: double.infinity,
              color: _isError ? cs.errorContainer : cs.primaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              child: SelectableText(
                _statusMessage!,
                style: TextStyle(color: _isError ? cs.onErrorContainer : cs.onPrimaryContainer),
              ),
            ),

          Material(
            color: cs.surface,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabs: const [
                Tab(text: '1. Facility, Edition & Subscription'),
                Tab(text: '2. Enabled Modules (17)'),
                Tab(text: '3. Facility Patient Fields'),
                Tab(text: '4. Centralized Branding & Theme'),
                Tab(text: '5. Network, Backup & Clock Recovery'),
                Tab(text: '6. Device Pairing Governance'),
                Tab(text: '7. Maintenance & Backup Runner'),
                Tab(text: '8. Initial Administrator Handover'),
              ],
            ),
          ),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildFacilityIdentityTab(),
                _buildEnabledModulesTab(),
                _buildPatientFieldsTab(),
                _buildBrandingAppearanceTab(),
                _buildNetworkBackupClockTab(),
                NetworkDeviceCenterScreen(controller: widget.controller),
                MaintenanceCenterScreen(controller: widget.controller),
                _buildInitialAdminHandoverTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFacilityIdentityTab() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Facility Identity, Edition & Subscription Lifecycle',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('input_tech_facility_name'),
                        controller: _facilityNameCtrl,
                        decoration: const InputDecoration(labelText: 'Facility Legal / Display Name'),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        key: const Key('dropdown_tech_facility_type'),
                        value: _facilityType,
                        decoration: const InputDecoration(labelText: 'Facility Type'),
                        items: _facilityTypes
                            .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                            .toList(),
                        onChanged: (v) => setState(() => _facilityType = v ?? 'GENERAL_HOSPITAL'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _branchCodeCtrl,
                        decoration: const InputDecoration(labelText: 'Branch Code'),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: TextField(
                        controller: _installIdCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Installation Identity (Matches Authority Token Scope)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        key: const Key('dropdown_tech_edition'),
                        value: _edition,
                        decoration: const InputDecoration(labelText: 'MedCore Edition'),
                        items: _editions
                            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                            .toList(),
                        onChanged: (v) => setState(() => _edition = v ?? 'PLATINUM'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _subStartCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Subscription Start UTC (ISO-8601 or blank)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: TextField(
                        controller: _subEndCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Subscription Expiry UTC (ISO-8601 or blank)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Apply Default Module Preset for Selected Edition on Next Save'),
                  value: _applyEditionModulePreset,
                  onChanged: (v) => setState(() => _applyEditionModulePreset = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Apply Default Patient-Field Profile for Selected Facility Type on Next Save',
                  ),
                  value: _applyFacilityPatientPreset,
                  onChanged: (v) => setState(() => _applyFacilityPatientPreset = v),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEnabledModulesTab() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Module Entitlements (Fail-Closed Backend + Sidebar Enforcement)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Disabling a module removes it from staff navigation AND enforces HTTP 403 MODULE_NOT_ENTITLED on every corresponding Local MedCore Service route.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    for (final mod in _allModules)
                      SizedBox(
                        width: 260,
                        child: SwitchListTile(
                          key: Key('switch_module_$mod'),
                          dense: true,
                          title: Text(mod, style: const TextStyle(fontWeight: FontWeight.w600)),
                          value: _enabledModules[mod] ?? true,
                          onChanged: (v) => setState(() => _enabledModules[mod] = v),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPatientFieldsTab() {
    final catalog = widget.controller.facilityConfig.patientFieldCatalog;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Configuration-Driven Facility Patient Fields (REQUIRED / OPTIONAL / HIDDEN)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Core identity fields (mrn, fullName, phone, gender) are structural invariants. Every field below is dynamically enforced by both Flutter registration forms and POST /api/v1/patients.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 14),
                for (final key in _patientFieldKeys)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            '${catalog[key]?['label'] ?? key} (${catalog[key]?['category'] ?? 'FIELD'})',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                        isExpanded: true,
                            key: Key('dropdown_pfield_$key'),
                            value: const ['REQUIRED', 'OPTIONAL', 'HIDDEN']
                                    .contains(_patientFields[key])
                                ? _patientFields[key]
                                : 'OPTIONAL',
                            items: const [
                              DropdownMenuItem(value: 'REQUIRED', child: Text('REQUIRED')),
                              DropdownMenuItem(value: 'OPTIONAL', child: Text('OPTIONAL')),
                              DropdownMenuItem(value: 'HIDDEN', child: Text('HIDDEN (Omitted)')),
                            ],
                            onChanged: (v) =>
                                setState(() => _patientFields[key] = v ?? 'OPTIONAL'),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBrandingAppearanceTab() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Centralized Branding & Appearance Configuration',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Single authoritative theme source for the entire MedCore Desktop client. Zero scattered widget color overrides.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('input_tech_app_display_name'),
                        controller: _appDisplayNameCtrl,
                        decoration: const InputDecoration(labelText: 'Application Display Name'),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: TextField(
                        controller: _facDisplayNameCtrl,
                        decoration: const InputDecoration(labelText: 'Facility Header Subtitle'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('input_tech_edition_label'),
                        controller: _editionLabelCtrl,
                        decoration: const InputDecoration(labelText: 'Edition Badge Label'),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: TextField(
                        controller: _logoCtrl,
                        decoration: const InputDecoration(labelText: 'Logo File Path / URL (Optional)'),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: TextField(
                        key: const Key('input_tech_primary_color'),
                        controller: _primaryColorCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Primary Brand Hex Color (e.g. #0F766E)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        key: const Key('dropdown_tech_theme_mode'),
                        value: _themeMode,
                        decoration: const InputDecoration(labelText: 'Theme Mode'),
                        items: const [
                          DropdownMenuItem(value: 'LIGHT', child: Text('LIGHT')),
                          DropdownMenuItem(value: 'DARK', child: Text('DARK')),
                          DropdownMenuItem(value: 'SYSTEM', child: Text('SYSTEM')),
                        ],
                        onChanged: (v) => setState(() => _themeMode = v ?? 'LIGHT'),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        key: const Key('dropdown_tech_ui_density'),
                        value: _uiDensity,
                        decoration: const InputDecoration(labelText: 'UI Density'),
                        items: const [
                          DropdownMenuItem(value: 'COMPACT', child: Text('COMPACT')),
                          DropdownMenuItem(value: 'STANDARD', child: Text('STANDARD')),
                          DropdownMenuItem(value: 'COMFORTABLE', child: Text('COMFORTABLE')),
                        ],
                        onChanged: (v) => setState(() => _uiDensity = v ?? 'STANDARD'),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Font Scale: ${_fontScale.toStringAsFixed(2)}x'),
                          Slider(
                            value: _fontScale,
                            min: 0.85,
                            max: 1.30,
                            divisions: 9,
                            label: '${_fontScale.toStringAsFixed(2)}x',
                            onChanged: (v) => setState(() => _fontScale = v),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNetworkBackupClockTab() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Network Policy & Vendor-Neutral Backup Provider Configuration',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Enable CONNECT VIA LAN'),
                        value: _allowLan,
                        onChanged: (v) => setState(() => _allowLan = v),
                      ),
                    ),
                    Expanded(
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Enable CONNECT VIA WI-FI'),
                        value: _allowWifi,
                        onChanged: (v) => setState(() => _allowWifi = v),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: TextField(
                        controller: _maxDevicesCtrl,
                        decoration: const InputDecoration(labelText: 'Max Authorized Devices'),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _backupProvider,
                        decoration: const InputDecoration(
                          labelText: 'Active Backup Provider (Zero Vendor Lock-In)',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'LOCAL_STORAGE',
                            child: Text('LOCAL_STORAGE (Verified Local Disk)'),
                          ),
                          DropdownMenuItem(
                            value: 'S3_COMPATIBLE',
                            child: Text('S3_COMPATIBLE (B2 / R2 / AWS S3 / Wasabi)'),
                          ),
                        ],
                        onChanged: (v) => setState(() => _backupProvider = v ?? 'LOCAL_STORAGE'),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: TextField(
                        controller: _localBackupDirCtrl,
                        decoration: const InputDecoration(labelText: 'Local Backup Directory'),
                      ),
                    ),
                  ],
                ),
                if (_backupProvider == 'S3_COMPATIBLE') ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                        isExpanded: true,
                          value: const [
                            'VENDOR_NEUTRAL_S3',
                            'BACKBLAZE_B2',
                            'CLOUDFLARE_R2',
                            'AWS_S3',
                            'WASABI',
                          ].contains(_s3VendorPreset)
                              ? _s3VendorPreset
                              : 'VENDOR_NEUTRAL_S3',
                          decoration: const InputDecoration(labelText: 'S3-Compatible Target Preset'),
                          items: const [
                            DropdownMenuItem(
                              value: 'VENDOR_NEUTRAL_S3',
                              child: Text('VENDOR_NEUTRAL_S3'),
                            ),
                            DropdownMenuItem(value: 'BACKBLAZE_B2', child: Text('BACKBLAZE_B2')),
                            DropdownMenuItem(value: 'CLOUDFLARE_R2', child: Text('CLOUDFLARE_R2')),
                            DropdownMenuItem(value: 'AWS_S3', child: Text('AWS_S3')),
                            DropdownMenuItem(value: 'WASABI', child: Text('WASABI')),
                          ],
                          onChanged: (v) =>
                              setState(() => _s3VendorPreset = v ?? 'VENDOR_NEUTRAL_S3'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _s3EndpointCtrl,
                          decoration: const InputDecoration(labelText: 'HTTPS Endpoint URL'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _s3BucketCtrl,
                          decoration: const InputDecoration(labelText: 'Bucket Name'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _s3RegionCtrl,
                          decoration: const InputDecoration(labelText: 'Region'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _s3PrefixCtrl,
                          decoration: const InputDecoration(labelText: 'Object Key Prefix'),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Future Optional Outbound Remote Reporting Boundary Flag (Local-First Preserved)',
                  ),
                  value: _futureRemoteReportingReady,
                  onChanged: (v) => setState(() => _futureRemoteReportingReady = v),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cryptographic Clock Rollback Recovery (RSA-2048 Authority Signed)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Recovers a fail-closed clock-tampered installation using an authority-signed Trusted-Time Response (MC_TIME_V1) and Single-Use Maintenance Token (MC_MAINT_V1). Private signing keys never reside on Desktop.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _issueClockChallenge,
                  icon: const Icon(Icons.schedule, size: 18),
                  label: const Text('1. Issue Trusted-Time Challenge'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _clockChallengeCtrl,
                  decoration: const InputDecoration(labelText: 'Challenge ID'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _clockTimeRespCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Signed Trusted-Time Response (MC_TIME_V1...)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _clockMaintTokenCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Signed Maintenance Recovery Token (MC_MAINT_V1...)',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _executeClockRecovery,
                  icon: const Icon(Icons.lock_reset, size: 18),
                  label: const Text('2. Verify Signatures & Recover Monotonic Clock'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Technician Credential Lifecycle & Secret Rotation',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Rotate the local installation technician secret. The old secret is immediately invalidated, pending first-run slips are consumed, and an immutable audit log is committed.',
                  style: TextStyle(fontSize: 12),
                ),
                if (_rotatedSecretDisplay != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.green),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Secret Rotated Successfully! Save this secret now:',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 12)),
                        const SizedBox(height: 6),
                        SelectableText(
                          _rotatedSecretDisplay!,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                TextField(
                  key: const Key('input_rotate_tech_secret'),
                  controller: _newTechSecretCtrl,
                  decoration: const InputDecoration(
                    labelText: 'New Technician Secret (min 12 characters, or leave blank to auto-generate)',
                    hintText: 'Enter new password or leave blank for secure 32-character token',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('btn_rotate_tech_secret'),
                  onPressed: _rotateTechnicianSecret,
                  icon: const Icon(Icons.password, size: 18),
                  label: const Text('Rotate Installation Secret'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _rotateTechnicianSecret() async {
    final text = _newTechSecretCtrl.text.trim();
    try {
      final res = await widget.controller.rotateTechnicianSecret(
        newSecret: text.isEmpty ? null : text,
      );
      if (!mounted) return;
      setState(() {
        _rotatedSecretDisplay = res['newSecret']?.toString();
        _statusMessage = 'Technician secret successfully rotated and audited.';
        _isError = false;
        _newTechSecretCtrl.clear();
      });
    } on MedCoreApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = e.toString();
        _isError = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = e.toString();
        _isError = true;
      });
    }
  }

  Future<void> _fetchAdminStatus() async {
    if (!mounted) return;
    setState(() => _isLoadingAdminStatus = true);
    try {
      final res = await widget.controller.getInitialAdminStatus();
      if (!mounted) return;
      setState(() {
        _adminStatusData = res;
        _isLoadingAdminStatus = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingAdminStatus = false);
    }
  }

  void _generateStrongTemporaryPassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#%&*';
    final rand = Random.secure();
    final pwd = List.generate(14, (_) => chars[rand.nextInt(chars.length)]).join();
    setState(() {
      _adminPasswordCtrl.text = 'MedCore-$pwd';
    });
  }

  Future<void> _provisionInitialAdministrator() async {
    setState(() {
      _statusMessage = null;
      _isError = false;
      _provisionedAdminResult = null;
    });

    final staffCode = _adminStaffCodeCtrl.text.trim();
    final fullName = _adminFullNameCtrl.text.trim();
    final email = _adminEmailCtrl.text.trim();
    final password = _adminPasswordCtrl.text.trim();
    final phone = _adminPhoneCtrl.text.trim();
    final nationalId = _adminNationalIdCtrl.text.trim();

    if (staffCode.isEmpty || fullName.isEmpty || email.isEmpty) {
      setState(() {
        _statusMessage = 'Staff Code, Full Name, and Email are required.';
        _isError = true;
      });
      return;
    }

    try {
      final res = await widget.controller.provisionInitialAdmin(
        staffCode: staffCode,
        fullName: fullName,
        email: email,
        password: password.isEmpty ? 'MedCore-${Random.secure().nextInt(99999999)}!' : password,
        phone: phone.isEmpty ? null : phone,
        nationalId: nationalId.isEmpty ? null : nationalId,
      );

      if (!mounted) return;
      setState(() {
        _provisionedAdminResult = res;
        _statusMessage = 'Hospital Administrator provisioned successfully. Deliver the secure handover slip below.';
        _isError = false;
      });
      await _fetchAdminStatus();
    } on MedCoreApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = e.toString();
        _isError = true;
      });
    }
  }

  Widget _buildInitialAdminHandoverTab() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tech = widget.controller.technicianSession;
    final hasAdmin = _adminStatusData?['hasAdmin'] == true;
    final admins = (_adminStatusData?['administrators'] as List?) ?? const [];

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Governance Notice
        Card(
          color: cs.primaryContainer.withOpacity(0.4),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_outlined, color: cs.primary, size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SECURE COMMISSIONING & HANDOVER GOVERNANCE (Khaled Constitution)',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Universal backdoor accounts and hardcoded default passwords have been permanently expunged. '
                        'As a certified field installation technician, you must provision the facility designated Hospital Administrator '
                        'inside this authenticated technician session. A single-use temporary password will be generated and printed/copied onto '
                        'the physical handover certificate. The administrator will be strictly required to establish their private credentials upon first login (force_password_change = true).',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Facility Status Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      hasAdmin ? Icons.verified_user : Icons.warning_amber_rounded,
                      color: hasAdmin ? Colors.teal : Colors.amber.shade800,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        hasAdmin
                            ? 'Hospital Administrator Already Provisioned (${admins.length} active admin accounts)'
                            : 'Awaiting Initial Hospital Administrator Provisioning (No Admin Found)',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      icon: _isLoadingAdminStatus
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh, size: 20),
                      tooltip: 'Refresh Status',
                      onPressed: _isLoadingAdminStatus ? null : _fetchAdminStatus,
                    ),
                  ],
                ),
                if (admins.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: admins.map((a) {
                      final m = a is Map ? a : const {};
                      return Chip(
                        avatar: const Icon(Icons.person, size: 16),
                        label: Text('${m['fullName']} (${m['staffCode']}) • ${m['email']}'),
                        backgroundColor: cs.surfaceContainerHighest,
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Provisioning Form
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Provision Administrator Account',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('field_initial_admin_staff_code'),
                        controller: _adminStaffCodeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Staff Code *',
                          hintText: 'e.g. ADM-001',
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        key: const Key('field_initial_admin_full_name'),
                        controller: _adminFullNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Full Name *',
                          hintText: 'e.g. Dr. Jane Smith / General Director',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('field_initial_admin_email'),
                        controller: _adminEmailCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Official Hospital Email *',
                          hintText: 'e.g. admin@hospital.org',
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        key: const Key('field_initial_admin_phone'),
                        controller: _adminPhoneCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Phone Number (Optional)',
                          hintText: 'e.g. +1 555-0199',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('field_initial_admin_password'),
                        controller: _adminPasswordCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Temporary Password (leave blank to auto-generate)',
                          hintText: 'Minimum 8 characters',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      key: const Key('btn_generate_admin_pwd'),
                      onPressed: _generateStrongTemporaryPassword,
                      icon: const Icon(Icons.key, size: 18),
                      label: const Text('Generate Strong Password'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('field_initial_admin_national_id'),
                  controller: _adminNationalIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'National ID / Civil Registration (Optional)',
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const Key('btn_provision_initial_admin'),
                  onPressed: widget.controller.isBusy ? null : _provisionInitialAdministrator,
                  icon: const Icon(Icons.person_add_alt_1, size: 20),
                  label: const Text('Provision Hospital Administrator & Generate Handover Slip'),
                ),
              ],
            ),
          ),
        ),

        if (_provisionedAdminResult != null) ...[
          const SizedBox(height: 24),
          // Handover Slip Card
          Card(
            key: const Key('card_handover_slip'),
            elevation: 4,
            color: cs.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: cs.primary, width: 2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.workspace_premium, color: cs.primary, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'OFFICIAL SECURE COMMISSIONING HANDOVER SLIP',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: cs.primary,
                                letterSpacing: 0.8,
                              ),
                            ),
                            Text(
                              'MedCore Platinum Desktop • Local Service Single-Tenant Authority',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        key: const Key('btn_copy_handover_slip'),
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('Copy Handover Slip'),
                        onPressed: () {
                          final slipText = '''
======================================================================
           MEDCORE PLATINUM SECURE HANDOVER CERTIFICATE
======================================================================
Facility Name:      ${widget.controller.facilityConfig.facilityName}
Facility Code:      ${widget.controller.facilityConfig.hospitalCode}
Branch Code:        ${widget.controller.facilityConfig.branchCode}
Edition:            ${widget.controller.facilityConfig.edition}
Commissioning Date: ${_provisionedAdminResult?['provisionedAt'] ?? DateTime.now().toUtc().toIso8601String()}

--- ADMINISTRATOR CREDENTIALS ---
Staff Code:         ${_adminStaffCodeCtrl.text.trim()}
Full Name:          ${_adminFullNameCtrl.text.trim()}
Login Identifier:   ${_adminEmailCtrl.text.trim()}
Temporary Password: ${_provisionedAdminResult?['handoverTemporaryPassword']}
First Login Action: MANDATORY PASSWORD CHANGE (force_password_change = true)

--- TECHNICIAN COMMISSIONING RECORD ---
Technician Session: ${tech?.sessionUuid ?? '-'}
Installation ID:    ${widget.controller.facilityConfig.installationIdentity}
Service Device:     ${tech?.deviceId ?? '-'}

--- HANDOVER SIGN-OFF ---
Technician Signature:   ___________________________
Administrator Receiver: ___________________________
Date Received:          ___________________________
======================================================================
''';
                          Clipboard.setData(ClipboardData(text: slipText));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Handover slip copied to clipboard.')),
                          );
                        },
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  _buildSlipRow('Facility:', '${widget.controller.facilityConfig.facilityName} (${widget.controller.facilityConfig.hospitalCode})'),
                  _buildSlipRow('Administrator Name:', _adminFullNameCtrl.text.trim()),
                  _buildSlipRow('Staff Code:', _adminStaffCodeCtrl.text.trim()),
                  _buildSlipRow('Login Email:', _adminEmailCtrl.text.trim()),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ONE-TIME TEMPORARY PASSWORD:',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: cs.error,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          '${_provisionedAdminResult?['handoverTemporaryPassword']}',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Notice: This password is shown only once and will expire upon first successful login, '
                          'where the administrator will be forced to choose a confidential password.',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.tertiaryContainer.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lock_clock, size: 20, color: cs.primary),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Status: FORCE_PASSWORD_CHANGE = TRUE. The user cannot access clinical or financial records until a new password is set.',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSlipRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
