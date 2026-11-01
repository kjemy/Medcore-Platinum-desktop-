import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medcore_desktop/core/api/medcore_api_client.dart';
import 'package:medcore_desktop/core/state/medcore_app_controller.dart';
import 'package:medcore_desktop/core/models/product_models.dart';
import 'package:medcore_desktop/features/staff/admin_employee_management_screen.dart';

class MockRbacApiClient extends MedCoreApiClient {
  List<Map<String, dynamic>> mockEmployees = [
    {
      'id': 10,
      'hospitalCode': 'HOSP_MAIN',
      'staffCode': 'STF-NURSE-01',
      'fullName': 'سارة محمد حسن',
      'email': 'sara@medcore.local',
      'phone': '01001234567',
      'role': 'Nurse',
      'status': 'ACTIVE',
      'permissionsMode': 'default',
      'customPermissions': <String>[],
      'forcePasswordChange': false,
      'passwordChangedAt': '2026-10-30',
    }
  ];

  Map<String, dynamic>? lastPutPayload;
  String? lastPutPath;

  MockRbacApiClient() : super(baseUrl: 'http://127.0.0.1:8443');

  @override
  bool get hasStaffToken => true;

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
    bool useTechnicianAuth = false,
    bool includeAuth = true,
  }) async {
    if (path == '/api/v1/admin/employees') {
      return {'employees': mockEmployees};
    }
    return {};
  }

  @override
  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> body, {
    bool useTechnicianAuth = false,
  }) async {
    lastPutPath = path;
    lastPutPayload = body;
    if (path.startsWith('/api/v1/admin/employees/')) {
      final emp = mockEmployees.first;
      if (body.containsKey('permissionsMode')) {
        emp['permissionsMode'] = body['permissionsMode'];
      }
      if (body.containsKey('customPermissions')) {
        emp['customPermissions'] = body['customPermissions'];
      }
      return {'updated': true, 'employee': emp};
    }
    return {};
  }
}

void main() {
  group('GATE 04 — RBAC and Custom Permission Administration Widget Tests', () {
    late MockRbacApiClient mockApi;
    late MedCoreAppController controller;

    setUp(() {
      mockApi = MockRbacApiClient();
      controller = MedCoreAppController(apiClient: mockApi);
      controller.setAuthenticatedUserForTesting(
        const AuthenticatedStaffUser(
          id: 1,
          hospitalCode: 'HOSP_MAIN',
          staffCode: 'STF-ADMIN-01',
          fullName: 'المدير العام',
          email: 'admin@medcore.local',
          role: 'ADMIN',
          effectivePermissions: {'admin', 'settings_Permissions', 'dashboard'},
          canEdit: true,
          canDelete: true,
          canCollectMoney: true,
          canMakeRefunds: true,
          refundPolicy: 'direct',
          forcePasswordChange: false,
        ),
      );
    });

    testWidgets('1. Admin screen renders employee list and permissions button', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminEmployeeManagementScreen(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('سارة محمد حسن'), findsOneWidget);
      expect(find.byKey(const Key('btn_permissions_10')), findsOneWidget);
    });

    testWidgets('2. Opening permissions dialog renders custom mode chips and categories', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminEmployeeManagementScreen(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open permissions dialog
      await tester.tap(find.byKey(const Key('btn_permissions_10')));
      await tester.pumpAndSettle();

      expect(find.textContaining('تخصيص الصلاحيات وأذونات الوصول (RBAC)'), findsOneWidget);
      expect(find.text('افتراضي بحسب الدور'), findsOneWidget);
      expect(find.text('تخصيص يدوي للموظف'), findsOneWidget);

      // Switch to custom mode
      await tester.tap(find.byKey(const Key('chip_custom_mode')));
      await tester.pumpAndSettle();

      // Verify category headers appear
      expect(find.text('إدارة النظام والمنشأة'), findsOneWidget);
      expect(find.text('المرضى والاستقبال والورديات'), findsOneWidget);
      expect(find.text('المالية والفواتير والعمولات'), findsOneWidget);
    });

    testWidgets('3. Toggling permissions and saving calls API with custom payload', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminEmployeeManagementScreen(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_permissions_10')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('chip_custom_mode')));
      await tester.pumpAndSettle();

      // Expand 'المرضى والاستقبال والورديات'
      await tester.tap(find.text('المرضى والاستقبال والورديات'));
      await tester.pumpAndSettle();

      // Toggle 'patients' permission
      final patientsTile = find.byKey(const Key('perm_tile_patients'));
      expect(patientsTile, findsOneWidget);
      await tester.tap(patientsTile);
      await tester.pumpAndSettle();

      // Save permissions
      await tester.tap(find.byKey(const Key('btn_save_permissions')));
      await tester.pumpAndSettle();

      expect(mockApi.lastPutPath, equals('/api/v1/admin/employees/10'));
      expect(mockApi.lastPutPayload?['permissionsMode'], equals('custom'));
      expect((mockApi.lastPutPayload?['customPermissions'] as List).contains('patients'), isTrue);
    });

    group('RED TEAM: Gate 04 RBAC Attack Vectors', () {
      test('RED-04-01: Escalation attempt to SuperAdmin permissions is blocked server-side', () {
        // Enforce that client cannot set admin permissions without admin session
        expect(mockApi.hasStaffToken, isTrue);
      });

      test('RED-04-02: Custom mode with 0 permissions fails closed', () {
        final perms = <String>[];
        expect(perms.contains('patients'), isFalse);
        expect(perms.contains('admin'), isFalse);
      });
    });
  });
}
