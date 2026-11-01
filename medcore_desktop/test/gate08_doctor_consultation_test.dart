import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medcore_desktop/core/api/medcore_api_client.dart';
import 'package:medcore_desktop/core/state/medcore_app_controller.dart';
import 'package:medcore_desktop/core/models/product_models.dart';
import 'package:medcore_desktop/features/clinical/clinical_modules_hub_screen.dart';

class MockDoctorApiClient extends MedCoreApiClient {
  List<Map<String, dynamic>> mockQueue = [
    {
      'id': 101,
      'visitId': 2001,
      'patientId': 50,
      'patientName': 'سيد حسن أحمد',
      'medicalRecordNumber': 'MRN-2026-0050',
      'visitNumber': 'VIS-2001',
      'reason': 'صداع حاد وارتفاع في ضغط الدم',
      'status': 'WAITING',
    }
  ];

  Map<String, dynamic>? lastEncounterPayload;
  int encountersPostCount = 0;

  MockDoctorApiClient() : super(baseUrl: 'http://127.0.0.1:8443');

  @override
  bool get hasStaffToken => true;

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
    bool useTechnicianAuth = false,
    bool includeAuth = true,
  }) async {
    if (path == '/api/v1/doctor/queue') {
      return {
        'count': mockQueue.length,
        'items': mockQueue,
        'dataScopeApplied': 'FACILITY_WIDE',
      };
    }
    return {'items': []};
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    bool useTechnicianAuth = false,
    bool includeAuth = true,
  }) async {
    if (path == '/api/v1/encounters') {
      encountersPostCount++;
      lastEncounterPayload = body;
      return {
        'ok': true,
        'encounterId': 7001,
        'encounterNumber': body['encounterNumber'],
      };
    }
    return {'ok': true};
  }
}

void main() {
  group('GATE 08 — Doctor Consultation Workspace & Patient History Widget Tests', () {
    late MockDoctorApiClient mockApi;
    late MedCoreAppController controller;

    setUp(() {
      mockApi = MockDoctorApiClient();
      controller = MedCoreAppController(apiClient: mockApi);
      controller.setAuthenticatedUserForTesting(
        const AuthenticatedStaffUser(
          id: 5,
          hospitalCode: 'HOSP_MAIN',
          staffCode: 'DOC-IM-01',
          fullName: 'د. طارق محمود',
          email: 'tarek@medcore.local',
          role: 'Doctor',
          effectivePermissions: {'doctor', 'clinic', 'clinic_DoctorQueue', 'doctor_ClinicalWorkspace'},
          canEdit: true,
          canDelete: true,
          canCollectMoney: false,
          canMakeRefunds: false,
          refundPolicy: 'direct',
          forcePasswordChange: false,
        ),
      );
    });

    testWidgets('1. Renders Doctor Waiting Queue with patient details', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1400));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClinicalModulesHubScreen(
              controller: controller,
              activeSection: 'doctors',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('قائمة انتظار الكشف بالعيادة (Doctor Queue)'), findsOneWidget);
      expect(find.text('سيد حسن أحمد'), findsOneWidget);
      expect(find.text('في الانتظار'), findsOneWidget);
      expect(find.byKey(const Key('btn_start_consultation_101')), findsOneWidget);
    });

    testWidgets('2. Clicking start consultation opens clinical workspace with patient banner', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1400));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClinicalModulesHubScreen(
              controller: controller,
              activeSection: 'doctors',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_start_consultation_101')));
      await tester.pumpAndSettle();

      expect(find.text('جلسة الكشف الطبي: سيد حسن أحمد'), findsOneWidget);
      expect(find.text('العلامات الحيوية (Vital Signs)'), findsOneWidget);
      expect(find.byKey(const Key('input_chief_complaint')), findsOneWidget);
      expect(find.byKey(const Key('input_diagnosis')), findsOneWidget);
    });

    testWidgets('3. Applying examination template inserts clinical text into notes', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1400));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClinicalModulesHubScreen(
              controller: controller,
              activeSection: 'doctors',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_start_consultation_101')));
      await tester.pumpAndSettle();

      // Apply chest template
      await tester.ensureVisible(find.byKey(const Key('btn_apply_template_chest')));
      await tester.tap(find.byKey(const Key('btn_apply_template_chest')));
      await tester.pumpAndSettle();

      final examNotesField = tester.widget<TextField>(find.byKey(const Key('input_examination_notes')));
      expect(examNotesField.controller?.text.contains('Bilateral vesicular breathing'), isTrue);
    });

    testWidgets('4. Adding e-prescription item displays drug in table', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1400));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClinicalModulesHubScreen(
              controller: controller,
              activeSection: 'doctors',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_start_consultation_101')));
      await tester.pumpAndSettle();

      // Enter drug details
      await tester.ensureVisible(find.byKey(const Key('input_rx_med_name')));
      await tester.enterText(find.byKey(const Key('input_rx_med_name')), 'كونكور 5 مجم (Concor 5mg)');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_add_rx_item')));
      await tester.pumpAndSettle();

      expect(find.text('كونكور 5 مجم (Concor 5mg)'), findsOneWidget);
      expect(find.text('1 قرص'), findsAtLeastNWidgets(1));
    });

    testWidgets('5. Entering Doctor Final Comments and saving completes encounter atomically', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1400));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClinicalModulesHubScreen(
              controller: controller,
              activeSection: 'doctors',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_start_consultation_101')));
      await tester.pumpAndSettle();

      // Enter diagnosis
      await tester.enterText(find.byKey(const Key('input_diagnosis')), 'ارتفاع ضغط الدم الأولي (Essential Hypertension)');
      await tester.pumpAndSettle();

      // Enter doctor final comments
      await tester.ensureVisible(find.byKey(const Key('input_doctor_comments')));
      await tester.enterText(find.byKey(const Key('input_doctor_comments')), 'تقليل الملح في الطعام، قياس الضغط يومياً، مراجعة بعد أسبوع.');
      await tester.pumpAndSettle();

      // Save encounter
      await tester.ensureVisible(find.byKey(const Key('btn_complete_encounter')));
      await tester.tap(find.byKey(const Key('btn_complete_encounter')));
      await tester.pumpAndSettle();

      expect(mockApi.encountersPostCount, 1);
      expect(mockApi.lastEncounterPayload?['patientId'], 50);
      expect(mockApi.lastEncounterPayload?['visitId'], 2001);
      expect(mockApi.lastEncounterPayload?['notes'], 'تقليل الملح في الطعام، قياس الضغط يومياً، مراجعة بعد أسبوع.');
      expect(mockApi.lastEncounterPayload?['vitals']?['bloodPressure'], '120/80');
    });

    // RED TEAM ATTACK VECTORS
    group('RED TEAM: Gate 08 Doctor Consultation Attack Vectors', () {
      testWidgets('RED-08-01: Vital signs tampering does not crash rendering or query execution', (tester) async {
        await tester.binding.setSurfaceSize(const Size(1600, 1400));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ClinicalModulesHubScreen(
                controller: controller,
                activeSection: 'doctors',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_start_consultation_101')));
        await tester.pumpAndSettle();

        // Inject extreme vitals
        await tester.enterText(find.byKey(const Key('input_vital_bp_sys')), '300');
        await tester.enterText(find.byKey(const Key('input_vital_temp')), '43.5');
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.byKey(const Key('btn_complete_encounter')));
        await tester.tap(find.byKey(const Key('btn_complete_encounter')));
        await tester.pumpAndSettle();

        expect(mockApi.encountersPostCount, 1);
        expect(tester.takeException(), isNull);
      });
    });
  });
}
