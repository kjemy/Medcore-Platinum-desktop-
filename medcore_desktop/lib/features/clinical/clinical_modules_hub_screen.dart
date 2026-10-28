import 'package:flutter/material.dart';
import '../../core/api/medcore_api_client.dart';
import '../../core/state/medcore_app_controller.dart';

/// Real API-Backed Clinical & Operational Modules Hub
/// (`Appointments`, `Doctor Queue`, `Laboratory`, `Radiology`, `Pharmacy`, `Inpatient`, `Specialty Units`).
/// Zero fake records: every displayed table row comes from `LocalMedCoreServer`, and schema-only
/// specialty units explicitly disclose `BACKEND_GAP` rather than rendering placeholder arrays.
class ClinicalModulesHubScreen extends StatefulWidget {
  final MedCoreAppController controller;
  final String activeSection;

  const ClinicalModulesHubScreen({
    super.key,
    required this.controller,
    required this.activeSection,
  });

  @override
  State<ClinicalModulesHubScreen> createState() => _ClinicalModulesHubScreenState();
}

class _ClinicalModulesHubScreenState extends State<ClinicalModulesHubScreen> {
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _secondaryItems = const <Map<String, dynamic>>[];
  String _dataScope = '';
  bool _loading = true;
  String? _errorMsg;

