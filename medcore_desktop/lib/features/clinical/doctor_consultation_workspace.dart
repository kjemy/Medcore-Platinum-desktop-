import 'package:flutter/material.dart';
import '../../core/api/medcore_api_client.dart';
import '../../core/localization/medcore_localizations.dart';
import '../../core/localization/medcore_strings_ar.dart';
import '../../core/state/medcore_app_controller.dart';

class DoctorConsultationWorkspace extends StatefulWidget {
  final MedCoreAppController controller;
  final List<Map<String, dynamic>> queueItems;
  final VoidCallback onRefreshQueue;

  const DoctorConsultationWorkspace({
    super.key,
    required this.controller,
    required this.queueItems,
    required this.onRefreshQueue,
  });

  @override
  State<DoctorConsultationWorkspace> createState() => _DoctorConsultationWorkspaceState();
}

class _DoctorConsultationWorkspaceState extends State<DoctorConsultationWorkspace> {
  Map<String, dynamic>? _selectedPatient;

  // Vitals inputs
  final TextEditingController _bpSysCtrl = TextEditingController(text: '120');
  final TextEditingController _bpDiaCtrl = TextEditingController(text: '80');
  final TextEditingController _hrCtrl = TextEditingController(text: '72');
  final TextEditingController _tempCtrl = TextEditingController(text: '37.0');
  final TextEditingController _spo2Ctrl = TextEditingController(text: '98');
  final TextEditingController _glucoseCtrl = TextEditingController(text: '105');

  // Clinical Findings inputs
  final TextEditingController _chiefComplaintCtrl = TextEditingController();
  final TextEditingController _diagnosisCtrl = TextEditingController();
  final TextEditingController _examNotesCtrl = TextEditingController();
  final TextEditingController _doctorCommentsCtrl = TextEditingController();

  // e-Rx inputs
  final TextEditingController _rxMedNameCtrl = TextEditingController();
  final TextEditingController _rxDoseCtrl = TextEditingController(text: '1 قرص');
  final TextEditingController _rxFreqCtrl = TextEditingController(text: 'كل 8 ساعات');
  final TextEditingController _rxDurationCtrl = TextEditingController(text: '5 أيام');
  final List<Map<String, String>> _prescriptions = [];

  bool _isSaving = false;
  String? _feedbackMessage;
  bool _isError = false;

  @override
  void dispose() {
    _bpSysCtrl.dispose();
    _bpDiaCtrl.dispose();
    _hrCtrl.dispose();
    _tempCtrl.dispose();
    _spo2Ctrl.dispose();
    _glucoseCtrl.dispose();
    _chiefComplaintCtrl.dispose();
    _diagnosisCtrl.dispose();
    _examNotesCtrl.dispose();
    _doctorCommentsCtrl.dispose();
    _rxMedNameCtrl.dispose();
    _rxDoseCtrl.dispose();
    _rxFreqCtrl.dispose();
    _rxDurationCtrl.dispose();
    super.dispose();
  }

  void _selectPatient(Map<String, dynamic> item) {
    setState(() {
      _selectedPatient = item;
      _chiefComplaintCtrl.text = (item['reason'] ?? item['chiefComplaint'] ?? '').toString();
      _diagnosisCtrl.clear();
      _examNotesCtrl.clear();
      _doctorCommentsCtrl.clear();
      _prescriptions.clear();
      _feedbackMessage = null;
      _isError = false;
    });
  }

  void _applyTemplate(String title, String content) {
    setState(() {
      if (_examNotesCtrl.text.trim().isEmpty) {
        _examNotesCtrl.text = '[$title]\n$content';
      } else {
        _examNotesCtrl.text = '${_examNotesCtrl.text}\n\n[$title]\n$content';
      }
    });
  }

  void _addPrescriptionItem() {
    final med = _rxMedNameCtrl.text.trim();
    if (med.isEmpty) return;
    setState(() {
      _prescriptions.add({
        'medication': med,
        'dose': _rxDoseCtrl.text.trim(),
        'frequency': _rxFreqCtrl.text.trim(),
        'duration': _rxDurationCtrl.text.trim(),
      });
      _rxMedNameCtrl.clear();
    });
  }

