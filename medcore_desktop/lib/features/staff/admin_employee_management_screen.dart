import 'package:flutter/material.dart';
import '../../core/api/medcore_api_client.dart';
import '../../core/state/medcore_app_controller.dart';

class AdminEmployeeManagementScreen extends StatefulWidget {
  final MedCoreAppController controller;

  const AdminEmployeeManagementScreen({
    super.key,
    required this.controller,
  });

  @override
  State<AdminEmployeeManagementScreen> createState() => _AdminEmployeeManagementScreenState();
}

class _AdminEmployeeManagementScreenState extends State<AdminEmployeeManagementScreen> {
  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _employees = [];
  String _searchQuery = '';
  String _selectedRoleFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await widget.controller.api.getJson('/api/v1/admin/employees');
      final list = (res['employees'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      setState(() {
        _employees = list;
        _isLoading = false;
      });
    } on MedCoreApiException catch (e) {
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load employees: $e';
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredEmployees {
    return _employees.where((emp) {
      final role = (emp['role'] ?? '').toString();
      final name = (emp['fullName'] ?? '').toString().toLowerCase();
      final code = (emp['staffCode'] ?? '').toString().toLowerCase();
      final email = (emp['email'] ?? '').toString().toLowerCase();
      final q = _searchQuery.toLowerCase();

      final matchesQuery = q.isEmpty || name.contains(q) || code.contains(q) || email.contains(q);
      final matchesRole = _selectedRoleFilter == 'ALL' || role == _selectedRoleFilter;
      return matchesQuery && matchesRole;
    }).toList();
  }

  void _showAddEmployeeDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _AddEmployeeDialog(
        api: widget.controller.api,
        onCreated: _loadEmployees,
      ),
    );
  }

