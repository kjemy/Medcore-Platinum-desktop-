import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import '../../core/api/medcore_api_client.dart';
import '../../core/state/medcore_app_controller.dart';

class ConnectionAndLoginScreen extends StatefulWidget {
  final MedCoreAppController controller;

  const ConnectionAndLoginScreen({
    super.key,
    required this.controller,
  });

  @override
  State<ConnectionAndLoginScreen> createState() => _ConnectionAndLoginScreenState();
}

class _ConnectionAndLoginScreenState extends State<ConnectionAndLoginScreen> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _hospCtrl;
  late final TextEditingController _deviceCtrl;
  final TextEditingController _identifierCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();

  String? _statusMsg;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.controller.api.baseUrl);
    _hospCtrl = TextEditingController(text: widget.controller.api.hospitalCode);
    _deviceCtrl = TextEditingController(text: widget.controller.api.deviceId);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _hospCtrl.dispose();
    _deviceCtrl.dispose();
    _identifierCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _probeConnection() async {
    setState(() {
      _statusMsg = null;
      _isError = false;
    });
    try {
      await widget.controller.connectAndLoadBootstrap(
        baseUrl: _urlCtrl.text,
        hospitalCode: _hospCtrl.text,
        deviceId: _deviceCtrl.text,
      );
      if (!mounted) return;
      setState(() {
        _statusMsg =
            'Connected to Local MedCore Service (${widget.controller.facilityConfig.facilityName} • ${widget.controller.branding.editionLabel}).';
        _isError = false;
      });
    } on MedCoreApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMsg = e.toString();
        _isError = true;
      });
    }
  }

  Future<void> _handleStaffLogin() async {
    setState(() {
      _statusMsg = null;
      _isError = false;
    });
    try {
      widget.controller.api.configureConnection(
        baseUrl: _urlCtrl.text,
        hospitalCode: _hospCtrl.text,
        deviceId: _deviceCtrl.text,
      );
      await widget.controller.loginStaff(
        identifier: _identifierCtrl.text,
        password: _passwordCtrl.text,
      );
    } on MedCoreApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMsg = e.toString();
        _isError = true;
      });
    }
  }

  Future<void> _showLanWifiPairingDialog() async {
    final nameCtrl = TextEditingController(text: 'Workstation ${_deviceCtrl.text}');
    String connType = 'LAN';
    String roleScope = 'WORKSTATION';
    String? pairingCodeResult;
    String? dialogErr;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Connect Device via LAN / Wi-Fi (Secure Pairing)'),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Security Boundary: Discovery is NOT authorization. Submitting a pairing request registers this device as PENDING with zero data access until approved on the Main Host. MariaDB remains strictly loopback-isolated (127.0.0.1).',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Device Display Name'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: connType,
                      decoration: const InputDecoration(labelText: 'Connection Mode'),
                      items: const [
                        DropdownMenuItem(value: 'LAN', child: Text('CONNECT VIA LAN (Ethernet)')),
                        DropdownMenuItem(value: 'WIFI', child: Text('CONNECT VIA WI-FI (Hospital WLAN)')),
                      ],
                      onChanged: (v) => setDialogState(() => connType = v ?? 'LAN'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: roleScope,
                      decoration: const InputDecoration(labelText: 'Requested Device Role'),
                      items: const [
                        DropdownMenuItem(value: 'WORKSTATION', child: Text('WORKSTATION')),
                        DropdownMenuItem(value: 'TABLET_CLINICAL', child: Text('TABLET_CLINICAL')),
                        DropdownMenuItem(value: 'KIOSK', child: Text('KIOSK (Untrusted Screen)')),
                      ],
                      onChanged: (v) => setDialogState(() => roleScope = v ?? 'WORKSTATION'),
                    ),
                    if (dialogErr != null) ...[
                      const SizedBox(height: 12),
                      Text(dialogErr!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                    ],
                    if (pairingCodeResult != null) ...[
                      const SizedBox(height: 14),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'PENDING APPROVAL — Present Verification Code to Main Host:',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 6),
                              SelectableText(
                                pairingCodeResult!,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Close'),
                ),
                FilledButton(
                  onPressed: () async {
                    setDialogState(() {
                      dialogErr = null;
                      pairingCodeResult = null;
                    });
                    try {
                      widget.controller.api.configureConnection(
                        baseUrl: _urlCtrl.text,
                        hospitalCode: _hospCtrl.text,
                        deviceId: _deviceCtrl.text,
                      );
                      final fp = sha256
                          .convert(utf8.encode('${_deviceCtrl.text}|${nameCtrl.text}|WINDOWS'))
                          .toString();
                      final res = await widget.controller.api.postJson(
                        '/api/v1/network/pairing/request',
                        {
                          'hospitalCode': _hospCtrl.text.trim(),
                          'deviceId': _deviceCtrl.text.trim(),
                          'deviceName': nameCtrl.text.trim(),
                          'connectionType': connType,
                          'platform': 'WINDOWS',
                          'roleScope': roleScope,
                          'medcoreVersion': '1.0.0-rc.1',
                          'hwFingerprintSha256': fp,
                          'devicePublicKeyEd25519': 'ED25519-CLIENT-${_deviceCtrl.text.trim()}',
                        },
                        includeAuth: false,
                      );
                      setDialogState(() {
                        pairingCodeResult =
                            res['pairingVerificationCode']?.toString() ?? 'ALREADY_ACTIVE';
                      });
                    } on MedCoreApiException catch (e) {
                      setDialogState(() => dialogErr = e.toString());
                    }
                  },
                  child: const Text('Request Pairing'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showProtectedTechnicianGateDialog() async {
    final secretCtrl = TextEditingController();
    final authorityTokenCtrl = TextEditingController();
    final challengeIdCtrl = TextEditingController();
    final timeResponseCtrl = TextEditingController();
    bool useRsaAuthorityToken = false;
    String? gateError;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Protected Technician / Service Mode Gate'),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Isolated Service Boundary: Ordinary hospital user credentials cannot unlock Technician Mode. Authenticate via installation technician secret or signed RSA-2048 MC_MAINT_V1 authority token.',
                        style: TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Use Signed RSA-2048 Authority Token (MC_MAINT_V1)'),
                        value: useRsaAuthorityToken,
                        onChanged: (v) => setDialogState(() => useRsaAuthorityToken = v),
                      ),
                      const SizedBox(height: 8),
                      if (!useRsaAuthorityToken)
                        TextField(
                          key: const Key('input_tech_secret'),
                          controller: secretCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Installation Technician Secret',
                            helperText:
                                'First install: check runtime/security/FIRST_RUN_COMMISSIONING_SECRET.txt or provision via bin/commission.dart',
                            helperMaxLines: 2,
                          ),
                        )
                      else ...[
                        OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              widget.controller.api.configureConnection(
                                baseUrl: _urlCtrl.text,
                                hospitalCode: _hospCtrl.text,
                                deviceId: _deviceCtrl.text,
                              );
                              final ch = await widget.controller.api.postJson(
                                '/api/v1/technician/time-challenge',
                                {'hospitalCode': _hospCtrl.text.trim()},
                                includeAuth: false,
                              );
                              setDialogState(() {
                                challengeIdCtrl.text = ch['challengeId']?.toString() ?? '';
                              });
                            } on MedCoreApiException catch (e) {
                              setDialogState(() => gateError = e.toString());
                            }
                          },
                          icon: const Icon(Icons.schedule),
                          label: const Text('1. Issue Trusted-Time Challenge'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: challengeIdCtrl,
                          decoration: const InputDecoration(labelText: 'Challenge ID'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: timeResponseCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Signed Trusted-Time Response (MC_TIME_V1...)',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: authorityTokenCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Signed Technician Token (MC_MAINT_V1...)',
                          ),
                        ),
                      ],
                      if (gateError != null) ...[
                        const SizedBox(height: 12),
                        Text(gateError!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  key: const Key('btn_open_tech_session'),
                  onPressed: () async {
                    setDialogState(() => gateError = null);
                    try {
                      widget.controller.api.configureConnection(
                        baseUrl: _urlCtrl.text,
                        hospitalCode: _hospCtrl.text,
                        deviceId: _deviceCtrl.text,
                      );
                      await widget.controller.openTechnicianSession(
                        technicianSecret: useRsaAuthorityToken ? null : secretCtrl.text,
                        authorityToken: useRsaAuthorityToken ? authorityTokenCtrl.text : null,
                        challengeId: useRsaAuthorityToken ? challengeIdCtrl.text : null,
                        trustedTimeResponse:
                            useRsaAuthorityToken ? timeResponseCtrl.text : null,
                      );
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    } on MedCoreApiException catch (e) {
                      setDialogState(() => gateError = e.toString());
                    }
                  },
                  icon: const Icon(Icons.engineering),
                  label: const Text('Enter Technician Mode'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final branding = widget.controller.branding;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Column: Facility Branding & Local Service Connection
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Image.asset(
                            'assets/branding/medcore_platinum_logo.png',
                            height: 52,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                        Row(
                          children: [
                            Icon(Icons.local_hospital, color: cs.primary, size: 32),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                branding.appDisplayName,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${branding.facilityDisplayName} • ${branding.editionLabel}',
                          style: theme.textTheme.bodyMedium?.copyWith(color: cs.primary),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Local MedCore Service Connection (HTTP Only — No Direct DB)',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          key: const Key('input_service_url'),
                          controller: _urlCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Local Service Base URL',
                            prefixIcon: Icon(Icons.dns_outlined),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                key: const Key('input_hospital_code'),
                                controller: _hospCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Hospital / Tenant Code',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                key: const Key('input_device_id'),
                                controller: _deviceCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Enrolled Device ID',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              key: const Key('btn_probe_service'),
                              onPressed: widget.controller.isBusy ? null : _probeConnection,
                              icon: const Icon(Icons.sync, size: 18),
                              label: const Text('Verify Service & Load Branding'),
                            ),
                            OutlinedButton.icon(
                              key: const Key('btn_lan_wifi_pair'),
                              onPressed: _showLanWifiPairingDialog,
                              icon: const Icon(Icons.wifi_tethering, size: 18),
                              label: const Text('Connect via LAN / Wi-Fi'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const Divider(),
                        TextButton.icon(
                          key: const Key('btn_tech_gate'),
                          onPressed: _showProtectedTechnicianGateDialog,
                          icon: const Icon(Icons.engineering_outlined, size: 18),
                          label: const Text('Technician / Service Installation Gate'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 28),
                  // Right Column: Hospital Employee Sign-In
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Hospital Staff Sign-In',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Device-bound offline session authenticated by Local MedCore Service.',
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          key: const Key('input_staff_identifier'),
                          controller: _identifierCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Employee Email or Staff Code',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          key: const Key('input_staff_password'),
                          controller: _passwordCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          onSubmitted: (_) => _handleStaffLogin(),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          key: const Key('btn_staff_login'),
                          onPressed: widget.controller.isBusy ? null : _handleStaffLogin,
                          icon: const Icon(Icons.login),
                          label: Text(widget.controller.isBusy ? 'Authenticating...' : 'Sign In'),
                        ),
                        if (_statusMsg != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _isError ? cs.errorContainer : cs.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: SelectableText(
                              _statusMsg!,
                              style: TextStyle(
                                fontSize: 12,
                                color: _isError ? cs.onErrorContainer : cs.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
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
