import 'package:flutter/material.dart';
import '../api/medcore_api_client.dart';
import '../models/product_models.dart';
import '../navigation/desktop_navigation_catalog.dart';

/// Single Centralized Product State, Branding/Theme Source, Staff Session & Isolated Technician Session.
/// Rule: Theme values and module entitlements come strictly from this centralized configuration source.
class MedCoreAppController extends ChangeNotifier {
  final MedCoreApiClient api;

  FacilityConfigModel _facilityConfig = const FacilityConfigModel(
    hospitalCode: 'HOSP_MAIN',
    facilityName: 'MedCore Local Installation',
  );
  AuthenticatedStaffUser? _currentUser;
  TechnicianSessionInfo? _technicianSession;
  Map<String, dynamic>? _lastHealthSnapshot;

  String _activeRouteId = 'dashboard';
  int? _focusedPatientIdForLedger;
  bool _isBusy = false;
  String? _globalErrorBanner;

  MedCoreAppController({MedCoreApiClient? apiClient})
      : api = apiClient ?? MedCoreApiClient();

  FacilityConfigModel get facilityConfig => _facilityConfig;
  BrandingConfig get branding => _facilityConfig.branding;
  AuthenticatedStaffUser? get currentUser => _currentUser;
  TechnicianSessionInfo? get technicianSession => _technicianSession;
  Map<String, dynamic>? get lastHealthSnapshot => _lastHealthSnapshot;

  bool get isStaffAuthenticated => _currentUser != null && api.hasStaffToken;
  bool get isTechnicianModeActive => _technicianSession != null && api.hasTechnicianToken;
  bool get isServiceHealthy => _lastHealthSnapshot?['status'] == 'HEALTHY';

  String get activeRouteId => _activeRouteId;
  int? get focusedPatientIdForLedger => _focusedPatientIdForLedger;
  bool get isBusy => _isBusy;
  String? get globalErrorBanner => _globalErrorBanner;

