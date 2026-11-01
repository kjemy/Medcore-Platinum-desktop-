import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medcore_desktop/core/api/medcore_api_client.dart';
import 'package:medcore_desktop/core/state/medcore_app_controller.dart';
import 'package:medcore_desktop/core/models/product_models.dart';
import 'package:medcore_desktop/features/reception/shifts_and_visits_screen.dart';

class MockReceptionApiClient extends MedCoreApiClient {
  int postCallCount = 0;
  Map<String, dynamic>? lastVisitPayload;
  String? lastIdempotencyKey;

  MockReceptionApiClient() : super(baseUrl: 'http://127.0.0.1:8443');

  @override
  bool get hasStaffToken => true;

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
    bool useTechnicianAuth = false,
    bool includeAuth = true,
  }) async {
    if (path == '/api/v1/shifts/current') {
      return {
        'openShift': {
          'id': 101,
          'shiftCode': 'SH-2026-AM',
          'openingBalance': '500.0000',
          'cashIn': '1250.0000',
          'expectedCash': '1750.0000',
          'status': 'OPEN',
        }
      };
    }
    if (path == '/api/v1/shifts') {
      return {'items': []};
    }
    if (path == '/api/v1/patients') {
      return {
        'items': [
          {
            'id': 10,
            'fullName': 'محمود عبد العزيز',
            'medicalRecordNumber': 'MRN-2026-0010',
          }
        ]
      };
    }
    if (path == '/api/v1/staff') {
      return {
        'items': [
          {
            'id': 1,
            'fullName': 'د. أحمد إبراهيم',
            'staffCode': 'DOC-IM-01',
            'role': 'Doctor',
          }
        ]
      };
    }
    return {};
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    bool useTechnicianAuth = false,
    bool includeAuth = true,
  }) async {
    postCallCount++;
    if (path == '/api/v1/visits') {
      lastVisitPayload = body;
      lastIdempotencyKey = body['idempotencyKey']?.toString();
      return {
        'ok': true,
        'visitId': 5001,
        'visitNumber': body['visitNumber'],
        'patientId': body['patientId'],
        'doctorId': body['doctorId'],
        'paidAmount': body['paidAmount'],
        'financialEventId': 9001,
      };
    }
    return {'ok': true};
  }
}