  Future<void> _completeEncounter() async {
    if (_selectedPatient == null) return;
    setState(() {
      _isSaving = true;
      _feedbackMessage = null;
      _isError = false;
    });

    final patientId = _selectedPatient!['patientId'] ?? _selectedPatient!['id'] ?? 1;
    final visitId = _selectedPatient!['visitId'] ?? _selectedPatient!['id'] ?? 101;
    final encNumber = 'ENC-${DateTime.now().millisecondsSinceEpoch % 100000}';

    final payload = <String, dynamic>{
      'visitId': visitId,
      'patientId': patientId,
      'encounterNumber': encNumber,
      'chiefComplaint': _chiefComplaintCtrl.text.trim(),
      'vitals': {
        'bloodPressure': '${_bpSysCtrl.text.trim()}/${_bpDiaCtrl.text.trim()}',
        'heartRate': _hrCtrl.text.trim(),
        'temperature': _tempCtrl.text.trim(),
        'spo2': _spo2Ctrl.text.trim(),
        'glucose': _glucoseCtrl.text.trim(),
      },
      'examination': {
        'notes': _examNotesCtrl.text.trim(),
      },
      'diagnoses': [
        {
          'code': 'ICD-MAIN',
          'description': _diagnosisCtrl.text.trim().isEmpty ? 'Clinical Diagnosis' : _diagnosisCtrl.text.trim(),
          'type': 'PRIMARY',
        }
      ],
      'plan': {
        'prescriptions': _prescriptions,
      },
      'notes': _doctorCommentsCtrl.text.trim(),
    };

    try {
      await widget.controller.api.postJson('/api/v1/encounters', payload);
      if (mounted) {
        setState(() {
          _isSaving = false;
          _feedbackMessage = 'تم حفظ التقرير الطبي للكشف $encNumber للمريض ${_selectedPatient!['patientName'] ?? _selectedPatient!['fullName'] ?? ''} بنجاح.';
          _selectedPatient = null;
        });
        widget.onRefreshQueue();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _feedbackMessage = 'خطأ أثناء حفظ الكشف: $e';
          _isError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_selectedPatient != null) {
      return _buildEncounterWorkspace(context);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_feedbackMessage != null)
          Card(
            color: _isError ? cs.errorContainer : Colors.green.shade50,
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _feedbackMessage!,
                style: TextStyle(
                  color: _isError ? cs.onErrorContainer : Colors.green.shade900,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.people_outline, color: Color(0xFF0F766E), size: 24),
                    const SizedBox(width: 8),
                    const Text(
                      'قائمة انتظار الكشف بالعيادة (Doctor Queue)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'تحديث القائمة',
                      onPressed: widget.onRefreshQueue,
                    ),
                  ],
                ),
                const Divider(height: 20),
                if (widget.queueItems.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.person_off_outlined, size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 12),
                          Text(
                            'لا يوجد مرضى في قائمة الانتظار حالياً.',
                            style: TextStyle(color: Colors.grey[600], fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: widget.queueItems.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, idx) {
                      final item = widget.queueItems[idx];
                      final name = item['patientName'] ?? item['fullName'] ?? 'مريض غير محدد';
                      final mrn = item['medicalRecordNumber'] ?? item['mrn'] ?? 'MRN-NEW';
                      final visitNo = item['visitNumber'] ?? 'VIS-${item['id']}';
                      final status = item['status'] ?? 'WAITING';

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF0F766E).withOpacity(0.15),
                          child: const Icon(Icons.person, color: Color(0xFF0F766E)),
                        ),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('$mrn • تذكرة: $visitNo'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.amber.shade300),
                              ),
                              child: Text(
                                status == 'WAITING' ? 'في الانتظار' : status,
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                              ),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              key: Key('btn_start_consultation_${item['id']}'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F766E),
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.medical_information, size: 16),
                              label: const Text('بدء الكشف الطبي'),
                              onPressed: () => _selectPatient(item),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEncounterWorkspace(BuildContext context) {
    final name = _selectedPatient!['patientName'] ?? _selectedPatient!['fullName'] ?? '';
    final mrn = _selectedPatient!['medicalRecordNumber'] ?? _selectedPatient!['mrn'] ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Patient Header Bar
        Card(
          color: const Color(0xFF0F766E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Colors.white,
                  child: Icon(Icons.person, color: Color(0xFF0F766E)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'جلسة الكشف الطبي: $name',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        'رقم الملف: $mrn • العيادة الخارجية',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  key: const Key('btn_back_to_queue'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white70)),
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: const Text('العودة لقائمة الانتظار'),
                  onPressed: () => setState(() => _selectedPatient = null),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Section 1: Vital Signs
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.monitor_heart, color: Colors.red, size: 20),
                    SizedBox(width: 8),
                    Text('العلامات الحيوية (Vital Signs)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('input_vital_bp_sys'),
                        controller: _bpSysCtrl,
                        decoration: const InputDecoration(labelText: 'الضغط الانقباضي (SYS)', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: const Key('input_vital_bp_dia'),
                        controller: _bpDiaCtrl,
                        decoration: const InputDecoration(labelText: 'الضغط الانبساطي (DIA)', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: const Key('input_vital_hr'),
                        controller: _hrCtrl,
                        decoration: const InputDecoration(labelText: 'النبض (HR bpm)', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: const Key('input_vital_temp'),
                        controller: _tempCtrl,
                        decoration: const InputDecoration(labelText: 'حرارة الجسم (°C)', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: const Key('input_vital_spo2'),
                        controller: _spo2Ctrl,
                        decoration: const InputDecoration(labelText: 'الأكسجين (SpO2 %)', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: const Key('input_vital_glucose'),
                        controller: _glucoseCtrl,
                        decoration: const InputDecoration(labelText: 'السكر (mg/dL)', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Section 2: Chief Complaint & Diagnosis
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.notes, color: Color(0xFF0F766E), size: 20),
                    SizedBox(width: 8),
                    Text('الشكوى المرضية والتشخيص الطبي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('input_chief_complaint'),
                  controller: _chiefComplaintCtrl,
                  decoration: const InputDecoration(
                    labelText: 'الشكوى الرئيسية للمريض والأعراض الحالية *',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('input_diagnosis'),
                  controller: _diagnosisCtrl,
                  decoration: const InputDecoration(
                    labelText: 'التشخيص الطبي النهائي (ICD-10 أو التوصيف الإكلينيكي) *',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Section 3: Clinical Examination & Templates Applicator
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.assignment, color: Color(0xFF0F766E), size: 20),
                    const SizedBox(width: 8),
                    const Text('نتائج الفحص الإكلينيكي وقوالب المعاينة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const Spacer(),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          key: const Key('btn_apply_template_chest'),
                          onPressed: () => _applyTemplate('فحص الصدر والتنفس', 'Bilateral vesicular breathing, no added sounds, S1/S2 heard normal, no murmurs.'),
                          child: const Text('قالب الصدر والتنفس'),
                        ),
                        OutlinedButton(
                          key: const Key('btn_apply_template_ent'),
                          onPressed: () => _applyTemplate('فحص الأنف والأذن والحنجرة', 'EAC clear bilaterally, TM intact, Pharynx mildly congested, tonsils grade 1.'),
                          child: const Text('قالب الأنف والأذن'),
                        ),
                        OutlinedButton(
                          key: const Key('btn_apply_template_pediatric'),
                          onPressed: () => _applyTemplate('الفحص الدوري للأطفال', 'Weight and height within normal percentiles, active, alert, no signs of distress.'),
                          child: const Text('قالب فحص الأطفال'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('input_examination_notes'),
                  controller: _examNotesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'تفاصيل الفحص السريري والمعاينة',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Section 4: Electronic Prescriptions (e-Rx)
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.medication, color: Color(0xFF0F766E), size: 20),
                    SizedBox(width: 8),
                    Text('الروشتة الإلكترونية والعلاج الدوائي (e-Rx)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        key: const Key('input_rx_med_name'),
                        controller: _rxMedNameCtrl,
                        decoration: const InputDecoration(labelText: 'اسم الدواء والشكل الصيدلي', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        key: const Key('input_rx_dose'),
                        controller: _rxDoseCtrl,
                        decoration: const InputDecoration(labelText: 'الجرعة', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        key: const Key('input_rx_freq'),
                        controller: _rxFreqCtrl,
                        decoration: const InputDecoration(labelText: 'التكرار', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        key: const Key('input_rx_duration'),
                        controller: _rxDurationCtrl,
                        decoration: const InputDecoration(labelText: 'المدة', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      key: const Key('btn_add_rx_item'),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E), foregroundColor: Colors.white),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('إضافة للروشتة'),
                      onPressed: _addPrescriptionItem,
                    ),
                  ],
                ),
                if (_prescriptions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Table(
                    border: TableBorder.all(color: Colors.grey.shade300),
                    children: [
                      TableRow(
                        decoration: BoxDecoration(color: Colors.grey.shade100),
                        children: const [
                          Padding(padding: EdgeInsets.all(6), child: Text('الدواء', style: TextStyle(fontWeight: FontWeight.bold))),
                          Padding(padding: EdgeInsets.all(6), child: Text('الجرعة', style: TextStyle(fontWeight: FontWeight.bold))),
                          Padding(padding: EdgeInsets.all(6), child: Text('التكرار', style: TextStyle(fontWeight: FontWeight.bold))),
                          Padding(padding: EdgeInsets.all(6), child: Text('المدة', style: TextStyle(fontWeight: FontWeight.bold))),
                          Padding(padding: EdgeInsets.all(6), child: Text('إجراء', style: TextStyle(fontWeight: FontWeight.bold))),
                        ],
                      ),
                      ..._prescriptions.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final rx = entry.value;
                        return TableRow(
                          children: [
                            Padding(padding: const EdgeInsets.all(6), child: Text(rx['medication'] ?? '')),
                            Padding(padding: const EdgeInsets.all(6), child: Text(rx['dose'] ?? '')),
                            Padding(padding: const EdgeInsets.all(6), child: Text(rx['frequency'] ?? '')),
                            Padding(padding: const EdgeInsets.all(6), child: Text(rx['duration'] ?? '')),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                              onPressed: () => setState(() => _prescriptions.removeAt(idx)),
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Section 5: Doctor Final Comments & Recommendations
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.comment, color: Color(0xFF0F766E), size: 20),
                    SizedBox(width: 8),
                    Text('توجيهات وملاحظات الطبيب النهائية (Doctor Final Comments)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('input_doctor_comments'),
                  controller: _doctorCommentsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'التوجيهات العامة، النظام الغذائي، التوصيات وموعد المراجعة القادمة',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Complete Encounter Button
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            key: const Key('btn_complete_encounter'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: _isSaving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.check_circle_outline),
            label: Text(_isSaving ? 'جارٍ حفظ الكشف الطبي...' : 'حفظ التقرير الطبي وإنهاء الكشف'),
            onPressed: _isSaving ? null : _completeEncounter,
          ),
        ),
      ],
    );
  }
}
