import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medcore_desktop/core/api/medcore_api_client.dart';
import 'package:medcore_desktop/core/models/product_models.dart';
import 'package:medcore_desktop/core/state/medcore_app_controller.dart';
import 'package:medcore_desktop/features/clinical/clinical_modules_hub_screen.dart';
import 'package:medcore_desktop/features/scheduling/resource_scheduling_management_screen.dart';

void main() {
  group('GATES 16–20 — Clinical & Operational Parity Screens Tests (GAP-016 to GAP-020)', () {
    testWidgets('1. GAP-016: Weekly Clinic Shift Schedules visual calendar and shift addition',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final mockHttp = MockClient((http.Request req) async {
        if (req.url.path == '/api/v1/scheduling/resources') {
          return http.Response(
            jsonEncode({'ok': true, 'data': {'count': 1, 'items': [{'id': 1, 'resourceCode': 'DOC-01', 'name': 'Dr. Khaled', 'resourceType': 'DOCTOR', 'isActive': true}]}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.url.path == '/api/v1/scheduling/rules') {
          return http.Response(
            jsonEncode({'ok': true, 'data': {'count': 0, 'items': []}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(jsonEncode({'ok': true, 'data': {}}), 200, headers: {'content-type': 'application/json'});
      });

      final api = MedCoreApiClient(baseUrl: 'http://127.0.0.1:8080', hospitalCode: 'HOSP_TEST', deviceId: 'DEV-TEST', httpClient: mockHttp);
      final controller = MedCoreAppController(apiClient: api);
      controller.setAuthenticatedUserForTesting(
        const AuthenticatedStaffUser(
          id: 1,
          hospitalCode: 'HOSP_TEST',
          staffCode: 'ADMIN-01',
          fullName: 'Hospital Administrator',
          email: 'admin@medcore.local',
          role: 'Administrator',
          effectivePermissions: {'admin', 'appointments'},
          canEdit: true,
          canDelete: true,
          canCollectMoney: false,
          canMakeRefunds: false,
          refundPolicy: 'NONE',
          forcePasswordChange: false,
        ),
      );

      await tester.pumpWidget(MaterialApp(home: ResourceSchedulingManagementScreen(controller: controller)));
      await tester.pumpAndSettle();

      // Tap Weekly Clinic Shifts segment
      final shiftTab = find.text('Weekly Clinic Shifts (GAP-016)');
      expect(shiftTab, findsOneWidget);
      await tester.tap(shiftTab);
      await tester.pumpAndSettle();

      // Verify header and day chips
      expect(find.text('Weekly Clinic Shift Schedules (GAP-016)'), findsOneWidget);
      expect(find.textContaining('Saturday'), findsWidgets);
      expect(find.text('Add Shift'), findsOneWidget);
    });

    testWidgets('2. GAP-017: Pharmacy POS Counter Dispensing card and inventory batches',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      bool dispenseCalled = false;
      final mockHttp = MockClient((http.Request req) async {
        if (req.url.path == '/api/v1/inventory/items') {
          return http.Response(
            jsonEncode({'ok': true, 'data': {'items': [{'id': 1, 'item_name': 'Paracetamol 500mg', 'stock_quantity': 250}]}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.url.path == '/api/v1/inventory/batches') {
          return http.Response(
            jsonEncode({'ok': true, 'data': {'items': [{'batch_number': 'B-2026-001', 'quantity': 100}]}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.url.path == '/api/v1/pharmacy/dispense' && req.method == 'POST') {
          dispenseCalled = true;
          return http.Response(
            jsonEncode({'ok': true, 'data': {'status': 'DISPENSED', 'quantity': '1'}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(jsonEncode({'ok': true, 'data': {}}), 200, headers: {'content-type': 'application/json'});
      });

      final api = MedCoreApiClient(baseUrl: 'http://127.0.0.1:8080', hospitalCode: 'HOSP_TEST', deviceId: 'DEV-TEST', httpClient: mockHttp);
      final controller = MedCoreAppController(apiClient: api);
      controller.setAuthenticatedUserForTesting(
        const AuthenticatedStaffUser(
          id: 1,
          hospitalCode: 'HOSP_TEST',
          staffCode: 'PHARM-01',
          fullName: 'Pharmacist Sarah',
          email: 'pharm@medcore.local',
          role: 'Pharmacist',
          effectivePermissions: {'pharmacy_inventory', 'pharmacy_Dispensing'},
          canEdit: true,
          canDelete: false,
          canCollectMoney: true,
          canMakeRefunds: false,
          refundPolicy: 'NONE',
          forcePasswordChange: false,
        ),
      );

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ClinicalModulesHubScreen(controller: controller, activeSection: 'pharmacy'))));
      await tester.pumpAndSettle();

      expect(find.text('Pharmacy POS Counter Dispensing (GAP-017)'), findsOneWidget);
      expect(find.text('Dispense (FIFO)'), findsOneWidget);

      await tester.tap(find.text('Dispense (FIFO)'));
      await tester.pumpAndSettle();

      expect(dispenseCalled, isTrue);
    });

    testWidgets('3. GAP-018: Diagnostic Results Entry (LIS) dialog and sign-off',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      bool resultSaved = false;
      final mockHttp = MockClient((http.Request req) async {
        if (req.url.path == '/api/v1/orders' && req.method == 'GET') {
          return http.Response(
            jsonEncode({'ok': true, 'data': {'items': [{'id': 201, 'order_number': 'ORD-LAB-201', 'patient_id': 15, 'status': 'PENDING', 'clinical_indication': 'Fever & Fatigue'}]}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.url.path == '/api/v1/orders/201/results' && req.method == 'POST') {
          resultSaved = true;
          return http.Response(
            jsonEncode({'ok': true, 'data': {'status': 'RECORDED'}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(jsonEncode({'ok': true, 'data': {}}), 200, headers: {'content-type': 'application/json'});
      });

      final api = MedCoreApiClient(baseUrl: 'http://127.0.0.1:8080', hospitalCode: 'HOSP_TEST', deviceId: 'DEV-TEST', httpClient: mockHttp);
      final controller = MedCoreAppController(apiClient: api);
      controller.setAuthenticatedUserForTesting(
        const AuthenticatedStaffUser(
          id: 1,
          hospitalCode: 'HOSP_TEST',
          staffCode: 'LAB-01',
          fullName: 'Lab Technologist',
          email: 'lab@medcore.local',
          role: 'Technician',
          effectivePermissions: {'lab', 'lab_Dashboard', 'lab_ResultsEntry'},
          canEdit: true,
          canDelete: false,
          canCollectMoney: false,
          canMakeRefunds: false,
          refundPolicy: 'NONE',
          forcePasswordChange: false,
        ),
      );

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ClinicalModulesHubScreen(controller: controller, activeSection: 'laboratory'))));
      await tester.pumpAndSettle();

      expect(find.text('Laboratory Orders & Specimens (LIS)'), findsOneWidget);
      expect(find.text('Enter Results'), findsOneWidget);

      await tester.tap(find.text('Enter Results'));
      await tester.pumpAndSettle();

      expect(find.text('Record Diagnostic Result (Order #201)'), findsOneWidget);
      expect(find.text('Save & Sign Off'), findsOneWidget);

      await tester.tap(find.text('Save & Sign Off'));
      await tester.pumpAndSettle();

      expect(resultSaved, isTrue);
    });

    testWidgets('4. GAP-019 & GAP-020: Inpatient Visual Bed Matrix and Specialty Units Tabs',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final mockHttp = MockClient((http.Request req) async {
        if (req.url.path == '/api/v1/beds') {
          return http.Response(
            jsonEncode({'ok': true, 'data': {'items': [{'id': 1, 'bed_code': 'BED-ICU-01', 'room_number': 'ICU-1', 'status': 'AVAILABLE'}, {'id': 2, 'bed_code': 'BED-WARD-02', 'room_number': 'Room 102', 'status': 'OCCUPIED', 'patient_id': '105'}]}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.url.path == '/api/v1/clinical/nursing/tasks') {
          return http.Response(
            jsonEncode({'ok': true, 'data': {'items': [{'id': 1, 'description': 'Administer medication', 'status': 'PENDING'}]}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(jsonEncode({'ok': true, 'data': {}}), 200, headers: {'content-type': 'application/json'});
      });

      final api = MedCoreApiClient(baseUrl: 'http://127.0.0.1:8080', hospitalCode: 'HOSP_TEST', deviceId: 'DEV-TEST', httpClient: mockHttp);
      final controller = MedCoreAppController(apiClient: api);
      controller.setAuthenticatedUserForTesting(
        const AuthenticatedStaffUser(
          id: 1,
          hospitalCode: 'HOSP_TEST',
          staffCode: 'NURSE-01',
          fullName: 'Head Nurse',
          email: 'nurse@medcore.local',
          role: 'Nurse',
          effectivePermissions: {'inpatient', 'inpatient_BedMap', 'inpatient_Admissions', 'nurse', 'icu_nicu', 'surgery', 'dialysis'},
          canEdit: true,
          canDelete: false,
          canCollectMoney: false,
          canMakeRefunds: false,
          refundPolicy: 'NONE',
          forcePasswordChange: false,
        ),
      );

      // Verify Inpatient Bed Matrix (GAP-020)
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ClinicalModulesHubScreen(controller: controller, activeSection: 'inpatient'))));
      await tester.pumpAndSettle();

      expect(find.text('Inpatient Admission & Bed Allocation (GAP-020)'), findsOneWidget);
      expect(find.text('BED-ICU-01'), findsOneWidget);
      expect(find.text('BED-WARD-02'), findsOneWidget);
      expect(find.text('AVAILABLE'), findsOneWidget);
      expect(find.text('OCCUPIED'), findsOneWidget);

      // Verify Specialty Care Units (GAP-019)
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ClinicalModulesHubScreen(controller: controller, activeSection: 'specialty_units'))));
      await tester.pumpAndSettle();

      expect(find.text('Nursing Station'), findsOneWidget);
      expect(find.text('ICU Monitoring'), findsOneWidget);
      expect(find.text('Operating Theater'), findsOneWidget);
      expect(find.text('Dialysis Unit'), findsOneWidget);
    });
  });
}
