import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api/medcore_api_client.dart';
import '../../core/state/medcore_app_controller.dart';

/// Authoritative Patient Financial Ledger, Documents & Financial Reports Workspace.
/// Hard Invariant: Flutter NEVER calculates a second financial truth. Every balance,
/// charge, payment, discount, debt, attribution, trial-balance bucket, and document
/// is read directly from Local MedCore Service (MariaDB authoritative ledger).
class PatientFinancialLedgerScreen extends StatefulWidget {
  final MedCoreAppController controller;

  const PatientFinancialLedgerScreen({
    super.key,
    required this.controller,
  });

  @override
  State<PatientFinancialLedgerScreen> createState() => _PatientFinancialLedgerScreenState();
}

class _PatientFinancialLedgerScreenState extends State<PatientFinancialLedgerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _patientIdInputCtrl = TextEditingController();

  List<Map<String, dynamic>> _patients = const <Map<String, dynamic>>[];
  int? _selectedPatientId;
  int? _selectedVisitId;

  Map<String, dynamic>? _patientLedger;
  Map<String, dynamic>? _invoiceDoc;
  Map<String, dynamic>? _receiptDoc;
  Map<String, dynamic>? _statementDoc;
  Map<String, dynamic>? _outstandingReport;
  Map<String, dynamic>? _financialHistoryReport;
  Map<String, dynamic>? _allocationReport;

  bool _loading = true;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    _selectedPatientId = widget.controller.focusedPatientIdForLedger;
    if (_selectedPatientId != null) {
      _patientIdInputCtrl.text = _selectedPatientId.toString();
    }
    _initializeFinanceWorkspace();
  }

  @override
  void didUpdateWidget(covariant PatientFinancialLedgerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final focused = widget.controller.focusedPatientIdForLedger;
    if (focused != null && focused != _selectedPatientId) {
      _selectedPatientId = focused;
      _patientIdInputCtrl.text = focused.toString();
      _loadPatientLedgerAndDocs(focused);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _patientIdInputCtrl.dispose();
    super.dispose();
  }

  Future<void> _initializeFinanceWorkspace() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    final cfg = widget.controller.facilityConfig;
    final user = widget.controller.currentUser;
    if (user == null) return;

    try {
      if (cfg.isModuleEnabled('Patients') && user.hasAnyPermission(const ['patients'])) {
        final pRes = await widget.controller.api.getJson('/api/v1/patients');
        final rawItems = pRes['items'] as List? ?? const [];
        _patients = rawItems.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        if (_selectedPatientId == null && _patients.isNotEmpty) {
          _selectedPatientId = int.tryParse(_patients.first['id'].toString());
          if (_selectedPatientId != null) {
            _patientIdInputCtrl.text = _selectedPatientId.toString();
          }
        }
      }

      if (_selectedPatientId != null && user.hasAnyPermission(const ['finance_Invoices'])) {
        await _loadPatientLedgerAndDocs(_selectedPatientId!, updateLoadingState: false);
      }

      if (user.hasAnyPermission(const ['finance_Revenue'])) {
        await _loadTenantFinancialReports(updateLoadingState: false);
      }
    } on MedCoreApiException catch (e) {
      _errorMsg = e.toString();
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _loadPatientLedgerAndDocs(
    int patientId, {
    bool updateLoadingState = true,
  }) async {
    if (updateLoadingState) {
      setState(() {
        _loading = true;
        _errorMsg = null;
      });
    }
    try {
      final ledger = await widget.controller.api.getJson(
        '/api/v1/finance/patients/$patientId/ledger',
      );
      final statement = await widget.controller.api.getJson(
        '/api/v1/finance/documents/patient-statement/$patientId',
      );
      final visits = (ledger['visits'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      int? visitIdToLoad = _selectedVisitId;
      if (visits.isNotEmpty &&
          (visitIdToLoad == null || !visits.any((v) => v['visitId'] == visitIdToLoad))) {
        visitIdToLoad = visits.last['visitId'] as int?;
      } else if (visits.isEmpty) {
        visitIdToLoad = null;
      }

      Map<String, dynamic>? invoice;
      Map<String, dynamic>? receipt;
      if (visitIdToLoad != null) {
        invoice = await widget.controller.api.getJson(
          '/api/v1/finance/documents/invoice/$visitIdToLoad',
        );
        receipt = await widget.controller.api.getJson(
          '/api/v1/finance/documents/receipt/$visitIdToLoad',
        );
      }

      if (!mounted) return;
      setState(() {
        _selectedPatientId = patientId;
        _selectedVisitId = visitIdToLoad;
        _patientLedger = ledger;
        _statementDoc = statement;
        _invoiceDoc = invoice;
        _receiptDoc = receipt;
        if (updateLoadingState) _loading = false;
      });
    } on MedCoreApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = e.toString();
        if (updateLoadingState) _loading = false;
      });
    }
  }

  Future<void> _loadVisitDocuments(int visitId) async {
    setState(() {
      _selectedVisitId = visitId;
      _errorMsg = null;
    });
    try {
      final invoice = await widget.controller.api.getJson(
        '/api/v1/finance/documents/invoice/$visitId',
      );
      final receipt = await widget.controller.api.getJson(
        '/api/v1/finance/documents/receipt/$visitId',
      );
      if (!mounted) return;
      setState(() {
        _invoiceDoc = invoice;
        _receiptDoc = receipt;
      });
    } on MedCoreApiException catch (e) {
      if (!mounted) return;
      setState(() => _errorMsg = e.toString());
    }
  }

  Future<void> _loadTenantFinancialReports({bool updateLoadingState = true}) async {
    if (updateLoadingState) {
      setState(() {
        _loading = true;
        _errorMsg = null;
      });
    }
    try {
      final outstanding = await widget.controller.api.getJson(
        '/api/v1/finance/reports/outstanding-balances',
      );
      final history = await widget.controller.api.getJson(
        '/api/v1/finance/reports/financial-history',
      );
      final allocations = await widget.controller.api.getJson(
        '/api/v1/finance/reports/allocations',
      );
      if (!mounted) return;
      setState(() {
        _outstandingReport = outstanding;
        _financialHistoryReport = history;
        _allocationReport = allocations;
        if (updateLoadingState) _loading = false;
      });
    } on MedCoreApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = e.toString();
        if (updateLoadingState) _loading = false;
      });
    }
  }

  Future<void> _copyJsonToClipboard(String label, Map<String, dynamic> doc) async {
    final formatted = const JsonEncoder.withIndent('  ').convert(doc);
    await Clipboard.setData(ClipboardData(text: formatted));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied authoritative $label payload to clipboard.')),
    );
  }

  Future<void> _showCollectArDialog(BuildContext context) async {
    if (_selectedPatientId == null) return;
    final summary = _patientLedger?['summary'] as Map<String, dynamic>?;
    final currentArBalance = summary?['outstandingBalance']?.toString() ?? '0.00';

    final amountCtrl = TextEditingController(text: currentArBalance != '0.00' ? currentArBalance : '');
    final notesCtrl = TextEditingController();
    String? dialogError;

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Collect Patient AR (Standalone)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Patient ID: $_selectedPatientId'),
                Text('Current AR Balance: $currentArBalance'),
                const SizedBox(height: 12),
                if (dialogError != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(bottom: 8),
                    color: Colors.red.shade100,
                    child: Text(dialogError!, style: TextStyle(color: Colors.red.shade900)),
                  ),
                TextField(
                  key: const Key('input_ar_collection_amount'),
                  controller: amountCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Collection Amount',
                    hintText: '0.00',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('input_ar_collection_notes'),
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Notes / Reference',
                    hintText: 'e.g. Cash settlement at counter',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              key: const Key('btn_submit_collect_ar'),
              onPressed: () async {
                final amtStr = amountCtrl.text.trim();
                if (amtStr.isEmpty) {
                  setDialogState(() => dialogError = 'Amount is required.');
                  return;
                }
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await widget.controller.api.postJson('/api/v1/finance/ar-collections', {
                    'patientId': _selectedPatientId,
                    'amount': amtStr,
                    'paymentMethod': 'CASH',
                    'notes': notesCtrl.text.trim(),
                    'idempotencyKey': 'AR-COLL-${DateTime.now().millisecondsSinceEpoch}',
                  });
                  if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Successfully collected AR amount: $amtStr')),
                    );
                    await _loadPatientLedgerAndDocs(_selectedPatientId!);
                  }
                } on MedCoreApiException catch (e) {
                  setDialogState(() => dialogError = e.message);
                } catch (e) {
                  setDialogState(() => dialogError = e.toString());
                }
              },
              child: const Text('Post Collection Leg'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final visits = ((_patientLedger?['visits'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header & Patient / Visit Context Selector
        Container(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(bottom: BorderSide(color: cs.outlineVariant)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Patient Financial Ledger, Documents & Allocation Reports',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Direct MariaDB read-back via Local MedCore Service • Zero duplicated client-side accounting truth',
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (_patients.isNotEmpty)
                    SizedBox(
                      width: 280,
                      child: DropdownButtonFormField<int>(
                        key: const Key('dropdown_ledger_patient'),
                        isExpanded: true,
                        value: _patients.any((p) =>
                                int.tryParse(p['id'].toString()) == _selectedPatientId)
                            ? _selectedPatientId
                            : null,
                        decoration: const InputDecoration(labelText: 'Patient Account'),
                        items: _patients
                            .map(
                              (p) => DropdownMenuItem<int>(
                                value: int.parse(p['id'].toString()),
                                child: Text(
                                  '#${p['id']} ${p['fullName']} (${p['mrn']})',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (pid) {
                          if (pid != null) {
                            _patientIdInputCtrl.text = pid.toString();
                            _loadPatientLedgerAndDocs(pid);
                          }
                        },
                      ),
                    )
                  else
                    SizedBox(
                      width: 150,
                      child: TextField(
                        key: const Key('input_ledger_patient_id'),
                        controller: _patientIdInputCtrl,
                        decoration: const InputDecoration(labelText: 'Patient ID'),
                        onSubmitted: (v) {
                          final pid = int.tryParse(v.trim());
                          if (pid != null) _loadPatientLedgerAndDocs(pid);
                        },
                      ),
                    ),
                  const SizedBox(width: 10),
                  if (visits.isNotEmpty) ...[
                    SizedBox(
                      width: 210,
                      child: DropdownButtonFormField<int>(
                        key: const Key('dropdown_ledger_visit'),
                        isExpanded: true,
                        value: visits.any((v) => v['visitId'] == _selectedVisitId)
                            ? _selectedVisitId
                            : null,
                        decoration: const InputDecoration(labelText: 'Visit Document'),
                        items: visits
                            .map(
                              (v) => DropdownMenuItem<int>(
                                value: v['visitId'] as int,
                                child: Text(
                                  '${v['visitNumber']} (${v['status']})',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (vid) {
                          if (vid != null) _loadVisitDocuments(vid);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  OutlinedButton.icon(
                    key: const Key('btn_refresh_finance'),
                    onPressed: _loading ? null : _initializeFinanceWorkspace,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Refresh'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    key: const Key('btn_collect_patient_ar'),
                    onPressed: (_loading || _selectedPatientId == null)
                        ? null
                        : () => _showCollectArDialog(context),
                    icon: const Icon(Icons.payments, size: 18),
                    label: const Text('Collect AR'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: const [
                  Tab(text: '1. Patient Financial Account'),
                  Tab(text: '2. Invoice'),
                  Tab(text: '3. Payment Receipt'),
                  Tab(text: '4. Patient Statement'),
                  Tab(text: '5. Outstanding Balances'),
                  Tab(text: '6. Financial History & Trial Balance'),
                  Tab(text: '7. Doctor / Clinic / Lab Allocations'),
                ],
              ),
            ],
          ),
        ),

        if (_errorMsg != null)
          Container(
            color: cs.errorContainer,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            child: SelectableText(
              _errorMsg!,
              style: TextStyle(color: cs.onErrorContainer),
            ),
          ),

        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildPatientAccountTab(context),
                    _buildInvoiceTab(context),
                    _buildReceiptTab(context),
                    _buildStatementTab(context),
                    _buildOutstandingBalancesTab(context),
                    _buildFinancialHistoryTab(context),
                    _buildAllocationsTab(context),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildPatientAccountTab(BuildContext context) {
    final ledger = _patientLedger;
    if (ledger == null) {
      return const Center(
        child: Text('Select a registered patient to inspect their authoritative MariaDB financial ledger.'),
      );
    }

    final pat = Map<String, dynamic>.from(ledger['patient'] as Map);
    final summary = Map<String, dynamic>.from(ledger['accountSummary'] as Map);
    final attr = Map<String, dynamic>.from(ledger['financialAttribution'] as Map);
    final history = (ledger['financialHistory'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final visits = (ledger['visits'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final gaps = (ledger['documentedBackendGaps'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final currency = (summary['currency'] ?? 'EGP').toString();

    return ListView(
      key: const Key('ledger_account_scroll'),
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.person_outline, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${pat['fullName']} • MRN: ${pat['mrn']} (ID #${pat['id']})',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Phone: ${pat['phone'] ?? '-'} • Insurance: ${pat['insuranceCompanyId'] ?? 'Self-Pay'} (Policy: ${pat['insurancePolicyNo'] ?? '-'})',
                      ),
                    ],
                  ),
                ),
                Chip(
                  label: Text(
                    'Outstanding Debt: ${summary['outstandingPatientDebt']} $currency',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _LedgerStatTile('Authoritative Balance', '${summary['authoritativePatientBalance']} $currency'),
            _LedgerStatTile('Total Gross Charges', '${summary['totalGrossCharges']} $currency'),
            _LedgerStatTile('Total Discounts', '${summary['totalDiscounts']} $currency'),
            _LedgerStatTile('Total Net Billed', '${summary['totalNetBilled']} $currency'),
            _LedgerStatTile('Insurance Responsibility', '${summary['totalInsuranceResponsibility']} $currency'),
            _LedgerStatTile('Patient Responsibility', '${summary['totalPatientResponsibility']} $currency'),
            _LedgerStatTile('Payments Collected', '${summary['totalPaymentsCollected']} $currency'),
            _LedgerStatTile('Refund-Marked Visits', '${summary['visitsMarkedRefundedAmount']} $currency'),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Authoritative Revenue & Cost Attribution (FIN-004)',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 18,
                  runSpacing: 8,
                  children: [
                    Text('Hospital Service Labor Net: ${attr['hospitalServiceLaborBilled']} $currency'),
                    Text('Doctor Commission Accrued: ${attr['doctorCommissionAccrued']} $currency'),
                    Text(
                      'Hospital Retained Labor: ${attr['hospitalRetainedLaborAfterDoctorCommission']} $currency',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text('Hospital Consumables Billed: ${attr['hospitalConsumablesBilled']} $currency'),
                    Text('Consumables FIFO Cost: ${attr['hospitalConsumablesFifoCost']} $currency'),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'By Department: ${jsonEncode(attr['byDepartment'] ?? {})} • By Clinic: ${jsonEncode(attr['byClinic'] ?? {})} • By Service Category: ${jsonEncode(attr['byServiceCategory'] ?? {})}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Patient Visits & Responsible Payer Breakdown (${visits.length})',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                if (visits.isEmpty)
                  const Text('No financial visits recorded for this patient.')
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Visit / Invoice')),
                        DataColumn(label: Text('Date (UTC)')),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('Responsible Entity')),
                        DataColumn(label: Text('Gross')),
                        DataColumn(label: Text('Discount')),
                        DataColumn(label: Text('Insurance')),
                        DataColumn(label: Text('Patient Resp.')),
                        DataColumn(label: Text('Paid')),
                        DataColumn(label: Text('Balance')),
                      ],
                      rows: visits
                          .map(
                            (v) => DataRow(
                              cells: [
                                DataCell(Text('${v['visitNumber']} / ${v['invoiceNumber']}')),
                                DataCell(Text('${v['createdAt'] ?? '-'}')),
                                DataCell(Text('${v['status']}')),
                                DataCell(Text('${v['responsibleEntity']}')),
                                DataCell(Text('${v['grossAmount']}')),
                                DataCell(Text('${v['discountAmount']}')),
                                DataCell(Text('${v['insuranceCoveredAmount']}')),
                                DataCell(Text('${v['patientResponsibilityAmount']}')),
                                DataCell(Text('${v['paidAmount']}')),
                                DataCell(Text('${v['balanceAmount']}')),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Immutable Double-Entry Financial Events & Postings (${history.length})',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                if (history.isEmpty)
                  const Text('No immutable financial postings recorded for this patient.')
                else
                  for (final ev in history)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${ev['entryType']} • Ref: ${ev['documentReference']} • Event UUID: ${ev['eventUuid']} • ${ev['dateUtc']}',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              'Net: ${ev['netAmount']} • Paid: ${ev['paidAmount']} • Balance: ${ev['balanceAmount']} • Doctor Commission: ${ev['doctorCommissionAmount']} • Responsible: ${ev['responsibleEntity']}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 6),
                            for (final p in (ev['postings'] as List? ?? const []))
                              Text(
                                '  ↳ [${(p as Map)['direction']}] ${p['accountBucket']}: ${p['amount']} (${p['postingType']}${p['beneficiaryType'] != null ? ' • ${p['beneficiaryType']} #${p['beneficiaryId']}' : ''})',
                                style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
        if (gaps.isNotEmpty) ...[
          const SizedBox(height: 16),
          _BackendGapDisclosureCard(gaps: gaps),
        ],
      ],
    );
  }

  Widget _buildInvoiceTab(BuildContext context) {
    final doc = _invoiceDoc;
    if (doc == null) {
      return const Center(child: Text('No visit selected or no visits exist for this patient.'));
    }
    final totals = Map<String, dynamic>.from(doc['totals'] as Map);
    final pat = Map<String, dynamic>.from(doc['patient'] as Map);
    final fac = Map<String, dynamic>.from(doc['facility'] as Map);
    final clinical = Map<String, dynamic>.from(doc['clinicalContext'] as Map);
    final items = (doc['lineItems'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'INVOICE ${doc['documentNumber']} (Visit ${doc['visitNumber']})',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _copyJsonToClipboard('Invoice', doc),
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy Authoritative JSON'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Facility: ${fac['facilityName']} (${fac['hospitalCode']} • ${fac['branchCode']}) • Issued: ${doc['issuedAt']} • Status: ${doc['status']}',
                ),
                Text(
                  'Patient: ${pat['fullName']} (MRN: ${pat['mrn']}) • Doctor: ${clinical['doctorName'] ?? '-'} • Shift: ${clinical['shiftCode'] ?? '-'}',
                ),
                const Divider(height: 24),
                DataTable(
                  columns: const [
                    DataColumn(label: Text('Code')),
                    DataColumn(label: Text('Service / Item')),
                    DataColumn(label: Text('Type')),
                    DataColumn(label: Text('Qty')),
                    DataColumn(label: Text('Gross')),
                    DataColumn(label: Text('Discount')),
                    DataColumn(label: Text('Net')),
                  ],
                  rows: items
                      .map(
                        (it) => DataRow(
                          cells: [
                            DataCell(Text('${it['serviceCode']}')),
                            DataCell(Text('${it['serviceName']}')),
                            DataCell(Text('${it['itemType']}')),
                            DataCell(Text('${it['quantity']}')),
                            DataCell(Text('${it['grossAmount']}')),
                            DataCell(Text('${it['discountAmount']}')),
                            DataCell(Text('${it['netAmount']}')),
                          ],
                        ),
                      )
                      .toList(),
                ),
                const Divider(height: 24),
                Wrap(
                  spacing: 20,
                  runSpacing: 8,
                  children: [
                    Text('Gross: ${totals['grossAmount']} ${totals['currency']}'),
                    Text('Discount: ${totals['discountAmount']} ${totals['currency']}'),
                    Text('Net: ${totals['netAmount']} ${totals['currency']}'),
                    Text('Insurance Covered: ${totals['insuranceCoveredAmount']} ${totals['currency']}'),
                    Text('Patient Responsibility: ${totals['patientResponsibilityAmount']} ${totals['currency']}'),
                    Text('Paid: ${totals['paidAmount']} ${totals['currency']}'),
                    Text(
                      'Balance Due: ${totals['balanceDue']} ${totals['currency']}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
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

  Widget _buildReceiptTab(BuildContext context) {
    final doc = _receiptDoc;
    if (doc == null) {
      return const Center(child: Text('No visit receipt loaded.'));
    }
    final fac = Map<String, dynamic>.from(doc['facility'] as Map);
    final pat = Map<String, dynamic>.from(doc['patient'] as Map);
    final shift = Map<String, dynamic>.from(doc['cashierShift'] as Map);
    final pay = Map<String, dynamic>.from(doc['paymentSummary'] as Map);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'PAYMENT RECEIPT ${doc['receiptNumber']}',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _copyJsonToClipboard('Payment Receipt', doc),
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy Authoritative JSON'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      key: const Key('btn_print_receipt_escpos'),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          final res = await widget.controller.api.postJson('/api/v1/printing/format', {
                            'format': 'ESC_POS',
                            'documentType': 'RECEIPT',
                            'documentId': doc['receiptNumber'] ?? 'REC-1',
                            'facilityName': fac['facilityName'] ?? 'MedCore Hospital',
                            'patientName': pat['fullName'] ?? 'Patient',
                            'patientMrn': pat['mrn'] ?? 'MRN-000',
                            'grossAmount': doc['grossAmount']?.toString() ?? '0',
                            'netAmount': doc['netAmount']?.toString() ?? '0',
                            'paidAmount': doc['paidAmount']?.toString() ?? '0',
                            'balanceAmount': doc['balanceAmount']?.toString() ?? '0',
                            'currency': doc['currency'] ?? 'EGP',
                          });
                          if (!mounted) return;
                          messenger.showSnackBar(
                            SnackBar(content: Text('Thermal Print Queued: ${res['jobId']} (${res['status']})')),
                          );
                        } catch (e) {
                          if (!mounted) return;
                          messenger.showSnackBar(
                            SnackBar(content: Text('Print error: $e')),
                          );
                        }
                      },
                      icon: const Icon(Icons.print, size: 16),
                      label: const Text('Print Receipt (ESC/POS)'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Facility: ${fac['facilityName']} (${fac['hospitalCode']})'),
                Text('Invoice Ref: ${doc['invoiceNumber']} • Visit: ${doc['visitNumber']} (${doc['visitStatus']})'),
                Text('Immutable Financial Event UUID: ${doc['financialEventUuid'] ?? '-'}'),
                Text('Collected At (UTC): ${doc['collectedAtUtc'] ?? '-'}'),
                Text(
                  'Cashier Shift: ${shift['shiftCode'] ?? '-'} • Cashier: ${shift['cashierName'] ?? '-'} (${shift['cashierStaffCode'] ?? '-'})',
                ),
                const Divider(height: 24),
                Text('Patient: ${pat['fullName']} (MRN: ${pat['mrn']})'),
                const SizedBox(height: 8),
                Text('Patient Responsibility: ${pay['patientResponsibilityAmount']} ${pay['currency']}'),
                Text(
                  'Amount Received: ${pay['amountReceived']} ${pay['currency']}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text('Remaining Balance on Visit: ${pay['remainingPatientBalanceOnVisit']} ${pay['currency']}'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatementTab(BuildContext context) {
    final doc = _statementDoc;
    if (doc == null) {
      return const Center(child: Text('Select a patient to view their Statement of Account.'));
    }
    final pat = Map<String, dynamic>.from(doc['patient'] as Map);
    final summary = Map<String, dynamic>.from(doc['accountSummary'] as Map);
    final lines = (doc['statementLines'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'PATIENT STATEMENT OF ACCOUNT — ${pat['fullName']} (${pat['mrn']})',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _copyJsonToClipboard('Patient Statement', doc),
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy Statement JSON'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Generated (UTC): ${doc['generatedAtUtc']} • Closing Authoritative Balance: ${summary['authoritativePatientBalance']} ${summary['currency']}',
                ),
                const SizedBox(height: 12),
                if (lines.isEmpty)
                  const Text('No statement lines recorded.')
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Date')),
                        DataColumn(label: Text('Reference')),
                        DataColumn(label: Text('Description')),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('Patient Debit')),
                        DataColumn(label: Text('Payment Credit')),
                        DataColumn(label: Text('Running Balance')),
                      ],
                      rows: lines
                          .map(
                            (l) => DataRow(
                              cells: [
                                DataCell(Text('${l['date'] ?? '-'}')),
                                DataCell(Text('${l['reference']}')),
                                DataCell(Text('${l['description']}')),
                                DataCell(Text('${l['status']}')),
                                DataCell(Text('${l['patientDebit']}')),
                                DataCell(Text('${l['patientPaymentCredit']}')),
                                DataCell(Text('${l['runningComputedBalance']}')),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOutstandingBalancesTab(BuildContext context) {
    final rep = _outstandingReport;
    if (rep == null) {
      return const Center(
        child: Text('Outstanding Balance Report requires finance_Revenue permission.'),
      );
    }
    final summary = Map<String, dynamic>.from(rep['summary'] as Map);
    final patients = (rep['patientsWithDebt'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final openVisits = (rep['openReceivableVisits'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _LedgerStatTile('Patients With Open Debt', '${summary['patientsWithDebtCount']}'),
            _LedgerStatTile('Total Patient Balances', '${summary['totalPatientOutstandingBalance']}'),
            _LedgerStatTile('Ledger AR (Patient Bucket)', '${summary['ledgerArPatientBucket']}'),
            _LedgerStatTile('Ledger AR (Insurance Bucket)', '${summary['ledgerArInsuranceBucket']}'),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Patients With Positive Outstanding Debt (${patients.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (patients.isEmpty)
                  const Text('Zero patients currently hold unpaid debt.')
                else
                  DataTable(
                    columns: const [
                      DataColumn(label: Text('ID')),
                      DataColumn(label: Text('MRN')),
                      DataColumn(label: Text('Patient Name')),
                      DataColumn(label: Text('Phone')),
                      DataColumn(label: Text('Outstanding Balance')),
                    ],
                    rows: patients
                        .map(
                          (p) => DataRow(
                            cells: [
                              DataCell(Text('#${p['patientId']}')),
                              DataCell(Text('${p['mrn']}')),
                              DataCell(Text('${p['fullName']}')),
                              DataCell(Text('${p['phone'] ?? '-'}')),
                              DataCell(Text('${p['outstandingBalance']}')),
                            ],
                          ),
                        )
                        .toList(),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Visits With Open Patient or Insurance Receivable (${openVisits.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (openVisits.isEmpty)
                  const Text('No open receivable visits.')
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Visit')),
                        DataColumn(label: Text('Patient')),
                        DataColumn(label: Text('Net')),
                        DataColumn(label: Text('Insurance AR')),
                        DataColumn(label: Text('Paid')),
                        DataColumn(label: Text('Patient Balance Due')),
                      ],
                      rows: openVisits
                          .map(
                            (v) => DataRow(
                              cells: [
                                DataCell(Text('${v['visitNumber']}')),
                                DataCell(Text('${v['patientName']} (${v['mrn']})')),
                                DataCell(Text('${v['netAmount']}')),
                                DataCell(Text('${v['insuranceCoveredAmount']}')),
                                DataCell(Text('${v['paidAmount']}')),
                                DataCell(Text('${v['patientBalanceDue']}')),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFinancialHistoryTab(BuildContext context) {
    final rep = _financialHistoryReport;
    if (rep == null) {
      return const Center(
        child: Text('Financial History & Trial Balance requires finance_Revenue permission.'),
      );
    }
    final tb = Map<String, dynamic>.from(rep['trialBalance'] as Map);
    final buckets = (tb['buckets'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final events = (rep['events'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Double-Entry Trial Balance Conservation: ${tb['isBalanced'] == true ? 'BALANCED (PASS)' : 'IMBALANCED (ALERT)'}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                Text(
                  'Total Debits: ${tb['totalDebits']} == Total Credits: ${tb['totalCredits']}',
                ),
                const SizedBox(height: 10),
                if (buckets.isNotEmpty)
                  DataTable(
                    columns: const [
                      DataColumn(label: Text('Account Bucket')),
                      DataColumn(label: Text('Total Debits')),
                      DataColumn(label: Text('Total Credits')),
                      DataColumn(label: Text('Posted Legs')),
                    ],
                    rows: buckets
                        .map(
                          (b) => DataRow(
                            cells: [
                              DataCell(Text('${b['accountBucket']}')),
                              DataCell(Text('${b['totalDebits']}')),
                              DataCell(Text('${b['totalCredits']}')),
                              DataCell(Text('${b['legsCount']}')),
                            ],
                          ),
                        )
                        .toList(),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recent Financial Events (${events.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                for (final e in events.take(25))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '#${e['id']} ${e['eventType']} (${e['sourceEntityType']} #${e['sourceEntityId']}) — Net: ${e['netAmount']} • Paid: ${e['paidAmount']}',
                    ),
                    subtitle: Text(
                      'UUID: ${e['eventUuid']} • Commission: ${e['commissionAmount']} • ${e['createdAt']}',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAllocationsTab(BuildContext context) {
    final rep = _allocationReport;
    if (rep == null) {
      return const Center(
        child: Text('Allocation Report requires finance_Revenue permission.'),
      );
    }
    final docs = (rep['doctorCommissionLedger'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final srvAttr = (rep['clinicDepartmentAndLabServiceAttribution'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final compSplit = (rep['hospitalComponentSplit'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final gaps = (rep['documentedBackendGaps'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Doctor Commission Payable Sub-Ledger (PAYABLE_COMMISSION_DOCTOR)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (docs.isEmpty)
                  const Text('No doctor commission postings accrued yet.')
                else
                  DataTable(
                    columns: const [
                      DataColumn(label: Text('Doctor')),
                      DataColumn(label: Text('Dept / Clinic')),
                      DataColumn(label: Text('Accrued')),
                      DataColumn(label: Text('Settled')),
                      DataColumn(label: Text('Net Payable')),
                    ],
                    rows: docs
                        .map(
                          (d) => DataRow(
                            cells: [
                              DataCell(Text('${d['doctorName']} (${d['staffCode'] ?? '-'})')),
                              DataCell(Text('${d['departmentId'] ?? '-'} / ${d['clinicId'] ?? '-'}')),
                              DataCell(Text('${d['accruedCommission']}')),
                              DataCell(Text('${d['settledCommission']}')),
                              DataCell(Text('${d['netPayableBalance']}')),
                            ],
                          ),
                        )
                        .toList(),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Hospital Service Labor vs Consumable Material Cost Split (FIN-004)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (compSplit.isEmpty)
                  const Text('No cost-split lines posted yet.')
                else
                  DataTable(
                    columns: const [
                      DataColumn(label: Text('Component Type')),
                      DataColumn(label: Text('Billed Gross')),
                      DataColumn(label: Text('Billed Net')),
                      DataColumn(label: Text('FIFO COGS')),
                    ],
                    rows: compSplit
                        .map(
                          (c) => DataRow(
                            cells: [
                              DataCell(Text('${c['componentType']}')),
                              DataCell(Text('${c['billedGross']}')),
                              DataCell(Text('${c['billedNet']}')),
                              DataCell(Text('${c['fifoCogs']}')),
                            ],
                          ),
                        )
                        .toList(),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Clinic / Department / Lab / Service Item Attribution',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (srvAttr.isEmpty)
                  const Text('No visit line items posted yet.')
                else
                  DataTable(
                    columns: const [
                      DataColumn(label: Text('Department')),
                      DataColumn(label: Text('Clinic')),
                      DataColumn(label: Text('Item Category')),
                      DataColumn(label: Text('Count')),
                      DataColumn(label: Text('Net Billed')),
                    ],
                    rows: srvAttr
                        .map(
                          (s) => DataRow(
                            cells: [
                              DataCell(Text('${s['departmentId']}')),
                              DataCell(Text('${s['clinicId']}')),
                              DataCell(Text('${s['itemType']}')),
                              DataCell(Text('${s['itemCount']}')),
                              DataCell(Text('${s['netBilled']}')),
                            ],
                          ),
                        )
                        .toList(),
                  ),
              ],
            ),
          ),
        ),
        if (gaps.isNotEmpty) ...[
          const SizedBox(height: 16),
          _BackendGapDisclosureCard(gaps: gaps),
        ],
      ],
    );
  }
}

class _LedgerStatTile extends StatelessWidget {
  final String label;
  final String value;

  const _LedgerStatTile(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 215,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _BackendGapDisclosureCard extends StatelessWidget {
  final List<Map<String, dynamic>> gaps;

  const _BackendGapDisclosureCard({required this.gaps});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.secondaryContainer.withOpacity(0.45),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.info_outline, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Explicit Accounting Capability Disclosures (BACKEND_GAP — No Fabricated Ledger Math)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final g in gaps)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '• [${g['gapId']} / ${g['status']}] ${g['description']}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
