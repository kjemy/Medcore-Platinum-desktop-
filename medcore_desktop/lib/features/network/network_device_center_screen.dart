import 'package:flutter/material.dart';
import '../../core/api/medcore_api_client.dart';
import '../../core/state/medcore_app_controller.dart';

/// Network & Connected Devices Center (`CONNECT VIA LAN`, `CONNECT VIA WI-FI`).
/// Enforces and visualizes:
/// - `Discovery != Authorization` (PENDING devices require 6-character SHA-256-verified pairing code)
/// - `MariaDB 127.0.0.1 Loopback Isolation` (no direct client -> DB access over LAN/Wi-Fi)
/// - Device table (`deviceName`, `ip`, `connectionType`, `status`, `medcoreVersion`, `role`, `lastSeen`)
/// - Immediate session termination upon device revocation
/// - Honest `TLS_CERT_INFRASTRUCTURE_PENDING` disclosure
class NetworkDeviceCenterScreen extends StatefulWidget {
  final MedCoreAppController controller;

  const NetworkDeviceCenterScreen({
    super.key,
    required this.controller,
  });

  @override
  State<NetworkDeviceCenterScreen> createState() => _NetworkDeviceCenterScreenState();
}

class _NetworkDeviceCenterScreenState extends State<NetworkDeviceCenterScreen> {
  Map<String, dynamic>? _topology;
  bool _loading = true;
  String? _feedback;
  bool _isError = false;

  bool get _useTechAuth => widget.controller.isTechnicianModeActive;

  bool get _canMutateDevices =>
      _useTechAuth || (widget.controller.currentUser?.canEdit == true);

  @override
  void initState() {
    super.initState();
    _loadTopology();
  }