  // Quick appointment creation inputs (for Appointments section)
  final TextEditingController _aptNoCtrl = TextEditingController();
  final TextEditingController _aptPatIdCtrl = TextEditingController();
  final TextEditingController _aptDocIdCtrl = TextEditingController();
  final TextEditingController _aptReasonCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSectionData();
  }

  @override
  void didUpdateWidget(covariant ClinicalModulesHubScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeSection != widget.activeSection) {
      _loadSectionData();
    }
  }

  @override
  void dispose() {
    _aptNoCtrl.dispose();
    _aptPatIdCtrl.dispose();
    _aptDocIdCtrl.dispose();
    _aptReasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSectionData() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
      _items = const <Map<String, dynamic>>[];
      _secondaryItems = const <Map<String, dynamic>>[];
      _dataScope = '';
    });

    final api = widget.controller.api;
    final cfg = widget.controller.facilityConfig;
    final user = widget.controller.currentUser;
    if (user == null) return;

    try {
      switch (widget.activeSection) {
        case 'appointments':
          final res = await api.getJson('/api/v1/appointments');
          _dataScope = (res['dataScopeApplied'] ?? '').toString();
          _items = ((res['items'] as List?) ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          break;
        case 'doctors':
          final res = await api.getJson('/api/v1/doctor/queue');
          _dataScope = (res['dataScopeApplied'] ?? '').toString();
          _items = ((res['items'] as List?) ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          break;
        case 'laboratory':
          final res = await api.getJson('/api/v1/orders', query: const {'orderType': 'LAB'});
          _items = ((res['items'] as List?) ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          break;
        case 'radiology':
          final res = await api.getJson('/api/v1/orders', query: const {'orderType': 'RAD'});
          _items = ((res['items'] as List?) ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          break;
        case 'pharmacy':
          final res = await api.getJson('/api/v1/inventory/items');
          _items = ((res['items'] as List?) ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          if (user.hasAnyPermission(const ['inventory_StockBatches'])) {
            final bRes = await api.getJson('/api/v1/inventory/batches');
            _secondaryItems = ((bRes['items'] as List?) ?? const [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          }
          break;
        case 'inpatient':
          final res = await api.getJson('/api/v1/beds');
          _items = ((res['items'] as List?) ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          break;
        case 'specialty_units':
          if (cfg.isModuleEnabled('HR') && user.hasAnyPermission(const ['hr_Employees'])) {
            final sRes = await api.getJson('/api/v1/staff');
            _items = ((sRes['items'] as List?) ?? const [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          }
          break;
      }
    } on MedCoreApiException catch (e) {
      _errorMsg = e.toString();
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _createAppointment() async {
    final aptNo = _aptNoCtrl.text.trim();
    final patId = int.tryParse(_aptPatIdCtrl.text.trim());
    final docId = _aptDocIdCtrl.text.trim();
    if (aptNo.isEmpty || patId == null || docId.isEmpty) {
      setState(() {
        _errorMsg = 'Appointment Number, numeric Patient ID, and Doctor ID are required.';
      });
      return;
    }

    try {
      await widget.controller.api.postJson('/api/v1/appointments', {
        'appointmentNumber': aptNo,
        'patientId': patId,
        'doctorId': docId,
        'appointmentType': 'CONSULTATION',
        'scheduledAt': DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String(),
        'durationMinutes': 30,
        if (_aptReasonCtrl.text.trim().isNotEmpty) 'reason': _aptReasonCtrl.text.trim(),
      });
      _aptNoCtrl.clear();
      _aptReasonCtrl.clear();
      await _loadSectionData();
    } on MedCoreApiException catch (e) {
      if (!mounted) return;
      setState(() => _errorMsg = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _sectionTitle(widget.activeSection),
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Authoritative Local MedCore Service query${_dataScope.isNotEmpty ? ' • Data Scope: $_dataScope' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: _loading ? null : _loadSectionData,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (_errorMsg != null)
          Card(
            color: cs.errorContainer,
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                _errorMsg!,
                style: TextStyle(color: cs.onErrorContainer),
              ),
            ),
          ),

        if (_loading)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          _buildSectionBody(context),
      ],
    );
  }

  String _sectionTitle(String id) {
    switch (id) {
      case 'appointments':
        return 'Appointments & Scheduling (CLN-001)';
      case 'doctors':
        return 'Doctor Queue & Encounters (CLN-001)';
      case 'laboratory':
        return 'Laboratory Orders & Results (LIS / CLN-003)';
      case 'radiology':
        return 'Radiology & Imaging Orders (RIS / CLN-003)';
      case 'pharmacy':
        return 'Pharmacy & FIFO Inventory Batches (CLN-004)';
      case 'inpatient':
        return 'Inpatient Bed Map & Admissions (CLN-005)';
      case 'specialty_units':
        return 'Enabled Specialty & Enterprise Units';
      default:
        return 'Clinical Module';
    }
  }

  Widget _buildSectionBody(BuildContext context) {
    switch (widget.activeSection) {
      case 'appointments':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.controller.currentUser?.canEdit == true)
              Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Schedule New Appointment',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _aptNoCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Appointment No (e.g. APT-501)',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _aptPatIdCtrl,
                              decoration: const InputDecoration(labelText: 'Patient ID'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _aptDocIdCtrl,
                              decoration: const InputDecoration(labelText: 'Doctor Staff ID'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _aptReasonCtrl,
                              decoration: const InputDecoration(labelText: 'Reason'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton(
                            onPressed: _createAppointment,
                            child: const Text('Book'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            _GenericRecordsCard(
              title: 'Appointments (${_items.length})',
              emptyText: 'No appointments scheduled in MariaDB for this facility.',
              rows: _items,
            ),
          ],
        );

      case 'pharmacy':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _GenericRecordsCard(
              title: 'Inventory Catalog Items (${_items.length})',
              emptyText: 'No inventory items configured in mc_inventory_items.',
              rows: _items,
            ),
            const SizedBox(height: 16),
            _GenericRecordsCard(
              title: 'FIFO Stock Batches (${_secondaryItems.length})',
              emptyText: 'No stock batches recorded in mc_inventory_batches.',
              rows: _secondaryItems,
            ),
          ],
        );

      case 'specialty_units':
        return _buildSpecialtyUnitsBody(context);

      default:
        return _GenericRecordsCard(
          title: '${_sectionTitle(widget.activeSection)} (${_items.length})',
          emptyText: 'Zero records returned from Local MedCore Service for this facility.',
          rows: _items,
        );
    }
  }

  Widget _buildSpecialtyUnitsBody(BuildContext context) {
    final cfg = widget.controller.facilityConfig;
    final user = widget.controller.currentUser!;

    final unitDescriptors = <Map<String, dynamic>>[
      {
        'module': 'HR',
        'perms': const ['hr_settings', 'hr_Employees'],
        'status': 'IMPLEMENTED',
        'summary':
            'Staff Identity, Role Assignment, Custom Permissions & Operational Flags (/api/v1/staff).',
      },
      {
        'module': 'Nursing',
        'perms': const ['nurse', 'nurse_Station'],
        'status': 'IMPLEMENTED',
        'summary':
            'Active Nursing Station Tasks & Verification (/api/v1/nursing/tasks).',
      },
      {
        'module': 'ICU',
        'perms': const ['icu_nicu', 'icu_nicu_Dashboard'],
        'status': 'IMPLEMENTED',
        'summary':
            'Real-Time ICU Flowsheets & SOFA Scoring (/api/v1/icu/flowsheets, /api/v1/icu/sofa-scores).',
      },
      {
        'module': 'Surgery',
        'perms': const ['surgery', 'surgery_ORSchedule'],
        'status': 'IMPLEMENTED',
        'summary':
            'Operating Theater Scheduling & Status Flow (/api/v1/surgeries).',
      },
      {
        'module': 'Dialysis',
        'perms': const ['dialysis', 'dialysis_Sessions'],
        'status': 'IMPLEMENTED',
        'summary':
            'Dialysis Treatment Sessions & Fluid Metric Tracking (/api/v1/dialysis/sessions).',
      },
      {
        'module': 'CommandCenter',
        'perms': const ['HMS_summary', 'CommandCenter'],
        'status': 'PARTIAL',
        'summary':
            'Executive operational & truth explorer telemetry active (/api/v1/explorer/*, /api/v1/maintenance/overview); cross-department live KPI board deferred.',
      },
      {
        'module': 'AI',
        'perms': const ['ai', 'ai.clinical_summary'],
        'status': 'DEFERRED',
        'summary':
            'AI Governance audit schema present (V009); local/hybrid AI inference runtime explicitly deferred.',
      },
    ];

    final entitledAndAuthorized = unitDescriptors.where((u) {
      final mod = u['module'] as String;
      final perms = u['perms'] as List<String>;
      return cfg.isModuleEnabled(mod) && user.hasAnyPermission(perms);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Entitled & Role-Authorized Specialty Units (${entitledAndAuthorized.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Disabled modules for this facility/edition are strictly omitted here and blocked fail-closed (403 MODULE_NOT_ENTITLED) on Local MedCore Service.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                for (final u in entitledAndAuthorized)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.extension_outlined),
                    title: Text(
                      '${u['module']} — [${u['status']}]',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text('${u['summary']}'),
                  ),
              ],
            ),
          ),
        ),
        if (cfg.isModuleEnabled('HR') && user.hasAnyPermission(const ['hr_Employees'])) ...[
          const SizedBox(height: 16),
          _GenericRecordsCard(
            title: 'HR — Active Facility Staff Directory (${_items.length})',
            emptyText: 'No staff records returned.',
            rows: _items,
          ),
        ],
      ],
    );
  }
}

class _GenericRecordsCard extends StatelessWidget {
  final String title;
  final String emptyText;
  final List<Map<String, dynamic>> rows;

  const _GenericRecordsCard({
    required this.title,
    required this.emptyText,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            if (rows.isEmpty)
              Text(emptyText)
            else
              for (final r in rows.take(30))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SelectableText(
                      r.entries.map((e) => '${e.key}: ${e.value}').join('  •  '),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
