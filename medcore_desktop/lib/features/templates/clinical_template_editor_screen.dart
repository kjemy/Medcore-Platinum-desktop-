import 'package:flutter/material.dart';
import '../../core/state/medcore_app_controller.dart';

/// Visual Clinical Template Editor & Interactive Form Runtime
/// Supports dynamic section and field creation (Text, Multiline, Integer, Decimal, Date, Select, Boolean)
/// with real-time validation rules, interactive preview, version lifecycle and MariaDB persistence.
class ClinicalTemplateEditorScreen extends StatefulWidget {
  final MedCoreAppController controller;

  const ClinicalTemplateEditorScreen({super.key, required this.controller});

  @override
  State<ClinicalTemplateEditorScreen> createState() => _ClinicalTemplateEditorScreenState();
}

class _ClinicalTemplateEditorScreenState extends State<ClinicalTemplateEditorScreen> {
  bool _loading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _templates = [];
  Map<String, dynamic>? _selectedTemplate;

  // Editor mode: 'builder' | 'preview'
  String _activeTab = 'builder';

  // Template metadata
  final _tmplNoCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  String _selectedSpecialty = 'GENERAL_MEDICINE';
  String _selectedCategory = 'CONSULTATION';

  // Dynamic sections and fields
  List<Map<String, dynamic>> _sections = [];

  // Preview form values
  final Map<String, dynamic> _previewValues = {};
  final Map<String, String?> _previewErrors = {};

  final List<String> _specialties = [
    'GENERAL_MEDICINE',
    'CARDIOLOGY',
    'PEDIATRICS',
    'ORTHOPEDICS',
    'NEUROLOGY',
    'ONCOLOGY',
    'DERMATOLOGY',
    'SURGERY',
    'ICU_CRITICAL_CARE',
    'OB_GYN',
  ];

  final List<String> _categories = [
    'CONSULTATION',
    'PROGRESS_NOTE',
    'ADMISSION_NOTE',
    'DISCHARGE_SUMMARY',
    'PROCEDURE_NOTE',
    'SPECIALTY_ASSESSMENT',
  ];

