import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medcore_desktop/core/api/medcore_api_client.dart';
import 'package:medcore_desktop/core/state/medcore_app_controller.dart';
import 'package:medcore_desktop/features/technician/technician_console_screen.dart';
import 'package:medcore_desktop/main.dart';

void main() {
  group('MedCore Platinum Desktop — Product Layer Foundation & Governance Gates', () {
    test('1. Static Architectural Proof: Zero mysql_client dependency & zero fake data stubs in lib/', () {
      final pubspecFile = File('pubspec.yaml');
      expect(pubspecFile.existsSync(), isTrue);
      final pubspecText = pubspecFile.readAsStringSync();
      expect(pubspecText.contains('mysql_client'), isFalse,
          reason: 'Flutter Desktop MUST NEVER connect directly to MariaDB.');

      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue);
      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      expect(dartFiles.length, greaterThanOrEqualTo(12));

      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        expect(content.contains('mysql_client'), isFalse,
            reason: 'Forbidden DB driver import in ${file.path}');
        expect(content.contains('UnimplementedError'), isFalse,
            reason: 'Forbidden crash stub in ${file.path}');
      }
    });

    testWidgets(
      '2. Centralized Branding/Theme + Module-Aware Navigation + Staff/Technician Separation',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(1440, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final mockHttp = MockClient((http.Request req) async {
          final path = req.url.path;
          if (path == '/api/v1/health') {
            return _okJson({
              'status': 'HEALTHY',
              'database': '11.4.4-MariaDB',
              'tableCount': 98,
              'appliedMigrations': 15,
            });
          }
          if (path == '/api/v1/product/bootstrap') {
            return _okJson(_sampleFacilityConfig(
              appDisplayName: 'Al-Noor Dental Desktop',
              facilityName: 'Al-Noor Specialized Dental Center',
              facilityType: 'DENTAL_CLINIC',
              edition: 'GOLD',
              editionLabel: 'MedCore GOLD',
              themeMode: 'DARK',
              uiDensity: 'COMPACT',
              fontScale: 1.15,
              labEnabled: false,
              inpatientEnabled: false,
            ));
          }
          if (path == '/api/v1/auth/login') {
            return _okJson({
              'token': 'mcs_staff_token_001',
              'user': {
                'id': 10,
                'hospitalCode': 'HOSP_DENTAL',
                'staffCode': 'ADM-01',
                'fullName': 'Dr. Sara El-Masry',
                'email': 'sara@alnoor.local',
                'role': 'HospitalAdmin',
                'effectivePermissions': [
                  'dashboard',
                  'patients_all',
                  'patients.write',
                  'finance_Invoices',
                  'finance_Revenue',
                  'lab_Dashboard', // Role has permission, BUT module is disabled!
                  'inpatient_BedMap', // Role has permission, BUT module is disabled!
                  'settings_Devices',
                  'security_Center',
                ],
                'operationalFlags': {
                  'canEdit': true,
                  'canDelete': false,
                  'canCollectMoney': true,
                  'canMakeRefunds': false,
                  'refundPolicy': 'none',
                },
              },
            });
          }
          if (path == '/api/v1/product/config') {
            return _okJson(_sampleFacilityConfig(
              appDisplayName: 'Al-Noor Dental Desktop',
              facilityName: 'Al-Noor Specialized Dental Center',
              facilityType: 'DENTAL_CLINIC',
              edition: 'GOLD',
              editionLabel: 'MedCore GOLD',
              themeMode: 'DARK',
              uiDensity: 'COMPACT',
              fontScale: 1.15,
              labEnabled: false,
              inpatientEnabled: false,
            ));
          }
          return _okJson({});
        });

        final controller = MedCoreAppController(
          apiClient: MedCoreApiClient(
            baseUrl: 'http://127.0.0.1:8443',
            hospitalCode: 'HOSP_DENTAL',
            deviceId: 'DEV-MAIN-HOST',
            httpClient: mockHttp,
          ),
        );

        await tester.pumpWidget(MedCorePlatinumDesktopApp(controller: controller));
        await tester.pumpAndSettle();

        // Connect & load bootstrap branding
        await controller.connectAndLoadBootstrap(
          baseUrl: 'http://127.0.0.1:8443',
          hospitalCode: 'HOSP_DENTAL',
          deviceId: 'DEV-MAIN-HOST',
        );
        await tester.pumpAndSettle();

        final matApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
        expect(matApp.title, equals('Al-Noor Dental Desktop'));
        expect(matApp.themeMode, equals(ThemeMode.dark));
        expect(matApp.darkTheme?.visualDensity, equals(VisualDensity.compact));

        // Sign in as HospitalAdmin
        await controller.loginStaff(identifier: 'ADM-01', password: 'TestPassword!123');
        await tester.pumpAndSettle();

        // Centralized branding appears in top desktop shell bar
        expect(find.text('Al-Noor Dental Desktop'), findsOneWidget);
        expect(find.text('MedCore GOLD'), findsOneWidget);

        // Enabled modules appear in sidebar; disabled modules (Laboratory, Inpatient) are omitted
        expect(find.byKey(const Key('nav_patients')), findsOneWidget);
        expect(find.byKey(const Key('nav_finance_ledger')), findsOneWidget);
        expect(find.byKey(const Key('nav_laboratory')), findsNothing);
        expect(find.byKey(const Key('nav_inpatient')), findsNothing);

        // Ordinary hospital staff shell NEVER exposes Technician Console
        expect(find.byType(TechnicianConsoleScreen), findsNothing);
        expect(find.byKey(const Key('btn_tech_save_config')), findsNothing);

        // Fail-closed route guard if disabled module route is selected programmatically
        controller.selectRoute('laboratory');
        await tester.pumpAndSettle();
        expect(find.text('Module Not Entitled (Laboratory)'), findsOneWidget);
      },
    );

    testWidgets(
      '3. Protected Technician Mode Isolation, Live Configuration Save & Clean Exit',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(1440, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        Map<String, dynamic> activeCfg = _sampleFacilityConfig(
          appDisplayName: 'MedCore Platinum Desktop',
          facilityName: 'Cairo General Hospital',
          facilityType: 'GENERAL_HOSPITAL',
          edition: 'PLATINUM',
          editionLabel: 'MedCore PLATINUM',
          themeMode: 'LIGHT',
          uiDensity: 'STANDARD',
          fontScale: 1.0,
          labEnabled: true,
          inpatientEnabled: true,
        );

        final mockHttp = MockClient((http.Request req) async {
          final path = req.url.path;
          if (path == '/api/v1/technician/session/open') {
            return _okJson({
              'technicianToken': 'mct_isolated_tech_session_999',
              'session': {
                'sessionUuid': 'TSESS-999',
                'hospitalCode': 'HOSP_MAIN',
                'authMethod': 'INSTALLATION_SECRET',
                'deviceId': 'DEV-MAIN-HOST',
                'expiresAt': '2026-10-29T00:00:00Z',
              },
            }, status: 201);
          }
          if (path == '/api/v1/technician/config' && req.method == 'GET') {
            expect(req.headers['x-medcore-tech-token'], equals('mct_isolated_tech_session_999'));
            return _okJson({'configuration': activeCfg});
          }
          if (path == '/api/v1/technician/config' && req.method == 'PUT') {
            expect(req.headers['x-medcore-tech-token'], equals('mct_isolated_tech_session_999'));
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            final branding = Map<String, dynamic>.from(body['branding'] as Map);
            activeCfg = _sampleFacilityConfig(
              appDisplayName: branding['appDisplayName'].toString(),
              facilityName: body['facilityName'].toString(),
              facilityType: body['facilityType'].toString(),
              edition: body['edition'].toString(),
              editionLabel: branding['editionLabel'].toString(),
              themeMode: 'DARK',
              uiDensity: 'COMPACT',
              fontScale: 1.0,
              labEnabled: true,
              inpatientEnabled: true,
              configVersion: 2,
            );
            return _okJson(activeCfg);
          }
          if (path == '/api/v1/technician/session/close') {
            return _okJson({'closed': true});
          }
          return _okJson({});
        });

        final controller = MedCoreAppController(
          apiClient: MedCoreApiClient(httpClient: mockHttp),
        );

        await tester.pumpWidget(MedCorePlatinumDesktopApp(controller: controller));
        await tester.pumpAndSettle();

        await controller.openTechnicianSession(technicianSecret: 'test-only-env-secret');
        await tester.pumpAndSettle();

        expect(find.byType(TechnicianConsoleScreen), findsOneWidget);
        expect(find.text('PROTECTED TECHNICIAN / SERVICE INSTALLATION CONSOLE'), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('input_tech_facility_name')),
          'Alexandria Surgical Institute',
        );
        await tester.tap(find.byKey(const Key('btn_tech_save_config')));
        await tester.pumpAndSettle();

        expect(controller.facilityConfig.facilityName, equals('Alexandria Surgical Institute'));
        expect(controller.facilityConfig.configVersion, equals(2));

        await tester.tap(find.byKey(const Key('btn_tech_exit')));
        await tester.pumpAndSettle();

        expect(controller.isTechnicianModeActive, isFalse);
        expect(find.byType(TechnicianConsoleScreen), findsNothing);
        expect(find.text('Hospital Staff Sign-In'), findsOneWidget);
      },
    );

    testWidgets(
      '4. Facility-Specific Dynamic Patient Fields: HIDDEN Omitted & REQUIRED Enforced',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(1440, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        int postPatientCalls = 0;
        Map<String, dynamic>? submittedPayload;

        final mockHttp = MockClient((http.Request req) async {
          final path = req.url.path;
          if (path == '/api/v1/auth/login') {
            return _okJson({
              'token': 'mcs_rec_01',
              'user': {
                'id': 12,
                'hospitalCode': 'HOSP_DENTAL',
                'staffCode': 'REC-01',
                'fullName': 'Mona Reception',
                'email': 'mona@alnoor.local',
                'role': 'Reception',
                'effectivePermissions': ['dashboard', 'patients', 'patients.write'],
                'operationalFlags': {
                  'canEdit': true,
                  'canDelete': false,
                  'canCollectMoney': false,
                  'canMakeRefunds': false,
                  'refundPolicy': 'none',
                },
              },
            });
          }
          if (path == '/api/v1/product/config') {
            return _okJson(_sampleFacilityConfig(
              appDisplayName: 'Dental Clinic',
              facilityName: 'Dental Clinic',
              facilityType: 'DENTAL_CLINIC',
              edition: 'SILVER',
              editionLabel: 'MedCore SILVER',
              themeMode: 'LIGHT',
              uiDensity: 'STANDARD',
              fontScale: 1.0,
              labEnabled: false,
              inpatientEnabled: false,
              patientFieldsOverride: const {
                'nationalId': 'REQUIRED',
                'allergies': 'OPTIONAL',
                'bloodGroup': 'HIDDEN',
                'inpatientAdmissionNotes': 'HIDDEN',
                'icuTriageNotes': 'HIDDEN',
                'nursingIntakeAssessment': 'HIDDEN',
              },
            ));
          }
          if (path == '/api/v1/patients' && req.method == 'GET') {
            return _okJson({'dataScopeApplied': 'department', 'count': 0, 'items': []});
          }
          if (path == '/api/v1/patients' && req.method == 'POST') {
            postPatientCalls++;
            submittedPayload = jsonDecode(req.body) as Map<String, dynamic>;
            return _okJson({
              'id': 501,
              'mrn': submittedPayload!['mrn'],
              'fullName': submittedPayload!['fullName'],
              'balance': '0.0000',
            }, status: 201);
          }
          return _okJson({});
        });

        final controller = MedCoreAppController(
          apiClient: MedCoreApiClient(httpClient: mockHttp),
        );

        await tester.pumpWidget(MedCorePlatinumDesktopApp(controller: controller));
        await controller.loginStaff(identifier: 'REC-01', password: 'pw');
        controller.selectRoute('patients');
        await tester.pumpAndSettle();

        // HIDDEN hospital-only fields MUST NOT render in Dental Clinic
        expect(find.byKey(const Key('pat_dynamic_bloodGroup')), findsNothing);
        expect(find.byKey(const Key('pat_dynamic_inpatientAdmissionNotes')), findsNothing);
        expect(find.byKey(const Key('pat_dynamic_icuTriageNotes')), findsNothing);
        expect(find.byKey(const Key('pat_dynamic_nursingIntakeAssessment')), findsNothing);

        // REQUIRED & OPTIONAL fields DO render
        expect(find.byKey(const Key('pat_dynamic_nationalId')), findsOneWidget);
        expect(find.byKey(const Key('pat_dynamic_allergies')), findsOneWidget);

        // Fill core fields but leave REQUIRED nationalId blank -> must block submission
        await tester.enterText(find.byKey(const Key('pat_input_mrn')), 'MRN-DENT-01');
        await tester.enterText(find.byKey(const Key('pat_input_fullName')), 'Karim Nabil');
        await tester.enterText(find.byKey(const Key('pat_input_phone')), '01099998888');
        await tester.tap(find.byKey(const Key('btn_register_patient')));
        await tester.pumpAndSettle();

        expect(postPatientCalls, equals(0));
        expect(find.textContaining('Required by facility configuration'), findsOneWidget);

        // Now populate REQUIRED nationalId and submit -> dispatches cleanly with zero hidden fields
        await tester.enterText(find.byKey(const Key('pat_dynamic_nationalId')), '29501011234567');
        await tester.tap(find.byKey(const Key('btn_register_patient')));
        await tester.pumpAndSettle();

        expect(postPatientCalls, equals(1));
        expect(submittedPayload!['nationalId'], equals('29501011234567'));
        expect(submittedPayload!.containsKey('icuTriageNotes'), isFalse);
      },
    );

    testWidgets(
      '5. Patient Financial Ledger Renders Authoritative MariaDB Balances & BACKEND_GAP Disclosures',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(1440, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final mockHttp = MockClient((http.Request req) async {
          final path = req.url.path;
          if (path == '/api/v1/auth/login') {
            return _okJson({
              'token': 'mcs_fin_01',
              'user': {
                'id': 20,
                'hospitalCode': 'HOSP_MAIN',
                'staffCode': 'FIN-01',
                'fullName': 'Hany Accountant',
                'email': 'hany@hosp.local',
                'role': 'Accountant',
                'effectivePermissions': [
                  'dashboard',
                  'patients_all',
                  'finance_Invoices',
                  'finance_Revenue',
                ],
                'operationalFlags': {
                  'canEdit': true,
                  'canDelete': false,
                  'canCollectMoney': true,
                  'canMakeRefunds': true,
                  'refundPolicy': 'approval',
                },
              },
            });
          }
          if (path == '/api/v1/product/config') {
            return _okJson(_sampleFacilityConfig(
              appDisplayName: 'MedCore Platinum Desktop',
              facilityName: 'Cairo General Hospital',
              facilityType: 'GENERAL_HOSPITAL',
              edition: 'PLATINUM',
              editionLabel: 'MedCore PLATINUM',
              themeMode: 'LIGHT',
              uiDensity: 'STANDARD',
              fontScale: 1.0,
              labEnabled: true,
              inpatientEnabled: true,
            ));
          }
          if (path == '/api/v1/patients') {
            return _okJson({
              'dataScopeApplied': 'tenantWide',
              'count': 1,
              'items': [
                {'id': 77, 'mrn': 'MRN-77', 'fullName': 'Tarek Mansour', 'balance': '325.0000'}
              ],
            });
          }
          if (path == '/api/v1/finance/patients/77/ledger') {
            return _okJson({
              'patient': {
                'id': 77,
                'hospitalCode': 'HOSP_MAIN',
                'mrn': 'MRN-77',
                'fullName': 'Tarek Mansour',
                'phone': '01011112222',
                'insuranceCompanyId': 'INS-AXA',
                'insurancePolicyNo': 'POL-900',
              },
              'accountSummary': {
                'currency': 'EGP',
                'authoritativePatientBalance': '325.0000',
                'outstandingPatientDebt': '325.0000',
                'activeVisitsBalanceSum': '325.0000',
                'totalGrossCharges': '1100.0000',
                'totalDiscounts': '100.0000',
                'totalNetBilled': '1000.0000',
                'totalInsuranceResponsibility': '275.0000',
                'totalPatientResponsibility': '725.0000',
                'totalPaymentsCollected': '400.0000',
                'visitsMarkedRefundedAmount': '0.0000',
              },
              'financialAttribution': {
                'hospitalServiceLaborBilled': '700.0000',
                'hospitalRetainedLaborAfterDoctorCommission': '525.0000',
                'hospitalConsumablesBilled': '300.0000',
                'hospitalConsumablesFifoCost': '120.0000',
                'doctorCommissionAccrued': '175.0000',
                'byDepartment': {'SURG': '1000.0000'},
                'byClinic': {'CLN-1': '1000.0000'},
                'byServiceCategory': {'SERVICE': '1000.0000'},
              },
              'visits': [
                {
                  'visitId': 901,
                  'visitNumber': 'VIS-901',
                  'invoiceNumber': 'INV-VIS-901',
                  'visitType': 'OUTPATIENT',
                  'status': 'ACTIVE',
                  'responsibleEntity': 'SHARED_PATIENT_AND_INSURANCE',
                  'grossAmount': '1100.0000',
                  'discountAmount': '100.0000',
                  'netAmount': '1000.0000',
                  'insuranceCoveredAmount': '275.0000',
                  'patientResponsibilityAmount': '725.0000',
                  'paidAmount': '400.0000',
                  'balanceAmount': '325.0000',
                  'createdAt': '2026-10-28T10:00:00Z',
                }
              ],
              'financialHistory': [
                {
                  'entryType': 'VISIT_CHECKOUT',
                  'eventUuid': 'FEV-901',
                  'documentReference': 'INV-VIS-901',
                  'visitNumber': 'VIS-901',
                  'dateUtc': '2026-10-28T10:00:00Z',
                  'responsibleEntity': 'SHARED_PATIENT_AND_INSURANCE',
                  'netAmount': '1000.0000',
                  'paidAmount': '400.0000',
                  'balanceAmount': '325.0000',
                  'doctorCommissionAmount': '175.0000',
                  'postings': [
                    {
                      'direction': 'CREDIT',
                      'accountBucket': 'PAYABLE_COMMISSION_DOCTOR',
                      'amount': '175.0000',
                      'postingType': 'COMMISSION_ACCRUAL',
                      'beneficiaryType': 'DOCTOR',
                      'beneficiaryId': '4',
                    }
                  ],
                }
              ],
              'refundRequests': [],
              'documentedBackendGaps': [
                {
                  'gapId': 'FIN-GAP-REFUND-REVERSAL',
                  'status': 'BACKEND_GAP',
                  'description': 'Refund reversal double-entry leg is documented as BACKEND_GAP.',
                }
              ],
            });
          }
          if (path == '/api/v1/finance/documents/patient-statement/77') {
            return _okJson({
              'documentType': 'PATIENT_STATEMENT',
              'generatedAtUtc': '2026-10-28T10:05:00Z',
              'patient': {'fullName': 'Tarek Mansour', 'mrn': 'MRN-77'},
              'accountSummary': {'authoritativePatientBalance': '325.0000', 'currency': 'EGP'},
              'statementLines': [],
            });
          }
          if (path == '/api/v1/finance/documents/invoice/901') {
            return _okJson({
              'documentType': 'INVOICE',
              'documentNumber': 'INV-VIS-901',
              'visitNumber': 'VIS-901',
              'issuedAt': '2026-10-28T10:00:00Z',
              'status': 'ACTIVE',
              'facility': {'facilityName': 'Cairo General Hospital', 'hospitalCode': 'HOSP_MAIN', 'branchCode': 'MAIN'},
              'patient': {'fullName': 'Tarek Mansour', 'mrn': 'MRN-77'},
              'clinicalContext': {'doctorName': 'Dr. Omar', 'shiftCode': 'SH-01'},
              'lineItems': [],
              'totals': {
                'currency': 'EGP',
                'grossAmount': '1100.0000',
                'discountAmount': '100.0000',
                'netAmount': '1000.0000',
                'insuranceCoveredAmount': '275.0000',
                'patientResponsibilityAmount': '725.0000',
                'paidAmount': '400.0000',
                'balanceDue': '325.0000',
              },
            });
          }
          if (path == '/api/v1/finance/documents/receipt/901') {
            return _okJson({
              'documentType': 'PAYMENT_RECEIPT',
              'receiptNumber': 'RCPT-VIS-901',
              'invoiceNumber': 'INV-VIS-901',
              'visitNumber': 'VIS-901',
              'visitStatus': 'ACTIVE',
              'financialEventUuid': 'FEV-901',
              'collectedAtUtc': '2026-10-28T10:00:00Z',
              'facility': {'facilityName': 'Cairo General Hospital', 'hospitalCode': 'HOSP_MAIN'},
              'patient': {'fullName': 'Tarek Mansour', 'mrn': 'MRN-77'},
              'cashierShift': {'shiftCode': 'SH-01', 'cashierName': 'Hany', 'cashierStaffCode': 'FIN-01'},
              'paymentSummary': {
                'currency': 'EGP',
                'patientResponsibilityAmount': '725.0000',
                'amountReceived': '400.0000',
                'remainingPatientBalanceOnVisit': '325.0000',
              },
            });
          }
          if (path == '/api/v1/finance/reports/outstanding-balances') {
            return _okJson({
              'summary': {
                'patientsWithDebtCount': 1,
                'totalPatientOutstandingBalance': '325.0000',
                'ledgerArPatientBucket': '325.0000',
                'ledgerArInsuranceBucket': '275.0000',
              },
              'patientsWithDebt': [],
              'openReceivableVisits': [],
            });
          }
          if (path == '/api/v1/finance/reports/financial-history') {
            return _okJson({
              'trialBalance': {
                'isBalanced': true,
                'totalDebits': '1395.0000',
                'totalCredits': '1395.0000',
                'buckets': [],
              },
              'events': [],
            });
          }
          if (path == '/api/v1/finance/reports/allocations') {
            return _okJson({
              'doctorCommissionLedger': [],
              'clinicDepartmentAndLabServiceAttribution': [],
              'hospitalComponentSplit': [],
              'documentedBackendGaps': [],
            });
          }
          return _okJson({});
        });

        final controller = MedCoreAppController(
          apiClient: MedCoreApiClient(httpClient: mockHttp),
        );

        await tester.pumpWidget(MedCorePlatinumDesktopApp(controller: controller));
        await controller.loginStaff(identifier: 'FIN-01', password: 'pw');
        controller.openPatientFinancialLedger(77);
        await tester.pumpAndSettle();

        expect(find.textContaining('Outstanding Debt: 325.0000 EGP'), findsOneWidget);

        await tester.drag(
          find.byKey(const Key('ledger_account_scroll')),
          const Offset(0, -650),
        );
        await tester.pumpAndSettle();

        expect(find.text('SHARED_PATIENT_AND_INSURANCE'), findsOneWidget);
        expect(find.textContaining('PAYABLE_COMMISSION_DOCTOR: 175.0000'), findsOneWidget);
        expect(find.textContaining('FIN-GAP-REFUND-REVERSAL'), findsOneWidget);
      },
    );

    testWidgets(
      '6. Network Device Pairing Approval + Maintenance Center Report & Verified Backup Execution',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(1440, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        String? approvedPairingCode;
        bool reportGenerated = false;
        bool backupExecuted = false;

        final mockHttp = MockClient((http.Request req) async {
          final path = req.url.path;
          if (path == '/api/v1/auth/login') {
            return _okJson({
              'token': 'mcs_adm_99',
              'user': {
                'id': 1,
                'hospitalCode': 'HOSP_MAIN',
                'staffCode': 'SUP-01',
                'fullName': 'System Admin',
                'email': 'admin@hosp.local',
                'role': 'SuperAdmin',
                'effectivePermissions': [
                  'dashboard',
                  'settings_Devices',
                  'settings_Backups',
                  'security_Center',
                ],
                'operationalFlags': {
                  'canEdit': true,
                  'canDelete': true,
                  'canCollectMoney': true,
                  'canMakeRefunds': true,
                  'refundPolicy': 'direct',
                },
              },
            });
          }
          if (path == '/api/v1/product/config') {
            return _okJson(_sampleFacilityConfig(
              appDisplayName: 'MedCore Platinum Desktop',
              facilityName: 'Cairo General Hospital',
              facilityType: 'GENERAL_HOSPITAL',
              edition: 'ENTERPRISE_LAN',
              editionLabel: 'MedCore ENTERPRISE_LAN',
              themeMode: 'LIGHT',
              uiDensity: 'STANDARD',
              fontScale: 1.0,
              labEnabled: true,
              inpatientEnabled: true,
            ));
          }
          if (path == '/api/v1/network/topology') {
            return _okJson({
              'hospitalCode': 'HOSP_MAIN',
              'connectionModes': {
                'connectViaLanEnabled': true,
                'connectViaWifiEnabled': true,
                'maxAuthorizedDevices': 25,
              },
              'securityPosture': {
                'discoveryEqualsAuthorization': false,
                'mariaDbHost': '127.0.0.1',
                'mariaDbPort': 3307,
                'mariaDbLoopbackOnlyEnforced': true,
                'tlsCertificateRuntimeStatus': 'TLS_CERT_INFRASTRUCTURE_PENDING',
                'tlsNotice': 'mTLS runtime pending.',
              },
              'summary': {
                'totalDevices': 2,
                'activeCount': 1,
                'pendingCount': 1,
                'revokedCount': 0,
              },
              'devices': [
                {
                  'deviceId': 'DEV-WIFI-NURSE-02',
                  'deviceName': 'Nurse Tablet 02',
                  'ip': '192.168.10.42',
                  'connectionType': 'WIFI',
                  'status': approvedPairingCode == 'A7B9K2' ? 'ACTIVE' : 'PENDING',
                  'medcoreVersion': '1.0.0-rc.1',
                  'role': 'TABLET_CLINICAL',
                  'isTrustedSecureRuntime': true,
                  'lastSeen': '2026-10-28T12:00:00Z',
                  'requiresPairingCodeVerification': approvedPairingCode != 'A7B9K2',
                }
              ],
            });
          }
          if (path == '/api/v1/network/devices/DEV-WIFI-NURSE-02/approve') {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            approvedPairingCode = body['pairingVerificationCode']?.toString();
            return _okJson({'deviceId': 'DEV-WIFI-NURSE-02', 'status': 'ACTIVE'});
          }
          if (path == '/api/v1/maintenance/overview') {
            return _okJson({
              'overallStatus': 'HEALTHY',
              'applicationVersion': '1.0.0-rc.1',
              'facilityName': 'Cairo General Hospital',
              'serviceStatus': {'status': 'RUNNING', 'operationalMode': 'LOCAL_FIRST', 'boundPort': 8443},
              'databaseStatus': {'engine': 'MariaDB', 'serverVersion': '11.4.4-MariaDB', 'databaseName': 'medcore_local', 'loopbackIsolated': true},
              'migrationStatus': {'appliedCount': 15, 'latestVersion': 'V015'},
              'storageStatus': {'tableCount': 98, 'totalBytes': 1048576, 'approxTotalRows': 240},
              'securityStatus': {'clockGuardStatus': 'OK', 'securityRootAnchored': true, 'activeStaffSessions': 1, 'activeTechnicianSessions': 0},
              'licenseStatus': {'edition': 'ENTERPRISE_LAN', 'status': 'ACTIVE'},
              'networkStatus': {'activeDevicesCount': 2, 'pendingPairingCount': 0, 'allowLanConnections': true, 'allowWifiConnections': true},
              'diagnostics': {
                'financialTrialBalance': {'balanced': true, 'totalDebits': '500.0000', 'totalCredits': '500.0000', 'postedEntriesCount': 6},
                'openCashierShiftsCount': 1,
                'pendingDualControlRequestsCount': 0,
              },
              'backupStatus': {'configuredProvider': 'LOCAL_STORAGE', 'totalRecordedRuns': backupExecuted ? 1 : 0, 'recentRuns': []},
              'logs': {'securityLogs': [], 'auditLogs': []},
              'errors': [],
              'maintenanceHistory': {'generatedReports': [], 'consumedAuthorityTokens': []},
            });
          }
          if (path == '/api/v1/backups/status') {
            return _okJson({
              'pipelineStages': [
                '1_MARIADB_SNAPSHOT',
                '2_GZIP_COMPRESS',
                '3_AUTHENTICATED_ENCRYPT',
                '4_SHA256_CHECKSUM',
                '5_PROVIDER_UPLOAD',
                '6_INDEPENDENT_READBACK_VERIFICATION',
              ],
            });
          }
          if (path == '/api/v1/maintenance/reports' && req.method == 'POST') {
            reportGenerated = true;
            return _okJson({
              'reportUuid': 'MREP-2026-0001',
              'overallStatus': 'HEALTHY',
              'redactionPolicy': 'PII_AND_SECRETS_EXCLUDED',
            }, status: 201);
          }
          if (path == '/api/v1/backups/run' && req.method == 'POST') {
            backupExecuted = true;
            return _okJson({
              'backupUuid': 'BK-2026-0001',
              'status': 'VERIFIED',
              'archiveSha256': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
              'readBackVerified': true,
            }, status: 201);
          }
          return _okJson({});
        });

        final controller = MedCoreAppController(
          apiClient: MedCoreApiClient(httpClient: mockHttp),
        );

        await tester.pumpWidget(MedCorePlatinumDesktopApp(controller: controller));
        await controller.loginStaff(identifier: 'SUP-01', password: 'pw');

        // Navigate to Network & Devices
        controller.selectRoute('network_devices');
        await tester.pumpAndSettle();

        expect(find.text('127.0.0.1 LOOPBACK ONLY'), findsOneWidget);
        expect(find.textContaining('TLS_CERT_INFRASTRUCTURE_PENDING'), findsOneWidget);
        final approveBtn = find.byKey(const Key('btn_approve_device_DEV-WIFI-NURSE-02'));
        expect(approveBtn, findsOneWidget);
        await tester.ensureVisible(approveBtn);
        await tester.pumpAndSettle();

        await tester.tap(approveBtn);
        await tester.pumpAndSettle();

        await tester.enterText(find.byKey(const Key('input_approve_pairing_code')), 'a7b9k2');
        await tester.tap(find.byKey(const Key('btn_confirm_approve_device')));
        await tester.pumpAndSettle();

        expect(approvedPairingCode, equals('A7B9K2'));

        // Navigate to Maintenance Center
        controller.selectRoute('maintenance_center');
        await tester.pumpAndSettle();

        expect(find.text('15 Applied (Latest: V015)'), findsOneWidget);
        expect(find.text('BALANCED (PASS)'), findsOneWidget);

        await tester.tap(find.byKey(const Key('btn_run_verified_backup')));
        await tester.pumpAndSettle();
        expect(backupExecuted, isTrue);
        expect(find.textContaining('BK-2026-0001'), findsOneWidget);

        await tester.tap(find.byKey(const Key('btn_generate_maintenance_report')));
        await tester.pumpAndSettle();
        expect(reportGenerated, isTrue);
        expect(find.textContaining('MREP-2026-0001'), findsNWidgets(2));
      },
    );
  });
}

