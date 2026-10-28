import 'package:flutter/material.dart';
import 'core/shell/medcore_desktop_shell.dart';
import 'core/state/medcore_app_controller.dart';
import 'features/auth/connection_and_login_screen.dart';
import 'features/technician/technician_console_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MedCorePlatinumDesktopApp());
}

/// Root MedCore Platinum Flutter Desktop Application.
/// Architectural Invariants:
/// 1. Connects strictly over HTTP JSON to `LocalMedCoreServer` (zero direct MariaDB access).
/// 2. Centralized branding, theme mode, color seed, visual density, and font scaling
///    flow from one single source (`MedCoreAppController.branding`).
/// 3. Protected Technician / Service Mode (`TechnicianConsoleScreen`) is strictly
///    isolated from ordinary hospital staff sessions (`MedCoreDesktopShell`).
class MedCorePlatinumDesktopApp extends StatefulWidget {
  final MedCoreAppController? controller;

  const MedCorePlatinumDesktopApp({
    super.key,
    this.controller,
  });

  @override
  State<MedCorePlatinumDesktopApp> createState() => _MedCorePlatinumDesktopAppState();
}

class _MedCorePlatinumDesktopAppState extends State<MedCorePlatinumDesktopApp> {
  late final MedCoreAppController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
      _ownsController = false;
    } else {
      _controller = MedCoreAppController();
      _ownsController = true;
    }
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final branding = _controller.branding;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: branding.appDisplayName,
          theme: _controller.buildTheme(Brightness.light),
          darkTheme: _controller.buildTheme(Brightness.dark),
          themeMode: branding.flutterThemeMode,
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(
                textScaler: TextScaler.linear(branding.fontScale),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: _resolveAuthoritativeBoundaryScreen(),
        );
      },
    );
  }

  Widget _resolveAuthoritativeBoundaryScreen() {
    if (_controller.isTechnicianModeActive) {
      return TechnicianConsoleScreen(controller: _controller);
    }
    if (_controller.isStaffAuthenticated) {
      return MedCoreDesktopShell(controller: _controller);
    }
    return ConnectionAndLoginScreen(controller: _controller);
  }
}
