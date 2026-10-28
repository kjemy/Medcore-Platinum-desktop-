import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import '../../core/api/medcore_api_client.dart';
import '../../core/state/medcore_app_controller.dart';

/// Cashier Shifts & Atomic Visit Checkout Workspace.
/// Strictly delegates all financial math, cost-split posting, and shift reconciliation
/// to `LocalMedCoreServer` (`/api/v1/shifts/*` and `/api/v1/visits`).
/// Zero floating-point currency arithmetic in Flutter.
class ShiftsAndVisitsScreen extends StatefulWidget {
  final MedCoreAppController controller;

  const ShiftsAndVisitsScreen({
    super.key,
    required this.controller,
  });

  @override
  State<ShiftsAndVisitsScreen> createState() => _ShiftsAndVisitsScreenState();
}

class _ShiftsAndVisitsScreenState extends State<ShiftsAndVisitsScreen> {
  // Open Shift inputs
  final TextEditingController _shiftCodeCtrl = TextEditingController();
  final TextEditingController _openingBalCtrl = TextEditingController(text: '0.0000');

  // Visit Checkout inputs
  final TextEditingController _visitNumberCtrl = TextEditingController();
  final TextEditingController _idempotencyCtrl = TextEditingController();
  final TextEditingController _patientIdCtrl = TextEditingController();
  final TextEditingController _doctorIdCtrl = TextEditingController();
  final TextEditingController _shiftIdCtrl = TextEditingController();
  final TextEditingController _serviceCodeCtrl = TextEditingController(text: 'SRV-001');
  final TextEditingController _serviceNameCtrl = TextEditingController(text: 'Outpatient Consultation');
  final TextEditingController _laborGrossCtrl = TextEditingController(text: '0.0000');
  final TextEditingController _consumableGrossCtrl = TextEditingController(text: '0.0000');
  final TextEditingController _consumableFifoCtrl = TextEditingController(text: '0.0000');
  final TextEditingController _discountCtrl = TextEditingController(text: '0.0000');
  final TextEditingController _insuranceCtrl = TextEditingController(text: '0.0000');
  final TextEditingController _paidCtrl = TextEditingController(text: '0.0000');
  final TextEditingController _commissionPctCtrl = TextEditingController(text: '0.0000');

  Map<String, dynamic>? _openShift;
  List<Map<String, dynamic>> _shifts = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _patients = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _doctors = const <Map<String, dynamic>>[];
  Map<String, dynamic>? _lastCreatedVisit;

