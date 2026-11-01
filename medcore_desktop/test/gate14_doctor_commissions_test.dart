import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medcore_desktop/core/api/medcore_api_client.dart';
import 'package:medcore_desktop/core/state/medcore_app_controller.dart';
import 'package:medcore_desktop/core/models/product_models.dart';
import 'package:medcore_desktop/features/finance/doctor_commissions_screen.dart';

class MockCommissionsApiClient extends MedCoreApiClient {
  List<Map<String, dynamic>> mockProfiles = [
    {
      'id': 1,
      'doctorId': 10,
      'consultationPercentage': '25.00',
      'procedurePercentage': '40.00',
      'fixedCutPerVisit': '50.0000',
      'status': 'ACTIVE',
    }
  ];

  int createProfileCallCount = 0;
  Map<String, dynamic>? lastCreatedProfile;

  MockCommissionsApiClient() : super(baseUrl: 'http://127.0.0.1:8443');

  @override
  bool get hasStaffToken => true;

  @override
  Future<List<Map<String, dynamic>>> getDoctorCommissions() async {
    return List<Map<String, dynamic>>.from(mockProfiles);
  }

  @override
  Future<Map<String, dynamic>> createDoctorCommissionProfile(Map<String, dynamic> payload) async {
    createProfileCallCount++;
    lastCreatedProfile = payload;
    final item = Map<String, dynamic>.from(payload);
    item['id'] = mockProfiles.length + 1;
    mockProfiles.add(item);
    return {'ok': true, 'profile': item};
  }
}

void main() {
  group('GATE 14 — Doctor Commissions & Settlements Widget Tests', () {
    late MockCommissionsApiClient mockApi;
    late MedCoreAppController controller;

    setUp(() {
      mockApi = MockCommissionsApiClient();
      controller = MedCoreAppController(apiClient: mockApi);
      controller.setAuthenticatedUserForTesting(
        const AuthenticatedStaffUser(
          id: 1,
          hospitalCode: 'HOSP_MAIN',
          staffCode: 'STF-ADMIN-01',
          fullName: 'المدير المالي',
          email: 'finance@medcore.local',
          role: 'ADMIN',
          effectivePermissions: {'admin', 'finance', 'finance_Commissions', 'doctor_Commissions'},
          canEdit: true,
          canDelete: true,
          canCollectMoney: true,
          canMakeRefunds: true,
          refundPolicy: 'direct',
          forcePasswordChange: false,
        ),
      );
    });

    testWidgets('1. Renders Doctor Commissions screen and active profiles table', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DoctorCommissionsScreen(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('العمولات والتسويات المالية للأطباء (Commissions & Settlements)'), findsOneWidget);
      expect(find.text('طبيب #10'), findsOneWidget);
      expect(find.text('25.00 %'), findsOneWidget);
      expect(find.text('40.00 %'), findsOneWidget);
      expect(find.byKey(const Key('btn_create_commission_profile')), findsOneWidget);
    });

    testWidgets('2. Creating a new commission profile calls API with validated percentages', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DoctorCommissionsScreen(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_create_commission_profile')));
      await tester.pumpAndSettle();

      expect(find.text('إنشاء ملف عمولة طبيب جديد'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('input_comm_doctor_id')), '25');
      await tester.enterText(find.byKey(const Key('input_comm_consultation_pct')), '30.00');
      await tester.enterText(find.byKey(const Key('input_comm_procedure_pct')), '50.00');
      await tester.enterText(find.byKey(const Key('input_comm_fixed_cut')), '75.0000');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_save_commission_profile')));
      await tester.pumpAndSettle();

      expect(mockApi.createProfileCallCount, 1);
      expect(mockApi.lastCreatedProfile?['doctorId'], 25);
      expect(mockApi.lastCreatedProfile?['consultationPercentage'], '30.00');
      expect(find.text('طبيب #25'), findsOneWidget);
    });

    // RED TEAM ATTACK VECTORS
    group('RED TEAM: Gate 14 Commissions Attack Vectors', () {
      testWidgets('RED-14-01: Non-numeric doctor ID fails closed without calling API', (tester) async {
        await tester.binding.setSurfaceSize(const Size(1600, 1000));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DoctorCommissionsScreen(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_create_commission_profile')));
        await tester.pumpAndSettle();

        await tester.enterText(find.byKey(const Key('input_comm_doctor_id')), 'ABC_INVALID');
        await tester.pumpAndSettle();

        final initialCount = mockApi.createProfileCallCount;
        await tester.tap(find.byKey(const Key('btn_save_commission_profile')));
        await tester.pumpAndSettle();

        expect(mockApi.createProfileCallCount, initialCount);
      });
    });
  });
}