  /// Centralized ThemeData generator (Light & Dark) driven 100% by `BrandingConfig`.
  ThemeData buildTheme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: branding.seedColor,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      visualDensity: branding.flutterVisualDensity,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardTheme(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  void clearError() {
    if (_globalErrorBanner != null) {
      _globalErrorBanner = null;
      notifyListeners();
    }
  }

  /// Probes Local MedCore Service health and loads public facility branding bootstrap.
  Future<void> connectAndLoadBootstrap({
    required String baseUrl,
    required String hospitalCode,
    required String deviceId,
  }) async {
    _setBusy(true);
    _globalErrorBanner = null;
    try {
      api.configureConnection(
        baseUrl: baseUrl,
        hospitalCode: hospitalCode,
        deviceId: deviceId,
      );
      _lastHealthSnapshot = await api.getJson('/api/v1/health', includeAuth: false);
      final bootstrap = await api.getJson(
        '/api/v1/product/bootstrap',
        query: {'hospitalCode': hospitalCode},
        includeAuth: false,
      );
      _facilityConfig = FacilityConfigModel.fromBootstrapJson(bootstrap);
      notifyListeners();
    } on MedCoreApiException catch (e) {
      _globalErrorBanner = e.toString();
      notifyListeners();
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  /// Authenticates an ordinary hospital employee (`/api/v1/auth/login`) and loads full facility config.
  Future<void> loginStaff({
    required String identifier,
    required String password,
  }) async {
    _setBusy(true);
    _globalErrorBanner = null;
    try {
      // Strictly ensure technician mode is not mixed with ordinary hospital staff login
      api.setTechnicianToken(null);
      _technicianSession = null;

      final loginData = await api.postJson(
        '/api/v1/auth/login',
        {
          'hospitalCode': api.hospitalCode,
          'identifier': identifier.trim(),
          'password': password,
          'deviceId': api.deviceId,
        },
        includeAuth: false,
      );

      api.setStaffBearerToken(loginData['token']?.toString());
      _currentUser = AuthenticatedStaffUser.fromJson(
        Map<String, dynamic>.from(loginData['user'] as Map),
      );

      await refreshFullFacilityConfig();
      _activeRouteId = 'dashboard';
      notifyListeners();
    } on MedCoreApiException catch (e) {
      _globalErrorBanner = e.toString();
      notifyListeners();
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> refreshFullFacilityConfig() async {
    if (isStaffAuthenticated) {
      final full = await api.getJson('/api/v1/product/config');
      _facilityConfig = FacilityConfigModel.fromFullJson(full);
      notifyListeners();
    } else if (isTechnicianModeActive) {
      final techResp = await api.getJson('/api/v1/technician/config', useTechnicianAuth: true);
      if (techResp['configuration'] is Map) {
        _facilityConfig = FacilityConfigModel.fromFullJson(
          Map<String, dynamic>.from(techResp['configuration'] as Map),
        );
        notifyListeners();
      }
    }
  }

  Future<void> logoutStaff() async {
    try {
      if (api.hasStaffToken) {
        await api.postJson('/api/v1/auth/logout', const <String, dynamic>{});
      }
    } catch (_) {}
    api.setStaffBearerToken(null);
    _currentUser = null;
    _activeRouteId = 'dashboard';
    _focusedPatientIdForLedger = null;
    notifyListeners();
  }

  /// Opens an isolated Protected Technician / Service Mode session (`/api/v1/technician/session/open`).
  Future<void> openTechnicianSession({
    String? technicianSecret,
    String? authorityToken,
    String? challengeId,
    String? trustedTimeResponse,
  }) async {
    _setBusy(true);
    _globalErrorBanner = null;
    try {
      // Strictly isolate Technician Mode from ordinary hospital staff sessions
      api.setStaffBearerToken(null);
      _currentUser = null;

      final res = await api.postJson(
        '/api/v1/technician/session/open',
        {
          'hospitalCode': api.hospitalCode,
          'deviceId': api.deviceId,
          if (technicianSecret != null && technicianSecret.isNotEmpty)
            'technicianSecret': technicianSecret,
          if (authorityToken != null && authorityToken.isNotEmpty)
            'authorityToken': authorityToken,
          if (challengeId != null && challengeId.isNotEmpty)
            'challengeId': challengeId,
          if (trustedTimeResponse != null && trustedTimeResponse.isNotEmpty)
            'trustedTimeResponse': trustedTimeResponse,
        },
        includeAuth: false,
      );

      api.setTechnicianToken(res['technicianToken']?.toString());
      _technicianSession = TechnicianSessionInfo.fromJson(
        Map<String, dynamic>.from(res['session'] as Map),
      );

      await refreshFullFacilityConfig();
      notifyListeners();
    } on MedCoreApiException catch (e) {
      _globalErrorBanner = e.toString();
      notifyListeners();
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> saveTechnicianConfiguration(Map<String, dynamic> payload) async {
    if (!isTechnicianModeActive) {
      throw const MedCoreApiException(
        statusCode: 403,
        code: 'TECHNICIAN_SESSION_REQUIRED',
        message: 'Technician session is required to modify installation configuration.',
      );
    }
    _setBusy(true);
    _globalErrorBanner = null;
    try {
      final updated = await api.putJson(
        '/api/v1/technician/config',
        payload,
        useTechnicianAuth: true,
      );
      _facilityConfig = FacilityConfigModel.fromFullJson(updated);
      notifyListeners();
    } on MedCoreApiException catch (e) {
      _globalErrorBanner = e.toString();
      notifyListeners();
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> exitTechnicianMode() async {
    try {
      if (api.hasTechnicianToken) {
        await api.postJson(
          '/api/v1/technician/session/close',
          const <String, dynamic>{},
          useTechnicianAuth: true,
        );
      }
    } catch (_) {}
    api.setTechnicianToken(null);
    _technicianSession = null;
    notifyListeners();
  }

  /// Checks whether an initial administrator has already been provisioned for the tenant.
  Future<Map<String, dynamic>> getInitialAdminStatus() async {
    if (!isTechnicianModeActive) {
      throw const MedCoreApiException(
        statusCode: 403,
        code: 'TECHNICIAN_SESSION_REQUIRED',
        message: 'Technician session is required to inspect initial administrator status.',
      );
    }
    return await api.getJson(
      '/api/v1/technician/initial-admin/status',
      useTechnicianAuth: true,
    );
  }

  /// Provisions the initial Hospital Administrator during certified technician commissioning.
  Future<Map<String, dynamic>> provisionInitialAdmin({
    required String staffCode,
    required String fullName,
    required String email,
    required String password,
    String? phone,
    String? nationalId,
  }) async {
    if (!isTechnicianModeActive) {
      throw const MedCoreApiException(
        statusCode: 403,
        code: 'TECHNICIAN_SESSION_REQUIRED',
        message: 'Technician session is required to provision the initial administrator.',
      );
    }
    _setBusy(true);
    _globalErrorBanner = null;
    try {
      final res = await api.postJson(
        '/api/v1/technician/initial-admin',
        {
          'staffCode': staffCode.trim(),
          'fullName': fullName.trim(),
          'email': email.trim(),
          'password': password,
          if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
          if (nationalId != null && nationalId.trim().isNotEmpty) 'nationalId': nationalId.trim(),
        },
        useTechnicianAuth: true,
      );
      return res;
    } on MedCoreApiException catch (e) {
      _globalErrorBanner = e.toString();
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  /// Changes the authenticated staff member's password and clears forcePasswordChange.
  Future<void> changeStaffPassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    _setBusy(true);
    _globalErrorBanner = null;
    try {
      await api.postJson(
        '/api/v1/auth/change-password',
        {
          'oldPassword': oldPassword,
          'newPassword': newPassword,
        },
      );
      if (_currentUser != null) {
        _currentUser = _currentUser!.copyWith(forcePasswordChange: false);
      }
      notifyListeners();
    } on MedCoreApiException catch (e) {
      _globalErrorBanner = e.toString();
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  void setAuthenticatedUserForTesting(AuthenticatedStaffUser? user) {
    _currentUser = user;
    notifyListeners();
  }

  List<DesktopRouteEntry> get visibleNavigationRoutes {
    final user = _currentUser;
    if (user == null) return const <DesktopRouteEntry>[];
    return DesktopNavigationCatalog.staffRoutes
        .where((r) => r.isVisibleTo(config: _facilityConfig, user: user))
        .toList();
  }

  bool canAccessRoute(String routeId) {
    final user = _currentUser;
    if (user == null) return false;
    final entry = DesktopNavigationCatalog.findById(routeId);
    if (entry == null) return false;
    return entry.isVisibleTo(config: _facilityConfig, user: user);
  }

  void selectRoute(String routeId, {int? focusPatientId}) {
    _activeRouteId = routeId;
    if (focusPatientId != null) {
      _focusedPatientIdForLedger = focusPatientId;
    }
    notifyListeners();
  }

  void openPatientFinancialLedger(int patientId) {
    _focusedPatientIdForLedger = patientId;
    _activeRouteId = 'finance_ledger';
    notifyListeners();
  }

  void _setBusy(bool value) {
    _isBusy = value;
    notifyListeners();
  }
}
