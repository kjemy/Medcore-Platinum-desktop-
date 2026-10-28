import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api/medcore_api_client.dart';
import '../../core/state/medcore_app_controller.dart';

/// Unified Maintenance Center, Database Lifecycle & Backup Engine Operations Screen.
///
/// Follows the MedCore Constitution:
/// - Flutter Client -> Local MedCore Service -> MariaDB
/// - Flutter NEVER connects directly to MariaDB.
/// - Reuses authoritative diagnostics from Local MedCore Service (`/api/v1/maintenance/*`,
///   `/api/v1/backups/*`, `/api/v1/database/*`) in both Staff-Authorized mode (`security_Center`)
///   and Protected Technician Mode (`X-MedCore-Tech-Token`).
class MaintenanceCenterScreen extends StatefulWidget {
  final MedCoreAppController controller;

  const MaintenanceCenterScreen({
    super.key,
    required this.controller,
  });

  @override
  State<MaintenanceCenterScreen> createState() => _MaintenanceCenterScreenState();
}

class _MaintenanceCenterScreenState extends State<MaintenanceCenterScreen> {
  static const String appVersion = '1.0.0-rc.1';
  Map<String, dynamic>? _overview;
  Map<String, dynamic>? _backupStatus;
  Map<String, dynamic>? _dbStatus;
  Map<String, dynamic>? _dbLocation;
  Map<String, dynamic>? _latestGeneratedReport;
  bool _loading = true;
  bool _actionBusy = false;
  String? _feedback;
  bool _isError = false;

  bool get _useTechAuth => widget.controller.isTechnicianModeActive;

  bool get _canRunBackup =>
      _useTechAuth ||
      ((widget.controller.currentUser?.hasAnyPermission(const ['settings_Backups']) ?? false) &&
          (widget.controller.currentUser?.canEdit ?? false));

  @override
  void initState() {
    super.initState();
    _loadMaintenanceTelemetry();
  }

  Future<void> _loadMaintenanceTelemetry() async {
    setState(() => _loading = true);
    String? errMsg;
    Map<String, dynamic>? overview;
    Map<String, dynamic>? backupStatus;
    Map<String, dynamic>? dbStatus;
    Map<String, dynamic>? dbLocation;

    try {
      overview = await widget.controller.api.getJson(
        '/api/v1/maintenance/overview',
        useTechnicianAuth: _useTechAuth,
      );
      if (_useTechAuth ||
          (widget.controller.currentUser?.hasAnyPermission(const ['settings_Backups']) ?? false)) {
        backupStatus = await widget.controller.api.getJson(
          '/api/v1/backups/status',
          useTechnicianAuth: _useTechAuth,
        );
        try {
          dbStatus = await widget.controller.api.getJson(
            '/api/v1/database/status',
            useTechnicianAuth: _useTechAuth,
          );
          dbLocation = await widget.controller.api.getJson(
            '/api/v1/database/location',
            useTechnicianAuth: _useTechAuth,
          );
        } catch (_) {}
      }
    } on MedCoreApiException catch (e) {
      errMsg = e.toString();
    }

    if (!mounted) return;
    setState(() {
      _overview = overview;
      _backupStatus = backupStatus;
      _dbStatus = dbStatus;
      _dbLocation = dbLocation;
      if (errMsg != null) {
        _feedback = errMsg;
        _isError = true;
      }
      _loading = false;
    });
  }

