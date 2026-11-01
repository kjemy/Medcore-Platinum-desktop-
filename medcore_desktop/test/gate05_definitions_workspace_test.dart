import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medcore_desktop/core/api/medcore_api_client.dart';
import 'package:medcore_desktop/core/state/medcore_app_controller.dart';
import 'package:medcore_desktop/core/models/product_models.dart';
import 'package:medcore_desktop/features/definitions/definitions_workspace_screen.dart';

class MockDefinitionsApiClient extends MedCoreApiClient {
  final Map<String, List<Map<String, dynamic>>> storage = {
    'financial_categories': [
      {
        'id': 1,
        'public_id': 'def_fin_01',
        'code': 'FIN-CAT-01',
        'name_ar': 'إيرادات الكشوفات الطبية',
        'name_en': 'Clinic Consultations Revenue',
        'description': 'عائدات كشوفات العيادات الخارجية',
        'is_active': 1,
      }
    ],
    'payment_methods': [
      {
        'id': 2,
        'public_id': 'def_pay_01',
        'code': 'PAY-CASH',
        'name_ar': 'نقداً / كاش',
        'name_en': 'Cash',
        'description': 'الدفع المباشر بالخزينة',
        'is_active': 1,
      }
    ],
  };

  String? lastCreatedType;
  Map<String, dynamic>? lastCreatedPayload;
  String? lastUpdatedId;
  Map<String, dynamic>? lastUpdatedPayload;
  String? lastDeletedId;

  MockDefinitionsApiClient() : super(baseUrl: 'http://127.0.0.1:8443');

  @override
  bool get hasStaffToken => true;

  @override
  Future<List<Map<String, dynamic>>> getDefinitions(String type) async {
    return List<Map<String, dynamic>>.from(storage[type] ?? []);
  }

  @override
  Future<Map<String, dynamic>> createDefinition(String type, Map<String, dynamic> body) async {
    lastCreatedType = type;
    lastCreatedPayload = body;
    final newItem = Map<String, dynamic>.from(body);
    newItem['id'] = 999;
    newItem['public_id'] = 'def_${body['code']}';
    storage.putIfAbsent(type, () => []).add(newItem);
    return {'created': true, 'item': newItem};
  }

  @override
  Future<Map<String, dynamic>> updateDefinition(String publicId, Map<String, dynamic> body) async {
    lastUpdatedId = publicId;
    lastUpdatedPayload = body;
    for (final list in storage.values) {
      for (final item in list) {
        if (item['public_id'] == publicId || item['id'].toString() == publicId) {
          item.addAll(body);
          return {'updated': true, 'item': item};
        }
      }
    }
    return {'updated': false};
  }

  @override
  Future<Map<String, dynamic>> deleteDefinition(String publicId) async {
    lastDeletedId = publicId;
    for (final list in storage.values) {
      list.removeWhere((item) => item['public_id'] == publicId || item['id'].toString() == publicId);
    }
    return {'deleted': true};
  }
}

