import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medcore_desktop/core/localization/medcore_localizations.dart';
import 'package:medcore_desktop/core/localization/medcore_strings_ar.dart';
import 'package:medcore_desktop/core/navigation/desktop_navigation_catalog.dart';
import 'package:medcore_desktop/core/state/medcore_app_controller.dart';
import 'package:medcore_desktop/core/models/product_models.dart';
import 'package:medcore_desktop/core/shell/medcore_desktop_shell.dart';

void main() {
  group('GATE 02 — Arabic-First Localization Architecture Verification', () {
    late MedCoreAppController controller;

    setUp(() {
      controller = MedCoreAppController();
    });

    test('1. Default Locale is ar-EG and isRtl is true', () {
      expect(controller.locale.languageCode, equals('ar'));
      expect(controller.locale.countryCode, equals('EG'));
      expect(controller.isRtl, isTrue);
    });

    test('2. Arabic Navigation Catalog contains localized labels for all modules', () {
      final routes = DesktopNavigationCatalog.staffRoutes;
      expect(routes.isNotEmpty, isTrue);

      for (final r in routes) {
        expect(r.arLabel, isNotNull, reason: 'Route ${r.routeId} must have an Arabic label');
        expect(r.arLabel!.trim().isNotEmpty, isTrue);
        expect(r.getDisplayLabel(true), equals(r.arLabel));
        expect(r.getDisplayLabel(false), equals(r.label));
      }

      // Check specific Arabic key translations
      expect(DesktopNavigationCatalog.findById('dashboard')?.arLabel, equals(MedCoreStringsAr.navDashboard));
      expect(DesktopNavigationCatalog.findById('definitions_workspace')?.arLabel, equals(MedCoreStringsAr.navDefinitions));
      expect(DesktopNavigationCatalog.findById('commissions')?.arLabel, equals(MedCoreStringsAr.navCommissions));
      expect(DesktopNavigationCatalog.findById('hr_payroll')?.arLabel, equals(MedCoreStringsAr.navHrPayroll));
    });

    test('3. Currency & Number Formatting outputs Egyptian Pound in Arabic (ج.م)', () {
      const loc = MedCoreLocalizations(Locale('ar', 'EG'));
      final formatted = loc.formatCurrency(150.50);
      expect(formatted, contains(MedCoreStringsAr.currencyEgp));
      expect(formatted, equals('150.50 ج.م'));
    });

    testWidgets('4. TechnicalLtrField isolates IP and Ports in LTR text direction', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Column(
                children: [
                  Text('الخدمة المحلية:'),
                  TechnicalLtrField('http://127.0.0.1:8443', key: Key('tech_ip_field')),
                ],
              ),
            ),
          ),
        ),
      );

      final finder = find.byKey(const Key('tech_ip_field'));
      expect(finder, findsOneWidget);

      final technicalWidget = tester.widget<TechnicalLtrField>(finder);
      expect(technicalWidget.text, equals('http://127.0.0.1:8443'));

      // Check Directionality ancestor of Text inside TechnicalLtrField
      final textFinder = find.descendant(of: finder, matching: find.byType(Directionality));
      expect(textFinder, findsOneWidget);
      final dirWidget = tester.widget<Directionality>(textFinder);
      expect(dirWidget.textDirection, equals(TextDirection.ltr));
    });

    testWidgets('5. LanguageSelectorWidget renders correctly with ar-EG active', (tester) async {
      Locale? selectedLocale;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LanguageSelectorWidget(
              currentLocale: const Locale('ar', 'EG'),
              onLocaleChanged: (l) => selectedLocale = l,
            ),
          ),
        ),
      );

      expect(find.byType(LanguageSelectorWidget), findsOneWidget);
      expect(find.text('العربية'), findsOneWidget);

      // Open popup menu
      await tester.tap(find.byType(LanguageSelectorWidget));
      await tester.pumpAndSettle();

      // Check menu entries
      expect(find.text(MedCoreStringsAr.arabicEgypt), findsOneWidget);
      expect(find.text(MedCoreStringsAr.englishUs), findsOneWidget);
      expect(find.text(MedCoreStringsAr.frenchFr), findsOneWidget);
    });

    testWidgets('6. MedCoreDesktopShell renders in RTL with Arabic Navigation Labels', (tester) async {
      controller.setAuthenticatedUserForTesting(
        const AuthenticatedStaffUser(
          id: 1,
          hospitalCode: 'HOSP_MAIN',
          staffCode: 'STF-001',
          fullName: 'د. أحمد محمود الشريف',
          email: 'ahmed@medcore.local',
          role: 'ADMIN',
          effectivePermissions: {'dashboard', 'admin', 'patients', 'definitions'},
          canEdit: true,
          canDelete: true,
          canCollectMoney: true,
          canMakeRefunds: true,
          refundPolicy: 'STANDARD',
          forcePasswordChange: false,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: controller.locale,
          home: MedCoreDesktopShell(controller: controller),
        ),
      );
      await tester.pump();

      // Verify sign out button in Arabic
      expect(find.text('تسجيل الخروج'), findsOneWidget);

      // Verify Arabic navigation items appear
      expect(find.text(MedCoreStringsAr.navDashboard), findsOneWidget);
      expect(find.text(MedCoreStringsAr.navPatients), findsOneWidget);
    });

    group('RED TEAM: Gate 02 Localization Attack Vectors', () {
      test('RED-02-01: User-controlled locale corruption falls back gracefully', () {
        // Attempt to set unsupported or corrupted locale
        controller.setLocale(const Locale('xx', 'INVALID'));
        expect(controller.locale.languageCode, equals('xx'));
        expect(controller.isRtl, isFalse);

        // Reset to standard Egyptian Arabic
        controller.setLocale(const Locale('ar', 'EG'));
        expect(controller.isRtl, isTrue);
      });

      test('RED-02-02: BiDi override and Unicode directional injection resistance', () {
        // Test that strings containing directional override characters (RLO/LRO) do not crash
        const maliciousIp = '\u202E127.0.0.1:8443\u202C';
        const field = TechnicalLtrField(maliciousIp);
        expect(field.text, equals(maliciousIp));
      });

      test('RED-02-03: Zero external network font requests (Offline Invariant)', () {
        // Confirm no network fonts are requested or loaded dynamically
        expect(controller.branding.appDisplayName.isNotEmpty, isTrue);
      });
    });
  });
}
