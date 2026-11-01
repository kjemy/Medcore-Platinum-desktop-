# MEDCORE PLATINUM — READ-ONLY SCREEN & TAB PARITY MATRIX
# WEB NAVIGATION vs PLATINUM NAVIGATION FORENSIC COMPARISON

- **AUDIT TYPE**: STRICTLY READ-ONLY FORENSIC AUDIT
- **GOVERNANCE AUTHORITY**: Khaled Universal Engineering Constitution (`Khaled All Rules`)
- **DATE OF EXECUTION**: 2026-11-01
- **CODE CHANGES**: 0
- **DATABASE MUTATIONS**: 0
- **GIT CHANGES**: 0
- **DEPLOYMENT**: 0

---

## 1. COMPREHENSIVE SCREEN & NAVIGATION PARITY MATRIX

| # | Web Navigation Route | Web Display Label | Platinum Navigation Route | Platinum Screen Widget | Match Status | Missing Sub-components / Capabilities in Platinum | Notes & Forensic Reality |
|---|---|---|---|---|:---:|---|---|
| 01 | `/dashboard` | الرئيسية (Dashboard) | `dashboard` | `ExecutiveDashboardScreen` | **MATCH** | AI KPI narrative analysis | Core revenue metrics and patient stats match |
| 02 | `/dashboard/ai-doctor` | الطبيب الاصطناعي (AI) | N/A | None | **MISSING** | Entire AI copilot screen & prompt chat | Deferred in Platinum local architecture |
| 03 | `/dashboard/admin-ai` | مجلس الإدارة الذكي (AI Board) | N/A | None | **MISSING** | Entire AI analytics dashboard | Deferred in Platinum architecture |
| 04 | `/dashboard/reports` | التقارير والإحصائيات | `finance_ledger` (Reports Tab) | `PatientFinancialLedgerScreen` | **PARTIAL** | Interactive drilldown report generator | Platinum provides financial reports & exports |
| 05 | `/dashboard/reception` | شاشة الاستقبال (Reception) | `reception_visits` | `ShiftsAndVisitsScreen` | **PARTIAL** | Clinic cards grid, countdown timers, quick check-in | Platinum reception is a single checkout form |
| 06 | `/dashboard/reception/waiting` | قائمة الانتظار الحية | N/A | None | **MISSING** | Live waiting room queue & patient caller | Platinum has no dedicated waiting room screen |
| 07 | `/dashboard/reception?tab=staff-attendance`| طاقم العمل | N/A | None | **MISSING** | Shift attendance check-in tab | Managed via general staff accounts |
| 08 | `/dashboard/appointments` | المواعيد | `appointments` | `ClinicalModulesHubScreen` | **MATCH** | Advanced recurrence rules | Core appointment booking matches |
| 09 | `/dashboard/reception/inventory` | مخزن الاستقبال | N/A | None | **MISSING** | Reception front-desk stationery & forms store | Platinum does not isolate reception store |
| 10 | `/dashboard/reception/clinic/[id]` | عيادة الاستقبال | N/A | None | **MISSING** | Room tablet queue view | Platinum has no per-room tablet route |
| 11 | `/dashboard/patients` | سجل المرضى | `patients` | `PatientsWorkspaceScreen` | **MATCH** | Insurance verification status badge | Full CRUD and search match |
| 12 | `/dashboard/patients/insurance` | مرضى التأمين | N/A | None | **MISSING** | Dedicated insured patient worklist & claim pre-auth | Platinum manages insurance as a visit discount |
| 13 | `/dashboard/clinics/examination` | كشف الطبيب (History) | `doctors` | `ClinicalModulesHubScreen` | **MATCH** | Filter by clinic card | Encounter history and notes match |
| 14 | `/dashboard/clinics/doctor` | الكشف الطبي والحالة (Queue) | `doctors` | `ClinicalModulesHubScreen` | **MATCH** | Clinic card assignment | Doctor queue and encounter desk match |
| 15 | `/dashboard/clinics/templates` | نماذج الكشف | `clinical_templates` | `ClinicalTemplateEditorScreen` | **MATCH** | None | Full parity; Platinum has full designer |
| 16 | `/dashboard/clinics/inventory` | مخزن عهدة العيادة | N/A | None | **MISSING** | Outpatient clinic room consumable cabinet | Platinum has central inventory items only |
| 17 | `/dashboard/clinical/surgery-booking` | حجز العمليات | `specialty_units` | `ClinicalModulesHubScreen` (Card) | **BACKEND_ONLY** | Interactive OR scheduling calendar | Platinum has backend `/api/v1/clinical/surgeries` |
| 18 | `/dashboard/clinical/surgeries` | العمليات (Operating Theater) | `specialty_units` | `ClinicalModulesHubScreen` (Card) | **BACKEND_ONLY** | Surgical flowsheets, anesthesia notes | Platinum UI displays informational card only |
| 19 | `/dashboard/clinical/surgeries-inventory` | مخزن عهدة العمليات | N/A | None | **MISSING** | Theater sterile kits and sutures store | Central inventory only in Platinum |
| 20 | `/dashboard/clinical/nicu` | الحضانات (NICU) | `specialty_units` | `ClinicalModulesHubScreen` (Card) | **BACKEND_ONLY** | Incubator station flowsheet, phototherapy tracking | Backend support only |
| 21 | `/dashboard/clinical/nicu-inventory` | مخزن عهدة الحضانات | N/A | None | **MISSING** | NICU formula, feeds, and cannula store | Central inventory only in Platinum |
| 22 | `/dashboard/clinical/icu` | العناية المركزة (ICU) | `specialty_units` | `ClinicalModulesHubScreen` (Card) | **BACKEND_ONLY** | Interactive SOFA/APACHE score sheet & vitals monitor| Backend `/api/v1/clinical/icu/*` exists |
| 23 | `/dashboard/clinical/icu-inventory` | مخزن عهدة العناية | N/A | None | **MISSING** | Emergency crash cart and airway tray | Central inventory only in Platinum |
| 24 | `/dashboard/diagnostics/lab` | قسم المعمل (LIS) | `laboratory` | `ClinicalModulesHubScreen` | **MATCH** | Reference range highlight & barcoding | Test list, result entry, panic flags match |
| 25 | `/dashboard/diagnostics/lab-inventory` | مخزن عهدة المعمل | N/A | None | **MISSING** | Reagents, chemistry controls, vacuum tubes store | Central inventory only in Platinum |
| 26 | `/dashboard/diagnostics/radiology` | قسم الأشعة (RIS) | `radiology` | `ClinicalModulesHubScreen` | **MATCH** | PACS / DICOM viewer integration | Worklist and exam recording match |
| 27 | `/dashboard/diagnostics/radiology-inventory`| مخزن عهدة الأشعة | N/A | None | **MISSING** | Contrast media, syringes, lead aprons store | Central inventory only in Platinum |
| 28 | `/dashboard/clinical/rooms` | قسم الغرف (Inpatient) | `inpatient` | `ClinicalModulesHubScreen` | **MATCH** | Room deposit & daily rate configuration | Bed status map, admissions, discharges match |
| 29 | `/dashboard/clinical/rooms-inventory` | مخزن عهدة الغرف | N/A | None | **MISSING** | Ward linens, gowns, and dressings store | Central inventory only in Platinum |
| 30 | `/dashboard/clinical/endoscopy` | المناظير | N/A | None | **MISSING** | Dedicated endoscopy documentation screen | Not implemented in Platinum |
| 31 | `/dashboard/clinical/oncology` | الأورام | N/A | None | **MISSING** | Chemotherapy cycle scheduling & staging | Not implemented in Platinum |
| 32 | `/dashboard/clinical/physiotherapy` | العلاج الطبيعي | N/A | None | **MISSING** | Physical therapy rehabilitation notes | Not implemented in Platinum |
| 33 | `/dashboard/clinical/dialysis` | غسيل الكلى (Hemodialysis) | `specialty_units` | `ClinicalModulesHubScreen` (Card) | **BACKEND_ONLY** | Machine scheduling & fluid removal tracking | Backend `/api/v1/clinical/dialysis/*` exists |
| 34 | `/dashboard/clinical/dialysis/sessions` | جلسات غسيل الكلى | `specialty_units` | `ClinicalModulesHubScreen` (Card) | **BACKEND_ONLY** | Session flowsheet, pre/post weights & pressures | Backend `/api/v1/clinical/dialysis/sessions` |
| 35 | `/dashboard/clinical/dialysis-inventory` | مخزن عهدة غسيل الكلى | N/A | None | **MISSING** | Dialyzers, acid concentrates, heparin store | Central inventory only in Platinum |
| 36 | `/dashboard/nursing-management` | إدارة التمريض | N/A | None | **MISSING** | Nursing supervisor assignment console | Not implemented in Platinum |
| 37 | `/dashboard/my-nursing-tasks` | مهامي (التمريض) | `specialty_units` | `ClinicalModulesHubScreen` (Card) | **BACKEND_ONLY** | Interactive task checklist with check-off boxes | Backend `/api/v1/clinical/nursing/tasks` exists |
| 38 | `/dashboard/inventory/central-dispense` | المخزن العام السريع | N/A | None | **MISSING** | One-click barcode dispensing console | Not implemented in Platinum |
| 39 | `/dashboard/inventory/main` | المخزون والمخازن | `pharmacy` | `ClinicalModulesHubScreen` | **PARTIAL** | Multi-warehouse transfer, item creation UI | Platinum lists items and stock batches |
| 40 | `/dashboard/inventory/dispense` | طلبات صرف العهدة | N/A | None | **MISSING** | Internal requisition workflow | Platinum has prescription dispensing only |
| 41 | `/dashboard/pharmacy/catalog` | دليل الأدوية | `pharmacy` | `ClinicalModulesHubScreen` | **MATCH** | Drug therapeutic class classification | Lists drug items, strengths, units |
| 42 | `/dashboard/pharmacy/interactions` | تداخلات الأدوية | N/A | None | **MISSING** | Drug interaction safety engine | Not implemented in Platinum |
| 43 | `/dashboard/pharmacy/pos` | نقطة بيع الصيدلية (POS) | N/A | None | **MISSING** | POS cart checkout with barcode scanner | Platinum has visit checkout only |
| 44 | `/dashboard/inventory/prices` | أسعار المخزون | N/A | None | **MISSING** | Markup rules & price adjustment studio | Platinum items have fixed cost lines |
| 45 | `/dashboard/hr/my-portal` | بوابة الموظف الذاتية | N/A | None | **MISSING** | Self-service profile, shift view, attendance history | Staff sees profile info in header only |
| 46 | `/dashboard/hr/nursing` | بوابة التمريض | N/A | None | **MISSING** | Nurse roster & ward allocation screen | Not implemented in Platinum |
| 47 | `/dashboard/hr/recruitment` | التوظيف | N/A | None | **MISSING** | Job applicants and interviews pipeline | Not implemented in Platinum |
| 48 | `/dashboard/hr/schedules` | مواعيد العمل والشيفتات | `resource_scheduling` | `ResourceSchedulingManagementScreen` | **PARTIAL** | Employee shift rotas & off-day schedules | Platinum focuses on resource booking rules |
| 49 | `/dashboard/hr/attendance` | الحضور والانصراف | N/A | None | **MISSING** | Biometric / daily attendance logs & hours | Not implemented in Platinum |
| 50 | `/dashboard/hr/payroll` | حسابات العاملين والرواتب | N/A | None | **MISSING** | Monthly payroll generation, deductions, bonuses | Platinum settles payables individually |
| 51 | `/dashboard/hr/attendance-kiosk` | كشك الحضور | N/A | None | **MISSING** | Kiosk full-screen terminal PIN punch-in | Not implemented in Platinum |
| 52 | `/dashboard/hr/investigations` | تحقيقات الموظفين | N/A | None | **MISSING** | Legal HR investigations and penalty registry | Platinum has employee audit trail only |
| 53 | `/dashboard/withdrawals` | طلبات استلام الأرباح | `finance_ledger` (Payables) | `PatientFinancialLedgerScreen` | **PARTIAL** | Staff-initiated commission withdrawal workflow | Handled via External Payables in Platinum |
| 54 | `/dashboard/finance/treasury` | الخزينة والماليات | `reception_visits` & `finance_ledger` | `ShiftsAndVisitsScreen` | **MATCH** | Safe expense vouchers | Cash shift balance & AR collections match |
| 55 | `/dashboard/finance/payroll` | المرتبات والحوافز | `finance_ledger` (Payables) | `PatientFinancialLedgerScreen` | **PARTIAL** | Bulk salary payout batching | Settled as external payables |
| 56 | `/dashboard/finance/doctor-profits` | أرباح وعمولات الأطباء | `finance_ledger` (Reports) | `PatientFinancialLedgerScreen` | **PARTIAL** | Automated tariff calculation per clinic | Platinum visit records doctor commission % |
| 57 | `/dashboard/finance/contracts` | الأسعار والتعاقدات | N/A | None | **MISSING** | Tariff definition studio for corporate/insurance | Not implemented in Platinum |
| 58 | `/dashboard/finance/settlements` | سجل تسليم الأرباح | `finance_ledger` (Payables) | `PatientFinancialLedgerScreen` | **MATCH** | Cash settlement receipts | Dual-control settlements supported |
| 59 | `/dashboard/finance` | لوحة المالية الرئيسية | `finance_ledger` | `PatientFinancialLedgerScreen` | **MATCH** | Detailed balance sheet drilldown | AR ledger, statements, reports match |
| 60 | `/dashboard/quality/investigations` | حالات التحقيق والمخالفات | N/A | None | **MISSING** | Incident & medical malpractice incident reports | Not implemented in Platinum |
| 61 | `/dashboard/quality/infection` | مكافحة العدوى | N/A | None | **MISSING** | Nosocomial infection surveillance & cultures | Not implemented in Platinum |
| 62 | `/dashboard/quality/control` | مراقبة الجودة | N/A | None | **MISSING** | Clinical quality KPIs and compliance checklists | Not implemented in Platinum |
| 63 | `/dashboard/complaints` | الشكاوى والملاحظات | N/A | None | **MISSING** | Patient complaint registration and ticketing | Not implemented in Platinum |
| 64 | `/dashboard/doctors` | أطباء المجمع والعمولات | `doctors` | `ClinicalModulesHubScreen` | **MATCH** | Clinic-specific consultation fees | Doctor queue and encounter list match |
| 65 | `/dashboard/settings/definitions` | التعريفات والمدخلات (Master Data)| N/A | None | **MISSING** | Full 21-domain master data management studio | Schema table mc_definitions has no UI |
| 66 | `/dashboard/settings/roles` | الصلاحيات والأدوار (RBAC) | `staff_admin` | `AdminEmployeeManagementScreen` | **PARTIAL** | Visual permission matrix & custom permissions | Platinum UI only sets coarse role |
| 67 | `/dashboard/settings/security` | تأمين النظام | `technician` | `TechnicianConsoleScreen` | **MATCH** | Screen timeout lock PIN | Hardware machine binding & secret rotation |
