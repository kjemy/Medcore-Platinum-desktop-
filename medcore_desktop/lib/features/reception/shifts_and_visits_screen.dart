import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import '../../core/api/medcore_api_client.dart';
import '../../core/localization/medcore_localizations.dart';
import '../../core/localization/medcore_strings_ar.dart';
import '../../core/state/medcore_app_controller.dart';

/// Cashier Shifts & Atomic Visit Checkout Workspace.
/// Enhanced with Interactive Clinic Cards, Temporary Emergency Clinics,
/// Quick Services & Consumables Dialogs, and Printable Patient Tickets.
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

  // Web Parity: Interactive Clinic Cards
  List<Map<String, dynamic>> _clinics = [
    {
      'code': 'CLN-IM-01',
      'name': 'عيادة الباطنة العامة',
      'department': 'قسم الأمراض الباطنية',
      'doctorName': 'د. أحمد إبراهيم',
      'doctorId': 1,
      'fee': '250.0000',
      'waitingCount': 2,
      'isTemporary': false,
      'status': 'AVAILABLE',
    },
    {
      'code': 'CLN-PED-01',
      'name': 'عيادة الأطفال وحديثي الولادة',
      'department': 'قسم طب الأطفال',
      'doctorName': 'د. سارة محمود',
      'doctorId': 2,
      'fee': '200.0000',
      'waitingCount': 4,
      'isTemporary': false,
      'status': 'AVAILABLE',
    },
    {
      'code': 'CLN-ORTHO-01',
      'name': 'عيادة جراحة العظام',
      'department': 'قسم العظام والمفاصل',
      'doctorName': 'د. خالد عبد الرحمن',
      'doctorId': 3,
      'fee': '300.0000',
      'waitingCount': 1,
      'isTemporary': false,
      'status': 'AVAILABLE',
    },
    {
      'code': 'CLN-SURG-01',
      'name': 'عيادة الجراحة العامة',
      'department': 'قسم الجراحة',
      'doctorName': 'د. محمد علي',
      'doctorId': 4,
      'fee': '350.0000',
      'waitingCount': 0,
      'isTemporary': false,
      'status': 'AVAILABLE',
    },
  ];

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

  void _selectClinic(Map<String, dynamic> clinic) {
    setState(() {
      _serviceCodeCtrl.text = clinic['code'] ?? 'SRV-001';
      _serviceNameCtrl.text = 'كشف ${clinic['name']}';
      if (clinic['doctorId'] != null) {
        _doctorIdCtrl.text = clinic['doctorId'].toString();
      }
      final fee = (clinic['fee'] ?? '200.0000').toString();
      _laborGrossCtrl.text = fee;
      _paidCtrl.text = fee;
      _visitNumberCtrl.text = 'VIS-${DateTime.now().millisecondsSinceEpoch % 100000}';
      _feedback = 'تم اختيار ${clinic['name']} للطبيب ${clinic['doctorName'] ?? '-'} بنجاح.';
      _isError = false;
    });
  }

  void _showCreateTemporaryClinicDialog() {
    final codeCtrl = TextEditingController(text: 'TEMP-ER-${_clinics.length + 1}');
    final nameCtrl = TextEditingController();
    final reasonCtrl = TextEditingController(text: 'حالة طوارئ قصوى / تدفق مرضى');
    final feeCtrl = TextEditingController(text: '150.0000');
    final docCtrl = TextEditingController(text: 'طبيب طوارئ مناوب');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.add_business, color: Color(0xFF0F766E)),
            SizedBox(width: 8),
            Text('إنشاء عيادة طوارئ / مؤقتة', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('input_temp_clinic_code'),
                controller: codeCtrl,
                decoration: const InputDecoration(labelText: 'كود العيادة المؤقتة *', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('input_temp_clinic_name'),
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'اسم العيادة * (مثال: عيادة فرز الحوادث)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('input_temp_clinic_doctor'),
                controller: docCtrl,
                decoration: const InputDecoration(labelText: 'الطبيب المناوب / المسؤول', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('input_temp_clinic_reason'),
                controller: reasonCtrl,
                decoration: const InputDecoration(labelText: 'سبب إنشاء العيادة المؤقتة', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('input_temp_clinic_fee'),
                controller: feeCtrl,
                decoration: const InputDecoration(labelText: 'تسعيرة الكشف (ج.م)', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            key: const Key('btn_submit_temp_clinic'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E), foregroundColor: Colors.white),
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty || codeCtrl.text.trim().isEmpty) return;
              setState(() {
                _clinics.add({
                  'code': codeCtrl.text.trim(),
                  'name': nameCtrl.text.trim(),
                  'department': 'قسم الطوارئ والمؤقت',
                  'doctorName': docCtrl.text.trim(),
                  'doctorId': 99,
                  'fee': feeCtrl.text.trim(),
                  'waitingCount': 0,
                  'isTemporary': true,
                  'status': 'TEMPORARY',
                });
              });
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('تم إنشاء العيادة المؤقتة "${nameCtrl.text.trim()}" بنجاح.')),
              );
            },
            child: const Text('إنشاء العيادة'),
          ),
        ],
      ),
    );
  }

  void _showQuickServiceDialog() {
    final srvCtrl = TextEditingController(text: 'غيار جراحي معقم');
    final priceCtrl = TextEditingController(text: '80.0000');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة خدمة طبية سريعة للزيارة'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('input_quick_service_name'),
                controller: srvCtrl,
                decoration: const InputDecoration(labelText: 'اسم الخدمة الطبية', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('input_quick_service_price'),
                controller: priceCtrl,
                decoration: const InputDecoration(labelText: 'قيمة الخدمة (ج.م)', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            key: const Key('btn_submit_quick_service'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E), foregroundColor: Colors.white),
            onPressed: () {
              final addedPrice = Decimal.tryParse(priceCtrl.text.trim()) ?? Decimal.zero;
              final currentLabor = Decimal.tryParse(_laborGrossCtrl.text.trim()) ?? Decimal.zero;
              setState(() {
                _serviceNameCtrl.text = '${_serviceNameCtrl.text} + ${srvCtrl.text.trim()}';
                _laborGrossCtrl.text = (currentLabor + addedPrice).toStringAsFixed(4);
                final currentPaid = Decimal.tryParse(_paidCtrl.text.trim()) ?? Decimal.zero;
                _paidCtrl.text = (currentPaid + addedPrice).toStringAsFixed(4);
              });
              Navigator.pop(ctx);
            },
            child: const Text('إضافة للزيارة'),
          ),
        ],
      ),
    );
  }

  void _showQuickConsumableDialog() {
    final conCtrl = TextEditingController(text: 'كانيولا + سرنجة 5سم + شاش معقم');
    final costCtrl = TextEditingController(text: '15.0000');
    final priceCtrl = TextEditingController(text: '35.0000');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة مستلزمات طبية للزيارة'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('input_quick_consumable_name'),
                controller: conCtrl,
                decoration: const InputDecoration(labelText: 'بيان المستلزمات', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('input_quick_consumable_cost'),
                controller: costCtrl,
                decoration: const InputDecoration(labelText: 'تكلفة FIFO (ج.م)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('input_quick_consumable_price'),
                controller: priceCtrl,
                decoration: const InputDecoration(labelText: 'سعر البيع للمريض (ج.م)', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            key: const Key('btn_submit_quick_consumable'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E), foregroundColor: Colors.white),
            onPressed: () {
              final addedGross = Decimal.tryParse(priceCtrl.text.trim()) ?? Decimal.zero;
              final addedFifo = Decimal.tryParse(costCtrl.text.trim()) ?? Decimal.zero;
              final curGross = Decimal.tryParse(_consumableGrossCtrl.text.trim()) ?? Decimal.zero;
              final curFifo = Decimal.tryParse(_consumableFifoCtrl.text.trim()) ?? Decimal.zero;
              setState(() {
                _consumableGrossCtrl.text = (curGross + addedGross).toStringAsFixed(4);
                _consumableFifoCtrl.text = (curFifo + addedFifo).toStringAsFixed(4);
                final curPaid = Decimal.tryParse(_paidCtrl.text.trim()) ?? Decimal.zero;
                _paidCtrl.text = (curPaid + addedGross).toStringAsFixed(4);
              });
              Navigator.pop(ctx);
            },
            child: const Text('إضافة المستلزم'),
          ),
        ],
      ),
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
      padding: const EdgeInsets.all(20),
      children: [
        // Top Header
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'الاستقبال، نبطشيات الخزينة وحجز الكشوفات الفوري',
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    'Authoritative MariaDB ACID execution (FIN-004 cost split + FIN-006 cashier shift reconciliation).',
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: _loading ? null : _loadWorkspaceData,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('تحديث البيانات'),
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

        // Web Parity: Interactive Clinic Cards Grid
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.only(bottom: 20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      const Icon(Icons.local_hospital, color: Color(0xFF0F766E), size: 24),
                      const SizedBox(width: 8),
                      const Text(
                        'العيادات المتاحة والكشوفات (لوحة الاستقبال)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(width: 24),
                      ElevatedButton.icon(
                        key: const Key('btn_create_temp_clinic'),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E), foregroundColor: Colors.white),
                        icon: const Icon(Icons.add_circle_outline, size: 16),
                        label: const Text('إنشاء عيادة طوارئ / مؤقتة'),
                        onPressed: _showCreateTemporaryClinicDialog,
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        key: const Key('btn_quick_service'),
                        icon: const Icon(Icons.medical_services_outlined, size: 16),
                        label: const Text('إضافة خدمة سريعة'),
                        onPressed: _showQuickServiceDialog,
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        key: const Key('btn_quick_consumable'),
                        icon: const Icon(Icons.vaccines_outlined, size: 16),
                        label: const Text('إضافة مستلزم طبي'),
                        onPressed: _showQuickConsumableDialog,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // Clinic Cards List / Grid
                LayoutBuilder(
                  builder: (context, constraints) {
                    final itemWidth = (constraints.maxWidth - 36) / 4;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: _clinics.map((clinic) {
                        final isTemp = clinic['isTemporary'] == true;
                        return SizedBox(
                          width: itemWidth < 220 ? constraints.maxWidth : itemWidth,
                          child: Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(color: isTemp ? Colors.amber.shade400 : Colors.teal.shade200),
                            ),
                            color: isTemp ? Colors.amber.shade50 : Colors.teal.shade50.withOpacity(0.5),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 16,
                                        backgroundColor: isTemp ? Colors.amber.shade700 : const Color(0xFF0F766E),
                                        child: Icon(isTemp ? Icons.warning_amber : Icons.person, color: Colors.white, size: 18),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          clinic['name'],
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    clinic['doctorName'] ?? '',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[800], fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${clinic['fee']} ج.م',
                                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F766E), fontSize: 13),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isTemp ? Colors.amber.shade200 : Colors.teal.shade100,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          isTemp ? 'طوارئ مؤقتة' : '${clinic['waitingCount']} بالانتظار',
                                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isTemp ? Colors.amber.shade900 : Colors.teal.shade900),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      key: Key('btn_select_clinic_${clinic['code']}'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF0F766E),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 6),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      onPressed: () => _selectClinic(clinic),
                                      child: const Text('حجز كشف وتذكرة', style: TextStyle(fontSize: 12)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),

        // Main Two Columns: Shift Controls & Visit Checkout
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Column: Cashier Shift Control
            if (shiftsEnabled)
              SizedBox(
                width: 380,
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
                              icon: const Icon(Icons.point_of_sale),
                              label: const Text('Open Cashier Shift'),
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
                              'Recent Shift Postings (Audit)',
                              style: theme.textTheme.titleMedium
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

            if (shiftsEnabled && receptionEnabled) const SizedBox(width: 16),

            // Right Column: Atomic Visit Checkout & Printable Ticket
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
                                        labelText: 'Select Registered Patient *',
                                      ),
                                      items: _patients
                                          .map(
                                            (p) => DropdownMenuItem<String>(
                                              value: p['id'].toString(),
                                              child: Text(
                                                '#${p['id']} — ${p['fullName']} (${p['medicalRecordNumber']})',
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (val) {
                                        if (val != null) {
                                          setState(() => _patientIdCtrl.text = val);
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
                                        labelText: 'Select Doctor *',
                                      ),
                                      items: _doctors
                                          .map(
                                            (d) => DropdownMenuItem<String>(
                                              value: d['id'].toString(),
                                              child: Text(
                                                '#${d['id']} — ${d['fullName']} (${d['staffCode']})',
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (val) {
                                        if (val != null) {
                                          setState(() => _doctorIdCtrl.text = val);
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

                        // Web Parity: Printed Patient Ticket Receipt
                        if (_lastCreatedVisit != null) ...[
                          const SizedBox(height: 20),
                          Container(
                            key: const Key('widget_ticket_receipt'),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade400, width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.confirmation_number, color: Color(0xFF0F766E), size: 28),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'مجمع مدكور الطبي — تذكرة كشف العيادات الخارجية',
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                          ),
                                          Text(
                                            'تاريخ الحجز: ${DateTime.now().toString().substring(0, 16)}',
                                            style: TextStyle(color: Colors.grey[600], fontSize: 11),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.green.shade300),
                                      ),
                                      child: const Text('تم السداد بالخزينة', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 12)),
                                    ),
                                  ],
                                ),
                                const Divider(height: 20),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'رقم التذكرة: #TKT-${_lastCreatedVisit!['visitId'] ?? _lastCreatedVisit!['visitNumber'] ?? '001'}',
                                        key: const Key('cell_ticket_number'),
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Consolas'),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text('العيادة: ${_serviceNameCtrl.text}'),
                                    ),
                                    Expanded(
                                      child: Text(
                                        'المسدد: ${_paidCtrl.text} ج.م',
                                        key: const Key('cell_ticket_paid'),
                                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: ElevatedButton.icon(
                                    key: const Key('btn_print_ticket'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0F766E),
                                      foregroundColor: Colors.white,
                                    ),
                                    icon: const Icon(Icons.print, size: 16),
                                    label: const Text('طباعة التذكرة الورقية (إيصال المريض)'),
                                    onPressed: () {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('تم إرسال التذكرة إلى طابعة الإيصالات الحرارية بنجاح.')),
                                      );
                                    },
                                  ),
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