  bool _loading = true;
  String? _feedback;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _loadWorkspaceData();
  }

  @override
  void dispose() {
    _shiftCodeCtrl.dispose();
    _openingBalCtrl.dispose();
    _visitNumberCtrl.dispose();
    _idempotencyCtrl.dispose();
    _patientIdCtrl.dispose();
    _doctorIdCtrl.dispose();
    _shiftIdCtrl.dispose();
    _serviceCodeCtrl.dispose();
    _serviceNameCtrl.dispose();
    _laborGrossCtrl.dispose();
    _consumableGrossCtrl.dispose();
    _consumableFifoCtrl.dispose();
    _discountCtrl.dispose();
    _insuranceCtrl.dispose();
    _paidCtrl.dispose();
    _commissionPctCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadWorkspaceData() async {
    setState(() => _loading = true);
    final cfg = widget.controller.facilityConfig;
    final user = widget.controller.currentUser;
    if (user == null) return;

    Map<String, dynamic>? openShift;
    var shifts = <Map<String, dynamic>>[];
    var patients = <Map<String, dynamic>>[];
    var doctors = <Map<String, dynamic>>[];
    String? errMsg;

    try {
      if (cfg.isModuleEnabled('Shifts') && user.hasAnyPermission(const ['shifts'])) {
        final cur = await widget.controller.api.getJson('/api/v1/shifts/current');
        if (cur['openShift'] is Map) {
          openShift = Map<String, dynamic>.from(cur['openShift'] as Map);
          if (_shiftIdCtrl.text.trim().isEmpty && openShift['id'] != null) {
            _shiftIdCtrl.text = openShift['id'].toString();
          }
        }
        final listRes = await widget.controller.api.getJson('/api/v1/shifts');
        final rawShifts = listRes['items'] as List? ?? const [];
        shifts = rawShifts.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }

      if (cfg.isModuleEnabled('Patients') && user.hasAnyPermission(const ['patients'])) {
        final pRes = await widget.controller.api.getJson('/api/v1/patients');
        final rawPatients = pRes['items'] as List? ?? const [];
        patients = rawPatients.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }

      if (cfg.isModuleEnabled('HR') && user.hasAnyPermission(const ['hr_Employees'])) {
        final sRes = await widget.controller.api.getJson('/api/v1/staff');
        final rawStaff = sRes['items'] as List? ?? const [];
        doctors = rawStaff
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((s) => (s['role'] ?? '').toString().toLowerCase().contains('doctor'))
            .toList();
      }
    } on MedCoreApiException catch (e) {
      errMsg = e.toString();
    }

    if (!mounted) return;
    setState(() {
      _openShift = openShift;
      _shifts = shifts;
      _patients = patients;
      _doctors = doctors;
      if (errMsg != null) {
        _feedback = errMsg;
        _isError = true;
      }
      _loading = false;
    });
  }

  String? _validateDecimalField(String label, String raw, {bool allowNegative = false}) {
    final parsed = Decimal.tryParse(raw.trim());
    if (parsed == null) {
      return '$label must be a valid exact decimal number (e.g. 250.0000).';
    }
    if (!allowNegative && parsed < Decimal.zero) {
      return '$label cannot be negative.';
    }
    return null;
  }

  Future<void> _openNewShift() async {
    setState(() {
      _feedback = null;
      _isError = false;
    });
    if (_shiftCodeCtrl.text.trim().isEmpty) {
      setState(() {
        _feedback = 'Shift Code is required to open a cashier shift.';
        _isError = true;
      });
      return;
    }
    final decErr = _validateDecimalField('Opening Balance', _openingBalCtrl.text);
    if (decErr != null) {
      setState(() {
        _feedback = decErr;
        _isError = true;
      });
      return;
    }

    try {
      final created = await widget.controller.api.postJson('/api/v1/shifts/open', {
        'shiftCode': _shiftCodeCtrl.text.trim(),
        'openingBalance': Decimal.parse(_openingBalCtrl.text.trim()).toStringAsFixed(4),
      });
      _shiftCodeCtrl.clear();
      if (created['id'] != null) {
        _shiftIdCtrl.text = created['id'].toString();
      }
      if (!mounted) return;
      setState(() {
        _feedback =
            'Opened Cashier Shift ${created['shiftCode']} (#${created['id']}) with opening balance ${created['openingBalance']}.';
        _isError = false;
      });
      await _loadWorkspaceData();
    } on MedCoreApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _feedback = e.toString();
        _isError = true;
      });
    }
  }

  Future<void> _showCloseShiftDialog(Map<String, dynamic> shift) async {
    final countedCtrl = TextEditingController(
      text: (shift['expectedCash'] ?? shift['openingBalance'] ?? '0.0000').toString(),
    );
    final notesCtrl = TextEditingController();
    String? dialogErr;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text('Close & Reconcile Shift ${shift['shiftCode']} (#${shift['id']})'),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Opening: ${shift['openingBalance'] ?? '0.0000'} • Cash In: ${shift['cashIn'] ?? '0.0000'} • Expected Cash: ${shift['expectedCash'] ?? '-'}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: countedCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Physical Counted Cash (Exact Decimal)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Reconciliation Notes (Optional)',
                      ),
                    ),
                    if (dialogErr != null) ...[
                      const SizedBox(height: 10),
                      Text(dialogErr!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final decErr = _validateDecimalField('Counted Cash', countedCtrl.text);
                    if (decErr != null) {
                      setDialogState(() => dialogErr = decErr);
                      return;
                    }
                    try {
                      final res = await widget.controller.api.postJson('/api/v1/shifts/close', {
                        'shiftId': shift['id'],
                        'countedCash': Decimal.parse(countedCtrl.text.trim()).toStringAsFixed(4),
                        if (notesCtrl.text.trim().isNotEmpty) 'notes': notesCtrl.text.trim(),
                      });
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      if (!mounted) return;
                      setState(() {
                        _feedback =
                            'Closed Shift #${shift['id']} • Variance: ${res['varianceAmount'] ?? '0.0000'} • Status: ${res['status'] ?? 'CLOSED'}.';
                        _isError = false;
                      });
                      await _loadWorkspaceData();
                    } on MedCoreApiException catch (e) {
                      setDialogState(() => dialogErr = e.toString());
                    }
                  },
                  child: const Text('Close Shift Atomically'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _submitAtomicVisitCheckout() async {
    setState(() {
      _feedback = null;
      _isError = false;
    });

    final visitNo = _visitNumberCtrl.text.trim();
    final idem = _idempotencyCtrl.text.trim().isNotEmpty
        ? _idempotencyCtrl.text.trim()
        : 'IDEM-$visitNo';
    final patientId = int.tryParse(_patientIdCtrl.text.trim());
    final doctorId = int.tryParse(_doctorIdCtrl.text.trim());
    final shiftId = int.tryParse(_shiftIdCtrl.text.trim());

    if (visitNo.isEmpty || patientId == null || doctorId == null || shiftId == null) {
      setState(() {
        _feedback =
            'Visit Number, Patient ID, Doctor Staff ID, and Open Shift ID are mandatory for atomic checkout.';
        _isError = true;
      });
      return;
    }

    final decimalChecks = <String, String>{
      'Service Labor Gross': _laborGrossCtrl.text,
      'Consumable Gross': _consumableGrossCtrl.text,
      'Consumable FIFO Cost': _consumableFifoCtrl.text,
      'Discount Amount': _discountCtrl.text,
      'Insurance Covered Amount': _insuranceCtrl.text,
      'Paid Amount': _paidCtrl.text,
      'Doctor Commission %': _commissionPctCtrl.text,
    };
    for (final entry in decimalChecks.entries) {
      final err = _validateDecimalField(entry.key, entry.value);
      if (err != null) {
        setState(() {
          _feedback = err;
          _isError = true;
        });
        return;
      }
    }

    try {
      final res = await widget.controller.api.postJson('/api/v1/visits', {
        'visitNumber': visitNo,
        'idempotencyKey': idem,
        'patientId': patientId,
        'doctorId': doctorId,
        'shiftId': shiftId,
        'serviceCode': _serviceCodeCtrl.text.trim().isEmpty
            ? 'SRV-001'
            : _serviceCodeCtrl.text.trim(),
        'serviceName': _serviceNameCtrl.text.trim().isEmpty
            ? 'Consultation'
            : _serviceNameCtrl.text.trim(),
        'serviceLaborGross': Decimal.parse(_laborGrossCtrl.text.trim()).toStringAsFixed(4),
        'consumableGross': Decimal.parse(_consumableGrossCtrl.text.trim()).toStringAsFixed(4),
        'consumableFifoCost': Decimal.parse(_consumableFifoCtrl.text.trim()).toStringAsFixed(4),
        'discountAmount': Decimal.parse(_discountCtrl.text.trim()).toStringAsFixed(4),
        'insuranceCoveredAmount': Decimal.parse(_insuranceCtrl.text.trim()).toStringAsFixed(4),
        'paidAmount': Decimal.parse(_paidCtrl.text.trim()).toStringAsFixed(4),
        'doctorCommissionRatePercent':
            Decimal.parse(_commissionPctCtrl.text.trim()).toStringAsFixed(4),
      });

      if (!mounted) return;
      setState(() {
        _lastCreatedVisit = res;
        _feedback =
            'Committed Visit $visitNo (ID #${res['visitId'] ?? '-'}) atomically in MariaDB with balanced double-entry postings.';
        _isError = false;
      });
      await _loadWorkspaceData();
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cfg = widget.controller.facilityConfig;
    final shiftsEnabled = cfg.isModuleEnabled('Shifts');
    final receptionEnabled = cfg.isModuleEnabled('Reception');

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
                    'Reception, Cashier Shifts & Atomic Visit Checkout',
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    'Authoritative MariaDB ACID execution (FIN-004 cost split + FIN-006 cashier shift reconciliation). Zero client-side currency math.',
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: _loading ? null : _loadWorkspaceData,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reload Shifts & Patients'),
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (_feedback != null)
          Card(
            color: _isError ? cs.errorContainer : cs.primaryContainer,
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                _feedback!,
                style: TextStyle(
                  color: _isError ? cs.onErrorContainer : cs.onPrimaryContainer,
                ),
              ),
            ),
          ),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Column: Cashier Shift Control
            if (shiftsEnabled)
              SizedBox(
                width: 400,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Active Cashier Shift',
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            if (_openShift != null) ...[
                              Text(
                                '${_openShift!['shiftCode']} (Shift ID #${_openShift!['id']})',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: cs.primary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Opening: ${_openShift!['openingBalance']} • Cash In: ${_openShift!['cashIn']} • Expected: ${_openShift!['expectedCash']}',
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                key: const Key('btn_close_active_shift'),
                                onPressed: () => _showCloseShiftDialog(_openShift!),
                                icon: const Icon(Icons.lock_clock, size: 16),
                                label: const Text('Close & Reconcile Shift'),
                              ),
                            ] else
                              const Text('No currently open shift for your cashier account.'),
                            const Divider(height: 24),
                            const Text(
                              'Open New Cashier Shift',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              key: const Key('input_shift_code'),
                              controller: _shiftCodeCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Shift Code (e.g. SH-2026-AM)',
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              key: const Key('input_shift_opening_balance'),
                              controller: _openingBalCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Opening Cash Drawer Balance (DECIMAL)',
                              ),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              key: const Key('btn_open_shift'),
                              onPressed: _openNewShift,
                              icon: const Icon(Icons.point_of_sale, size: 18),
                              label: const Text('Open Shift'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Recent Cashier Shifts (${_shifts.length})',
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            if (_shifts.isEmpty)
                              const Text('No shifts recorded yet.')
                            else
                              for (final sh in _shifts.take(8))
                                ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    '${sh['shiftCode']} (#${sh['id']}) — ${sh['status']}',
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(
                                    'Expected: ${sh['expectedCash'] ?? sh['openingBalance']} • Variance: ${sh['varianceAmount'] ?? '-'}',
                                  ),
                                  trailing: sh['status'] == 'OPEN'
                                      ? TextButton(
                                          onPressed: () {
                                            setState(() {
                                              _shiftIdCtrl.text = sh['id'].toString();
                                            });
                                          },
                                          child: const Text('Use'),
                                        )
                                      : null,
                                ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            if (shiftsEnabled && receptionEnabled) const SizedBox(width: 20),

            // Right Column: Atomic Visit Checkout
            if (receptionEnabled)
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Atomic Visit Checkout & Double-Entry Cost Split',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Posts mc_visits + mc_visit_items + mc_visit_item_cost_lines + mc_financial_events + mc_financial_postings + mc_shifts + mc_patients.balance in one MariaDB ACID transaction.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                key: const Key('input_visit_number'),
                                controller: _visitNumberCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Visit Number * (e.g. VIS-1001)',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                key: const Key('input_visit_idempotency'),
                                controller: _idempotencyCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Idempotency Key (auto if blank)',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _patients.isNotEmpty
                                  ? DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      value: _patients.any(
                                              (p) => p['id'].toString() == _patientIdCtrl.text)
                                          ? _patientIdCtrl.text
                                          : null,
                                      decoration: const InputDecoration(
                                        labelText: 'Select Patient *',
                                      ),
                                      items: _patients
                                          .map(
                                            (p) => DropdownMenuItem<String>(
                                              value: p['id'].toString(),
                                              child: Text(
                                                '#${p['id']} ${p['fullName']} (${p['mrn']})',
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) {
                                        if (v != null) {
                                          setState(() => _patientIdCtrl.text = v);
                                        }
                                      },
                                    )
                                  : TextField(
                                      key: const Key('input_visit_patient_id'),
                                      controller: _patientIdCtrl,
                                      decoration: const InputDecoration(
                                        labelText: 'Patient ID *',
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _doctors.isNotEmpty
                                  ? DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      value: _doctors.any(
                                              (d) => d['id'].toString() == _doctorIdCtrl.text)
                                          ? _doctorIdCtrl.text
                                          : null,
                                      decoration: const InputDecoration(
                                        labelText: 'Attending Doctor *',
                                      ),
                                      items: _doctors
                                          .map(
                                            (d) => DropdownMenuItem<String>(
                                              value: d['id'].toString(),
                                              child: Text(
                                                '#${d['id']} ${d['fullName']} (${d['staffCode']})',
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) {
                                        if (v != null) {
                                          setState(() => _doctorIdCtrl.text = v);
                                        }
                                      },
                                    )
                                  : TextField(
                                      key: const Key('input_visit_doctor_id'),
                                      controller: _doctorIdCtrl,
                                      decoration: const InputDecoration(
                                        labelText: 'Doctor Staff ID *',
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 130,
                              child: TextField(
                                key: const Key('input_visit_shift_id'),
                                controller: _shiftIdCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Shift ID *',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            SizedBox(
                              width: 150,
                              child: TextField(
                                controller: _serviceCodeCtrl,
                                decoration: const InputDecoration(labelText: 'Service Code'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _serviceNameCtrl,
                                decoration: const InputDecoration(labelText: 'Service Name'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                key: const Key('input_visit_labor_gross'),
                                controller: _laborGrossCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Service Labor Gross',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _consumableGrossCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Consumables Billed Gross',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _consumableFifoCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Consumables FIFO Cost',
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
                                controller: _discountCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Discount Amount',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _insuranceCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Insurance Covered',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                key: const Key('input_visit_paid'),
                                controller: _paidCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Cash Paid Now',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _commissionPctCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Doctor Commission %',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          key: const Key('btn_commit_visit'),
                          onPressed: _submitAtomicVisitCheckout,
                          icon: const Icon(Icons.receipt_long),
                          label: const Text('Commit Atomic Visit & Post Financial Ledger'),
                        ),
                        if (_lastCreatedVisit != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Last Committed Visit #${_lastCreatedVisit!['visitId']} • Net: ${_lastCreatedVisit!['netAmount'] ?? '-'} • Paid: ${_lastCreatedVisit!['paidAmount'] ?? '-'} • Patient Balance Delta: ${_lastCreatedVisit!['balanceAmount'] ?? '-'}',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                                if (int.tryParse(_patientIdCtrl.text.trim()) != null &&
                                    cfg.isModuleEnabled('Finance'))
                                  OutlinedButton.icon(
                                    onPressed: () => widget.controller.openPatientFinancialLedger(
                                      int.parse(_patientIdCtrl.text.trim()),
                                    ),
                                    icon: const Icon(Icons.account_balance_wallet_outlined, size: 16),
                                    label: const Text('Open Patient Ledger & Receipt'),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
