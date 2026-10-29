import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medcore_desktop/core/api/medcore_api_client.dart';
import 'package:medcore_desktop/core/models/product_models.dart';
import 'package:medcore_desktop/core/shell/medcore_desktop_shell.dart';
import 'package:medcore_desktop/core/state/medcore_app_controller.dart';
import 'package:medcore_desktop/features/technician/technician_console_screen.dart';

void main() {
  group('MedCore Platinum Desktop — Initial Administrator Provisioning & Handover Tests', () {
    testWidgets('1. TechnicianConsoleScreen renders Tab 8 and provisions initial Hospital Administrator',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      bool provisionCalled = false;
      bool statusQueried = false;

      final mockHttp = MockClient((http.Request req) async {
        final path = req.url.path;

        if (path == '/api/v1/technician/session/open') {
          return http.Response(
            jsonEncode({
              'ok': true,
              'data': {
                'technicianToken': 'test-tech-token',
                'session': {
                  'sessionUuid': 'SES-TECH-001',
                  'hospitalCode': 'HOSP_TEST',
                  'authMethod': 'INSTALLATION_SECRET',
                  'deviceId': 'DEV-MAIN-HOST',
                  'expiresAt': '2026-10-29T12:00:00Z',
                },
              },
            }),
            201,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }

        if (path == '/api/v1/technician/config') {
          return http.Response(
            jsonEncode({
              'ok': true,
              'data': {
                'technicianSession': {
                  'sessionUuid': 'SES-TECH-001',
                  'hospitalCode': 'HOSP_TEST',
                  'authMethod': 'INSTALLATION_SECRET',
                  'deviceId': 'DEV-MAIN-HOST',
                  'expiresAt': '2026-10-29T12:00:00Z',
                },
                'configuration': {
                  'hospitalCode': 'HOSP_TEST',
                  'facilityName': 'Test General Hospital',
                  'facilityType': 'GENERAL_HOSPITAL',
                  'branchCode': 'MAIN',
                  'edition': 'PLATINUM',
                  'installationIdentity': 'INST-001',
                  'enabledModules': {'patients': true},
                  'patientFields': {},
                  'branding': {
                    'appDisplayName': 'MedCore Platinum Desktop',
                    'facilityDisplayName': 'Test General Hospital',
                    'editionLabel': 'MedCore PLATINUM',
                  },
                },
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }

        if (path == '/api/v1/technician/initial-admin/status') {
          statusQueried = true;
          return http.Response(
            jsonEncode({
              'ok': true,
              'data': {
                'hospitalCode': 'HOSP_TEST',
                'hasAdmin': false,
                'totalStaffCount': 0,
                'administrators': [],
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }

        if (path == '/api/v1/technician/initial-admin') {
          provisionCalled = true;
          expect(req.headers['x-medcore-tech-token'], equals('test-tech-token'));
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['staffCode'], equals('ADM-001'));
          expect(body['fullName'], equals('Hospital Director'));
          expect(body['email'], equals('admin@hospital.org'));

          return http.Response(
            jsonEncode({
              'ok': true,
              'data': {
                'status': 'SUCCESS',
                'message': 'Initial Hospital Administrator provisioned successfully.',
                'admin': {
                  'id': 1,
                  'hospitalCode': 'HOSP_TEST',
                  'staffCode': 'ADM-001',
                  'fullName': 'Hospital Director',
                  'email': 'admin@hospital.org',
                  'role': 'HospitalAdmin',
                  'effectivePermissions': ['admin_access', 'all_modules'],
                  'operationalFlags': {'canEdit': true, 'canDelete': true, 'canCollectMoney': true, 'canMakeRefunds': true, 'refundPolicy': 'full'},
                  'isActive': true,
                  'forcePasswordChange': true,
                },
                'handoverTemporaryPassword': 'MedCore-TempPass12345!',
                'forcePasswordChange': true,
                'facilityCode': 'HOSP_TEST',
                'provisionedAt': '2026-10-29T08:00:00Z',
                'technicianSessionUuid': 'SES-TECH-001',
              },
            }),
            201,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }

        return http.Response('{"error": "not found"}', 404);
      });

      final apiClient = MedCoreApiClient(httpClient: mockHttp);
      apiClient.setTechnicianToken('test-tech-token');

      final controller = MedCoreAppController(apiClient: apiClient);
      await controller.openTechnicianSession(technicianSecret: 'tech-secret');

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
            body: TechnicianConsoleScreen(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Tab 8 exists and navigate to it
      final tab8Finder = find.text('8. Initial Administrator Handover');
      expect(tab8Finder, findsOneWidget);
      await tester.ensureVisible(tab8Finder);
      await tester.pumpAndSettle();
      await tester.tap(tab8Finder);
      await tester.pumpAndSettle();

      expect(statusQueried, isTrue);
      expect(find.textContaining('Awaiting Initial Hospital Administrator Provisioning'), findsOneWidget);

      // Verify input fields
      expect(find.byKey(const Key('field_initial_admin_staff_code')), findsOneWidget);
      expect(find.byKey(const Key('field_initial_admin_full_name')), findsOneWidget);
      expect(find.byKey(const Key('field_initial_admin_email')), findsOneWidget);

      // Click "Generate Strong Password"
      final genBtn = find.byKey(const Key('btn_generate_admin_pwd'));
      expect(genBtn, findsOneWidget);
      await tester.tap(genBtn);
      await tester.pumpAndSettle();

      // Submit Provisioning
      final provisionBtn = find.byKey(const Key('btn_provision_initial_admin'));
      expect(provisionBtn, findsOneWidget);
      await tester.tap(provisionBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(provisionCalled, isTrue);

      // Drag to reveal Handover Slip Card
      await tester.drag(find.byType(ListView).last, const Offset(0, -600));
      await tester.pumpAndSettle();

      // Verify Handover Slip Card rendered
      expect(find.byKey(const Key('card_handover_slip')), findsOneWidget);
      expect(find.text('OFFICIAL SECURE COMMISSIONING HANDOVER SLIP'), findsOneWidget);
      expect(find.text('MedCore-TempPass12345!'), findsOneWidget);
      expect(find.textContaining('FORCE_PASSWORD_CHANGE = TRUE'), findsOneWidget);
      expect(find.byKey(const Key('btn_copy_handover_slip')), findsOneWidget);
    });

    testWidgets('2. MedCoreDesktopShell blocks user with forcePasswordChange and updates password',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      bool passwordChanged = false;

      final mockHttp = MockClient((http.Request req) async {
        final path = req.url.path;

        if (path == '/api/v1/auth/change-password') {
          passwordChanged = true;
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['oldPassword'], equals('MedCore-TempPass12345!'));
          expect(body['newPassword'], equals('NewPermanentSecurePassword#2026'));

          return http.Response(
            jsonEncode({
              'ok': true,
              'data': {
                'status': 'PASSWORD_CHANGED_SUCCESS',
                'staffId': 1,
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }

        if (path == '/api/v1/health') {
          return http.Response(
            jsonEncode({
              'ok': true,
              'data': {
                'status': 'HEALTHY',
                'database': '11.4.4-MariaDB',
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }

        if (path == '/api/v1/shifts/current') {
          return http.Response(
            jsonEncode({
              'ok': true,
              'data': {
                'openShift': null,
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }

        return http.Response('{"error": "not found"}', 404);
      });

      final apiClient = MedCoreApiClient(httpClient: mockHttp);
      apiClient.setStaffBearerToken('staff-test-token');

      final controller = MedCoreAppController(apiClient: apiClient);

      // Seed an authenticated staff user with forcePasswordChange = true
      final initialUser = AuthenticatedStaffUser.fromJson({
        'id': 1,
        'hospitalCode': 'HOSP_TEST',
        'staffCode': 'ADM-001',
        'fullName': 'Dr. Sarah Connor',
        'email': 'director@hospital.org',
        'role': 'HospitalAdmin',
        'effectivePermissions': ['admin_access', 'all_modules'],
        'operationalFlags': {'canEdit': true, 'canDelete': true, 'canCollectMoney': true, 'canMakeRefunds': true, 'refundPolicy': 'full'},
        'isActive': true,
        'forcePasswordChange': true,
      });

      // Set user into controller
      controller.setAuthenticatedUserForTesting(initialUser);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => MedCoreDesktopShell(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify the forced password change screen is blocking normal content
      expect(find.byKey(const Key('card_force_password_change')), findsOneWidget);
      expect(find.text('First Login — Set New Password'), findsOneWidget);
      expect(find.text('Password change required'), findsOneWidget);

      // Fill in passwords
      await tester.enterText(find.byKey(const Key('field_force_pwd_old')), 'MedCore-TempPass12345!');
      await tester.enterText(find.byKey(const Key('field_force_pwd_new')), 'NewPermanentSecurePassword#2026');
      await tester.enterText(find.byKey(const Key('field_force_pwd_confirm')), 'NewPermanentSecurePassword#2026');
      await tester.pumpAndSettle();

      // Submit password change
      await tester.tap(find.byKey(const Key('btn_force_pwd_submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(passwordChanged, isTrue);
      // Once changed, forcePasswordChange is cleared and executive dashboard is visible
      expect(find.byKey(const Key('card_force_password_change')), findsNothing);
      expect(controller.currentUser?.forcePasswordChange, isFalse);
    });
  });
}
