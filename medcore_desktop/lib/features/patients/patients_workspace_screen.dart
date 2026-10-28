import 'package:flutter/material.dart';
import '../../core/api/medcore_api_client.dart';
import '../../core/state/medcore_app_controller.dart';

/// Configuration-Driven Patients Directory & Registration Workspace.
/// Strictly renders ONLY non-HIDDEN facility patient fields and enforces REQUIRED fields dynamically.
class PatientsWorkspaceScreen extends StatefulWidget {
  final MedCoreAppController controller;

  const PatientsWorkspaceScreen({
    super.key,
    required this.controller,
  });

  @override
  State<PatientsWorkspaceScreen> createState() => _PatientsWorkspaceScreenState();
}

class _PatientsWorkspaceScreenState extends State<PatientsWorkspaceScreen> {
  final TextEditingController _mrnCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  String _gender = 'male';

  final Map<String, TextEditingController> _dynamicCtrls = <String, TextEditingController>{};
  List<Map<String, dynamic>> _patients = const <Map<String, dynamic>>[];
  String _dataScopeApplied = '';
  String? _feedback;
  bool _isError = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initDynamicControllers();
    _loadPatients();
  }

  void _initDynamicControllers() {
    for (final key in widget.controller.facilityConfig.patientFields.keys) {
      _dynamicCtrls.putIfAbsent(key, () => TextEditingController());
    }
  }

  @override
  void dispose() {
    _mrnCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    for (final c in _dynamicCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPatients() async {
    setState(() => _loading = true);
    try {
      final res = await widget.controller.api.getJson('/api/v1/patients');
      final rawItems = res['items'] as List? ?? const [];
      if (!mounted) return;
      setState(() {
        _dataScopeApplied = (res['dataScopeApplied'] ?? '').toString();
        _patients = rawItems.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    } on MedCoreApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _feedback = e.toString();
        _isError = true;
        _loading = false;
      });
    }
  }

  Future<void> _registerPatient() async {
    final cfg = widget.controller.facilityConfig;
    setState(() {
      _feedback = null;
      _isError = false;
    });

    if (_mrnCtrl.text.trim().isEmpty ||
        _nameCtrl.text.trim().isEmpty ||
        _phoneCtrl.text.trim().isEmpty) {
      setState(() {
        _feedback = 'MRN, Full Name, and Phone Number are mandatory core identity fields.';
        _isError = true;
      });
      return;
    }

    // Client-side dynamic validation mirroring authoritative backend facility config
    final payload = <String, dynamic>{
      'mrn': _mrnCtrl.text.trim(),
      'fullName': _nameCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'gender': _gender,
    };

    for (final entry in cfg.patientFields.entries) {
      final key = entry.key;
      final req = entry.value.toUpperCase();
      if (req == 'HIDDEN') continue;
      final val = (_dynamicCtrls[key]?.text ?? '').trim();
      if (req == 'REQUIRED' && val.isEmpty) {
        final label = cfg.patientFieldCatalog[key]?['label'] ?? key;
        setState(() {
          _feedback = 'Required by facility configuration: "$label" cannot be empty.';
          _isError = true;
        });
        return;
      }
      if (val.isNotEmpty) {
        payload[key] = val;
      }
    }

    try {
      await widget.controller.api.postJson('/api/v1/patients', payload);
      _mrnCtrl.clear();
      _nameCtrl.clear();
      _phoneCtrl.clear();
      for (final c in _dynamicCtrls.values) {
        c.clear();
      }
      if (!mounted) return;
      setState(() {
        _feedback = 'Patient persisted in MariaDB via Local MedCore Service.';
        _isError = false;
      });
      await _loadPatients();
    } on MedCoreApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _feedback = e.toString();
        _isError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    _initDynamicControllers();
    final cfg = widget.controller.facilityConfig;
    final theme = Theme.of(context);
    final canEdit = widget.controller.currentUser?.canEdit ?? false;
    final financeEnabled = cfg.isModuleEnabled('Finance') &&
        (widget.controller.currentUser?.hasAnyPermission(const ['finance', 'finance_Invoices']) ??
            false);

    // Filter out HIDDEN fields dynamically so Dental/Clinic never prompts for disabled Inpatient/ICU/Nursing fields!
    final visibleCustomFields = cfg.patientFields.entries
        .where((e) => e.value.toUpperCase() != 'HIDDEN')
        .toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left Pane: Configuration-Driven Registration Form
        SizedBox(
          width: 400,
          child: Card(
            margin: const EdgeInsets.all(16),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Patient Registration (${cfg.facilityType})',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Showing ${visibleCustomFields.length} active facility fields (${cfg.patientFields.length - visibleCustomFields.length} disabled fields hidden).',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const Key('pat_input_mrn'),
                  controller: _mrnCtrl,
                  decoration: const InputDecoration(labelText: 'MRN *'),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('pat_input_fullName'),
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Full Name *'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        key: const Key('pat_input_phone'),
                        controller: _phoneCtrl,
                        decoration: const InputDecoration(labelText: 'Phone *'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _gender,
                        decoration: const InputDecoration(labelText: 'Gender'),
                        items: const [
                          DropdownMenuItem(value: 'male', child: Text('Male')),
                          DropdownMenuItem(value: 'female', child: Text('Female')),
                        ],
                        onChanged: (v) => setState(() => _gender = v ?? 'male'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final field in visibleCustomFields) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      key: Key('pat_dynamic_${field.key}'),
                      controller: _dynamicCtrls[field.key],
                      decoration: InputDecoration(
                        labelText:
                            '${cfg.patientFieldCatalog[field.key]?['label'] ?? field.key}${field.value.toUpperCase() == 'REQUIRED' ? ' * (Required)' : ''}',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const Key('btn_register_patient'),
                  onPressed: canEdit ? _registerPatient : null,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Register Patient'),
                ),
                if (_feedback != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _feedback!,
                    style: TextStyle(
                      fontSize: 12,
                      color: _isError ? theme.colorScheme.error : theme.colorScheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Right Pane: Authoritative Patients Directory
        Expanded(
          child: Card(
            margin: const EdgeInsets.fromLTRB(0, 16, 16, 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Authoritative Patient Records (${_patients.length}) • Scope: $_dataScopeApplied',
                          style:
                              theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _loadPatients,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Reload'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _patients.isEmpty
                            ? const Center(
                                child: Text('No patient records found in MariaDB for this scope.'),
                              )
                            : ListView.separated(
                                itemCount: _patients.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (ctx, i) {
                                  final p = _patients[i];
                                  final pid = int.tryParse(p['id']?.toString() ?? '0') ?? 0;
                                  final bal = (p['balance'] ?? '0.0000').toString();
                                  return ListTile(
                                    title: Text(
                                      '${p['fullName']} (MRN: ${p['mrn']})',
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                    subtitle: Text(
                                      'Phone: ${p['phone']} • Balance: $bal${p['nationalId'] != null ? ' • ID: ${p['nationalId']}' : ''}',
                                    ),
                                    trailing: financeEnabled
                                        ? OutlinedButton.icon(
                                            key: Key('btn_open_ledger_$pid'),
                                            onPressed: () => widget.controller
                                                .openPatientFinancialLedger(pid),
                                            icon: const Icon(
                                                Icons.account_balance_wallet_outlined,
                                                size: 16),
                                            label: const Text('Financial Account'),
                                          )
                                        : null,
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
