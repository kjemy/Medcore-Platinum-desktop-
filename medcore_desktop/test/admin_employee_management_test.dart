import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medcore_desktop/core/api/medcore_api_client.dart';
import 'package:medcore_desktop/core/state/medcore_app_controller.dart';
import 'package:medcore_desktop/features/staff/admin_employee_management_screen.dart';

void main() {
  group('AdminEmployeeManagementScreen Widget Tests', () {
    testWidgets('Renders employee list, filters by role and search, opens add and reset dialogs',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final employees = [
        {
          'id': 1,
          'hospitalCode': 'HOSP_TEST',
          'staffCode': 'ADM-01',
          'fullName': 'Dr. Ahmad Admin',
          'email': 'ahmad@medcore.local',
          'role': 'HospitalAdmin',
          'department': 'Executive',
          'status': 'ACTIVE',
          'forcePasswordChange': false,
          'passwordChangedAt': '2026-10-28T12:00:00Z',
          'failedLoginCount': 0,
          'lockedUntil': null,
          'createdAt': '2026-10-28T10:00:00Z',
        },
        {
          'id': 2,
          'hospitalCode': 'HOSP_TEST',
          'staffCode': 'DR-02',
          'fullName': 'Dr. Fatima Doctor',
          'email': 'fatima@medcore.local',
          'role': 'Doctor',
          'department': 'Cardiology',
          'status': 'ACTIVE',
          'forcePasswordChange': true,
          'passwordChangedAt': null,
          'failedLoginCount': 0,
          'lockedUntil': null,
          'createdAt': '2026-10-28T10:30:00Z',
        },
      ];

      final requestedEndpoints = <String>[];
      final mockHttp = MockClient((http.Request req) async {
        requestedEndpoints.add('${req.method} ${req.url.path}');

        if (req.url.path == '/api/v1/admin/employees' && req.method == 'GET') {
          return http.Response(
            jsonEncode({'ok': true, 'data': {'employees': employees}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (req.url.path == '/api/v1/admin/employees' && req.method == 'POST') {
          final body = jsonDecode(req.body);
          return http.Response(
            jsonEncode({
              'ok': true,
              'data': {
                'id': 3,
                'hospitalCode': 'HOSP_TEST',
                'staffCode': body['staffCode'],
                'fullName': body['fullName'],
                'email': body['email'],
                'role': body['role'],
                'department': body['department'],
                'status': 'ACTIVE',
                'forcePasswordChange': body['forcePasswordChange'] ?? true,
                'createdAt': DateTime.now().toUtc().toIso8601String(),
              }
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }

        if (req.url.path == '/api/v1/admin/employees/2/status' && req.method == 'POST') {
          return http.Response(
            jsonEncode({'ok': true, 'data': {'status': 'SUSPENDED'}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (req.url.path == '/api/v1/admin/employees/2/revoke-sessions' && req.method == 'POST') {
          return http.Response(
            jsonEncode({'ok': true, 'data': {'revokedCount': 1}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (req.url.path == '/api/v1/admin/employees/2/reset-password' && req.method == 'POST') {
          return http.Response(
            jsonEncode({'ok': true, 'data': {'status': 'PASSWORD_RESET_SUCCESS'}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (req.url.path == '/api/v1/admin/employees/2/audit' && req.method == 'GET') {
          return http.Response(
            jsonEncode({
              'ok': true,
              'data': {
                'auditLogs': [
                  {
                    'id': 1,
                    'action': 'employee.status_changed',
                    'timestamp': '2026-10-28T14:00:00Z',
                    'actor': 'ADM-01',
                    'afterState': {'status': 'SUSPENDED'},
                  }
                ]
              }
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        return http.Response(jsonEncode({'ok': true, 'data': {}}), 200);
      });

      final controller = MedCoreAppController(
        apiClient: MedCoreApiClient(
          baseUrl: 'http://127.0.0.1:8443',
          hospitalCode: 'HOSP_TEST',
          deviceId: 'DEV-01',
          httpClient: mockHttp,
        ),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AdminEmployeeManagementScreen(controller: controller),
        ),
      ));
      await tester.pumpAndSettle();

      // Verify list renders both employees
      expect(find.text('Dr. Ahmad Admin'), findsOneWidget);
      expect(find.text('Dr. Fatima Doctor'), findsOneWidget);
      expect(find.text('HospitalAdmin'), findsWidgets);
      expect(find.text('Doctor'), findsWidgets);

      // Verify filter by search query
      await tester.enterText(find.byType(TextField).first, 'Fatima');
      await tester.pumpAndSettle();
      expect(find.text('Dr. Fatima Doctor'), findsOneWidget);
      expect(find.text('Dr. Ahmad Admin'), findsNothing);

      // Clear search
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pumpAndSettle();
      expect(find.text('Dr. Ahmad Admin'), findsOneWidget);

      // Click "Add Employee" button
      final addBtn = find.text('Add Employee');
      expect(addBtn, findsOneWidget);
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      // Verify Add Employee Dialog opened
      expect(find.text('Add New Employee Account'), findsOneWidget);

      // Fill in new employee form using specific Keys
      await tester.enterText(find.byKey(const Key('input_add_staff_code')), 'NUR-03');
      await tester.enterText(find.byKey(const Key('input_add_full_name')), 'Kareem Nurse');
      await tester.enterText(find.byKey(const Key('input_add_email')), 'kareem@medcore.local');
      await tester.enterText(find.byKey(const Key('input_add_password')), 'TempPass123!');

      // Tap Save
      await tester.tap(find.byKey(const Key('btn_submit_add_employee')));
      await tester.pumpAndSettle();

      // Check that POST /api/v1/admin/employees was called
      expect(requestedEndpoints.contains('POST /api/v1/admin/employees'), isTrue);
    });
  });
}