void main() {
  group('GATES 06 & 07 — Clinics, Reception & Interactive Clinic Cards Widget Tests', () {
    late MockReceptionApiClient mockApi;
    late MedCoreAppController controller;

    setUp(() {
      mockApi = MockReceptionApiClient();
      controller = MedCoreAppController(apiClient: mockApi);
      controller.setAuthenticatedUserForTesting(
        const AuthenticatedStaffUser(
          id: 1,
          hospitalCode: 'HOSP_MAIN',
          staffCode: 'STF-REC-01',
          fullName: 'موظف الاستقبال',
          email: 'rec@medcore.local',
          role: 'RECEPTION',
          effectivePermissions: {'reception', 'reception_QuickCheckIn', 'shifts', 'patients'},
          canEdit: true,
          canDelete: true,
          canCollectMoney: true,
          canMakeRefunds: true,
          refundPolicy: 'direct',
          forcePasswordChange: false,
        ),
      );
    });

    testWidgets('1. Renders interactive Clinic Cards board with doctors, fees, and waiting counts', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShiftsAndVisitsScreen(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('العيادات المتاحة والكشوفات (لوحة الاستقبال)'), findsOneWidget);
      expect(find.text('عيادة الباطنة العامة'), findsOneWidget);
      expect(find.text('عيادة الأطفال وحديثي الولادة'), findsOneWidget);
      expect(find.text('250.0000 ج.م'), findsOneWidget);
      expect(find.text('2 بالانتظار'), findsOneWidget);
    });

    testWidgets('2. Tapping Clinic Card populates visit checkout form with doctor, fee, and visit number', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShiftsAndVisitsScreen(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap select on CLN-IM-01
      await tester.tap(find.byKey(const Key('btn_select_clinic_CLN-IM-01')));
      await tester.pumpAndSettle();

      // Verify fee and visit number populated
      final laborField = tester.widget<TextField>(find.byKey(const Key('input_visit_labor_gross')));
      expect(laborField.controller?.text, '250.0000');

      final paidField = tester.widget<TextField>(find.byKey(const Key('input_visit_paid')));
      expect(paidField.controller?.text, '250.0000');

      final visitNoField = tester.widget<TextField>(find.byKey(const Key('input_visit_number')));
      expect(visitNoField.controller?.text.startsWith('VIS-'), isTrue);
    });

    testWidgets('3. Temporary Emergency Clinic creation adds dynamic clinic card with temporary badge', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShiftsAndVisitsScreen(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open temp clinic dialog
      await tester.tap(find.byKey(const Key('btn_create_temp_clinic')));
      await tester.pumpAndSettle();

      expect(find.text('إنشاء عيادة طوارئ / مؤقتة'), findsAtLeastNWidgets(1));

      await tester.enterText(find.byKey(const Key('input_temp_clinic_name')), 'عيادة فرز الطوارئ الميدانية');
      await tester.enterText(find.byKey(const Key('input_temp_clinic_doctor')), 'د. طوارئ مناوب');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_submit_temp_clinic')));
      await tester.pumpAndSettle();

      expect(find.text('عيادة فرز الطوارئ الميدانية'), findsOneWidget);
      expect(find.text('طوارئ مؤقتة'), findsOneWidget);
    });

    testWidgets('4. Quick service dialog adds service and updates labor fee', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShiftsAndVisitsScreen(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Pre-select clinic
      await tester.tap(find.byKey(const Key('btn_select_clinic_CLN-IM-01')));
      await tester.pumpAndSettle();

      // Open quick service
      await tester.tap(find.byKey(const Key('btn_quick_service')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('input_quick_service_name')), 'رسم قلب مع تقرير فوري');
      await tester.enterText(find.byKey(const Key('input_quick_service_price')), '100.0000');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_submit_quick_service')));
      await tester.pumpAndSettle();

      // 250 + 100 = 350.0000
      final laborField = tester.widget<TextField>(find.byKey(const Key('input_visit_labor_gross')));
      expect(laborField.controller?.text, '350.0000');
    });

    testWidgets('5. Quick consumable dialog updates consumable gross and FIFO cost', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShiftsAndVisitsScreen(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open quick consumable
      await tester.ensureVisible(find.byKey(const Key('btn_quick_consumable')));
      await tester.tap(find.byKey(const Key('btn_quick_consumable')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('input_quick_consumable_name')), 'كانيولا + سرنجة');
      await tester.enterText(find.byKey(const Key('input_quick_consumable_cost')), '20.0000');
      await tester.enterText(find.byKey(const Key('input_quick_consumable_price')), '45.0000');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_submit_quick_consumable')));
      await tester.pumpAndSettle();

      // Verify consumable and paid amounts
      final paidField = tester.widget<TextField>(find.byKey(const Key('input_visit_paid')));
      expect(paidField.controller?.text, '45.0000');
    });

    testWidgets('6. Committing atomic visit renders printable patient ticket receipt', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShiftsAndVisitsScreen(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select clinic
      await tester.tap(find.byKey(const Key('btn_select_clinic_CLN-IM-01')));
      await tester.pumpAndSettle();

      // Select patient from dropdown
      await tester.tap(find.text('Select Registered Patient *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('#10 — محمود عبد العزيز (MRN-2026-0010)').last);
      await tester.pumpAndSettle();

      // Commit visit
      await tester.ensureVisible(find.byKey(const Key('btn_commit_visit')));
      await tester.tap(find.byKey(const Key('btn_commit_visit')));
      await tester.pumpAndSettle();

      // Verify ticket receipt widget rendered
      expect(find.byKey(const Key('widget_ticket_receipt')), findsOneWidget);
      expect(find.text('رقم التذكرة: #TKT-5001'), findsOneWidget);
      expect(find.text('تم السداد بالخزينة'), findsOneWidget);
      expect(find.byKey(const Key('btn_print_ticket')), findsOneWidget);
    });

    // RED TEAM ATTACK VECTORS
    group('RED TEAM: Gates 06 & 07 Attack Vectors', () {
      testWidgets('RED-06-01: Negative fee or invalid decimal in checkout fails closed', (tester) async {
        await tester.binding.setSurfaceSize(const Size(1600, 1200));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ShiftsAndVisitsScreen(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Select clinic
        await tester.tap(find.byKey(const Key('btn_select_clinic_CLN-IM-01')));
        await tester.pumpAndSettle();

        // Select patient
        await tester.tap(find.text('Select Registered Patient *'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('#10 — محمود عبد العزيز (MRN-2026-0010)').last);
        await tester.pumpAndSettle();

        // Tamper with paid amount to negative
        await tester.enterText(find.byKey(const Key('input_visit_paid')), '-500.0000');
        await tester.pumpAndSettle();

        final initialPostCount = mockApi.postCallCount;
        await tester.ensureVisible(find.byKey(const Key('btn_commit_visit')));
        await tester.tap(find.byKey(const Key('btn_commit_visit')));
        await tester.pumpAndSettle();

        // API should NOT be called
        expect(mockApi.postCallCount, initialPostCount);
        expect(find.text('Paid Amount cannot be negative.'), findsOneWidget);
      });

      testWidgets('RED-07-01: Idempotency key is generated and passed for replay prevention', (tester) async {
        await tester.binding.setSurfaceSize(const Size(1600, 1200));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ShiftsAndVisitsScreen(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_select_clinic_CLN-IM-01')));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Select Registered Patient *'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('#10 — محمود عبد العزيز (MRN-2026-0010)').last);
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.byKey(const Key('btn_commit_visit')));
        await tester.tap(find.byKey(const Key('btn_commit_visit')));
        await tester.pumpAndSettle();

        // Verify idempotency key was included in wire payload
        expect(mockApi.lastIdempotencyKey, isNotNull);
        expect(mockApi.lastIdempotencyKey!.isNotEmpty, isTrue);
      });
    });
  });
}