  final List<String> _fieldTypes = [
    'text',
    'multiline',
    'integer',
    'decimal',
    'boolean',
    'select',
    'date',
  ];

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  @override
  void dispose() {
    _tmplNoCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final res = await widget.controller.api.getJson('/api/v1/clinical/templates');
      final items = ((res['items'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      setState(() {
        _templates = items;
        _loading = false;
        if (_selectedTemplate == null && items.isNotEmpty) {
          _selectTemplate(items.first);
        } else if (items.isEmpty) {
          _initNewTemplate();
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load templates: $e';
        _loading = false;
      });
    }
  }

  void _initNewTemplate() {
    setState(() {
      _selectedTemplate = null;
      _tmplNoCtrl.text = 'TMPL-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
      _titleCtrl.text = 'New Clinical Assessment Template';
      _selectedSpecialty = 'GENERAL_MEDICINE';
      _selectedCategory = 'CONSULTATION';
      _sections = [
        {
          'key': 'vitals_section',
          'title': 'Vital Signs & Biometrics',
          'fields': [
            {
              'key': 'systolicBp',
              'label': 'Systolic BP (mmHg)',
              'type': 'integer',
              'unit': 'mmHg',
              'required': true,
              'min': 60,
              'max': 250,
            },
            {
              'key': 'diastolicBp',
              'label': 'Diastolic BP (mmHg)',
              'type': 'integer',
              'unit': 'mmHg',
              'required': true,
              'min': 40,
              'max': 160,
            },
            {
              'key': 'heartRate',
              'label': 'Heart Rate (bpm)',
              'type': 'integer',
              'unit': 'bpm',
              'required': true,
              'min': 30,
              'max': 220,
            },
          ],
        },
        {
          'key': 'examination_section',
          'title': 'Physical Examination & Clinical Notes',
          'fields': [
            {
              'key': 'generalAppearance',
              'label': 'General Appearance',
              'type': 'text',
              'required': false,
            },
            {
              'key': 'abnormalFindings',
              'label': 'Abnormal Findings Present',
              'type': 'boolean',
              'required': true,
            },
            {
              'key': 'clinicalAssessment',
              'label': 'Detailed Assessment & Plan',
              'type': 'multiline',
              'required': false,
            },
          ],
        },
      ];
      _previewValues.clear();
      _previewErrors.clear();
    });
  }

  void _selectTemplate(Map<String, dynamic> t) {
    setState(() {
      _selectedTemplate = t;
      _tmplNoCtrl.text = (t['templateNumber'] ?? '').toString();
      _titleCtrl.text = (t['title'] ?? '').toString();
      _selectedSpecialty = (t['specialty'] ?? 'GENERAL_MEDICINE').toString();
      _selectedCategory = (t['category'] ?? 'CONSULTATION').toString();

      final content = t['content'] is Map ? Map<String, dynamic>.from(t['content'] as Map) : <String, dynamic>{};
      final rawSections = content['sections'] as List?;
      if (rawSections != null && rawSections.isNotEmpty) {
        _sections = rawSections.map((s) => Map<String, dynamic>.from(s as Map)).toList();
      } else {
        _sections = [];
      }
      _previewValues.clear();
      _previewErrors.clear();
    });
  }

  void _addSection() {
    final newIndex = _sections.length + 1;
    setState(() {
      _sections.add({
        'key': 'section_$newIndex',
        'title': 'Section $newIndex',
        'fields': <Map<String, dynamic>>[],
      });
    });
  }

  void _removeSection(int index) {
    setState(() {
      _sections.removeAt(index);
    });
  }

  void _addField(int sectionIndex) {
    final fields = (_sections[sectionIndex]['fields'] as List);
    final newFieldIndex = fields.length + 1;
    setState(() {
      fields.add({
        'key': 'field_${sectionIndex}_$newFieldIndex',
        'label': 'Field $newFieldIndex',
        'type': 'text',
        'required': false,
      });
    });
  }

  void _removeField(int sectionIndex, int fieldIndex) {
    setState(() {
      (_sections[sectionIndex]['fields'] as List).removeAt(fieldIndex);
    });
  }

  Map<String, dynamic> _buildContentJson() {
    return {
      'version': _selectedTemplate != null ? _selectedTemplate!['version'] : 1,
      'sections': _sections,
    };
  }

  Future<void> _saveDraft() async {
    final title = _titleCtrl.text.trim();
    final tmplNo = _tmplNoCtrl.text.trim();
    if (title.isEmpty || tmplNo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Template Title and Number are required.')),
      );
      return;
    }

    try {
      final content = _buildContentJson();
      if (_selectedTemplate == null) {
        // Create new template
        final res = await widget.controller.api.postJson('/api/v1/clinical/templates', {
          'templateNumber': tmplNo,
          'title': title,
          'specialty': _selectedSpecialty,
          'category': _selectedCategory,
          'content': content,
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Template created successfully as DRAFT.')),
        );
        await _loadTemplates();
        if (res['data'] != null) {
          _selectTemplate(Map<String, dynamic>.from(res['data'] as Map));
        }
      } else {
        // Update existing draft
        final id = _selectedTemplate!['id'];
        final res = await widget.controller.api.putJson('/api/v1/clinical/templates/$id', {
          'title': title,
          'specialty': _selectedSpecialty,
          'category': _selectedCategory,
          'content': content,
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Draft updated successfully.')),
        );
        await _loadTemplates();
        if (res['data'] != null) {
          _selectTemplate(Map<String, dynamic>.from(res['data'] as Map));
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving template: $e')),
      );
    }
  }

  Future<void> _activateTemplate() async {
    if (_selectedTemplate == null) return;
    final id = _selectedTemplate!['id'];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Publish & Activate Template'),
        content: const Text(
          'Activating this template will make it the authoritative version for clinical encounters.\n'
          'Any previous active version of this template will be automatically retired.\n'
          'Once active, the template structure is sealed and immutable.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Activate')),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final res = await widget.controller.api.postJson('/api/v1/clinical/templates/$id/activate', {});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Template ACTIVATED successfully.')),
      );
      await _loadTemplates();
      if (res['data'] != null) {
        _selectTemplate(Map<String, dynamic>.from(res['data'] as Map));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error activating template: $e')),
      );
    }
  }

  Future<void> _createNextVersion() async {
    if (_selectedTemplate == null) return;
    final id = _selectedTemplate!['id'];

    try {
      final content = _buildContentJson();
      final res = await widget.controller.api.postJson('/api/v1/clinical/templates/$id/version', {
        'content': content,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New Draft Version created successfully.')),
      );
      await _loadTemplates();
      if (res['data'] != null) {
        _selectTemplate(Map<String, dynamic>.from(res['data'] as Map));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error creating next version: $e')),
      );
    }
  }

  void _validatePreviewForm() {
    final errors = <String, String?>{};
    for (final sec in _sections) {
      final fields = (sec['fields'] as List? ?? []);
      for (final f in fields) {
        final key = f['key'].toString();
        final label = f['label'].toString();
        final isReq = f['required'] == true;
        final type = f['type'].toString();
        final val = _previewValues[key];

        if (isReq && (val == null || (val is String && val.trim().isEmpty))) {
          errors[key] = '$label is required';
          continue;
        }

        if (val != null && (type == 'integer' || type == 'decimal')) {
          final numVal = num.tryParse(val.toString());
          if (numVal == null) {
            errors[key] = '$label must be a valid number';
          } else {
            if (f['min'] != null && numVal < num.parse(f['min'].toString())) {
              errors[key] = '$label minimum is ${f['min']}';
            }
            if (f['max'] != null && numVal > num.parse(f['max'].toString())) {
              errors[key] = '$label maximum is ${f['max']}';
            }
          }
        }
      }
    }

    setState(() {
      _previewErrors.clear();
      _previewErrors.addAll(errors);
    });

    if (errors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.green,
          content: Text('Form Validation Passed: All clinical rules and constraints satisfied!'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Validation Failed: ${errors.length} field constraint(s) violated.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDraft = _selectedTemplate == null || _selectedTemplate!['status'] == 'DRAFT';
    final isActive = _selectedTemplate != null && _selectedTemplate!['status'] == 'ACTIVE';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dynamic Clinical Template Engine'),
        actions: [
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('New Template'),
            onPressed: _initNewTemplate,
          ),
          const SizedBox(width: 8),
          if (isDraft)
            FilledButton.tonalIcon(
              icon: const Icon(Icons.save),
              label: const Text('Save Draft'),
              onPressed: _saveDraft,
            ),
          const SizedBox(width: 8),
          if (isDraft && _selectedTemplate != null)
            FilledButton.icon(
              icon: const Icon(Icons.publish),
              label: const Text('Activate / Publish'),
              style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
              onPressed: _activateTemplate,
            ),
          if (isActive)
            FilledButton.tonalIcon(
              icon: const Icon(Icons.fork_right),
              label: const Text('Bump to Next Version'),
              onPressed: _createNextVersion,
            ),
          const SizedBox(width: 16),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)))
              : Row(
                  children: [
                    // Left Column: Templates Master List
                    SizedBox(
                      width: 320,
                      child: Card(
                        margin: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                'Templates Catalog (${_templates.length})',
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                            const Divider(height: 1),
                            Expanded(
                              child: ListView.separated(
                                itemCount: _templates.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (ctx, i) {
                                  final t = _templates[i];
                                  final isSel = _selectedTemplate?['id'] == t['id'];
                                  final status = (t['status'] ?? 'DRAFT').toString();
                                  final ver = t['version'] ?? 1;

                                  Color statusColor = Colors.orange;
                                  if (status == 'ACTIVE') statusColor = Colors.green;
                                  if (status == 'RETIRED') statusColor = Colors.grey;

                                  return ListTile(
                                    selected: isSel,
                                    title: Text(t['title'] ?? 'Untitled', maxLines: 1, overflow: TextOverflow.ellipsis),
                                    subtitle: Text('${t['templateNumber']} • v$ver • ${t['specialty']}'),
                                    trailing: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: statusColor.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: statusColor),
                                      ),
                                      child: Text(
                                        status,
                                        style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    onTap: () => _selectTemplate(t),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Right Column: Editor Workspace
                    Expanded(
                      child: Card(
                        margin: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                        child: Column(
                          children: [
                            // Header Toolbar & Tabs
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _selectedTemplate != null
                                          ? '${_selectedTemplate!['title']} (v${_selectedTemplate!['version']} - ${_selectedTemplate!['status']})'
                                          : 'Draft Template Builder',
                                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  SegmentedButton<String>(
                                    segments: const [
                                      ButtonSegment(
                                        value: 'builder',
                                        icon: Icon(Icons.design_services_outlined),
                                        label: Text('Visual Schema Builder'),
                                      ),
                                      ButtonSegment(
                                        value: 'preview',
                                        icon: Icon(Icons.remove_red_eye_outlined),
                                        label: Text('Doctor Form Preview'),
                                      ),
                                    ],
                                    selected: {_activeTab},
                                    onSelectionChanged: (val) {
                                      setState(() {
                                        _activeTab = val.first;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),

                            // Content: Builder or Preview
                            Expanded(
                              child: _activeTab == 'builder' ? _buildSchemaBuilder() : _buildInteractivePreview(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildSchemaBuilder() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Metadata Row
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Template Properties & Classification', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _tmplNoCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Template Number / Code',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 4,
                        child: TextField(
                          controller: _titleCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Template Title',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          value: _selectedSpecialty,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Specialty',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: _specialties.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))).toList(),
                          onChanged: (v) => setState(() => _selectedSpecialty = v!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          value: _selectedCategory,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Category',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))).toList(),
                          onChanged: (v) => setState(() => _selectedCategory = v!),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Sections Builder
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Sections & Field Architecture (${_sections.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.add),
                label: const Text('Add Section'),
                onPressed: _addSection,
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_sections.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('No sections configured. Click "Add Section" to begin constructing template fields.'),
              ),
            )
          else
            ...List.generate(_sections.length, (sIdx) {
              final section = _sections[sIdx];
              final fields = (section['fields'] as List? ?? []);

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.folder_outlined, color: Colors.blueGrey),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              initialValue: section['title']?.toString() ?? '',
                              decoration: const InputDecoration(
                                labelText: 'Section Title',
                                border: UnderlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: (v) => section['title'] = v,
                            ),
                          ),
                          const SizedBox(width: 16),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            tooltip: 'Remove Section',
                            onPressed: () => _removeSection(sIdx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Fields in this section
                      ...List.generate(fields.length, (fIdx) {
                        final field = Map<String, dynamic>.from(fields[fIdx] as Map);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              // Label
                              Expanded(
                                flex: 3,
                                child: TextFormField(
                                  initialValue: field['label']?.toString() ?? '',
                                  decoration: const InputDecoration(
                                    labelText: 'Field Label',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (v) {
                                    field['label'] = v;
                                    fields[fIdx] = field;
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Key
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  initialValue: field['key']?.toString() ?? '',
                                  decoration: const InputDecoration(
                                    labelText: 'Key Identifier',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (v) {
                                    field['key'] = v;
                                    fields[fIdx] = field;
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Type
                              Expanded(
                                flex: 2,
                                child: DropdownButtonFormField<String>(
                                  value: field['type']?.toString() ?? 'text',
                                  decoration: const InputDecoration(
                                    labelText: 'Type',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  items: _fieldTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                                  onChanged: (v) {
                                    setState(() {
                                      field['type'] = v;
                                      fields[fIdx] = field;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Required Checkbox
                              Row(
                                children: [
                                  Checkbox(
                                    value: field['required'] == true,
                                    onChanged: (v) {
                                      setState(() {
                                        field['required'] = v;
                                        fields[fIdx] = field;
                                      });
                                    },
                                  ),
                                  const Text('Required', style: TextStyle(fontSize: 12)),
                                ],
                              ),
                              const SizedBox(width: 8),

                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.red, size: 20),
                                tooltip: 'Remove Field',
                                onPressed: () => _removeField(sIdx, fIdx),
                              ),
                            ],
                          ),
                        );
                      }),

                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add Field to Section'),
                          onPressed: () => _addField(sIdx),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildInteractivePreview() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Interactive Doctor Preview: This runtime renders actual dynamic forms from the JSON schema definition.\n'
                    'Fill in clinical values and test client-side clinical constraint validation.',
                    style: TextStyle(color: Colors.blue.shade900),
                  ),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Test Clinical Capture'),
                  onPressed: _validatePreviewForm,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          ..._sections.map((sec) {
            final fields = (sec['fields'] as List? ?? []);

            return Card(
              margin: const EdgeInsets.only(bottom: 20),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sec['title']?.toString() ?? 'Section',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const Divider(height: 24),
                    ...fields.map((f) => _buildPreviewField(f)),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPreviewField(dynamic f) {
    final field = Map<String, dynamic>.from(f as Map);
    final key = field['key'].toString();
    final label = field['label'].toString();
    final isReq = field['required'] == true;
    final type = field['type'].toString();
    final unit = field['unit']?.toString();
    final error = _previewErrors[key];

    Widget inputWidget;

    switch (type) {
      case 'boolean':
        inputWidget = CheckboxListTile(
          title: Text('$label${isReq ? " *" : ""}'),
          value: _previewValues[key] == true,
          contentPadding: EdgeInsets.zero,
          onChanged: (v) {
            setState(() {
              _previewValues[key] = v;
            });
          },
        );
        break;
      case 'select':
        final options = (field['options'] as List? ?? ['Option 1', 'Option 2', 'Option 3'])
            .map((e) => e.toString())
            .toList();
        inputWidget = DropdownButtonFormField<String>(
          value: _previewValues[key]?.toString(),
          decoration: InputDecoration(
            labelText: '$label${isReq ? " *" : ""}',
            errorText: error,
            border: const OutlineInputBorder(),
          ),
          items: options.map((opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(),
          onChanged: (v) {
            setState(() {
              _previewValues[key] = v;
            });
          },
        );
        break;
      case 'multiline':
        inputWidget = TextFormField(
          initialValue: _previewValues[key]?.toString() ?? '',
          maxLines: 4,
          decoration: InputDecoration(
            labelText: '$label${isReq ? " *" : ""}',
            errorText: error,
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) => _previewValues[key] = v,
        );
        break;
      case 'integer':
      case 'decimal':
        inputWidget = TextFormField(
          initialValue: _previewValues[key]?.toString() ?? '',
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: '$label${isReq ? " *" : ""}',
            suffixText: unit,
            errorText: error,
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) => _previewValues[key] = v,
        );
        break;
      case 'date':
      case 'text':
      default:
        inputWidget = TextFormField(
          initialValue: _previewValues[key]?.toString() ?? '',
          decoration: InputDecoration(
            labelText: '$label${isReq ? " *" : ""}',
            errorText: error,
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) => _previewValues[key] = v,
        );
        break;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: inputWidget,
    );
  }
}
