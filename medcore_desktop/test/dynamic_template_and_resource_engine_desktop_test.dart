import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medcore_desktop/core/api/medcore_api_client.dart';
import 'package:medcore_desktop/core/navigation/desktop_navigation_catalog.dart';
import 'package:medcore_desktop/core/models/product_models.dart';
import 'package:medcore_desktop/core/state/medcore_app_controller.dart';
import 'package:medcore_desktop/features/templates/clinical_template_editor_screen.dart';
import 'package:medcore_desktop/features/scheduling/resource_scheduling_management_screen.dart';

void main() {
  group('Dynamic Clinical Template & Resource Engine Desktop Tests', () {
    testWidgets('1. ClinicalTemplateEditorScreen: Catalog, Builder, Preview & Validation',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final templates = [
        {
          'id': 101,
          'hospitalCode': 'HOSP_TEST',
          'templateNumber': 'TMPL-CARDIO-V1',
          'title': 'Cardiology Examination',
          'specialty': 'CARDIOLOGY',
          'category': 'CONSULTATION',
          'status': 'ACTIVE',
          'version': 1,
          'content': {
            'sections': [
              {
                'key': 'vitals',
                'title': 'Vitals & Biometrics',
                'fields': [
                  {
                    'key': 'systolicBp',
                    'label': 'Systolic Blood Pressure',
                    'type': 'integer',
                    'unit': 'mmHg',
                    'required': true,
                    'min': 60,
                    'max': 250,
                  },
                  {
                    'key': 'murmurPresent',
                    'label': 'Murmur Present',
                    'type': 'boolean',
                    'required': true,
                  },
                ],
              },
            ],
          },
        },
      ];

      final mockHttp = MockClient((http.Request req) async {
        if (req.url.path == '/api/v1/clinical/templates' && req.method == 'GET') {
          return http.Response(
            jsonEncode({'ok': true, 'data': {'count': templates.length, 'items': templates}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(jsonEncode({'ok': true, 'data': {}}), 200,
            headers: {'content-type': 'application/json'});
      });

      final api = MedCoreApiClient(
        baseUrl: 'http://127.0.0.1:8080',
        hospitalCode: 'HOSP_TEST',
        deviceId: 'DEV-DESKTOP-TEST',
        httpClient: mockHttp,
      );

      final controller = MedCoreAppController(apiClient: api);
      controller.setAuthenticatedUserForTesting(
        const AuthenticatedStaffUser(
          id: 1,
          hospitalCode: 'HOSP_TEST',
          staffCode: 'DR-01',
          fullName: 'Dr. Gregory House',
          email: 'house@medcore.local',
          role: 'Doctor',
          effectivePermissions: {'doctor', 'doctor_ClinicalWorkspace'},
          canEdit: true,
          canDelete: true,
          canCollectMoney: false,
          canMakeRefunds: false,
          refundPolicy: 'NONE',
          forcePasswordChange: false,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(useMaterial3: true),
          home: ClinicalTemplateEditorScreen(controller: controller),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Template catalog item rendered
      expect(find.text('Dynamic Clinical Template Engine'), findsOneWidget);
      expect(find.text('Cardiology Examination'), findsWidgets);
      expect(find.text('TMPL-CARDIO-V1 • v1 • CARDIOLOGY'), findsOneWidget);

      // Verify sections and fields in Visual Builder
      expect(find.text('Vitals & Biometrics'), findsWidgets);
      expect(find.text('Systolic Blood Pressure'), findsWidgets);
      expect(find.text('Murmur Present'), findsWidgets);

      // Switch to Doctor Form Preview
      final previewTab = find.text('Doctor Form Preview');
      expect(previewTab, findsOneWidget);
      await tester.tap(previewTab);
      await tester.pumpAndSettle();

      // Verify Preview runtime UI
      expect(find.text('Interactive Doctor Preview: This runtime renders actual dynamic forms from the JSON schema definition.\nFill in clinical values and test client-side clinical constraint validation.'), findsOneWidget);
      expect(find.text('Test Clinical Capture'), findsOneWidget);

      // Tap Test Clinical Capture without filling required fields
      await tester.tap(find.text('Test Clinical Capture'));
      await tester.pumpAndSettle();

      // Verify error message for required fields
      expect(find.text('Systolic Blood Pressure is required'), findsOneWidget);
    });

    testWidgets('2. ResourceSchedulingManagementScreen: Resources, Rules, and Conflict Check',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final resources = [
        {
          'id': 1,
          'resourceCode': 'DOC-CARDIO-01',
          'name': 'Dr. Gregory House',
          'resourceType': 'DOCTOR',
          'departmentId': 'Cardiology',
          'isActive': true,
        },
        {
          'id': 2,
          'resourceCode': 'ROOM-301',
          'name': 'Examination Room 301',
          'resourceType': 'ROOM',
          'departmentId': 'Cardiology',
          'isActive': true,
        },
      ];

      final rules = [
        {
          'id': 1,
          'ruleCode': 'RULE-ECHO',
          'name': 'Echocardiogram Exam',
          'appointmentType': 'ECHOCARDIOGRAM',
          'primaryResourceType': 'DOCTOR',
          'requiredCoResourceTypes': ['ROOM'],
          'defaultDurationMinutes': 45,
          'bufferBeforeMinutes': 10,
          'bufferAfterMinutes': 15,
          'isActive': true,
        },
      ];

      final mockHttp = MockClient((http.Request req) async {
        if (req.url.path == '/api/v1/scheduling/resources') {
          return http.Response(
            jsonEncode({'ok': true, 'data': {'items': resources}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.url.path == '/api/v1/scheduling/rules') {
          return http.Response(
            jsonEncode({'ok': true, 'data': {'items': rules}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.url.path == '/api/v1/scheduling/conflicts/check') {
          return http.Response(
            jsonEncode({
              'ok': true,
              'data': {
                'hasConflict': true,
                'conflicts': [
                  {
                    'resource_code': 'ROOM-301',
                    'resource_name': 'Examination Room 301',
                    'allocated_start': '2026-11-10 10:00:00',
                    'allocated_end': '2026-11-10 11:00:00',
                  }
                ],
              }
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(jsonEncode({'ok': true, 'data': {}}), 200,
            headers: {'content-type': 'application/json'});
      });

      final api = MedCoreApiClient(
        baseUrl: 'http://127.0.0.1:8080',
        hospitalCode: 'HOSP_TEST',
        deviceId: 'DEV-DESKTOP-TEST',
        httpClient: mockHttp,
      );

      final controller = MedCoreAppController(apiClient: api);
      controller.setAuthenticatedUserForTesting(
        const AuthenticatedStaffUser(
          id: 1,
          hospitalCode: 'HOSP_TEST',
          staffCode: 'ADM-01',
          fullName: 'Admin User',
          email: 'admin@medcore.local',
          role: 'HospitalAdmin',
          effectivePermissions: {'appointments', 'admin'},
          canEdit: true,
          canDelete: true,
          canCollectMoney: false,
          canMakeRefunds: false,
          refundPolicy: 'NONE',
          forcePasswordChange: false,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(useMaterial3: true),
          home: ResourceSchedulingManagementScreen(controller: controller),
        ),
      );

      await tester.pumpAndSettle();

      // Verify resources tab
      expect(find.text('Multi-Resource Slot Rule Engine'), findsOneWidget);
      expect(find.text('Dr. Gregory House'), findsOneWidget);
      expect(find.text('Examination Room 301'), findsOneWidget);

      // Switch to Rules & Buffer Windows tab
      final rulesTab = find.text('Rules & Buffer Windows (1)');
      expect(rulesTab, findsOneWidget);
      await tester.tap(rulesTab);
      await tester.pumpAndSettle();

      expect(find.text('Echocardiogram Exam'), findsOneWidget);
      expect(find.text('Duration: 45 min'), findsOneWidget);
      expect(find.text('Prep Buffer (Before): 10 min'), findsOneWidget);
      expect(find.text('Clean Buffer (After): 15 min'), findsOneWidget);

      // Switch to Live Conflict Verification Console
      final consoleTab = find.text('Live Conflict Verification Console');
      expect(consoleTab, findsOneWidget);
      await tester.tap(consoleTab);
      await tester.pumpAndSettle();

      expect(find.text('Multi-Resource Slot Booking Parameters'), findsOneWidget);
      expect(find.text('Examination Room 301 (ROOM)'), findsOneWidget);

      // Select Examination Room 301 filter chip
      await tester.tap(find.text('Examination Room 301 (ROOM)'));
      await tester.pumpAndSettle();

      // Tap Check Resource Conflicts
      await tester.tap(find.text('Check Resource Conflicts'));
      await tester.pumpAndSettle();

      // Verify conflict banner rendered
      expect(find.text('RESOURCE CONFLICT DETECTED (1)'), findsOneWidget);
      expect(find.text('• Examination Room 301 (ROOM-301) is already allocated from 2026-11-10 10:00:00 to 2026-11-10 11:00:00'), findsOneWidget);
    });

    test('3. DesktopNavigationCatalog includes dynamic templates and resource scheduling routes', () {
      final templateEntry = DesktopNavigationCatalog.findById('clinical_templates');
      expect(templateEntry, isNotNull);
      expect(templateEntry!.label, equals('Clinical Templates'));
      expect(templateEntry.requiredModule, equals('Doctors'));

      final schedulingEntry = DesktopNavigationCatalog.findById('resource_scheduling');
      expect(schedulingEntry, isNotNull);
      expect(schedulingEntry!.label, equals('Resource Scheduling'));
      expect(schedulingEntry.requiredModule, equals('Appointments'));
    });
  });
}
