import 'package:flutter/material.dart';
import '../../core/api/medcore_api_client.dart';
import '../../core/state/medcore_app_controller.dart';

class ExecutiveDashboardScreen extends StatefulWidget {
  final MedCoreAppController controller;

  const ExecutiveDashboardScreen({
    super.key,
    required this.controller,
  });

  @override
  State<ExecutiveDashboardScreen> createState() => _ExecutiveDashboardScreenState();
}

class _ExecutiveDashboardScreenState extends State<ExecutiveDashboardScreen> {
  Map<String, dynamic>? _health;
  Map<String, dynamic>? _openShift;
  String? _loadError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLiveTelemetry();
  }

  Future<void> _loadLiveTelemetry() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final health = await widget.controller.api.getJson('/api/v1/health', includeAuth: false);
      Map<String, dynamic>? shiftData;
      if (widget.controller.facilityConfig.isModuleEnabled('Shifts') &&
          widget.controller.currentUser!.hasAnyPermission(const ['shifts'])) {
        final shiftResp = await widget.controller.api.getJson('/api/v1/shifts/current');
        if (shiftResp['openShift'] is Map) {
          shiftData = Map<String, dynamic>.from(shiftResp['openShift'] as Map);
        }
      }
      if (!mounted) return;
      setState(() {
        _health = health;
        _openShift = shiftData;
        _loading = false;
      });
    } on MedCoreApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.controller.facilityConfig;
    final user = widget.controller.currentUser!;
    final theme = Theme.of(context);
    final enabledMods =
        cfg.enabledModules.entries.where((e) => e.value).map((e) => e.key).toList();
    final disabledMods =
        cfg.enabledModules.entries.where((e) => !e.value).map((e) => e.key).toList();

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
                    'Executive Overview — ${cfg.facilityName}',
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Facility Type: ${cfg.facilityType} • Edition: ${cfg.edition} • Branch: ${cfg.branchCode} • Config v${cfg.configVersion}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: _loading ? null : _loadLiveTelemetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh Live State'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (_loadError != null)
          Card(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(_loadError!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
            ),
          ),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _MetricCard(
              title: 'Local MedCore Service',
              value: _health?['status']?.toString() ?? (_loading ? 'Probing...' : 'UNREACHABLE'),
              subtitle:
                  'DB: ${_health?['database'] ?? '-'} • Tables: ${_health?['tableCount'] ?? '-'} • Migrations: ${_health?['appliedMigrations'] ?? '-'}',
              icon: Icons.verified_outlined,
            ),
            _MetricCard(
              title: 'Authenticated Staff Scope',
              value: user.role,
              subtitle:
                  '${user.fullName} (${user.staffCode}) • ${user.effectivePermissions.length} effective permissions',
              icon: Icons.admin_panel_settings_outlined,
            ),
            _MetricCard(
              title: 'Active Cashier Shift',
              value: _openShift != null
                  ? (_openShift!['shift_code'] ?? _openShift!['shiftCode'] ?? 'OPEN').toString()
                  : 'NO OPEN SHIFT',
              subtitle: _openShift != null
                  ? 'Expected Cash: ${_openShift!['expected_cash'] ?? _openShift!['expectedCash'] ?? '0.0000'}'
                  : 'Open a shift in Shifts & Visit Billing to collect cash',
              icon: Icons.point_of_sale_outlined,
            ),
            const _MetricCard(
              title: 'Architecture Mode',
              value: 'LOCAL-FIRST',
              subtitle: 'Flutter Desktop → Local MedCore Service → MariaDB (127.0.0.1)',
              icon: Icons.shield_outlined,
            ),
          ],
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Configured Module Entitlements (${enabledMods.length} Enabled / ${disabledMods.length} Disabled)',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in enabledMods)
                      Chip(
                        avatar: const Icon(Icons.check_circle_outline, size: 16),
                        label: Text(m),
                      ),
                    for (final m in disabledMods)
                      Chip(
                        avatar: Icon(Icons.block, size: 16, color: theme.colorScheme.error),
                        label: Text('$m (Disabled)'),
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
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 280,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: theme.colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
