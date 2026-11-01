import 'package:flutter/material.dart';
import '../../core/api/medcore_api_client.dart';
import '../../core/state/medcore_app_controller.dart';
import 'doctor_consultation_workspace.dart';

/// Interactive Real API-Backed Clinical & Operational Modules Hub
/// Supporting Full Parity for:
/// - Appointments & Scheduling
/// - Doctor Queue & Encounters (GAP-011, GAP-012, GAP-014)
/// - Laboratory Orders & Results Entry (LIS / GAP-018)
/// - Radiology Orders & Results Entry (RIS / GAP-018)
/// - Pharmacy POS Counter Dispensing & FIFO Batches (GAP-017)
/// - Inpatient Visual Bed Matrix & Admissions (GAP-020)
/// - Specialty Units Workspace: Nursing, ICU, Surgery, Dialysis (GAP-019)
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

  // Active specialty sub-tab: 'nursing' | 'icu' | 'surgery' | 'dialysis' | 'overview'
  String _specialtySubTab = 'nursing';

  // Quick appointment creation inputs
  final TextEditingController _aptNoCtrl = TextEditingController();
  final TextEditingController _aptPatIdCtrl = TextEditingController();
  final TextEditingController _aptDocIdCtrl = TextEditingController();
  final TextEditingController _aptReasonCtrl = TextEditingController();

  // Pharmacy POS inputs (GAP-017)
  final TextEditingController _posPrescriptionIdCtrl = TextEditingController(text: '1');
  final TextEditingController _posItemIdCtrl = TextEditingController(text: '1');
  final TextEditingController _posInvIdCtrl = TextEditingController(text: '1');
  final TextEditingController _posShiftIdCtrl = TextEditingController(text: '1');
  final TextEditingController _posQtyCtrl = TextEditingController(text: '1');

  // Inpatient Admission inputs (GAP-020)
  final TextEditingController _admPatIdCtrl = TextEditingController();
  final TextEditingController _admBedIdCtrl = TextEditingController();
  final TextEditingController _admDoctorIdCtrl = TextEditingController();
  final TextEditingController _admDiagnosisCtrl = TextEditingController();
  String _admissionType = 'EMERGENCY';

  // Specialty Care inputs (GAP-019)
  final TextEditingController _nursePatIdCtrl = TextEditingController();
  final TextEditingController _nurseTaskDescCtrl = TextEditingController();
  final TextEditingController _icuAdmissionIdCtrl = TextEditingController(text: 'ADM-01');
  final TextEditingController _icuHrCtrl = TextEditingController(text: '85');
  final TextEditingController _icuMapCtrl = TextEditingController(text: '75');
  final TextEditingController _icuRrCtrl = TextEditingController(text: '18');
  final TextEditingController _icuSpo2Ctrl = TextEditingController(text: '98');
  final TextEditingController _icuGcsCtrl = TextEditingController(text: '15');
  final TextEditingController _surgPatIdCtrl = TextEditingController();
  final TextEditingController _surgProcedureCtrl = TextEditingController();
  final TextEditingController _dialysisPatIdCtrl = TextEditingController();
  final TextEditingController _dialysisFluidCtrl = TextEditingController(text: '2000');

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
    _posPrescriptionIdCtrl.dispose();
    _posItemIdCtrl.dispose();
    _posInvIdCtrl.dispose();
    _posShiftIdCtrl.dispose();
    _posQtyCtrl.dispose();
    _admPatIdCtrl.dispose();
    _admBedIdCtrl.dispose();
    _admDoctorIdCtrl.dispose();
    _admDiagnosisCtrl.dispose();
    _nursePatIdCtrl.dispose();
    _nurseTaskDescCtrl.dispose();
    _icuAdmissionIdCtrl.dispose();
    _icuHrCtrl.dispose();
    _icuMapCtrl.dispose();
    _icuRrCtrl.dispose();
    _icuSpo2Ctrl.dispose();
    _icuGcsCtrl.dispose();
    _surgPatIdCtrl.dispose();
    _surgProcedureCtrl.dispose();
    _dialysisPatIdCtrl.dispose();
    _dialysisFluidCtrl.dispose();
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
          if (user.hasAnyPermission(const ['inventory_StockBatches', 'pharmacy_inventory'])) {
            try {
              final bRes = await api.getJson('/api/v1/inventory/batches');
              _secondaryItems = ((bRes['items'] as List?) ?? const [])
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
            } catch (_) {}
          }
          break;
        case 'inpatient':
          final res = await api.getJson('/api/v1/beds');
          _items = ((res['items'] as List?) ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          break;
        case 'specialty_units':
          await _loadSpecialtyData();
          break;
      }
    } on MedCoreApiException catch (e) {
      _errorMsg = e.toString();
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _loadSpecialtyData() async {
    final api = widget.controller.api;
    try {
      if (_specialtySubTab == 'nursing') {
        final res = await api.getJson('/api/v1/clinical/nursing/tasks');
        _items = ((res['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else if (_specialtySubTab == 'icu') {
        final res = await api.getJson('/api/v1/clinical/icu/flowsheets');
        _items = ((res['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else if (_specialtySubTab == 'surgery') {
        final res = await api.getJson('/api/v1/clinical/surgeries');
        _items = ((res['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else if (_specialtySubTab == 'dialysis') {
        final res = await api.getJson('/api/v1/clinical/dialysis/sessions');
        _items = ((res['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (_) {}
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

  // =========================================================================
  // GAP-018: Diagnostic Results Entry (LIS / RIS)
  // =========================================================================
  Future<void> _showResultsEntryDialog(Map<String, dynamic> order) async {
    final orderId = order['id'] ?? order['order_id'];
    final rawItems = (order['items'] as List?) ?? const [];
    final items = rawItems.map((e) => Map<String, dynamic>.from(e as Map)).toList();

    int selectedItemId = items.isNotEmpty ? (items.first['id'] ?? 1) : 1;
    String resultType = 'NUMERIC';
    final valCtrl = TextEditingController(text: '12.5');
    final unitCtrl = TextEditingController(text: 'g/dL');
    final rangeCtrl = TextEditingController(text: '11.5 - 15.5');
    final notesCtrl = TextEditingController(text: 'Result within normal reference range.');
    bool isPanic = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text('Record Diagnostic Result (Order #$orderId)'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Result Type & Metrics:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: resultType,
                    decoration: const InputDecoration(labelText: 'Result Type', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'NUMERIC', child: Text('NUMERIC (Quantitative)')),
                      DropdownMenuItem(value: 'TEXT', child: Text('TEXT (Narrative / Findings)')),
                      DropdownMenuItem(value: 'POS_NEG', child: Text('POSITIVE / NEGATIVE (Qualitative)')),
                    ],
                    onChanged: (v) => setDlgState(() => resultType = v!),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: valCtrl,
                    decoration: const InputDecoration(labelText: 'Observed Value / Reading', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: unitCtrl,
                          decoration: const InputDecoration(labelText: 'Unit (e.g. mg/dL)', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: rangeCtrl,
                          decoration: const InputDecoration(labelText: 'Normal Range', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    title: const Text('Critical Panic Value (Requires Immediate Notification)', style: TextStyle(color: Colors.red)),
                    value: isPanic,
                    onChanged: (v) => setDlgState(() => isPanic = v ?? false),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Pathologist / Radiologist Comments', border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await widget.controller.api.postJson('/api/v1/orders/$orderId/results', {
                    'orderItemId': selectedItemId,
                    'resultType': resultType,
                    'resultJson': {
                      'value': valCtrl.text.trim(),
                      'unit': unitCtrl.text.trim(),
                      'normalRange': rangeCtrl.text.trim(),
                    },
                    'isCriticalPanic': isPanic,
                    'notes': notesCtrl.text.trim(),
                  });
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Diagnostic result recorded and committed to MariaDB.')),
                  );
                  await _loadSectionData();
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              },
              child: const Text('Save & Sign Off'),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // GAP-017: Pharmacy POS Counter Dispensing
  // =========================================================================
  Future<void> _dispensePrescription() async {
    final presId = int.tryParse(_posPrescriptionIdCtrl.text.trim());
    final itemId = int.tryParse(_posItemIdCtrl.text.trim());
    final invId = int.tryParse(_posInvIdCtrl.text.trim());
    final shiftId = int.tryParse(_posShiftIdCtrl.text.trim());
    final qty = double.tryParse(_posQtyCtrl.text.trim());

    if (presId == null || itemId == null || invId == null || shiftId == null || qty == null || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Valid Prescription ID, Item ID, Inventory Item ID, Shift ID, and positive Quantity are required.')),
      );
      return;
    }

    try {
      await widget.controller.api.postJson('/api/v1/pharmacy/dispense', {
        'prescriptionId': presId,
        'prescriptionItemId': itemId,
        'inventoryItemId': invId,
        'shiftId': shiftId,
        'quantity': qty.toString(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Medication successfully dispensed and FIFO stock deducted from MariaDB.')),
      );
      await _loadSectionData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Dispense Error: $e')));
    }
  }

  // =========================================================================
  // GAP-020: Inpatient Admissions & Bed Matrix
  // =========================================================================
  Future<void> _admitPatient() async {
    final patId = _admPatIdCtrl.text.trim();
    final bedId = _admBedIdCtrl.text.trim();
    if (patId.isEmpty || bedId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Patient ID and Bed ID are required for admission.')),
      );
      return;
    }

    try {
      await widget.controller.api.postJson('/api/v1/admissions', {
        'patientId': patId,
        'bedId': bedId,
        'admissionType': _admissionType,
        if (_admDoctorIdCtrl.text.trim().isNotEmpty) 'attendingDoctorId': _admDoctorIdCtrl.text.trim(),
        if (_admDiagnosisCtrl.text.trim().isNotEmpty) 'diagnosisJson': _admDiagnosisCtrl.text.trim(),
      });
      _admPatIdCtrl.clear();
      _admBedIdCtrl.clear();
      _admDiagnosisCtrl.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Patient successfully admitted to bed.')),
      );
      await _loadSectionData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Admission Error: $e')));
    }
  }

  Future<void> _dischargePatient(int admissionId) async {
    final reasonCtrl = TextEditingController(text: 'Clinical improvement and discharge orders signed.');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Discharge Patient (Admission #$admissionId)'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(labelText: 'Discharge Summary / Reason', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await widget.controller.api.postJson('/api/v1/admissions/$admissionId/discharge', {
                  'dischargeReason': reasonCtrl.text.trim(),
                });
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Patient discharged and bed freed.')),
                );
                await _loadSectionData();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Discharge Error: $e')));
              }
            },
            child: const Text('Confirm Discharge'),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // GAP-019: Specialty Clinical Operations
  // =========================================================================
  Future<void> _createNursingTask() async {
    final patId = int.tryParse(_nursePatIdCtrl.text.trim()) ?? 1;
    final desc = _nurseTaskDescCtrl.text.trim();
    if (desc.isEmpty) return;

    try {
      await widget.controller.api.postJson('/api/v1/clinical/nursing/tasks', {
        'patientId': patId,
        'taskType': 'VITAL_MONITORING',
        'description': desc,
        'priority': 'HIGH',
      });
      _nurseTaskDescCtrl.clear();
      await _loadSpecialtyData();
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Task Error: $e')));
    }
  }

  Future<void> _completeNursingTask(int taskId) async {
    try {
      await widget.controller.api.postJson('/api/v1/clinical/nursing/tasks/$taskId/complete', {
        'notes': 'Completed per doctor protocol.',
      });
      await _loadSpecialtyData();
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Complete Error: $e')));
    }
  }

  Future<void> _recordIcuFlowsheet() async {
    try {
      await widget.controller.api.postJson('/api/v1/clinical/icu/flowsheets', {
        'admissionId': _icuAdmissionIdCtrl.text.trim(),
        'heartRate': int.tryParse(_icuHrCtrl.text.trim()) ?? 80,
        'meanArterialPressure': int.tryParse(_icuMapCtrl.text.trim()) ?? 75,
        'respiratoryRate': int.tryParse(_icuRrCtrl.text.trim()) ?? 18,
        'spo2': double.tryParse(_icuSpo2Ctrl.text.trim()) ?? 98.0,
        'gcsScore': int.tryParse(_icuGcsCtrl.text.trim()) ?? 15,
      });
      await _loadSpecialtyData();
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ICU Flowsheet recorded in MariaDB.')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ICU Error: $e')));
    }
  }

  Future<void> _scheduleSurgery() async {
    final patId = int.tryParse(_surgPatIdCtrl.text.trim()) ?? 1;
    final proc = _surgProcedureCtrl.text.trim();
    if (proc.isEmpty) return;

    try {
      await widget.controller.api.postJson('/api/v1/clinical/surgeries', {
        'patientId': patId,
        'surgeonStaffId': widget.controller.currentUser?.staffCode ?? 'DOC-01',
        'theaterId': 'OT-1',
        'procedureName': proc,
        'plannedDate': DateTime.now().toUtc().toIso8601String(),
      });
      _surgProcedureCtrl.clear();
      await _loadSpecialtyData();
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Surgery scheduled.')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Surgery Error: $e')));
    }
  }

  Future<void> _scheduleDialysis() async {
    final patId = int.tryParse(_dialysisPatIdCtrl.text.trim()) ?? 1;
    final fluid = double.tryParse(_dialysisFluidCtrl.text.trim()) ?? 2000.0;

    try {
      await widget.controller.api.postJson('/api/v1/clinical/dialysis/sessions', {
        'patientId': patId,
        'machineId': 'DIA-M01',
        'scheduledAt': DateTime.now().toUtc().toIso8601String(),
        'targetFluidRemovalMl': fluid,
      });
      await _loadSpecialtyData();
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dialysis session scheduled.')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Dialysis Error: $e')));
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
        return 'Doctor Queue & Clinical Encounters (GAP-011 / GAP-014)';
      case 'laboratory':
        return 'Laboratory Orders & Results Entry (LIS / GAP-018)';
      case 'radiology':
        return 'Radiology & Imaging Worklist (RIS / GAP-018)';
      case 'pharmacy':
        return 'Pharmacy Counter POS & FIFO Dispensing (GAP-017)';
      case 'inpatient':
        return 'Inpatient Visual Bed Map & Admissions (GAP-020)';
      case 'specialty_units':
        return 'Specialty Care Workspace: Nursing, ICU, Surgery, Dialysis (GAP-019)';
      default:
        return 'Clinical Module';
    }
  }

  Widget _buildSectionBody(BuildContext context) {
    switch (widget.activeSection) {
      case 'appointments':
        return _buildAppointmentsSection(context);
      case 'doctors':
        return DoctorConsultationWorkspace(
          controller: widget.controller,
          queueItems: _items,
          onRefreshQueue: _loadSectionData,
        );
      case 'laboratory':
      case 'radiology':
        return _buildDiagnosticsSection(context, isRadiology: widget.activeSection == 'radiology');
      case 'pharmacy':
        return _buildPharmacyPosSection(context);
      case 'inpatient':
        return _buildInpatientBedMatrix(context);
      case 'specialty_units':
        return _buildSpecialtyUnitsWorkspace(context);
      default:
        return _GenericRecordsCard(
          title: '${_sectionTitle(widget.activeSection)} (${_items.length})',
          emptyText: 'Zero records returned from Local MedCore Service for this facility.',
          rows: _items,
        );
    }
  }

  Widget _buildAppointmentsSection(BuildContext context) {
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
                  const Text('Schedule New Appointment', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _aptNoCtrl,
                          decoration: const InputDecoration(labelText: 'Appointment No (e.g. APT-501)'),
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
  }

  // =========================================================================
  // GAP-018: Diagnostic Results Entry (LIS / RIS) View
  // =========================================================================
  Widget _buildDiagnosticsSection(BuildContext context, {required bool isRadiology}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isRadiology ? 'Radiology Imaging Worklist (RIS)' : 'Laboratory Orders & Specimens (LIS)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Chip(
                      label: Text('${_items.length} Active Orders'),
                      backgroundColor: theme.colorScheme.primaryContainer,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  isRadiology
                      ? 'Record imaging findings, modalities, and radiologist impressions.'
                      : 'Record quantitative/qualitative specimen results, units, and panic flags.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_items.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No diagnostic orders currently pending.')),
            ),
          )
        else
          for (final order in _items)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(isRadiology ? Icons.monitor_heart : Icons.biotech, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Order #${order['order_number'] ?? order['id'] ?? 'N/A'} • Patient #${order['patient_id'] ?? 'N/A'}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: (order['status'] == 'COMPLETED') ? Colors.green.shade100 : Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${order['status'] ?? 'PENDING'}',
                            style: TextStyle(
                              color: (order['status'] == 'COMPLETED') ? Colors.green.shade900 : Colors.amber.shade900,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.edit_note, size: 16),
                          label: const Text('Enter Results'),
                          onPressed: () => _showResultsEntryDialog(order),
                        ),
                      ],
                    ),
                    if (order['clinical_indication'] != null) ...[
                      const SizedBox(height: 8),
                      Text('Clinical Indication: ${order['clinical_indication']}', style: const TextStyle(fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ),
      ],
    );
  }

  // =========================================================================
  // GAP-017: Pharmacy POS Counter Dispensing View
  // =========================================================================
  Widget _buildPharmacyPosSection(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // POS Dispensing Card
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.point_of_sale, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    const Text('Pharmacy POS Counter Dispensing (GAP-017)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Select prescription items to dispense with real-time FIFO stock deduction from MariaDB.', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _posPrescriptionIdCtrl,
                        decoration: const InputDecoration(labelText: 'Prescription ID', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _posItemIdCtrl,
                        decoration: const InputDecoration(labelText: 'Rx Item ID', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _posInvIdCtrl,
                        decoration: const InputDecoration(labelText: 'Inventory Item ID', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _posShiftIdCtrl,
                        decoration: const InputDecoration(labelText: 'Shift ID', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: _posQtyCtrl,
                        decoration: const InputDecoration(labelText: 'Quantity', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _dispensePrescription,
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('Dispense (FIFO)'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
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
  }

  // =========================================================================
  // GAP-020: Inpatient Visual Bed Map Matrix
  // =========================================================================
  Widget _buildInpatientBedMatrix(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Admission Form Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.bed, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    const Text('Inpatient Admission & Bed Allocation (GAP-020)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _admPatIdCtrl,
                        decoration: const InputDecoration(labelText: 'Patient ID', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _admBedIdCtrl,
                        decoration: const InputDecoration(labelText: 'Bed ID / Code', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _admissionType,
                        decoration: const InputDecoration(labelText: 'Admission Type', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 'EMERGENCY', child: Text('EMERGENCY')),
                          DropdownMenuItem(value: 'ELECTIVE', child: Text('ELECTIVE')),
                          DropdownMenuItem(value: 'ICU', child: Text('ICU TRANSFER')),
                        ],
                        onChanged: (v) => setState(() => _admissionType = v!),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _admDoctorIdCtrl,
                        decoration: const InputDecoration(labelText: 'Attending Doctor ID', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _admitPatient,
                      child: const Text('Admit to Bed'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Visual Bed Matrix Grid
        Text('Visual Ward & Bed Status Map (${_items.length} Beds)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        if (_items.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No inpatient beds registered in database.')),
            ),
          )
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final bed in _items)
                _buildBedCard(context, bed),
            ],
          ),
      ],
    );
  }

  Widget _buildBedCard(BuildContext context, Map<String, dynamic> bed) {
    final status = (bed['status'] ?? 'AVAILABLE').toString().toUpperCase();
    final isOccupied = status == 'OCCUPIED';
    final isCleaning = status == 'CLEANING' || status == 'MAINTENANCE';

    Color cardColor = Colors.green.shade50;
    Color borderColor = Colors.green.shade300;
    Color textColor = Colors.green.shade900;

    if (isOccupied) {
      cardColor = Colors.red.shade50;
      borderColor = Colors.red.shade300;
      textColor = Colors.red.shade900;
    } else if (isCleaning) {
      cardColor = Colors.amber.shade50;
      borderColor = Colors.amber.shade300;
      textColor = Colors.amber.shade900;
    }

    final bedCode = bed['bed_code'] ?? bed['code'] ?? bed['id'] ?? 'BED';
    final room = bed['room_id'] ?? bed['room_number'] ?? 'Ward A';

    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        border: Border.all(color: borderColor, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text('$bedCode', style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 13), overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: borderColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(status, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 10)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Room: $room', style: const TextStyle(fontSize: 12)),
          if (isOccupied) ...[
            const SizedBox(height: 6),
            Text('Patient: #${bed['current_patient_id'] ?? bed['patient_id'] ?? 'Assigned'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () {
                  final admId = int.tryParse(bed['admission_id']?.toString() ?? '1') ?? 1;
                  _dischargePatient(admId);
                },
                child: const Text('Discharge', style: TextStyle(fontSize: 11)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // =========================================================================
  // GAP-019: Specialty Clinical Workspaces (Nursing, ICU, Surgery, Dialysis)
  // =========================================================================
  Widget _buildSpecialtyUnitsWorkspace(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'nursing', icon: Icon(Icons.health_and_safety_outlined), label: Text('Nursing Station')),
            ButtonSegment(value: 'icu', icon: Icon(Icons.monitor_heart_outlined), label: Text('ICU Monitoring')),
            ButtonSegment(value: 'surgery', icon: Icon(Icons.masks_outlined), label: Text('Operating Theater')),
            ButtonSegment(value: 'dialysis', icon: Icon(Icons.water_drop_outlined), label: Text('Dialysis Unit')),
          ],
          selected: {_specialtySubTab},
          onSelectionChanged: (val) {
            setState(() {
              _specialtySubTab = val.first;
            });
            _loadSpecialtyData().then((_) {
              if (mounted) setState(() {});
            });
          },
        ),
        const SizedBox(height: 16),
        if (_specialtySubTab == 'nursing') _buildNursingWorkspace(context),
        if (_specialtySubTab == 'icu') _buildIcuWorkspace(context),
        if (_specialtySubTab == 'surgery') _buildSurgeryWorkspace(context),
        if (_specialtySubTab == 'dialysis') _buildDialysisWorkspace(context),
      ],
    );
  }

  Widget _buildNursingWorkspace(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _nursePatIdCtrl,
                    decoration: const InputDecoration(labelText: 'Patient ID', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _nurseTaskDescCtrl,
                    decoration: const InputDecoration(labelText: 'Nursing Task Description (e.g. Administer IV Cefotaxime 1g)', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _createNursingTask,
                  icon: const Icon(Icons.add_task),
                  label: const Text('Add Task'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _GenericRecordsCard(
          title: 'Active Nursing Station Tasks (${_items.length})',
          emptyText: 'No pending nursing tasks.',
          rows: _items,
        ),
      ],
    );
  }

  Widget _buildIcuWorkspace(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Record ICU Flowsheet & Vitals', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: TextField(controller: _icuAdmissionIdCtrl, decoration: const InputDecoration(labelText: 'Admission ID', border: OutlineInputBorder()))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: _icuHrCtrl, decoration: const InputDecoration(labelText: 'HR (bpm)', border: OutlineInputBorder()))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: _icuMapCtrl, decoration: const InputDecoration(labelText: 'MAP (mmHg)', border: OutlineInputBorder()))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: _icuRrCtrl, decoration: const InputDecoration(labelText: 'RR (/min)', border: OutlineInputBorder()))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: _icuSpo2Ctrl, decoration: const InputDecoration(labelText: 'SpO2 (%)', border: OutlineInputBorder()))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: _icuGcsCtrl, decoration: const InputDecoration(labelText: 'GCS (3-15)', border: OutlineInputBorder()))),
                    const SizedBox(width: 12),
                    FilledButton(onPressed: _recordIcuFlowsheet, child: const Text('Record')),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _GenericRecordsCard(
          title: 'ICU Patient Flowsheets & SOFA Trends (${_items.length})',
          emptyText: 'No ICU flowsheets recorded.',
          rows: _items,
        ),
      ],
    );
  }

  Widget _buildSurgeryWorkspace(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  child: TextField(controller: _surgPatIdCtrl, decoration: const InputDecoration(labelText: 'Patient ID', border: OutlineInputBorder())),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(controller: _surgProcedureCtrl, decoration: const InputDecoration(labelText: 'Surgical Procedure Name', border: OutlineInputBorder())),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _scheduleSurgery,
                  icon: const Icon(Icons.schedule),
                  label: const Text('Schedule Surgery'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _GenericRecordsCard(
          title: 'Operating Theater Surgeries (${_items.length})',
          emptyText: 'No surgical operations currently scheduled.',
          rows: _items,
        ),
      ],
    );
  }

  Widget _buildDialysisWorkspace(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  child: TextField(controller: _dialysisPatIdCtrl, decoration: const InputDecoration(labelText: 'Patient ID', border: OutlineInputBorder())),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(controller: _dialysisFluidCtrl, decoration: const InputDecoration(labelText: 'Target Fluid Removal (mL)', border: OutlineInputBorder())),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _scheduleDialysis,
                  icon: const Icon(Icons.water_drop),
                  label: const Text('Schedule Session'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _GenericRecordsCard(
          title: 'Dialysis Sessions (${_items.length})',
          emptyText: 'No dialysis sessions scheduled.',
          rows: _items,
        ),
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
