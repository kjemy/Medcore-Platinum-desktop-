import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medcore_desktop/core/api/medcore_api_client.dart';
import 'package:medcore_desktop/core/state/medcore_app_controller.dart';
import 'package:medcore_desktop/core/models/product_models.dart';
import 'package:medcore_desktop/features/notes/draggable_notes_overlay.dart';

class MockNotesApiClient extends MedCoreApiClient {
  List<Map<String, dynamic>> mockNotes = [
    {
      'id': 1,
      'public_id': 'note_101',
      'hospital_code': 'HOSP_MAIN',
      'created_by': 'STF-ADMIN-01',
      'content': 'ملاحظة داخلية: اجتماع مجلس الإدارة غداً الساعة 10 صباحاً',
      'priority': 'IMPORTANT',
      'is_pinned': 1,
      'created_at': '2026-11-01',
    }
  ];

  int createNoteCallCount = 0;
  String? lastCreatedContent;
  String? lastPinnedId;

  MockNotesApiClient() : super(baseUrl: 'http://127.0.0.1:8443');

  @override
  bool get hasStaffToken => true;

  @override
  Future<List<Map<String, dynamic>>> getInternalNotes() async {
    return List<Map<String, dynamic>>.from(mockNotes);
  }

  @override
  Future<Map<String, dynamic>> createInternalNote(String content, {String priority = 'NORMAL', bool isPinned = false}) async {
    createNoteCallCount++;
    lastCreatedContent = content;
    final newNote = {
      'id': mockNotes.length + 1,
      'public_id': 'note_${mockNotes.length + 1}',
      'hospital_code': 'HOSP_MAIN',
      'created_by': 'STF-TEST',
      'content': content,
      'priority': priority,
      'is_pinned': isPinned ? 1 : 0,
      'created_at': DateTime.now().toIso8601String(),
    };
    mockNotes.add(newNote);
    return {'ok': true, 'note': newNote};
  }

  @override
  Future<Map<String, dynamic>> togglePinInternalNote(String publicId) async {
    lastPinnedId = publicId;
    for (final n in mockNotes) {
      if (n['public_id'] == publicId || n['id'].toString() == publicId) {
        n['is_pinned'] = (n['is_pinned'] == 1) ? 0 : 1;
        return {'ok': true, 'is_pinned': n['is_pinned']};
      }
    }
    return {'ok': false};
  }
}

void main() {
  group('GATE 15 — Draggable Floating Note FAB (+) & Scratchpad Widget Tests', () {
    late MockNotesApiClient mockApi;
    late MedCoreAppController controller;

    setUp(() {
      mockApi = MockNotesApiClient();
      controller = MedCoreAppController(apiClient: mockApi);
      controller.setAuthenticatedUserForTesting(
        const AuthenticatedStaffUser(
          id: 1,
          hospitalCode: 'HOSP_MAIN',
          staffCode: 'STF-ADMIN-01',
          fullName: 'المدير العام',
          email: 'admin@medcore.local',
          role: 'ADMIN',
          effectivePermissions: {'admin', 'dashboard'},
          canEdit: true,
          canDelete: true,
          canCollectMoney: true,
          canMakeRefunds: true,
          refundPolicy: 'direct',
          forcePasswordChange: false,
        ),
      );
    });

    testWidgets('1. Draggable FAB (+) renders on screen and toggles scratchpad card', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                const Center(child: Text('Main Content')),
                DraggableNotesOverlay(controller: controller),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('fab_quick_notes')), findsOneWidget);
      expect(find.byKey(const Key('card_notes_scratchpad')), findsNothing);

      // Tap FAB to open scratchpad
      await tester.tap(find.byKey(const Key('fab_quick_notes')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('card_notes_scratchpad')), findsOneWidget);
      expect(find.text('الملاحظات والتذكيرات الداخلية'), findsOneWidget);
      expect(find.text('ملاحظة داخلية: اجتماع مجلس الإدارة غداً الساعة 10 صباحاً'), findsOneWidget);
    });

    testWidgets('2. Entering and saving a quick note calls API and renders in notes list', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                const Center(child: Text('Main Content')),
                DraggableNotesOverlay(controller: controller),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('fab_quick_notes')));
      await tester.pumpAndSettle();

      // Enter quick note
      await tester.enterText(find.byKey(const Key('input_quick_note_content')), 'تذكير: تسليم تقرير جرد الصيدلية');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_save_quick_note')));
      await tester.pumpAndSettle();

      expect(mockApi.createNoteCallCount, 1);
      expect(mockApi.lastCreatedContent, 'تذكير: تسليم تقرير جرد الصيدلية');
      expect(find.text('تذكير: تسليم تقرير جرد الصيدلية'), findsOneWidget);
    });

    testWidgets('3. Toggling pin icon calls pin API', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                const Center(child: Text('Main Content')),
                DraggableNotesOverlay(controller: controller),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('fab_quick_notes')));
      await tester.pumpAndSettle();

      // Tap pin on note_101
      await tester.tap(find.byKey(const Key('btn_pin_note_note_101')));
      await tester.pumpAndSettle();

      expect(mockApi.lastPinnedId, 'note_101');
    });

    // RED TEAM ATTACK VECTORS
    group('RED TEAM: Gate 15 Notes Attack Vectors', () {
      testWidgets('RED-15-01: Empty note content fails closed and does not call API', (tester) async {
        await tester.binding.setSurfaceSize(const Size(1600, 1000));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  const Center(child: Text('Main Content')),
                  DraggableNotesOverlay(controller: controller),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('fab_quick_notes')));
        await tester.pumpAndSettle();

        // Leave empty and tap save
        final initialCount = mockApi.createNoteCallCount;
        await tester.tap(find.byKey(const Key('btn_save_quick_note')));
        await tester.pumpAndSettle();

        expect(mockApi.createNoteCallCount, initialCount);
      });
    });
  });
}
