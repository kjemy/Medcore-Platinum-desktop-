import 'package:flutter/material.dart';
import '../api/medcore_api_client.dart';
import '../navigation/desktop_navigation_catalog.dart';
import '../state/medcore_app_controller.dart';
import '../../features/dashboard/executive_dashboard_screen.dart';
import '../../features/patients/patients_workspace_screen.dart';
import '../../features/reception/shifts_and_visits_screen.dart';
import '../../features/finance/patient_financial_ledger_screen.dart';
import '../../features/clinical/clinical_modules_hub_screen.dart';
import '../../features/network/network_device_center_screen.dart';
import '../../features/maintenance/maintenance_center_screen.dart';
import '../../features/staff/admin_employee_management_screen.dart';

/// Consistent Desktop Layout Shell (`Sidebar + Top Header Bar + Route/Entitlement Guard + Content Pane`).
class MedCoreDesktopShell extends StatelessWidget {
  final MedCoreAppController controller;

  const MedCoreDesktopShell({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final user = controller.currentUser!;
    final branding = controller.branding;
    final routes = controller.visibleNavigationRoutes;

    return Scaffold(
      body: Column(
        children: [
          // Top Desktop Application Status Bar
          Container(
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.55),
              border: Border(bottom: BorderSide(color: cs.outlineVariant)),
            ),
            child: Row(
              children: [
                Image.asset(
                  'assets/branding/medcore_platinum_logo.png',
                  height: 32,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(Icons.local_hospital, color: cs.primary, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        branding.appDisplayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${branding.facilityDisplayName} • Tenant: ${controller.facilityConfig.hospitalCode} (${controller.facilityConfig.facilityType})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Chip(
                  label: Text(
                    branding.editionLabel,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                  backgroundColor: cs.primaryContainer,
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 12),
                _StatusBadge(
                  icon: Icons.dns_outlined,
                  label: controller.api.baseUrl,
                  color: cs.primary,
                ),
                const SizedBox(width: 8),
                _StatusBadge(
                  icon: Icons.important_devices_outlined,
                  label: controller.api.deviceId,
                  color: cs.secondary,
                ),
                const SizedBox(width: 12),
                Flexible(
                  fit: FlexFit.loose,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        user.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${user.role} (${user.staffCode})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(color: cs.primary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  key: const Key('btn_staff_logout'),
                  onPressed: controller.logoutStaff,
                  icon: const Icon(Icons.logout, size: 16),
                  label: const Text('Sign Out'),
                ),
              ],
            ),
          ),

          if (controller.globalErrorBanner != null)
            MaterialBanner(
              backgroundColor: cs.errorContainer,
              content: Text(
                controller.globalErrorBanner!,
                style: TextStyle(color: cs.onErrorContainer),
              ),
              actions: [
                TextButton(
                  onPressed: controller.clearError,
                  child: const Text('Dismiss'),
                ),
              ],
            ),

          if (controller.facilityConfig.isSubscriptionExpired)
            MaterialBanner(
              backgroundColor: Colors.amber.shade900,
              content: Text(
                'SUBSCRIPTION EXPIRED: Facility subscription expired on ${controller.facilityConfig.subscriptionExpiresUtc}. Please contact service technician to renew.',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              actions: const [
                SizedBox.shrink(),
              ],
            ),

          // Main Desktop Workspace (Authorization- & Module-Aware Sidebar + Guarded Content)
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 255,
                  decoration: BoxDecoration(
                    color: cs.surface,
                    border: Border(right: BorderSide(color: cs.outlineVariant)),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        child: Center(
                          child: Image.asset(
                            'assets/branding/medcore_platinum_logo.png',
                            height: 38,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                        child: Text(
                          'AUTHORIZED MODULES',
                          style: theme.textTheme.labelSmall?.copyWith(
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (user.forcePasswordChange)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: cs.errorContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.warning, size: 16, color: cs.onErrorContainer),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Password change required',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: cs.onErrorContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      for (final route in routes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: ListTile(
                            key: Key('nav_${route.routeId}'),
                            dense: true,
                            enabled: !user.forcePasswordChange,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            selected: controller.activeRouteId == route.routeId,
                            selectedTileColor: cs.primaryContainer.withOpacity(0.55),
                            leading: Icon(route.icon, size: 20),
                            title: Text(
                              route.label,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            onTap: user.forcePasswordChange ? null : () => controller.selectRoute(route.routeId),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: _buildGuardedRouteBody(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuardedRouteBody(BuildContext context) {
    final user = controller.currentUser;
    if (user != null && user.forcePasswordChange) {
      return _ForcePasswordChangeScreen(controller: controller);
    }

    final routeId = controller.activeRouteId;
    final entry = DesktopNavigationCatalog.findById(routeId);

    // Fail-closed UI & Module Entitlement Guard (backed up by backend 403 MODULE_NOT_ENTITLED!)
    if (entry == null || !controller.canAccessRoute(routeId)) {
      final moduleDisabled = entry?.requiredModule != null &&
          !controller.facilityConfig.isModuleEnabled(entry!.requiredModule!);
      return Center(
        child: Card(
          margin: const EdgeInsets.all(32),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  moduleDisabled
                      ? 'Module Not Entitled (${entry.requiredModule})'
                      : 'Access Restricted by Role Permissions',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  moduleDisabled
                      ? 'This module is disabled in the active Facility / Edition configuration. Both UI navigation and Local MedCore Service APIs block access.'
                      : 'Your employee role does not hold the required permission key for "$routeId".',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => controller.selectRoute('dashboard'),
                  child: const Text('Return to Executive Overview'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    switch (routeId) {
      case 'dashboard':
        return ExecutiveDashboardScreen(controller: controller);
      case 'patients':
        return PatientsWorkspaceScreen(controller: controller);
      case 'reception_visits':
        return ShiftsAndVisitsScreen(controller: controller);
      case 'finance_ledger':
        return PatientFinancialLedgerScreen(controller: controller);
      case 'appointments':
      case 'doctors':
      case 'laboratory':
      case 'radiology':
      case 'pharmacy':
      case 'inpatient':
      case 'specialty_units':
        return ClinicalModulesHubScreen(
          controller: controller,
          activeSection: routeId,
        );
      case 'network_devices':
        return NetworkDeviceCenterScreen(controller: controller);
      case 'maintenance_center':
        return MaintenanceCenterScreen(controller: controller);
      case 'staff_admin':
        return AdminEmployeeManagementScreen(controller: controller);
      default:
        return ExecutiveDashboardScreen(controller: controller);
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatusBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _ForcePasswordChangeScreen extends StatefulWidget {
  final MedCoreAppController controller;

  const _ForcePasswordChangeScreen({required this.controller});

  @override
  State<_ForcePasswordChangeScreen> createState() => _ForcePasswordChangeScreenState();
}

class _ForcePasswordChangeScreenState extends State<_ForcePasswordChangeScreen> {
  final TextEditingController _oldPasswordCtrl = TextEditingController();
  final TextEditingController _newPasswordCtrl = TextEditingController();
  final TextEditingController _confirmPasswordCtrl = TextEditingController();
  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _errorMessage;
  bool _isSaving = false;

  @override
  void dispose() {
    _oldPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitPasswordChange() async {
    setState(() {
      _errorMessage = null;
    });

    final oldPwd = _oldPasswordCtrl.text;
    final newPwd = _newPasswordCtrl.text;
    final confirmPwd = _confirmPasswordCtrl.text;

    if (oldPwd.isEmpty || newPwd.isEmpty || confirmPwd.isEmpty) {
      setState(() => _errorMessage = 'All fields are required.');
      return;
    }
    if (newPwd.length < 8) {
      setState(() => _errorMessage = 'New password must be at least 8 characters long.');
      return;
    }
    if (newPwd != confirmPwd) {
      setState(() => _errorMessage = 'New password and confirmation do not match.');
      return;
    }
    if (newPwd == oldPwd) {
      setState(() => _errorMessage = 'New password cannot be identical to the temporary password.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await widget.controller.changeStaffPassword(
        oldPassword: oldPwd,
        newPassword: newPwd,
      );
    } on MedCoreApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final user = widget.controller.currentUser;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            key: const Key('card_force_password_change'),
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.primary, width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.lock_reset, color: cs.primary, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'First Login — Set New Password',
                              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${user?.fullName ?? "Administrator"} (${user?.staffCode ?? ""})',
                              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'You have logged in with a temporary commissioning password. In accordance with MedCore security policy, '
                    'you must establish your private confidential password before accessing clinical or administrative records.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: cs.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: cs.onErrorContainer, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  TextField(
                    key: const Key('field_force_pwd_old'),
                    controller: _oldPasswordCtrl,
                    obscureText: _obscureOld,
                    decoration: InputDecoration(
                      labelText: 'Temporary Commissioning Password *',
                      prefixIcon: const Icon(Icons.key),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureOld ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscureOld = !_obscureOld),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('field_force_pwd_new'),
                    controller: _newPasswordCtrl,
                    obscureText: _obscureNew,
                    decoration: InputDecoration(
                      labelText: 'New Secure Password *',
                      hintText: 'Minimum 8 characters',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureNew ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscureNew = !_obscureNew),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('field_force_pwd_confirm'),
                    controller: _confirmPasswordCtrl,
                    obscureText: _obscureConfirm,
                    decoration: InputDecoration(
                      labelText: 'Confirm New Password *',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureConfirm ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    key: const Key('btn_force_pwd_submit'),
                    onPressed: _isSaving ? null : _submitPasswordChange,
                    icon: _isSaving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_circle_outline, size: 20),
                    label: Text(_isSaving ? 'Updating Password...' : 'Save Password & Enter MedCore'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('btn_force_pwd_logout'),
                    onPressed: widget.controller.logoutStaff,
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Cancel & Log Out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