  void _showEditEmployeeDialog(Map<String, dynamic> emp) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _EditEmployeeDialog(
        api: widget.controller.api,
        employee: emp,
        onUpdated: _loadEmployees,
      ),
    );
  }

  void _showResetPasswordDialog(Map<String, dynamic> emp) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ResetPasswordDialog(
        api: widget.controller.api,
        employee: emp,
        onResetSuccess: _loadEmployees,
      ),
    );
  }

  void _showPermissionsDialog(Map<String, dynamic> emp) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ManageCustomPermissionsDialog(
        api: widget.controller.api,
        employee: emp,
        onUpdated: _loadEmployees,
      ),
    );
  }

  void _showAuditDialog(Map<String, dynamic> emp) {
    showDialog(
      context: context,
      builder: (ctx) => _EmployeeAuditDialog(
        api: widget.controller.api,
        employee: emp,
      ),
    );
  }

  Future<void> _toggleStatus(Map<String, dynamic> emp) async {
    final currentStatus = emp['status']?.toString().toUpperCase() ?? 'ACTIVE';
    final newStatus = currentStatus == 'ACTIVE' ? 'SUSPENDED' : 'ACTIVE';
    final staffId = emp['id'];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Change Status to $newStatus?'),
        content: Text(
          'Are you sure you want to change status for ${emp['fullName']} (${emp['staffCode']}) to $newStatus?'
          '${newStatus != 'ACTIVE' ? ' All active sessions will be terminated immediately.' : ''}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: newStatus == 'ACTIVE' ? Colors.green : Colors.red,
            ),
            child: Text('Confirm $newStatus'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await widget.controller.api.postJson('/api/v1/admin/employees/$staffId/status', {
        'status': newStatus,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Employee status updated to $newStatus')),
      );
      _loadEmployees();
    } on MedCoreApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: ${e.message}'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _revokeSessions(Map<String, dynamic> emp) async {
    final staffId = emp['id'];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke All Sessions'),
        content: Text('Force immediate logout for ${emp['fullName']} across all workstations and devices?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade800),
            child: const Text('Revoke Sessions'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final res = await widget.controller.api.postJson('/api/v1/admin/employees/$staffId/revoke-sessions', {});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Revoked ${res['revokedCount'] ?? 0} active session(s).')),
      );
      _loadEmployees();
    } on MedCoreApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: ${e.message}'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Staff & Employee Account Administration',
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Authoritative hospital employee lifecycle management: PBKDF2 password generation, RBAC roles, session revocation, and security audit trace.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                key: const Key('btn_add_employee'),
                onPressed: _showAddEmployeeDialog,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Add Employee'),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Refresh Employee List',
                onPressed: _isLoading ? null : _loadEmployees,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Filters & Search Row
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  key: const Key('input_employee_search'),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search by employee name, staff code, or email...',
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: DropdownButtonFormField<String>(
                  value: _selectedRoleFilter,
                  decoration: const InputDecoration(labelText: 'Filter Role'),
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('All Roles')),
                    DropdownMenuItem(value: 'Admin', child: Text('Admin')),
                    DropdownMenuItem(value: 'Doctor', child: Text('Doctor')),
                    DropdownMenuItem(value: 'Nurse', child: Text('Nurse')),
                    DropdownMenuItem(value: 'Receptionist', child: Text('Receptionist')),
                    DropdownMenuItem(value: 'Cashier', child: Text('Cashier')),
                    DropdownMenuItem(value: 'Pharmacist', child: Text('Pharmacist')),
                    DropdownMenuItem(value: 'LabTechnician', child: Text('Lab Technician')),
                    DropdownMenuItem(value: 'Radiologist', child: Text('Radiologist')),
                    DropdownMenuItem(value: 'Accountant', child: Text('Accountant')),
                    DropdownMenuItem(value: 'Maintenance', child: Text('Maintenance')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedRoleFilter = v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Main Employee Content
          if (_isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: cs.error),
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: cs.error)),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _loadEmployees, child: const Text('Try Again')),
                  ],
                ),
              ),
            )
          else if (_filteredEmployees.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  _employees.isEmpty ? 'No employee accounts enrolled yet.' : 'No matching employee accounts found.',
                  style: theme.textTheme.titleMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            )
          else
            Expanded(
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: ListView.separated(
                  itemCount: _filteredEmployees.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final emp = _filteredEmployees[index];
                    final isActive = (emp['status'] ?? 'ACTIVE') == 'ACTIVE';
                    final forcePwd = emp['forcePasswordChange'] == true;
                    final role = (emp['role'] ?? 'Employee').toString();

                    return ListTile(
                      key: Key('employee_row_${emp['id']}'),
                      leading: CircleAvatar(
                        backgroundColor: isActive ? cs.primaryContainer : cs.errorContainer,
                        foregroundColor: isActive ? cs.onPrimaryContainer : cs.onErrorContainer,
                        child: Text(
                          (emp['fullName']?.toString() ?? 'E').substring(0, 1).toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Row(
                        children: [
                          Text(
                            emp['fullName']?.toString() ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 8),
                          Chip(
                            label: Text(
                              emp['staffCode']?.toString() ?? '',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          const SizedBox(width: 6),
                          Chip(
                            label: Text(role, style: const TextStyle(fontSize: 11)),
                            backgroundColor: cs.secondaryContainer.withOpacity(0.5),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          if (forcePwd) ...[
                            const SizedBox(width: 6),
                            Chip(
                              avatar: const Icon(Icons.lock_reset, size: 14, color: Colors.amber),
                              label: const Text('Pwd Change Required', style: TextStyle(fontSize: 11, color: Colors.amber)),
                              backgroundColor: Colors.amber.withOpacity(0.12),
                              padding: EdgeInsets.zero,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ],
                          const SizedBox(width: 6),
                          Chip(
                            label: Text(
                              emp['status']?.toString() ?? 'ACTIVE',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isActive ? Colors.green.shade800 : Colors.red.shade800,
                              ),
                            ),
                            backgroundColor: (isActive ? Colors.green : Colors.red).withOpacity(0.12),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ],
                      ),
                      subtitle: Text(
                        'Email: ${emp['email'] ?? '—'}  |  Phone: ${emp['phone'] ?? '—'}  |  Last Password Change: ${emp['passwordChangedAt'] ?? 'Never'}',
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            tooltip: 'Edit Profile & Role',
                            onPressed: () => _showEditEmployeeDialog(emp),
                          ),
                          IconButton(
                            key: Key('btn_permissions_${emp['id']}'),
                            icon: const Icon(Icons.admin_panel_settings_outlined, size: 20, color: Colors.indigo),
                            tooltip: 'تخصيص الصلاحيات (RBAC)',
                            onPressed: () => _showPermissionsDialog(emp),
                          ),

                          IconButton(
                            icon: const Icon(Icons.password, size: 20),
                            tooltip: 'Reset Password',
                            onPressed: () => _showResetPasswordDialog(emp),
                          ),
                          IconButton(
                            icon: Icon(
                              isActive ? Icons.block : Icons.check_circle_outline,
                              size: 20,
                              color: isActive ? Colors.red : Colors.green,
                            ),
                            tooltip: isActive ? 'Suspend Account' : 'Activate Account',
                            onPressed: () => _toggleStatus(emp),
                          ),
                          IconButton(
                            icon: const Icon(Icons.power_settings_new, size: 20, color: Colors.orange),
                            tooltip: 'Revoke All Sessions',
                            onPressed: () => _revokeSessions(emp),
                          ),
                          IconButton(
                            icon: const Icon(Icons.shield_outlined, size: 20),
                            tooltip: 'Security Audit Log',
                            onPressed: () => _showAuditDialog(emp),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AddEmployeeDialog extends StatefulWidget {
  final MedCoreApiClient api;
  final VoidCallback onCreated;

  const _AddEmployeeDialog({required this.api, required this.onCreated});

  @override
  State<_AddEmployeeDialog> createState() => _AddEmployeeDialogState();
}

class _AddEmployeeDialogState extends State<_AddEmployeeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _staffCodeCtrl = TextEditingController();
  final _fullNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  String _role = 'Doctor';
  bool _forcePasswordChange = true;
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _errorMsg;

  @override
  void dispose() {
    _staffCodeCtrl.dispose();
    _fullNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _errorMsg = null;
    });

    try {
      await widget.api.postJson('/api/v1/admin/employees', {
        'staffCode': _staffCodeCtrl.text.trim(),
        'fullName': _fullNameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'role': _role,
        'password': _passwordCtrl.text,
        'forcePasswordChange': _forcePasswordChange,
      });
      if (mounted) {
        Navigator.pop(context);
        widget.onCreated();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Employee account created successfully.')),
        );
      }
    } on MedCoreApiException catch (e) {
      setState(() {
        _errorMsg = e.message;
        _submitting = false;
      });
    } catch (e) {
      setState(() {
        _errorMsg = e.toString();
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add New Employee Account'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_errorMsg != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.red.shade300),
                    ),
                    child: Text(_errorMsg!, style: TextStyle(color: Colors.red.shade900, fontSize: 13)),
                  ),
                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: TextFormField(
                        key: const Key('input_add_staff_code'),
                        controller: _staffCodeCtrl,
                        decoration: const InputDecoration(labelText: 'Staff Code *', hintText: 'EMP-001'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        key: const Key('input_add_full_name'),
                        controller: _fullNameCtrl,
                        decoration: const InputDecoration(labelText: 'Full Name *'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('input_add_email'),
                  controller: _emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email Address *'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (!v.contains('@')) return 'Invalid email';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _phoneCtrl,
                        decoration: const InputDecoration(labelText: 'Phone Number'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _role,
                        decoration: const InputDecoration(labelText: 'Canonical Role *'),
                        items: const [
                          DropdownMenuItem(value: 'Admin', child: Text('Admin')),
                          DropdownMenuItem(value: 'Doctor', child: Text('Doctor')),
                          DropdownMenuItem(value: 'Nurse', child: Text('Nurse')),
                          DropdownMenuItem(value: 'Receptionist', child: Text('Receptionist')),
                          DropdownMenuItem(value: 'Cashier', child: Text('Cashier')),
                          DropdownMenuItem(value: 'Pharmacist', child: Text('Pharmacist')),
                          DropdownMenuItem(value: 'LabTechnician', child: Text('Lab Technician')),
                          DropdownMenuItem(value: 'Radiologist', child: Text('Radiologist')),
                          DropdownMenuItem(value: 'Accountant', child: Text('Accountant')),
                          DropdownMenuItem(value: 'Maintenance', child: Text('Maintenance')),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _role = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('input_add_password'),
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Initial Password * (min 8 chars, mixed case + digit)',
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.length < 8) return 'Password must be at least 8 characters';
                    if (!v.contains(RegExp(r'[A-Z]')) || !v.contains(RegExp(r'[a-z]')) || !v.contains(RegExp(r'[0-9]'))) {
                      return 'Must include uppercase, lowercase, and digit';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  title: const Text('Require password change on first login'),
                  subtitle: const Text('Flag force_password_change = 1'),
                  value: _forcePasswordChange,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setState(() => _forcePasswordChange = v ?? true),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          key: const Key('btn_submit_add_employee'),
          onPressed: _submitting ? null : _submit,
          child: _submitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Create Account'),
        ),
      ],
    );
  }
}

class _EditEmployeeDialog extends StatefulWidget {
  final MedCoreApiClient api;
  final Map<String, dynamic> employee;
  final VoidCallback onUpdated;

  const _EditEmployeeDialog({required this.api, required this.employee, required this.onUpdated});

  @override
  State<_EditEmployeeDialog> createState() => _EditEmployeeDialogState();
}

class _EditEmployeeDialogState extends State<_EditEmployeeDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullNameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late String _role;
  bool _submitting = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _fullNameCtrl = TextEditingController(text: widget.employee['fullName']?.toString() ?? '');
    _emailCtrl = TextEditingController(text: widget.employee['email']?.toString() ?? '');
    _phoneCtrl = TextEditingController(text: widget.employee['phone']?.toString() ?? '');
    _role = widget.employee['role']?.toString() ?? 'Doctor';
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _errorMsg = null;
    });

    try {
      final staffId = widget.employee['id'];
      await widget.api.putJson('/api/v1/admin/employees/$staffId', {
        'fullName': _fullNameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'role': _role,
      });
      if (mounted) {
        Navigator.pop(context);
        widget.onUpdated();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Employee profile updated successfully.')),
        );
      }
    } on MedCoreApiException catch (e) {
      setState(() {
        _errorMsg = e.message;
        _submitting = false;
      });
    } catch (e) {
      setState(() {
        _errorMsg = e.toString();
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit Employee: ${widget.employee['staffCode']}'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_errorMsg != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Text(_errorMsg!, style: TextStyle(color: Colors.red.shade900, fontSize: 13)),
                ),
              TextFormField(
                controller: _fullNameCtrl,
                decoration: const InputDecoration(labelText: 'Full Name *'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(labelText: 'Email Address *'),
                validator: (v) => (v == null || !v.contains('@')) ? 'Valid email required' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _phoneCtrl,
                      decoration: const InputDecoration(labelText: 'Phone Number'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _role,
                      decoration: const InputDecoration(labelText: 'Role *'),
                      items: const [
                        DropdownMenuItem(value: 'Admin', child: Text('Admin')),
                        DropdownMenuItem(value: 'Doctor', child: Text('Doctor')),
                        DropdownMenuItem(value: 'Nurse', child: Text('Nurse')),
                        DropdownMenuItem(value: 'Receptionist', child: Text('Receptionist')),
                        DropdownMenuItem(value: 'Cashier', child: Text('Cashier')),
                        DropdownMenuItem(value: 'Pharmacist', child: Text('Pharmacist')),
                        DropdownMenuItem(value: 'LabTechnician', child: Text('Lab Technician')),
                        DropdownMenuItem(value: 'Radiologist', child: Text('Radiologist')),
                        DropdownMenuItem(value: 'Accountant', child: Text('Accountant')),
                        DropdownMenuItem(value: 'Maintenance', child: Text('Maintenance')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _role = v);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save Changes'),
        ),
      ],
    );
  }
}

class _ResetPasswordDialog extends StatefulWidget {
  final MedCoreApiClient api;
  final Map<String, dynamic> employee;
  final VoidCallback onResetSuccess;

  const _ResetPasswordDialog({required this.api, required this.employee, required this.onResetSuccess});

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  bool _forcePasswordChange = true;
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _errorMsg;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _errorMsg = null;
    });

    try {
      final staffId = widget.employee['id'];
      await widget.api.postJson('/api/v1/admin/employees/$staffId/reset-password', {
        'newPassword': _passwordCtrl.text,
        'forcePasswordChange': _forcePasswordChange,
      });
      if (mounted) {
        Navigator.pop(context);
        widget.onResetSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset successfully and active sessions revoked.')),
        );
      }
    } on MedCoreApiException catch (e) {
      setState(() {
        _errorMsg = e.message;
        _submitting = false;
      });
    } catch (e) {
      setState(() {
        _errorMsg = e.toString();
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Reset Password: ${widget.employee['fullName']}'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_errorMsg != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Text(_errorMsg!, style: TextStyle(color: Colors.red.shade900, fontSize: 13)),
                ),
              const Text(
                'Setting a new password will immediately revoke all existing active sessions for this employee and hash the password using PBKDF2.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('input_reset_new_password'),
                controller: _passwordCtrl,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'New Password * (min 8 chars, mixed case + digit)',
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.length < 8) return 'Password must be at least 8 characters';
                  if (!v.contains(RegExp(r'[A-Z]')) || !v.contains(RegExp(r'[a-z]')) || !v.contains(RegExp(r'[0-9]'))) {
                    return 'Must include uppercase, lowercase, and digit';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                title: const Text('Require password change upon next login'),
                value: _forcePasswordChange,
                dense: true,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setState(() => _forcePasswordChange = v ?? true),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          key: const Key('btn_submit_reset_password'),
          onPressed: _submitting ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade800),
          child: _submitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Reset Password'),
        ),
      ],
    );
  }
}

class _EmployeeAuditDialog extends StatefulWidget {
  final MedCoreApiClient api;
  final Map<String, dynamic> employee;

  const _EmployeeAuditDialog({required this.api, required this.employee});

  @override
  State<_EmployeeAuditDialog> createState() => _EmployeeAuditDialogState();
}

class _EmployeeAuditDialogState extends State<_EmployeeAuditDialog> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _auditData;

  @override
  void initState() {
    super.initState();
    _fetchAudit();
  }

  Future<void> _fetchAudit() async {
    try {
      final staffId = widget.employee['id'];
      final res = await widget.api.getJson('/api/v1/admin/employees/$staffId/audit');
      setState(() {
        _auditData = res;
        _loading = false;
      });
    } on MedCoreApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Security Audit: ${widget.employee['fullName']} (${widget.employee['staffCode']})'),
      content: SizedBox(
        width: 520,
        height: 380,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Account Security Status', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              Text('Failed Login Attempts: ${_auditData?['failedLoginCount'] ?? 0}'),
                              Text('Account Locked: ${_auditData?['isLocked'] == true ? "YES (Until ${_auditData?['lockedUntil']})" : "NO"}'),
                              Text('Force Password Change: ${_auditData?['forcePasswordChange'] == true ? "YES" : "NO"}'),
                              Text('Last Password Changed At: ${_auditData?['passwordChangedAt'] ?? "Never"}'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('Recent Security Events', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Expanded(
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: Builder(
                            builder: (context) {
                              final events = (_auditData?['events'] as List? ?? []);
                              if (events.isEmpty) {
                                return const Center(child: Text('No recorded security events for this employee.'));
                              }
                              return ListView.separated(
                                itemCount: events.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (ctx, i) {
                                  final ev = events[i] as Map;
                                  return ListTile(
                                    dense: true,
                                    title: Text(ev['eventType']?.toString() ?? 'EVENT', style: const TextStyle(fontWeight: FontWeight.w600)),
                                    subtitle: Text('${ev['details'] ?? ''}\nTimestamp: ${ev['createdAt'] ?? ''}'),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}


const Map<String, List<Map<String, String>>> kCategorizedPermissions = {
  'إدارة النظام والمنشأة': [
    {'key': 'dashboard', 'label': 'لوحة التحكم التنفيذية'},
    {'key': 'admin', 'label': 'صلاحيات المدير الكاملة'},
    {'key': 'settings_Definitions', 'label': 'إدارة التعريفات والبيانات الأساسية'},
    {'key': 'settings_Permissions', 'label': 'إدارة وتخصيص صلاحيات الموظفين'},
    {'key': 'security_Center', 'label': 'مركز الأمان وسجلات التدقيق'},
  ],
  'المرضى والاستقبال والورديات': [
    {'key': 'patients', 'label': 'إدارة ملفات وسجلات المرضى'},
    {'key': 'reception_PatientRegistration', 'label': 'تسجيل واستقبال مريض جديد'},
    {'key': 'shifts', 'label': 'فتح وإغلاق وتسوية الورديات'},
    {'key': 'reception_QuickCheckIn', 'label': 'تسجيل الدخول والزيارات السريعة'},
    {'key': 'appointments', 'label': 'حجز وجدولة المواعيد'},
  ],
  'العيادات الطبية والأطباء': [
    {'key': 'doctor', 'label': 'واجهة واستشارات الطبيب'},
    {'key': 'clinic', 'label': 'إدارة العيادة وقائمة الانتظار'},
    {'key': 'doctor_ClinicalWorkspace', 'label': 'مساحة العمل السريري والتشخيص'},
    {'key': 'clinical_templates', 'label': 'استخدام وإدارة القوالب السريرية'},
  ],
  'المالية والفواتير والعمولات': [
    {'key': 'finance', 'label': 'دفتر الأستاذ والتقارير المالية'},
    {'key': 'finance_Invoices', 'label': 'إصدار الفواتير وسندات القبض'},
    {'key': 'finance_Revenue', 'label': 'تقارير الإيرادات والمطابقات'},
    {'key': 'settings_CommissionRules', 'label': 'حسابات وعمولات الأطباء'},
  ],
  'المختبر والأشعة (LIS / RIS)': [
    {'key': 'lab', 'label': 'نظام المختبر والتحاليل LIS'},
    {'key': 'lab_ResultsEntry', 'label': 'إدخال واعتماد نتائج التحاليل'},
    {'key': 'rad', 'label': 'نظام الأشعة والتصوير الطبي RIS'},
    {'key': 'rad_Reporting', 'label': 'كتابة واعتماد تقارير الأشعة'},
  ],
  'الصيدلية والمخازن ومبيعات POS': [
    {'key': 'pharmacy_inventory', 'label': 'إدارة المخزون الدوائي'},
    {'key': 'pharmacy_Dispensing', 'label': 'صرف الأدوية ومبيعات الصيدلية POS'},
    {'key': 'inventory_ItemsCatalog', 'label': 'دليل الأصناف والمستلزمات'},
  ],
  'الأقسام الداخلية والوحدات التخصصية': [
    {'key': 'inpatient', 'label': 'إدارة الدخول والأقسام الداخلية'},
    {'key': 'inpatient_BedMap', 'label': 'خريطة الأسرة والإشغال'},
    {'key': 'nurse', 'label': 'رعاية التمريض والملاحظات'},
    {'key': 'icu_nicu', 'label': 'العناية المركزة والحضانات'},
    {'key': 'surgery', 'label': 'غرف العمليات والجراحة'},
    {'key': 'dialysis', 'label': 'وحدة الغسيل الكلوي'},
  ],
  'الأجهزة والصيانة والشبكة': [
    {'key': 'settings_Devices', 'label': 'إدارة وربط أجهزة الشبكة LAN'},
    {'key': 'settings_Backups', 'label': 'إدارة النسخ الاحتياطي والاستعادة'},
  ],
};

class _ManageCustomPermissionsDialog extends StatefulWidget {
  final MedCoreApiClient api;
  final Map<String, dynamic> employee;
  final VoidCallback onUpdated;

  const _ManageCustomPermissionsDialog({
    required this.api,
    required this.employee,
    required this.onUpdated,
  });

  @override
  State<_ManageCustomPermissionsDialog> createState() => _ManageCustomPermissionsDialogState();
}

class _ManageCustomPermissionsDialogState extends State<_ManageCustomPermissionsDialog> {
  late String _mode;
  late Set<String> _selectedPerms;
  bool _submitting = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _mode = (widget.employee['permissionsMode'] ?? 'default').toString();
    final rawPerms = widget.employee['customPermissions'];
    if (rawPerms is List) {
      _selectedPerms = rawPerms.map((e) => e.toString()).toSet();
    } else if (rawPerms is Set) {
      _selectedPerms = rawPerms.map((e) => e.toString()).toSet();
    } else {
      _selectedPerms = <String>{};
    }
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _errorMsg = null;
    });

    try {
      final staffId = widget.employee['id'];
      await widget.api.putJson('/api/v1/admin/employees/$staffId', {
        'permissionsMode': _mode,
        'customPermissions': _selectedPerms.toList(),
      });
      widget.onUpdated();
      if (!mounted) return;
      Navigator.pop(context);
    } on MedCoreApiException catch (e) {
      setState(() {
        _errorMsg = e.message;
        _submitting = false;
      });
    } catch (e) {
      setState(() {
        _errorMsg = 'Failed to save permissions: $e';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fullName = widget.employee['fullName']?.toString() ?? 'الموظف';
    final staffCode = widget.employee['staffCode']?.toString() ?? '';
    final role = widget.employee['role']?.toString() ?? '';

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.security, color: Colors.indigo),
          const SizedBox(width: 8),
          Expanded(
            child: Text('تخصيص الصلاحيات وأذونات الوصول (RBAC) - $fullName ($staffCode)'),
          ),
        ],
      ),
      content: SizedBox(
        width: 720,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errorMsg != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_errorMsg!, style: TextStyle(color: cs.onErrorContainer)),
              ),

            // Mode Selector
            Card(
              elevation: 0,
              color: cs.surfaceContainerHighest.withOpacity(0.5),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Text('نمط الصلاحيات:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 16),
                    ChoiceChip(
                      label: const Text('افتراضي بحسب الدور'),
                      selected: _mode == 'default',
                      onSelected: (s) {
                        if (s) setState(() => _mode = 'default');
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      key: const Key('chip_custom_mode'),
                      label: const Text('تخصيص يدوي للموظف'),
                      selected: _mode == 'custom',
                      onSelected: (s) {
                        if (s) setState(() => _mode = 'custom');
                      },
                    ),
                    const Spacer(),
                    Chip(
                      label: Text('الدور: $role', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            if (_mode == 'default')
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline, size: 48, color: cs.primary),
                      const SizedBox(height: 12),
                      Text(
                        'الموظف يعمل بنمط الصلاحيات الافتراضي لدور ($role).',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'لتمكين صلاحيات خاصة أو حجب أقسام محددة، اختر "تخصيص يدوي للموظف".',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView(
                  children: kCategorizedPermissions.entries.map((cat) {
                    final catName = cat.key;
                    final perms = cat.value;
                    final allSelected = perms.every((p) => _selectedPerms.contains(p['key']));

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ExpansionTile(
                        initiallyExpanded: false,
                        title: Text(catName, style: const TextStyle(fontWeight: FontWeight.bold)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  if (allSelected) {
                                    for (final p in perms) {
                                      _selectedPerms.remove(p['key']);
                                    }
                                  } else {
                                    for (final p in perms) {
                                      _selectedPerms.add(p['key']!);
                                    }
                                  }
                                });
                              },
                              child: Text(allSelected ? 'إلغاء الكل' : 'تحديد الكل'),
                            ),
                            const Icon(Icons.expand_more),
                          ],
                        ),
                        children: perms.map((p) {
                          final key = p['key']!;
                          final label = p['label']!;
                          final isChecked = _selectedPerms.contains(key);

                          return CheckboxListTile(
                            key: Key('perm_tile_$key'),
                            dense: true,
                            title: Text(label),
                            subtitle: Text(key, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            value: isChecked,
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedPerms.add(key);
                                } else {
                                  _selectedPerms.remove(key);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          key: const Key('btn_save_permissions'),
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save),
          label: const Text('حفظ الصلاحيات'),
        ),
      ],
    );
  }
}