  Future<void> _loadTopology() async {
    setState(() => _loading = true);
    try {
      final res = await widget.controller.api.getJson(
        '/api/v1/network/topology',
        useTechnicianAuth: _useTechAuth,
      );
      if (!mounted) return;
      setState(() {
        _topology = res;
        _loading = false;
      });
    } on MedCoreApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _feedback = e.toString();
        _isError = true;
        _loading = false;
      });
    }
  }

  Future<void> _showApprovePairingDialog(Map<String, dynamic> device) async {
    final codeCtrl = TextEditingController();
    String selectedRole = (device['role'] ?? 'WORKSTATION').toString();
    bool trustedSecureRuntime = device['isTrustedSecureRuntime'] != false;
    final needsCode = device['requiresPairingCodeVerification'] == true;
    String? dialogErr;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text('Approve Device Pairing — ${device['deviceName']} (${device['deviceId']})'),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'IP: ${device['ip']} • Mode: ${device['connectionType']} • Version: ${device['medcoreVersion']}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    if (needsCode) ...[
                      TextField(
                        key: const Key('input_approve_pairing_code'),
                        controller: codeCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: '6-Character Pairing Verification Code (from target device)',
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: const [
                        'MAIN_HOST',
                        'WORKSTATION',
                        'TABLET_CLINICAL',
                        'KIOSK',
                      ].contains(selectedRole)
                          ? selectedRole
                          : 'WORKSTATION',
                      decoration: const InputDecoration(labelText: 'Authorized Role Scope'),
                      items: const [
                        DropdownMenuItem(value: 'WORKSTATION', child: Text('WORKSTATION')),
                        DropdownMenuItem(value: 'TABLET_CLINICAL', child: Text('TABLET_CLINICAL')),
                        DropdownMenuItem(value: 'KIOSK', child: Text('KIOSK (Untrusted Public Screen)')),
                        DropdownMenuItem(value: 'MAIN_HOST', child: Text('MAIN_HOST')),
                      ],
                      onChanged: (v) => setDialogState(() => selectedRole = v ?? 'WORKSTATION'),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Trusted Secure Runtime (allows _secure locked pages)'),
                      value: selectedRole == 'KIOSK' ? false : trustedSecureRuntime,
                      onChanged: selectedRole == 'KIOSK'
                          ? null
                          : (v) => setDialogState(() => trustedSecureRuntime = v),
                    ),
                    if (dialogErr != null) ...[
                      const SizedBox(height: 8),
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
                FilledButton.icon(
                  key: const Key('btn_confirm_approve_device'),
                  onPressed: () async {
                    setDialogState(() => dialogErr = null);
                    try {
                      final encId = Uri.encodeComponent(device['deviceId'].toString());
                      await widget.controller.api.postJson(
                        '/api/v1/network/devices/$encId/approve',
                        {
                          if (needsCode) 'pairingVerificationCode': codeCtrl.text.trim().toUpperCase(),
                          'roleScope': selectedRole,
                          'isTrustedSecureRuntime':
                              selectedRole == 'KIOSK' ? false : trustedSecureRuntime,
                        },
                        useTechnicianAuth: _useTechAuth,
                      );
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      if (!mounted) return;
                      setState(() {
                        _feedback =
                            'Approved device ${device['deviceId']} (${device['deviceName']}) as ACTIVE ($selectedRole).';
                        _isError = false;
                      });
                      await _loadTopology();
                    } on MedCoreApiException catch (e) {
                      setDialogState(() => dialogErr = e.toString());
                    }
                  },
                  icon: const Icon(Icons.verified_user_outlined, size: 18),
                  label: const Text('Approve & Activate Device'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _revokeDevice(Map<String, dynamic> device) async {
    try {
      final encId = Uri.encodeComponent(device['deviceId'].toString());
      await widget.controller.api.postJson(
        '/api/v1/network/devices/$encId/revoke',
        {'reason': 'Revoked via MedCore Network & Devices Center'},
        useTechnicianAuth: _useTechAuth,
      );
      if (!mounted) return;
      setState(() {
        _feedback =
            'Revoked device ${device['deviceId']} and terminated all bound staff/technician sessions.';
        _isError = false;
      });
      await _loadTopology();
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
    final topo = _topology;
    final modes = topo?['connectionModes'] is Map
        ? Map<String, dynamic>.from(topo!['connectionModes'] as Map)
        : const <String, dynamic>{};
    final sec = topo?['securityPosture'] is Map
        ? Map<String, dynamic>.from(topo!['securityPosture'] as Map)
        : const <String, dynamic>{};
    final summary = topo?['summary'] is Map
        ? Map<String, dynamic>.from(topo!['summary'] as Map)
        : const <String, dynamic>{};
    final devices = (topo?['devices'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

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
                    'Network & Connected Devices Foundation',
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    'CONNECT VIA LAN • CONNECT VIA WI-FI • Explicit Pairing Approval • MariaDB Loopback Isolation',
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: _loading ? null : _loadTopology,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh Devices'),
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

        if (_loading)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _NetworkChipCard(
                icon: Icons.lan_outlined,
                title: 'CONNECT VIA LAN',
                value: modes['connectViaLanEnabled'] == true ? 'ENABLED' : 'DISABLED',
                subtitle: 'Max Authorized Devices: ${modes['maxAuthorizedDevices'] ?? '-'}',
              ),
              _NetworkChipCard(
                icon: Icons.wifi,
                title: 'CONNECT VIA WI-FI',
                value: modes['connectViaWifiEnabled'] == true ? 'ENABLED' : 'DISABLED',
                subtitle: 'Discovery != Authorization (Pairing Required)',
              ),
              _NetworkChipCard(
                icon: Icons.storage_outlined,
                title: 'MariaDB Network Isolation',
                value: sec['mariaDbLoopbackOnlyEnforced'] == true
                    ? '127.0.0.1 LOOPBACK ONLY'
                    : 'CHECK BINDING',
                subtitle:
                    'DB Host: ${sec['mariaDbHost'] ?? '-'}:${sec['mariaDbPort'] ?? '-'} (Never LAN-exposed)',
              ),
              _NetworkChipCard(
                icon: Icons.devices_other_outlined,
                title: 'Enrolled Fleet Summary',
                value: '${summary['activeCount'] ?? 0} Active / ${summary['pendingCount'] ?? 0} Pending',
                subtitle:
                    'Total: ${summary['totalDevices'] ?? 0} • Revoked: ${summary['revokedCount'] ?? 0}',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Honest TLS Security Disclosure Banner
          Card(
            color: cs.secondaryContainer.withOpacity(0.45),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.security_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Transport Security Posture [${sec['tlsCertificateRuntimeStatus'] ?? 'TLS_CERT_INFRASTRUCTURE_PENDING'}]: ${sec['tlsNotice'] ?? 'mTLS/TLS X.509 runtime provisioning pending.'}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Connected & Pending Devices Table
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Discovered, Pending & Authorized Devices (${devices.length})',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  if (devices.isEmpty)
                    const Text('No devices enrolled yet.')
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Device Name & ID')),
                          DataColumn(label: Text('IP Address')),
                          DataColumn(label: Text('Connection Type')),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('MedCore Version')),
                          DataColumn(label: Text('Role')),
                          DataColumn(label: Text('Last Seen (UTC)')),
                          DataColumn(label: Text('Governance Actions')),
                        ],
                        rows: devices.map((d) {
                          final status = (d['status'] ?? '').toString();
                          final devId = (d['deviceId'] ?? '').toString();
                          final isCurrent = devId == widget.controller.api.deviceId;
                          return DataRow(
                            cells: [
                              DataCell(Text('${d['deviceName']} ($devId)')),
                              DataCell(Text('${d['ip']}')),
                              DataCell(Text('${d['connectionType']}')),
                              DataCell(
                                Chip(
                                  label: Text(
                                    status,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                              DataCell(Text('${d['medcoreVersion']}')),
                              DataCell(Text('${d['role']}')),
                              DataCell(Text('${d['lastSeen'] ?? '-'}')),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_canMutateDevices && status != 'ACTIVE')
                                      FilledButton.tonal(
                                        key: Key('btn_approve_device_$devId'),
                                        onPressed: () => _showApprovePairingDialog(d),
                                        child: const Text('Approve Pairing'),
                                      ),
                                    if (_canMutateDevices &&
                                        status == 'ACTIVE' &&
                                        !isCurrent) ...[
                                      const SizedBox(width: 8),
                                      OutlinedButton(
                                        key: Key('btn_revoke_device_$devId'),
                                        onPressed: () => _revokeDevice(d),
                                        child: const Text('Revoke'),
                                      ),
                                    ],
                                    if (isCurrent)
                                      const Padding(
                                        padding: EdgeInsets.only(left: 8),
                                        child: Text(
                                          '(This Device)',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _NetworkChipCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;

  const _NetworkChipCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 265,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}
