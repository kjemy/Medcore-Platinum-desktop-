import 'package:flutter/material.dart';
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

  String? _statusMessage;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
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
      ],
    );
  }
}
