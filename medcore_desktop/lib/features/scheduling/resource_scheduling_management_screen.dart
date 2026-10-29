import 'package:flutter/material.dart';
import '../../core/state/medcore_app_controller.dart';

/// Dynamic Multi-Resource Slot Rule Engine Management & Conflict Viewer
/// Manages resources (Doctors, Rooms, Equipment, Devices), scheduling rules (durations & buffer windows),
/// and provides an interactive slot conflict testing and multi-resource allocation console.
class ResourceSchedulingManagementScreen extends StatefulWidget {
  final MedCoreAppController controller;

  const ResourceSchedulingManagementScreen({super.key, required this.controller});

  @override
  State<ResourceSchedulingManagementScreen> createState() => _ResourceSchedulingManagementScreenState();
}

class _ResourceSchedulingManagementScreenState extends State<ResourceSchedulingManagementScreen> {
  bool _loading = true;
  String? _errorMessage;

  List<Map<String, dynamic>> _resources = [];
  List<Map<String, dynamic>> _rules = [];

  // Active sub-tab: 'resources' | 'rules' | 'booking_console'
  String _activeTab = 'resources';

  // Conflict Testing / Booking form state
  final _aptNoCtrl = TextEditingController(text: 'APT-LIVE-001');
  final _patientIdCtrl = TextEditingController(text: '1');
  String _selectedAppointmentType = 'CONSULTATION';
  final DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  final TimeOfDay _selectedTime = const TimeOfDay(hour: 10, minute: 0);
  final Set<int> _selectedResourceIds = {};

  // Conflict state
  bool _conflictChecking = false;
  bool? _hasConflict;
  List<Map<String, dynamic>> _conflictDetails = [];
  Map<String, dynamic>? _lastBookingResult;