http.Response _okJson(Map<String, dynamic> data, {int status = 200}) {
  return http.Response(
    jsonEncode({'ok': true, 'data': data}),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

Map<String, dynamic> _sampleFacilityConfig({
  required String appDisplayName,
  required String facilityName,
  required String facilityType,
  required String edition,
  required String editionLabel,
  required String themeMode,
  required String uiDensity,
  required double fontScale,
  required bool labEnabled,
  required bool inpatientEnabled,
  int configVersion = 1,
  Map<String, String>? patientFieldsOverride,
}) {
  return {
    'hospitalCode': 'HOSP_MAIN',
    'facilityName': facilityName,
    'facilityType': facilityType,
    'branchCode': 'MAIN',
    'installationIdentity': 'INST-HOSP_MAIN',
    'edition': edition,
    'configVersion': configVersion,
    'enabledModules': {
      'Patients': true,
      'Appointments': true,
      'Reception': true,
      'Shifts': true,
      'Doctors': true,
      'Nursing': inpatientEnabled,
      'Inpatient': inpatientEnabled,
      'ICU': false,
      'Surgery': inpatientEnabled,
      'Dialysis': false,
      'Laboratory': labEnabled,
      'Radiology': labEnabled,
      'Pharmacy': true,
      'Finance': true,
      'CommandCenter': true,
      'HR': true,
      'AI': false,
    },
    'patientFields': patientFieldsOverride ??
        {
          'dateOfBirth': 'OPTIONAL',
          'age': 'OPTIONAL',
          'nationalId': 'OPTIONAL',
          'bloodGroup': 'OPTIONAL',
          'address': 'OPTIONAL',
          'insuranceCompanyId': 'OPTIONAL',
          'insurancePolicyNo': 'OPTIONAL',
          'emergencyContactName': 'OPTIONAL',
          'emergencyContactPhone': 'OPTIONAL',
          'allergies': 'OPTIONAL',
          'chronicConditions': 'OPTIONAL',
          'inpatientAdmissionNotes': 'OPTIONAL',
          'icuTriageNotes': 'OPTIONAL',
          'nursingIntakeAssessment': 'OPTIONAL',
        },
    'patientFieldCatalog': {
      'nationalId': {'label': 'National ID / Passport', 'category': 'DEMOGRAPHICS'},
      'allergies': {'label': 'Known Allergies', 'category': 'CLINICAL'},
      'bloodGroup': {'label': 'Blood Group', 'category': 'CLINICAL'},
      'inpatientAdmissionNotes': {'label': 'Inpatient Pre-Admission Intake', 'category': 'INPATIENT'},
      'icuTriageNotes': {'label': 'ICU Acuity Notes', 'category': 'ICU'},
      'nursingIntakeAssessment': {'label': 'Nursing Intake Notes', 'category': 'NURSING'},
    },
    'branding': {
      'appDisplayName': appDisplayName,
      'facilityDisplayName': facilityName,
      'editionLabel': editionLabel,
      'primaryColorHex': '#1D4ED8',
      'themeMode': themeMode,
      'fontScale': fontScale,
      'uiDensity': uiDensity,
    },
    'networkConfig': {
      'allowLanConnections': true,
      'allowWifiConnections': true,
      'maxAuthorizedDevices': 25,
    },
    'backupConfig': {
      'activeProvider': 'LOCAL_STORAGE',
      'localBackupDirectory': 'backups/local',
    },
    'remoteHybridConfig': {
      'operationalMode': 'LOCAL_FIRST',
      'futureOptionalRemoteReportingReady': false,
    },
  };
}