  Future<void> _generateFullMaintenanceReport() async {
    setState(() {
      _actionBusy = true;
      _feedback = null;
      _isError = false;
    });
    try {
      final rep = await widget.controller.api.postJson(
        '/api/v1/maintenance/reports',
        const <String, dynamic>{},
        useTechnicianAuth: _useTechAuth,
      );
      if (!mounted) return;
      setState(() {
        _latestGeneratedReport = rep;
        _feedback =
            'Generated & persisted PII-redacted Maintenance Report ${rep['reportUuid']} (Overall Status: ${rep['overallStatus']}).';
        _isError = false;
        _actionBusy = false;
      });
      await _loadMaintenanceTelemetry();
    } on MedCoreApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _feedback = e.toString();
        _isError = true;
        _actionBusy = false;
      });
    }
  }

  Future<void> _executeVerifiedLocalBackup() async {
    setState(() {
      _actionBusy = true;
      _feedback = null;
      _isError = false;
    });
    try {
      final run = await widget.controller.api.postJson(
        '/api/v1/backups/run',
        const {'providerId': 'LOCAL_STORAGE'},
        useTechnicianAuth: _useTechAuth,
      );
      if (!mounted) return;
      setState(() {
        _feedback =
            'Backup ${run['backupUuid']} completed with status [${run['status']}] • SHA-256: ${run['archiveSha256']} • Read-Back Verified: ${run['readBackVerified'] ?? true}.';
        _isError = false;
        _actionBusy = false;
      });
      await _loadMaintenanceTelemetry();
    } on MedCoreApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _feedback = e.toString();
        _isError = true;
        _actionBusy = false;
      });
    }
  }

  Future<void> _executeMultiFormatExport() async {
    setState(() {
      _actionBusy = true;
      _feedback = null;
      _isError = false;
    });
    try {
      final res = await widget.controller.api.postJson(
        '/api/v1/database/export',
        const {},
        useTechnicianAuth: _useTechAuth,
      );
      if (!mounted) return;
      setState(() {
        _feedback =
            'Multi-Format Export Complete: Generated SQL, CSV, JSON, XLSX & ZIP package. Location: ${res['backupDirectory']}';
        _isError = false;
        _actionBusy = false;
      });
      await _loadMaintenanceTelemetry();
    } on MedCoreApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _feedback = e.toString();
        _isError = true;
        _actionBusy = false;
      });
    }
  }

  Future<void> _openDatabaseExplorer() async {
    showDialog<void>(
      context: context,
      builder: (ctx) => _DatabaseExplorerDialog(
        api: widget.controller.api,
        useTechAuth: _useTechAuth,
      ),
    );
  }

  Future<void> _showLocationDialog() async {
    final loc = _dbLocation;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.folder_open),
            SizedBox(width: 8),
            Text('Database Physical Locations'),
          ],
        ),
        content: SizedBox(
          width: 550,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _locRow('Database Engine', loc?['engine'] ?? 'MariaDB'),
              _locRow('Database Name', loc?['databaseName'] ?? '-'),
              _locRow('Runtime Directory', loc?['runtimeDirectory'] ?? '-'),
              _locRow('Data Directory', loc?['databaseDataDirectory'] ?? '-'),
              _locRow('Backup Directory', loc?['backupDirectory'] ?? '-'),
              _locRow('Export Directory', loc?['exportDirectory'] ?? '-'),
              const Divider(height: 20),
              Text(
                loc?['safetyNotice'] ?? '',
                style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  static Widget _locRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          SelectableText(value, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Future<void> _showRestoreDialog() async {
    final pathCtrl = TextEditingController();
    final shaCtrl = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.restore, color: Colors.amber),
            SizedBox(width: 8),
            Text('Restore Database from Backup'),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'WARNING: Restoring will overwrite existing tables with data from the backup package. Active staff sessions will be invalidated.',
                style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pathCtrl,
                decoration: const InputDecoration(
                  labelText: 'Backup Package or Archive Path (.mcbak / directory)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: shaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Expected SHA-256 (Optional Checksum Verification)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            key: const Key('btn_confirm_restore'),
            onPressed: () async {
              final path = pathCtrl.text.trim();
              if (path.isEmpty) return;
              Navigator.of(ctx).pop();
              await _executeRestore(path, shaCtrl.text.trim());
            },
            icon: const Icon(Icons.restore),
            label: const Text('Execute Restore'),
          ),
        ],
      ),
    );
  }

  Future<void> _executeRestore(String path, String expectedSha) async {
    setState(() {
      _actionBusy = true;
      _feedback = null;
      _isError = false;
    });
    try {
      final res = await widget.controller.api.postJson(
        '/api/v1/database/restore',
        {
          'backupPath': path,
          if (expectedSha.isNotEmpty) 'expectedSha256': expectedSha,
        },
        useTechnicianAuth: true,
      );
      if (!mounted) return;
      setState(() {
        _feedback =
            'DATABASE RESTORED SUCCESSFULLY: Restored ${res['restoredTableCount']} tables. Trial Balance Conservation: ${res['financialTrialBalance']['balanced'] ? 'PASS' : 'FAIL'}.';
        _isError = false;
        _actionBusy = false;
      });
      await _loadMaintenanceTelemetry();
    } on MedCoreApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _feedback = 'Restore failed: ${e.message}';
        _isError = true;
        _actionBusy = false;
      });
    }
  }

  Future<void> _showFactoryResetDialog() async {
    final confirmCtrl = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('DANGER: FACTORY RESET DATABASE'),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This will COMPLETELY DESTROY AND RECREATE the local MariaDB database from zero.\n\n'
                '• A mandatory pre-reset backup will be verified before destruction.\n'
                '• All migrations (V001..V016) will execute from zero.\n'
                '• Baseline system tenant and security anchors will be reseeded.\n\n'
                'To confirm, type exactly: RESET MEDCORE',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: confirmCtrl,
                key: const Key('input_factory_reset_confirmation'),
                decoration: const InputDecoration(
                  labelText: 'Confirmation Phrase',
                  hintText: 'RESET MEDCORE',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('btn_confirm_factory_reset'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              if (confirmCtrl.text.trim() != 'RESET MEDCORE') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid confirmation phrase. Type RESET MEDCORE.')),
                );
                return;
              }
              Navigator.of(ctx).pop();
              await _executeFactoryReset(confirmCtrl.text.trim());
            },
            child: const Text('DESTROY & REBUILD DATABASE'),
          ),
        ],
      ),
    );
  }

  Future<void> _executeFactoryReset(String confirmation) async {
    setState(() {
      _actionBusy = true;
      _feedback = null;
      _isError = false;
    });
    try {
      final res = await widget.controller.api.postJson(
        '/api/v1/database/factory-reset',
        {
          'confirmationText': confirmation,
          'requireMandatoryBackup': true,
        },
        useTechnicianAuth: true,
      );
      if (!mounted) return;
      setState(() {
        _feedback =
            'FACTORY RESET COMPLETE: Rebuilt ${res['rebuiltTableCount']} tables across ${res['appliedMigrationsCount']} migrations. Baseline system data initialized. System Ready.';
        _isError = false;
        _actionBusy = false;
      });
      await _loadMaintenanceTelemetry();
    } on MedCoreApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _feedback = 'Factory reset failed: ${e.message}';
        _isError = true;
        _actionBusy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ov = _overview;
    final dbs = _dbStatus;

    final svc = ov?['serviceStatus'] is Map
        ? Map<String, dynamic>.from(ov!['serviceStatus'] as Map)
        : const <String, dynamic>{};
    final db = ov?['databaseStatus'] is Map
        ? Map<String, dynamic>.from(ov!['databaseStatus'] as Map)
        : const <String, dynamic>{};
    final mig = ov?['migrationStatus'] is Map
        ? Map<String, dynamic>.from(ov!['migrationStatus'] as Map)
        : const <String, dynamic>{};
    final stor = ov?['storageStatus'] is Map
        ? Map<String, dynamic>.from(ov!['storageStatus'] as Map)
        : const <String, dynamic>{};
    final sec = ov?['securityStatus'] is Map
        ? Map<String, dynamic>.from(ov!['securityStatus'] as Map)
        : const <String, dynamic>{};
    final lic = ov?['licenseStatus'] is Map
        ? Map<String, dynamic>.from(ov!['licenseStatus'] as Map)
        : const <String, dynamic>{};
    final net = ov?['networkStatus'] is Map
        ? Map<String, dynamic>.from(ov!['networkStatus'] as Map)
        : const <String, dynamic>{};
    final diag = ov?['diagnostics'] is Map
        ? Map<String, dynamic>.from(ov!['diagnostics'] as Map)
        : const <String, dynamic>{};
    final tb = diag['financialTrialBalance'] is Map
        ? Map<String, dynamic>.from(diag['financialTrialBalance'] as Map)
        : const <String, dynamic>{};
    final bkp = ov?['backupStatus'] is Map
        ? Map<String, dynamic>.from(ov!['backupStatus'] as Map)
        : const <String, dynamic>{};
    final logs = ov?['logs'] is Map
        ? Map<String, dynamic>.from(ov!['logs'] as Map)
        : const <String, dynamic>{};
    final errors = (ov?['errors'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final hist = ov?['maintenanceHistory'] is Map
        ? Map<String, dynamic>.from(ov!['maintenanceHistory'] as Map)
        : const <String, dynamic>{};

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 12,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Maintenance Center, Diagnostics & Backup Engine',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  'App Version: ${ov?['applicationVersion'] ?? appVersion} • Overall Status: ${ov?['overallStatus'] ?? '-'} • Facility: ${ov?['facilityName'] ?? '-'}',
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_canRunBackup)
                  FilledButton.tonalIcon(
                    key: const Key('btn_run_verified_backup'),
                    onPressed: _actionBusy ? null : _executeVerifiedLocalBackup,
                    icon: const Icon(Icons.backup_outlined, size: 18),
                    label: const Text('Run Verified Backup'),
                  ),
                FilledButton.icon(
                  key: const Key('btn_generate_maintenance_report'),
                  onPressed: _actionBusy ? null : _generateFullMaintenanceReport,
                  icon: const Icon(Icons.summarize_outlined, size: 18),
                  label: const Text('Generate Full Report'),
                ),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _loadMaintenanceTelemetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh'),
                ),
              ],
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
                style: TextStyle(color: _isError ? cs.onErrorContainer : cs.onPrimaryContainer),
              ),
            ),
          ),

        if (_latestGeneratedReport != null)
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.assignment_turned_in_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Report ${_latestGeneratedReport!['reportUuid']} persisted in mc_maintenance_reports (Redaction: PII_AND_SECRETS_EXCLUDED).',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final pretty =
                          const JsonEncoder.withIndent('  ').convert(_latestGeneratedReport);
                      await Clipboard.setData(ClipboardData(text: pretty));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Copied full PII-redacted Maintenance Report JSON.'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy Report JSON'),
                  ),
                ],
              ),
            ),
          ),

        if (_loading)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          // 14 Maintenance Telemetry Dimensions Summary Cards
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _MaintTile(
                title: '1. App & Service Status',
                value: '${svc['status'] ?? '-'} (${svc['operationalMode'] ?? '-'})',
                details: 'Version: ${ov?['applicationVersion']} • Port: ${svc['boundPort'] ?? '-'}',
              ),
              _MaintTile(
                title: '2. Database Engine',
                value: '${db['engine'] ?? 'MariaDB'} ${db['serverVersion'] ?? ''}',
                details:
                    'DB: ${db['databaseName']} • Loopback Isolated: ${db['loopbackIsolated']}',
              ),
              _MaintTile(
                title: '3. Schema Migrations',
                value: '${mig['appliedCount'] ?? 0} Applied (Latest: ${mig['latestVersion'] ?? '-'})',
                details: 'Verified via mc_schema_migrations SHA-256 ledger',
              ),
              _MaintTile(
                title: '4. Physical Storage',
                value: '${stor['tableCount'] ?? 0} Tables • ${stor['totalBytes'] ?? 0} Bytes',
                details: 'Approx Rows: ${stor['approxTotalRows'] ?? 0}',
              ),
              _MaintTile(
                title: '5. Security & Clock Guard',
                value: '${sec['clockGuardStatus'] ?? '-'}',
                details:
                    'Root Anchored: ${sec['securityRootAnchored']} • Staff Sessions: ${sec['activeStaffSessions']} • Tech Sessions: ${sec['activeTechnicianSessions']}',
              ),
              _MaintTile(
                title: '6. License & Entitlements',
                value: '${lic['edition'] ?? widget.controller.facilityConfig.edition}',
                details:
                    'Status: ${lic['status'] ?? 'ACTIVE'} • Expires: ${lic['expiresUtc'] ?? 'Perpetual/Local'}',
              ),
              _MaintTile(
                title: '7. Network & Connected Devices',
                value:
                    '${net['activeDevicesCount'] ?? 0} Active / ${net['pendingPairingCount'] ?? 0} Pending',
                details:
                    'LAN Allowed: ${net['allowLanConnections']} • Wi-Fi Allowed: ${net['allowWifiConnections']}',
              ),
              _MaintTile(
                title: '8. Financial Integrity',
                value: tb['balanced'] == true ? 'BALANCED (PASS)' : 'OUT OF BALANCE (FAIL)',
                details:
                    'Debits: ${tb['totalDebits'] ?? '0.0000'} • Credits: ${tb['totalCredits'] ?? '0.0000'} • Entries: ${tb['postedEntriesCount'] ?? 0}',
              ),
              _MaintTile(
                title: '9. Cashier & Shifts',
                value: '${diag['openCashierShiftsCount'] ?? 0} Open Shift(s)',
                details: 'Active Cashier Drawer Sessions',
              ),
              _MaintTile(
                title: '10. Dual Control Governance',
                value: '${diag['pendingDualControlRequestsCount'] ?? 0} Pending Approvals',
                details: 'Requires 4-Eyes Dual Approval for Execution',
              ),
              _MaintTile(
                title: '11. Local Backup Engine',
                value: '${bkp['configuredProvider'] ?? 'LOCAL_STORAGE'} Provider',
                details:
                    'Recorded Runs: ${bkp['totalRecordedRuns'] ?? 0} • Encrypted & Verified Local Storage',
              ),
              _MaintTile(
                title: '12. Audit & Security Logs',
                value:
                    '${(logs['auditLogs'] as List? ?? const []).length} Audit / ${(logs['securityLogs'] as List? ?? const []).length} Sec Logs',
                details: 'Immutable append-only activity ledger',
              ),
              _MaintTile(
                title: '13. Error Telemetry',
                value: '${errors.length} Recorded Issues',
                details: errors.isEmpty
                    ? 'Clean system runtime telemetry'
                    : 'Recent recorded system warning/error events',
              ),
              _MaintTile(
                title: '14. Maintenance Reports & Consumed Tokens',
                value:
                    '${(hist['generatedReports'] as List? ?? const []).length} Reports / ${(hist['consumedAuthorityTokens'] as List? ?? const []).length} Consumed Tokens',
                details: 'PII-redacted diagnostics & technician security tokens',
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Database Lifecycle Action Bar (Explorer, Location, Export, Restore, Danger Zone)
          Card(
            elevation: 1,
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.storage, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text(
                        'Database Engine: ${dbs?['engine'] ?? 'MariaDB'} ${dbs?['serverVersion'] ?? ''} • ${dbs?['databaseName'] ?? db['databaseName']}',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Chip(
                        label: Text(
                          'Status: ${dbs?['databaseStatus'] ?? 'ONLINE'}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                        backgroundColor: Colors.green.withOpacity(0.15),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.tonalIcon(
                        key: const Key('btn_database_explorer'),
                        onPressed: _openDatabaseExplorer,
                        icon: const Icon(Icons.table_chart_outlined, size: 18),
                        label: const Text('Explorer'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('btn_open_database_folder'),
                        onPressed: _showLocationDialog,
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: const Text('Location'),
                      ),
                      if (_canRunBackup)
                        FilledButton.tonalIcon(
                          key: const Key('btn_export_multi_format'),
                          onPressed: _actionBusy ? null : _executeMultiFormatExport,
                          icon: const Icon(Icons.file_download_outlined, size: 18),
                          label: const Text('Export Multi-Format (SQL, CSV, JSON, XLSX, ZIP)'),
                        ),
                      if (_useTechAuth) ...[
                        OutlinedButton.icon(
                          key: const Key('btn_restore_database'),
                          onPressed: _actionBusy ? null : _showRestoreDialog,
                          icon: const Icon(Icons.restore_outlined, size: 18),
                          label: const Text('Restore Database'),
                        ),
                        FilledButton(
                          key: const Key('btn_factory_reset'),
                          style: FilledButton.styleFrom(backgroundColor: Colors.red),
                          onPressed: _actionBusy ? null : _showFactoryResetDialog,
                          child: const Text('FACTORY RESET'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // P2 Backup Engine Architecture & Recent Runs
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Backup Engine Pipeline & Future-Ready Remote / Hybrid Boundary (P2)',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Pipeline: ${(_backupStatus?['pipelineStages'] as List?)?.join(' -> ') ?? '1_MARIADB_SNAPSHOT -> 2_GZIP_COMPRESS -> 3_AUTHENTICATED_ENCRYPT -> 4_SHA256_CHECKSUM -> 5_PROVIDER_UPLOAD -> 6_INDEPENDENT_READBACK_VERIFICATION'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Vendor-Neutral Providers: LOCAL_STORAGE (Verified) • S3_COMPATIBLE (Backblaze B2 / Cloudflare R2 / AWS S3 / Wasabi — Zero Vendor Lock-In) • CLOUD_ADAPTER • Local-First (Internet Optional)',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  if ((bkp['recentRuns'] as List? ?? const []).isEmpty)
                    const Text('No backup runs recorded in mc_backup_runs yet.')
                  else
                    for (final r in (bkp['recentRuns'] as List))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.archive_outlined, size: 18),
                        title: Text(
                          '${(r as Map)['backupUuid']} — [${r['status']}] (${r['triggerType']}) • Schema ${r['schemaVersion']}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          'Bytes: ${r['archiveSizeBytes']} • SHA-256: ${r['archiveSha256']} • Path: ${r['archivePath']}',
                        ),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Security Logs, Audit Logs, Errors & Maintenance History
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recent Security & Audit Logs',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        for (final l in (logs['securityLogs'] as List? ?? const []).take(5))
                          Text(
                            '• [SEC] ${(l as Map)['eventType']} (${l['severity']}) — Route: ${l['routePath']}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        const Divider(height: 16),
                        for (final a in (logs['auditLogs'] as List? ?? const []).take(5))
                          Text(
                            '• [AUDIT] ${(a as Map)['action']} on ${a['entityType']}:${a['entityId']} by ${a['actorRole']}',
                            style: const TextStyle(fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Maintenance Reports & System Errors',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        for (final r in (hist['generatedReports'] as List? ?? const []).take(4))
                          Text(
                            '• Report ${(r as Map)['reportUuid']} [${r['overallStatus']}] by ${r['generatedByActor']}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        if (errors.isNotEmpty) ...[
                          const Divider(height: 16),
                          for (final er in errors.take(6))
                            Text(
                              '• [${er['severity']}] ${er['module']}: ${er['errorCode']} (${er['endpoint'] ?? '-'})',
                              style: TextStyle(fontSize: 12, color: cs.error),
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
      ],
    );
  }
}

class _DatabaseExplorerDialog extends StatefulWidget {
  final MedCoreApiClient api;
  final bool useTechAuth;

  const _DatabaseExplorerDialog({
    required this.api,
    required this.useTechAuth,
  });

  @override
  State<_DatabaseExplorerDialog> createState() => _DatabaseExplorerDialogState();
}

class _DatabaseExplorerDialogState extends State<_DatabaseExplorerDialog> {
  bool _loading = true;
  List<Map<String, dynamic>> _tables = [];
  Map<String, dynamic>? _selectedTable;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadSchema();
  }

  Future<void> _loadSchema() async {
    try {
      final res = await widget.api.getJson(
        '/api/v1/database/schema',
        useTechnicianAuth: widget.useTechAuth,
      );
      final list = (res['tables'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _tables = list;
        _loading = false;
        if (list.isNotEmpty) _selectedTable = list.first;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _tables
        .where((t) => (t['tableName'] ?? '').toString().toLowerCase().contains(_search.toLowerCase()))
        .toList();

    return Dialog(
      child: SizedBox(
        width: 850,
        height: 580,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.table_view, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    'MedCore Database Explorer (${_tables.length} Tables)',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: 'Search tables...',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (val) => setState(() => _search = val),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : Row(
                        children: [
                          SizedBox(
                            width: 280,
                            child: ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (ctx, i) {
                                final t = filtered[i];
                                final isSel = _selectedTable?['tableName'] == t['tableName'];
                                return ListTile(
                                  dense: true,
                                  selected: isSel,
                                  title: Text(t['tableName'] ?? '', style: const TextStyle(fontSize: 12)),
                                  subtitle: Text('${(t['columns'] as List?)?.length ?? 0} cols • ${t['engine']}'),
                                  onTap: () => setState(() => _selectedTable = t),
                                );
                              },
                            ),
                          ),
                          const VerticalDivider(),
                          Expanded(
                            child: _selectedTable == null
                                ? const Center(child: Text('Select a table to view structure.'))
                                : ListView(
                                    children: [
                                      Text(
                                        'Table: ${_selectedTable!['tableName']}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                      Text('Engine: ${_selectedTable!['engine']} • Collation: ${_selectedTable!['collation']}'),
                                      const SizedBox(height: 10),
                                      const Text('Columns:', style: TextStyle(fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 6),
                                      for (final col in (_selectedTable!['columns'] as List? ?? const []))
                                        Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 3),
                                          child: Row(
                                            children: [
                                              Icon(
                                                col['key'] == 'PRI'
                                                    ? Icons.key
                                                    : Icons.table_rows_outlined,
                                                size: 14,
                                                color: col['key'] == 'PRI' ? Colors.amber : null,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                col['name'] ?? '',
                                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                              ),
                                              const Spacer(),
                                              Text(
                                                col['type'] ?? '',
                                                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MaintTile extends StatelessWidget {
  final String title;
  final String value;
  final String details;

  const _MaintTile({
    required this.title,
    required this.value,
    required this.details,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 280,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                value,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                details,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