  final List<String> _resourceTypes = [
    'DOCTOR',
    'ROOM',
    'THEATER',
    'EQUIPMENT',
    'DEVICE',
    'CHAIR',
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _aptNoCtrl.dispose();
    _patientIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final resList = await widget.controller.api.getJson('/api/v1/scheduling/resources');
      final rulesList = await widget.controller.api.getJson('/api/v1/scheduling/rules');

      setState(() {
        _resources = ((resList['items'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _rules = ((rulesList['items'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load scheduling configuration: $e';
        _loading = false;
      });
    }
  }

  Future<void> _showAddResourceDialog() async {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final deptCtrl = TextEditingController();
    String type = 'ROOM';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Register Scheduling Resource'),
          content: SizedBox(
            width: 450,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: codeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Resource Code (e.g. ROOM-101, ECHO-01)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Resource Name (e.g. Examination Room 101)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(
                    labelText: 'Resource Type',
                    border: OutlineInputBorder(),
                  ),
                  items: _resourceTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setDialogState(() => type = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: deptCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Department ID (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (codeCtrl.text.trim().isEmpty || nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                try {
                  await widget.controller.api.postJson('/api/v1/scheduling/resources', {
                    'resourceCode': codeCtrl.text.trim(),
                    'name': nameCtrl.text.trim(),
                    'resourceType': type,
                    'departmentId': deptCtrl.text.trim().isEmpty ? null : deptCtrl.text.trim(),
                    'isActive': true,
                  });
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Resource registered successfully.')),
                  );
                  await _loadData();
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              },
              child: const Text('Register'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddRuleDialog() async {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final aptTypeCtrl = TextEditingController();
    final durCtrl = TextEditingController(text: '30');
    final bufBeforeCtrl = TextEditingController(text: '10');
    final bufAfterCtrl = TextEditingController(text: '15');
    String primaryType = 'DOCTOR';
    final Set<String> coTypes = {'ROOM'};

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Configure Slot Allocation Rule'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: codeCtrl,
                    decoration: const InputDecoration(labelText: 'Rule Code', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Rule Name', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: aptTypeCtrl,
                    decoration: const InputDecoration(labelText: 'Appointment Type (e.g. CONSULTATION, SURGERY, ECHOCARDIOGRAM)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: primaryType,
                    decoration: const InputDecoration(labelText: 'Primary Required Resource', border: OutlineInputBorder()),
                    items: _resourceTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (v) => setDialogState(() => primaryType = v!),
                  ),
                  const SizedBox(height: 16),
                  const Text('Required Co-Resource Types:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Wrap(
                    spacing: 8,
                    children: _resourceTypes
                        .where((t) => t != primaryType)
                        .map((t) => FilterChip(
                              label: Text(t),
                              selected: coTypes.contains(t),
                              onSelected: (sel) {
                                setDialogState(() {
                                  if (sel) {
                                    coTypes.add(t);
                                  } else {
                                    coTypes.remove(t);
                                  }
                                });
                              },
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: durCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Duration (min)', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: bufBeforeCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Prep Buffer (min)', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: bufAfterCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Clean Buffer (min)', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (codeCtrl.text.trim().isEmpty || nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                try {
                  await widget.controller.api.postJson('/api/v1/scheduling/rules', {
                    'ruleCode': codeCtrl.text.trim(),
                    'name': nameCtrl.text.trim(),
                    'appointmentType': aptTypeCtrl.text.trim(),
                    'primaryResourceType': primaryType,
                    'requiredCoResourceTypes': coTypes.toList(),
                    'defaultDurationMinutes': int.parse(durCtrl.text.trim()),
                    'bufferBeforeMinutes': int.parse(bufBeforeCtrl.text.trim()),
                    'bufferAfterMinutes': int.parse(bufAfterCtrl.text.trim()),
                    'isActive': true,
                  });
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Rule configured successfully.')),
                  );
                  await _loadData();
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              },
              child: const Text('Save Rule'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkSlotConflicts() async {
    if (_selectedResourceIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one resource.')),
      );
      return;
    }

    setState(() {
      _conflictChecking = true;
      _hasConflict = null;
      _conflictDetails = [];
    });

    final startUtc = DateTime.utc(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
    final endUtc = startUtc.add(const Duration(minutes: 45));

    try {
      final res = await widget.controller.api.postJson('/api/v1/scheduling/conflicts/check', {
        'resourceIds': _selectedResourceIds.toList(),
        'start': startUtc.toIso8601String(),
        'end': endUtc.toIso8601String(),
      });

      final data = (res['data'] is Map ? res['data'] : res) as Map<String, dynamic>;
      setState(() {
        _conflictChecking = false;
        _hasConflict = data['hasConflict'] == true;
        _conflictDetails = ((data['conflicts'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (e) {
      setState(() {
        _conflictChecking = false;
        _errorMessage = 'Conflict check failed: $e';
      });
    }
  }

  Future<void> _bookMultiResourceSlot() async {
    if (_selectedResourceIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one resource.')),
      );
      return;
    }

    final startUtc = DateTime.utc(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    try {
      final res = await widget.controller.api.postJson('/api/v1/scheduling/appointments/multi-resource', {
        'appointmentNumber': _aptNoCtrl.text.trim(),
        'patientId': int.parse(_patientIdCtrl.text.trim()),
        'appointmentType': _selectedAppointmentType,
        'appointmentDateTime': startUtc.toIso8601String(),
        'resourceIds': _selectedResourceIds.toList(),
      });

      final data = (res['data'] is Map ? res['data'] : res) as Map<String, dynamic>;
      setState(() {
        _lastBookingResult = data;
        _hasConflict = false;
        _conflictDetails = [];
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.green,
          content: Text('Multi-resource appointment booked atomically with buffer protections!'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Booking Conflict / Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Multi-Resource Slot Rule Engine'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
          const SizedBox(width: 8),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add Resource'),
            onPressed: _showAddResourceDialog,
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.rule),
            label: const Text('Add Rule'),
            onPressed: _showAddRuleDialog,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)))
              : Column(
                  children: [
                    // Top Navigation
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: SegmentedButton<String>(
                        segments: [
                          ButtonSegment(
                            value: 'resources',
                            icon: const Icon(Icons.domain),
                            label: Text('Resources (${_resources.length})'),
                          ),
                          ButtonSegment(
                            value: 'rules',
                            icon: const Icon(Icons.rule_folder_outlined),
                            label: Text('Rules & Buffer Windows (${_rules.length})'),
                          ),
                          const ButtonSegment(
                            value: 'booking_console',
                            icon: Icon(Icons.event_available),
                            label: Text('Live Conflict Verification Console'),
                          ),
                        ],
                        selected: {_activeTab},
                        onSelectionChanged: (val) {
                          setState(() {
                            _activeTab = val.first;
                          });
                        },
                      ),
                    ),
                    const Divider(height: 1),

                    // Tab Body
                    Expanded(
                      child: _activeTab == 'resources'
                          ? _buildResourcesTab(theme)
                          : _activeTab == 'rules'
                              ? _buildRulesTab(theme)
                              : _buildBookingConsole(theme),
                    ),
                  ],
                ),
    );
  }

  Widget _buildResourcesTab(ThemeData theme) {
    if (_resources.isEmpty) {
      return const Center(child: Text('No resources configured. Click "Add Resource" to register Doctors, Rooms, Equipment.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _resources.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final r = _resources[i];
        final type = (r['resourceType'] ?? 'ROOM').toString();
        final isActive = r['isActive'] == true || r['isActive'] == 1;

        IconData icon = Icons.meeting_room;
        if (type == 'DOCTOR') icon = Icons.person;
        if (type == 'THEATER') icon = Icons.local_hospital;
        if (type == 'EQUIPMENT') icon = Icons.biotech;
        if (type == 'DEVICE') icon = Icons.monitor_heart;

        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
            ),
            title: Text(r['name'] ?? 'Unnamed Resource', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${r['resourceCode']} • $type • Dept: ${r['departmentId'] ?? "General"}'),
            trailing: Chip(
              label: Text(isActive ? 'ACTIVE' : 'INACTIVE'),
              backgroundColor: isActive ? Colors.green.shade50 : Colors.grey.shade200,
              labelStyle: TextStyle(color: isActive ? Colors.green.shade800 : Colors.grey.shade800, fontSize: 11),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRulesTab(ThemeData theme) {
    if (_rules.isEmpty) {
      return const Center(child: Text('No slot rules configured. Click "Add Rule" to configure appointment duration and buffer windows.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _rules.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final rule = _rules[i];
        final coTypes = (rule['requiredCoResourceTypes'] as List? ?? []).join(', ');

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(rule['name'] ?? 'Rule', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Chip(
                      label: Text(rule['appointmentType'] ?? 'GENERAL'),
                      backgroundColor: theme.colorScheme.secondaryContainer,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Rule Code: ${rule['ruleCode']} • Primary: ${rule['primaryResourceType']}'),
                if (coTypes.isNotEmpty) Text('Required Co-Resources: $coTypes'),
                const Divider(height: 16),
                Row(
                  children: [
                    _buildBufferTag('Duration', '${rule['defaultDurationMinutes']} min', Colors.blue),
                    const SizedBox(width: 12),
                    _buildBufferTag('Prep Buffer (Before)', '${rule['bufferBeforeMinutes']} min', Colors.orange),
                    const SizedBox(width: 12),
                    _buildBufferTag('Clean Buffer (After)', '${rule['bufferAfterMinutes']} min', Colors.purple),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBufferTag(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text('$label: $value', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  Widget _buildBookingConsole(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Multi-Resource Slot Booking Parameters', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _aptNoCtrl,
                          decoration: const InputDecoration(labelText: 'Appointment Number', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _patientIdCtrl,
                          decoration: const InputDecoration(labelText: 'Patient ID', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedAppointmentType,
                          decoration: const InputDecoration(labelText: 'Appointment Type', border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: 'CONSULTATION', child: Text('CONSULTATION')),
                            DropdownMenuItem(value: 'ECHOCARDIOGRAM', child: Text('ECHOCARDIOGRAM')),
                            DropdownMenuItem(value: 'SURGERY', child: Text('SURGERY')),
                            DropdownMenuItem(value: 'DIALYSIS_SESSION', child: Text('DIALYSIS_SESSION')),
                          ],
                          onChanged: (v) => setState(() => _selectedAppointmentType = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Select Resources to Allocate for this Slot:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _resources.map((r) {
                      final id = r['id'] as int;
                      final isSel = _selectedResourceIds.contains(id);
                      return FilterChip(
                        label: Text('${r['name']} (${r['resourceType']})'),
                        selected: isSel,
                        onSelected: (sel) {
                          setState(() {
                            if (sel) {
                              _selectedResourceIds.add(id);
                            } else {
                              _selectedResourceIds.remove(id);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      FilledButton.tonalIcon(
                        icon: _conflictChecking ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search),
                        label: const Text('Check Resource Conflicts'),
                        onPressed: _conflictChecking ? null : _checkSlotConflicts,
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        icon: const Icon(Icons.bookmark_added),
                        label: const Text('Book Multi-Resource Slot'),
                        onPressed: _bookMultiResourceSlot,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Conflict Banner
          if (_hasConflict == true)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade400),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 8),
                      Text('RESOURCE CONFLICT DETECTED (${_conflictDetails.length})', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._conflictDetails.map((c) => Text('• ${c['resource_name']} (${c['resource_code']}) is already allocated from ${c['allocated_start']} to ${c['allocated_end']}')),
                ],
              ),
            )
          else if (_hasConflict == false)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade400),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_outline, color: Colors.green),
                  SizedBox(width: 8),
                  Text('SLOT IS CLEAR: No conflicts detected across requested resources or buffer windows.', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                ],
              ),
            ),

          if (_lastBookingResult != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Authoritative Booking & Allocation Confirmation (MariaDB)', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('Appointment ID: ${_lastBookingResult!['appointment']['id']} • Number: ${_lastBookingResult!['appointment']['appointmentNumber']}'),
                    Text('Rule Applied: ${_lastBookingResult!['ruleApplied'] ?? "Default"} • Duration: ${_lastBookingResult!['durationMinutes']} min'),
                    Text('Prep Buffer: ${_lastBookingResult!['bufferBeforeMinutes']} min • Cleanup Buffer: ${_lastBookingResult!['bufferAfterMinutes']} min'),
                    const SizedBox(height: 8),
                    const Text('Allocated Resources:'),
                    ...((_lastBookingResult!['allocations'] as List?) ?? []).map(
                      (a) => Text('  - Resource ID ${a['resourceId']}: [${a['allocatedStart']}] → [${a['allocatedEnd']}] (${a['status']})'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