void main() {
  group('GATE 05 — Master Definitions Workspace Widget Tests', () {
    late MockDefinitionsApiClient mockApi;
    late MedCoreAppController controller;

    setUp(() {
      mockApi = MockDefinitionsApiClient();
      controller = MedCoreAppController(apiClient: mockApi);
      controller.setAuthenticatedUserForTesting(
        const AuthenticatedStaffUser(
          id: 1,
          hospitalCode: 'HOSP_MAIN',
          staffCode: 'STF-ADMIN-01',
          fullName: 'المدير العام',
          email: 'admin@medcore.local',
          role: 'ADMIN',
          effectivePermissions: {'admin', 'definitions', 'settings_MasterDefinitions'},
          canEdit: true,
          canDelete: true,
          canCollectMoney: true,
          canMakeRefunds: true,
          refundPolicy: 'direct',
          forcePasswordChange: false,
        ),
      );
    });

    testWidgets('1. Definitions workspace renders all 21 Arabic domains in sidebar', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DefinitionsWorkspaceScreen(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify header and sidebar title
      expect(find.text('دليل التعريفات الشاملة'), findsOneWidget);
      expect(find.text('21 مجالاً موحداً لإعدادات المستشفى'), findsOneWidget);

      // Verify domain items in sidebar
      expect(find.text('التصنيفات المالية'), findsAtLeastNWidgets(1));
      expect(find.text('طرق الدفع والتحصيل'), findsOneWidget);
      expect(find.text('بنود المصروفات'), findsOneWidget);
      expect(find.text('بنود الإيرادات'), findsOneWidget);

      // Verify active domain items table
      expect(find.text('FIN-CAT-01'), findsOneWidget);
      expect(find.text('إيرادات الكشوفات الطبية'), findsOneWidget);
    });

    testWidgets('2. Switching active domain loads items for that domain', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DefinitionsWorkspaceScreen(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on 'طرق الدفع والتحصيل'
      await tester.tap(find.text('طرق الدفع والتحصيل'));
      await tester.pumpAndSettle();

      expect(find.text('PAY-CASH'), findsOneWidget);
      expect(find.text('نقداً / كاش'), findsOneWidget);
    });

    testWidgets('3. Adding a new definition item sends validated payload to API', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DefinitionsWorkspaceScreen(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap 'إضافة عنصر جديد'
      await tester.tap(find.byKey(const Key('btn_add_definition')));
      await tester.pumpAndSettle();

      // Enter fields
      await tester.enterText(find.byKey(const Key('input_def_code')), 'FIN-CAT-NEW');
      await tester.enterText(find.byKey(const Key('input_def_name_ar')), 'إيرادات العمليات الجراحية');
      await tester.enterText(find.byKey(const Key('input_def_name_en')), 'Surgical Operations Revenue');
      await tester.enterText(find.byKey(const Key('input_def_description')), 'رسوم العمليات');
      await tester.pumpAndSettle();

      // Save
      await tester.tap(find.byKey(const Key('btn_save_definition')));
      await tester.pumpAndSettle();

      expect(mockApi.lastCreatedType, 'financial_categories');
      expect(mockApi.lastCreatedPayload?['code'], 'FIN-CAT-NEW');
      expect(mockApi.lastCreatedPayload?['name_ar'], 'إيرادات العمليات الجراحية');
      expect(find.text('FIN-CAT-NEW'), findsOneWidget);
    });

    testWidgets('4. Editing and updating a definition item calls updateDefinition', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DefinitionsWorkspaceScreen(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap edit on FIN-CAT-01
      await tester.tap(find.byKey(const Key('btn_edit_FIN-CAT-01')));
      await tester.pumpAndSettle();

      expect(find.text('تعديل عنصر التعريف'), findsOneWidget);

      // Modify description
      await tester.enterText(find.byKey(const Key('input_def_description')), 'وصف معدل ومحدث');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_save_definition')));
      await tester.pumpAndSettle();

      expect(mockApi.lastUpdatedId, 'def_fin_01');
      expect(mockApi.lastUpdatedPayload?['description'], 'وصف معدل ومحدث');
    });

    testWidgets('5. Deleting a definition item prompts confirmation and removes item', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DefinitionsWorkspaceScreen(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap delete on FIN-CAT-01
      await tester.tap(find.byKey(const Key('btn_delete_FIN-CAT-01')));
      await tester.pumpAndSettle();

      expect(find.text('تأكيد الحذف'), findsOneWidget);

      // Confirm delete
      await tester.tap(find.byKey(const Key('btn_confirm_delete_definition')));
      await tester.pumpAndSettle();

      expect(mockApi.lastDeletedId, 'def_fin_01');
      expect(find.text('FIN-CAT-01'), findsNothing);
    });

    // RED TEAM ATTACK VECTORS
    group('RED TEAM: Gate 05 Definitions Attack Vectors', () {
      testWidgets('RED-05-01: Injection attempt in code field is safely handled without XSS/SQL corruption', (tester) async {
        await tester.binding.setSurfaceSize(const Size(1600, 900));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DefinitionsWorkspaceScreen(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_add_definition')));
        await tester.pumpAndSettle();

        const injectionPayload = "'; DROP TABLE mc_definitions;-- <script>alert(1)</script>";
        await tester.enterText(find.byKey(const Key('input_def_code')), injectionPayload);
        await tester.enterText(find.byKey(const Key('input_def_name_ar')), 'اختبار هجوم الحقن');
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_save_definition')));
        await tester.pumpAndSettle();

        // System treats payload strictly as data without script evaluation or query crash
        expect(mockApi.lastCreatedPayload?['code'], injectionPayload);
        expect(tester.takeException(), isNull);
      });

      testWidgets('RED-05-02: Missing required code or Arabic name fails closed and does not call API', (tester) async {
        await tester.binding.setSurfaceSize(const Size(1600, 900));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DefinitionsWorkspaceScreen(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_add_definition')));
        await tester.pumpAndSettle();

        // Leave inputs blank
        mockApi.lastCreatedPayload = null;
        await tester.tap(find.byKey(const Key('btn_save_definition')));
        await tester.pumpAndSettle();

        // API should NOT have been called
        expect(mockApi.lastCreatedPayload, isNull);
        // Error message rendered
        expect(find.text('يرجى ملء الكود والاسم بالعربية.'), findsOneWidget);
      });
    });
  });
}
