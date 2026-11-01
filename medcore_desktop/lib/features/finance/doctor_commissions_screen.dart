import 'package:flutter/material.dart';
import '../../core/api/medcore_api_client.dart';
import '../../core/localization/medcore_localizations.dart';
import '../../core/localization/medcore_strings_ar.dart';
import '../../core/state/medcore_app_controller.dart';

class DoctorCommissionsScreen extends StatefulWidget {
  final MedCoreAppController controller;

  const DoctorCommissionsScreen({
    super.key,
    required this.controller,
  });

  @override
  State<DoctorCommissionsScreen> createState() => _DoctorCommissionsScreenState();
}

class _DoctorCommissionsScreenState extends State<DoctorCommissionsScreen> {
  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _profiles = [];

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final items = await widget.controller.api.getDoctorCommissions();
      if (mounted) {
        setState(() {
          _profiles = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _showCreateProfileDialog() {
    final docIdCtrl = TextEditingController(text: '1');
    final consultCtrl = TextEditingController(text: '20.00');
    final procCtrl = TextEditingController(text: '30.00');
    final cutCtrl = TextEditingController(text: '50.0000');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.payments_outlined, color: Color(0xFF0F766E)),
            SizedBox(width: 8),
            Text('إنشاء ملف عمولة طبيب جديد', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('input_comm_doctor_id'),
                controller: docIdCtrl,
                decoration: const InputDecoration(labelText: 'معرف الطبيب (Doctor Staff ID) *', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('input_comm_consultation_pct'),
                controller: consultCtrl,
                decoration: const InputDecoration(labelText: 'نسبة عمولة الكشف (%) *', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('input_comm_procedure_pct'),
                controller: procCtrl,
                decoration: const InputDecoration(labelText: 'نسبة عمولة الإجراءات والعمليات (%) *', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('input_comm_fixed_cut'),
                controller: cutCtrl,
                decoration: const InputDecoration(labelText: 'المبلغ المقطوع لكل كشف (ج.م)', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            key: const Key('btn_save_commission_profile'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E), foregroundColor: Colors.white),
            onPressed: () async {
              final docId = int.tryParse(docIdCtrl.text.trim());
              if (docId == null) return;
              Navigator.pop(ctx);
              try {
                await widget.controller.api.createDoctorCommissionProfile({
                  'doctorId': docId,
                  'consultationPercentage': consultCtrl.text.trim(),
                  'procedurePercentage': procCtrl.text.trim(),
                  'fixedCutPerVisit': cutCtrl.text.trim(),
                  'status': 'ACTIVE',
                });
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم إنشاء ملف عمولة الطبيب بنجاح.')),
                  );
                }
                _loadProfiles();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('خطأ أثناء الحفظ: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('حفظ الملف'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Header
        Row(
          children: [
            const Icon(Icons.account_balance_wallet, color: Color(0xFF0F766E), size: 28),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'العمولات والتسويات المالية للأطباء (Commissions & Settlements)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'حساب نسب الأطباء، التسويات المالية المعتمدة بنظام الرقابة المزدوجة (Dual-Control)',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              key: const Key('btn_create_commission_profile'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E), foregroundColor: Colors.white),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('إنشاء ملف عمولة جديد'),
              onPressed: _showCreateProfileDialog,
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث',
              onPressed: _loadProfiles,
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (_isLoading)
          const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
        else if (_error != null)
          Card(
            color: Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('خطأ أثناء تحميل البيانات: $_error', style: const TextStyle(color: Colors.red)),
            ),
          )
        else
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('ملفات عمولات الأطباء المعتمدة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const Divider(height: 20),
                  if (_profiles.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.receipt_long_outlined, size: 40, color: Colors.grey[400]),
                            const SizedBox(height: 8),
                            Text('لا توجد ملفات عمولات مسجلة بعد.', style: TextStyle(color: Colors.grey[600])),
                          ],
                        ),
                      ),
                    )
                  else
                    Table(
                      columnWidths: const {
                        0: FlexColumnWidth(1.5),
                        1: FlexColumnWidth(1.2),
                        2: FlexColumnWidth(1.2),
                        3: FlexColumnWidth(1.2),
                        4: FlexColumnWidth(1.0),
                      },
                      border: TableBorder(horizontalInside: BorderSide(color: Colors.grey.shade200)),
                      children: [
                        TableRow(
                          decoration: BoxDecoration(color: Colors.grey.shade100),
                          children: const [
                            Padding(padding: EdgeInsets.all(10), child: Text('معرف الطبيب', style: TextStyle(fontWeight: FontWeight.bold))),
                            Padding(padding: EdgeInsets.all(10), child: Text('نسبة الكشوفات', style: TextStyle(fontWeight: FontWeight.bold))),
                            Padding(padding: EdgeInsets.all(10), child: Text('نسبة الإجراءات', style: TextStyle(fontWeight: FontWeight.bold))),
                            Padding(padding: EdgeInsets.all(10), child: Text('المقطوع لكل كشف', style: TextStyle(fontWeight: FontWeight.bold))),
                            Padding(padding: EdgeInsets.all(10), child: Text('الحالة', style: TextStyle(fontWeight: FontWeight.bold))),
                          ],
                        ),
                        ..._profiles.map((p) {
                          final docId = p['doctor_id'] ?? p['doctorId'] ?? '-';
                          final consult = p['consultation_percentage'] ?? p['consultationPercentage'] ?? '0.00';
                          final proc = p['procedure_percentage'] ?? p['procedurePercentage'] ?? '0.00';
                          final cut = p['fixed_cut_per_visit'] ?? p['fixedCutPerVisit'] ?? '0.0000';
                          final status = p['status'] ?? 'ACTIVE';

                          return TableRow(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(10),
                                child: Text('طبيب #$docId', style: const TextStyle(fontWeight: FontWeight.w600)),
                              ),
                              Padding(padding: const EdgeInsets.all(10), child: Text('$consult %')),
                              Padding(padding: const EdgeInsets.all(10), child: Text('$proc %')),
                              Padding(padding: const EdgeInsets.all(10), child: Text('$cut ج.م')),
                              Padding(
                                padding: const EdgeInsets.all(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(4)),
                                  child: Text(status, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 11)),
                                ),
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
