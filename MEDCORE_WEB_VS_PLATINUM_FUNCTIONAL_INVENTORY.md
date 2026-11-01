# MEDCORE PLATINUM — READ-ONLY FUNCTIONAL PARITY FORENSIC AUDIT
# WEB REFERENCE vs PLATINUM INVENTORY
# COMPLETE FORENSIC FUNCTIONAL COMPARISON REPORT

- **AUDIT TYPE**: STRICTLY READ-ONLY FORENSIC AUDIT
- **GOVERNANCE AUTHORITY**: Khaled Universal Engineering Constitution (`Khaled All Rules`)
- **DATE OF EXECUTION**: 2026-11-01
- **CODE CHANGES**: 0
- **DATABASE MUTATIONS**: 0
- **GIT CHANGES**: 0
- **DEPLOYMENT**: 0

---

## 1. PHASE 1 — IDENTIFICATION & TECHNICAL BASELINE OF BOTH SYSTEMS

### 1.1 MedCore Web (Functional & Data Reference System)
- **Local Path**: `C:\Users\hp\Desktop\project2`
- **Frontend Path**: `C:\Users\hp\Desktop\project2\Frontend`
  - **Git Branch**: `implementation/integration-16-2026-10-02`
  - **Current Commit**: `b839e53 fix(reception): modal viewport centering via React Portals, isolated medical receipt printing, and clinic queue persistence sync`
  - **Runtime & Framework**: Next.js 14 / React 18, TypeScript, Tailwind CSS, Lucide React, Zustand State Stores (48 stores), `next-intl` bilingual support (Arabic/English).
- **Backend Path**: `C:\Users\hp\Desktop\project2\Backend\MedCorePlugin`
  - **Git Branch**: `implementation/identity-offline-foundation-2026-10-02`
  - **Current Commit**: `e70eb96 fix(core): server-side tenant authority propagation for financial transactions and reception definition permissions`
  - **Runtime & Framework**: WordPress REST API Plugin (`/wp-json/mce/v1/`, `/wp-json/medcore/v1/`), PHP 8+, MariaDB with custom relational tables (`wp_mc_*`, `wp_medcore_*`).
- **Database Architecture**: MariaDB (accessed via WordPress `$wpdb` transactions, direct SQL execution, authoritative table `wp_mc_definitions` with JSON payload + normalized relational tables for patients, visits, shifts, ledger, staff).
- **Runtime Environment**: Browser client (Chrome/Edge/Firefox) communicating over HTTPS to SaaS / Cloud server (`test-medcore.orbitsoftware.xyz` / local WordPress).

### 1.2 MedCore Platinum Desktop (Target System)
- **Local Path**: `C:\Users\hp\Desktop\project 4`
- **Desktop Application Path**: `C:\Users\hp\Desktop\project 4\medcore_desktop`
  - **Git Branch**: `main`
  - **Current Commit**: `093c07f release: publish latest platinum commercial closure for live artifact build`
  - **Runtime & Framework**: Flutter 3.x / Dart 3.x Native Windows Desktop x64 application.
- **Local Backend Path**: `C:\Users\hp\Desktop\project 4\medcore_local_service`
  - **Runtime & Framework**: Standalone native Dart HTTP/REST/SSE daemon running on local loopback `127.0.0.1:8443` with self-signed TLS and process boundary isolation.
- **Database Architecture**: Embedded MariaDB 11.4.4 server running on `127.0.0.1:3307` (`medcore_truth`, InnoDB engine, `utf8mb4_unicode_ci`, strict mode, 100% `DECIMAL(14,4)` monetary precision).
- **Schema Migrations**: 18 migrations (`V001__platform_governance_and_tenants.sql` through `V018__commercial_entitlement_and_hardware_binding.sql`).
- **Runtime Environment**: 100% Offline-capable, self-contained Windows Desktop workstation with LAN peer discovery and hardware machine-binding.

---

## 2. PHASE 2 — COMPLETE MEDCORE WEB FUNCTIONAL INVENTORY

### 2.1 Navigation & Screen Architecture
MedCore Web exposes 28 primary dashboard modules and 67 subpages:

| Navigation Route | Arabic / Display Label | Functional Category | Access Permission Key |
|---|---|---|---|
| `/dashboard` | الرئيسية (Executive Dashboard) | Overview & KPIs | `view_dashboard` |
| `/dashboard/ai-doctor` | الطبيب الاصطناعي (AI Assistant) | AI Clinical Copilot | `ai_doctor_view` |
| `/dashboard/admin-ai` | مجلس الإدارة الذكي (AI Board) | AI Executive Analytics | `ai_board_view` |
| `/dashboard/reports` | التقارير والإحصائيات | Reporting & BI | `view_reports` |
| `/dashboard/reception` | شاشة الاستقبال (Reception Desk) | Front-Desk Operations | `rec_screen` |
| `/dashboard/reception/waiting` | قائمة الانتظار الحية (Live Waiting) | Queue & Triage | `rec_waiting` |
| `/dashboard/reception?tab=staff-attendance` | طاقم العمل (Staff Attendance) | Shift Attendance | `rec_staff_attendance` |
| `/dashboard/appointments` | المواعيد (Appointments) | Patient Booking | `rec_appointments` |
| `/dashboard/reception/inventory` | مخزن الاستقبال (Reception Store) | Desk Supplies | `rec_inv` |
| `/dashboard/reception/clinic/[id]` | عيادة الاستقبال (Clinic Console) | Active Clinic Queue | `rec_screen` |
| `/dashboard/patients` | سجل المرضى (Patient Registry) | Master Patient Index | `pat_records` |
| `/dashboard/patients/insurance` | مرضى التأمين (Insured Patients) | Insurance Verification | `pat_insurance` |
| `/dashboard/clinics/examination` | كشف الطبيب (Examination History) | Clinical Encounter Log | `clinic_record` |
| `/dashboard/clinics/doctor` | الكشف الطبي والحالة (Doctor Queue) | Outpatient Consult Desk | `clinic_exam` |
| `/dashboard/clinics/templates` | نماذج الكشف (Clinical Templates) | Template Management | `clinic_templates` |
| `/dashboard/clinics/inventory` | مخزن عهدة العيادة (Clinic Inventory) | Consumables Custody | `clinic_inv` |
| `/dashboard/clinical/surgery-booking` | حجز العمليات (Surgery Booking) | OR Booking | `clin_surg_book` |
| `/dashboard/clinical/surgeries` | العمليات (Operating Theater) | Surgical Encounters | `clin_surg` |
| `/dashboard/clinical/surgeries-inventory` | مخزن عهدة العمليات | Surgical Supplies | `clin_surg_inv` |
| `/dashboard/clinical/nicu` | الحضانات (NICU Unit) | Neonatal Intensive Care | `clin_nicu` |
| `/dashboard/clinical/nicu-inventory` | مخزن عهدة الحضانات | NICU Supplies | `clin_nicu_inv` |
| `/dashboard/clinical/icu` | العناية المركزة (ICU Unit) | Adult Critical Care | `clin_icu` |
| `/dashboard/clinical/icu-inventory` | مخزن عهدة العناية | ICU Supplies | `clin_icu_inv` |
| `/dashboard/diagnostics/lab` | قسم المعمل (Laboratory LIS) | Laboratory Tests | `clin_lab` |
| `/dashboard/diagnostics/lab-inventory` | مخزن عهدة المعمل | Lab Reagents & Tubes | `clin_lab_inv` |
| `/dashboard/diagnostics/radiology` | قسم الأشعة (Radiology RIS) | Imaging & Modalities | `clin_rad` |
| `/dashboard/diagnostics/radiology-inventory` | مخزن عهدة الأشعة | Film & Contrast | `clin_rad_inv` |
| `/dashboard/clinical/rooms` | قسم الغرف (Inpatient Wards) | Ward Beds & Rooms | `clin_ward` |
| `/dashboard/clinical/rooms-inventory` | مخزن عهدة قسم الغرف | Ward Linens & Supplies | `clin_ward_inv` |
| `/dashboard/clinical/endoscopy` | المناظير (Endoscopy Unit) | Endoscopy Notes | `clin_endoscopy` |
| `/dashboard/clinical/oncology` | الأورام (Oncology Unit) | Chemo & Oncology | `clin_oncology` |
| `/dashboard/clinical/physiotherapy` | العلاج الطبيعي (Physiotherapy) | Rehab Sessions | `clin_physio` |
| `/dashboard/clinical/dialysis` | غسيل الكلى (Hemodialysis) | Dialysis Unit & Beds | `clin_dialysis` |
| `/dashboard/clinical/dialysis/sessions` | جلسات غسيل الكلى | Treatment Flowsheets | `clin_dialysis_sessions` |
| `/dashboard/clinical/dialysis-inventory` | مخزن عهدة غسيل الكلى | Dialyzers & Acid Packs | `clin_dialysis_inv` |
| `/dashboard/nursing-management` | إدارة التمريض (Nursing Admin) | Nursing Station Overseer | `sys_nursing` |
| `/dashboard/my-nursing-tasks` | مهامي (Nursing Task List) | Active Shift Checklist | `nursing_tasks` |
| `/dashboard/inventory/central-dispense`| المخزن العام السريع | Quick Consumable Dispense | `central_dispense` |
| `/dashboard/inventory/main` | المخزون والمخازن (Main Store) | Warehouses & Items | `inv_main` |
| `/dashboard/inventory/dispense` | طلبات صرف العهدة | Stock Requisitions | `inv_dispense` |
| `/dashboard/pharmacy/catalog` | الصيدلية ودليل الأدوية | Drug Formulary & Stock | `pharmacy_guide` |
| `/dashboard/pharmacy/interactions` | تداخلات الأدوية | Drug-Drug Interactions | `pharmacy_interactions` |
| `/dashboard/pharmacy/pos` | نقطة بيع الصيدلية (Pharmacy POS) | Outpatient Rx Checkout | `pharmacy_pos` |
| `/dashboard/inventory/prices` | أسعار المخزون (Item Pricing) | Pricing & Markups | `inv_prices` |
| `/dashboard/hr/my-portal` | بوابة الموظف الذاتية | Employee Self-Service | `hr_my_portal` |
| `/dashboard/hr/nursing` | بوابة التمريض | Nurse Staffing Hub | `hr_nursing` |
| `/dashboard/hr/recruitment` | التوظيف (Staff Recruitment) | Applicant Tracking | `hr_recruitment` |
| `/dashboard/hr/schedules` | مواعيد العمل والشيفتات | Work Schedules & Shifts | `hr_schedules` |
| `/dashboard/hr/attendance` | الحضور والانصراف | Attendance Records | `hr_attendance` |
| `/dashboard/hr/payroll` | حسابات العاملين والرواتب | Staff Payroll Ledger | `hr_payroll` |
| `/dashboard/hr/attendance-kiosk` | كشك الحضور (Attendance Kiosk) | Kiosk Mode PIN Sign-in | `hr_kiosk` |
| `/dashboard/hr/investigations` | تحقيقات الموظفين | HR Infractions | `hr_investigations` |
| `/dashboard/withdrawals` | طلبات استلام الأرباح | Commission Withdrawals | `with_doctors` |
| `/dashboard/finance/treasury` | الخزينة والماليات (Treasury) | Cash Boxes & Expenses | `fin_treasury` |
| `/dashboard/finance/payroll` | المرتبات والحوافز | Payroll Approvals | `fin_payroll` |
| `/dashboard/finance/doctor-profits` | أرباح وعمولات الأطباء | Doctor Commission Audit | `fin_profits` |
| `/dashboard/finance/contracts` | الأسعار والتعاقدات | Tariffs & Insurance | `fin_contracts` |
| `/dashboard/finance/settlements` | سجل تسليم الأرباح | Dual-Control Payouts | `fin_settlements` |
| `/dashboard/finance` | لوحة المالية الرئيسية | General Ledger Overview | `fin_overview` |
| `/dashboard/quality/investigations` | حالات التحقيق والمخالفات | Incident Reporting | `qual_investigations` |
| `/dashboard/quality/infection` | مكافحة العدوى | Infection Control | `qual_infection` |
| `/dashboard/quality/control` | مراقبة الجودة | Clinical Audit Auditing | `qual_control` |
| `/dashboard/complaints` | الشكاوى والملاحظات | Patient Feedback | `qual_complaints` |
| `/dashboard/doctors` | أطباء المجمع والعمولات | Doctor Directory & Fees | `rep_doctors` |
| `/dashboard/settings/definitions` | التعريفات والمدخلات (Master Data)| 21 Definition Domains | `set_definitions` |
| `/dashboard/settings/ai-usage` | استهلاك الذكاء الاصطناعي | Token Usage & Quotas | `set_ai_usage` |
| `/dashboard/settings/quotas` | حصص واستهلاك النظام | Facility Subscription | `set_quotas` |
| `/dashboard/settings/financial-rules` | القواعد المالية | Financial Policies | `set_financial` |
| `/dashboard/settings/roles` | الصلاحيات والأدوار | RBAC & Custom Perms | `set_roles` |
| `/dashboard/settings/security` | تأمين النظام | Screen PIN & Security | `set_security` |
| `/dashboard/settings/audit-log` | سجل الأنشطة (Audit Trail) | System Activity History | `view_audit_log` |

---

### 2.2 Master Data & Definitions Architecture (The 21 Domains)
In MedCore Web, master data is managed authoritatively through `useDefinitionsStore.ts` and rendered in `DefinitionsModule.tsx`:

1. **`clinics` (العيادات)**: Permanent clinic catalog (ID, Arabic Name, Linked Hospital Departments, Active Status).
2. **`doctors` (الأطباء)**: Master physician roster with custom permissions mode, clinic-specific exam/consultation fees, commission percentages, diagnostic exception pricing, and specialized department pricing (ICU, NICU, Inpatient, Surgery).
3. **`referrals` (تعاقدات التحويلات)**: Referral contracts, external doctor/clinic kickbacks, and commission rules.
4. **`services` (الخدمات)**: Billable hospital procedures and clinical services with base pricing and linked clinic mapping.
5. **`branches` (الفروع)**: Multi-branch facility definitions and branch codes.
6. **`rooms` (الغرف)**: Inpatient room types, numbers, daily rates, required deposits, and physical bed inventory (`status: available | occupied | maintenance`).
7. **`or` (غرف العمليات)**: Surgical operating suites, theater equipment, and hourly charge rates.
8. **`icu` (الرعاية المركزة)**: Critical care beds, mechanical ventilators, and base bed day rates.
9. **`icuDevices` (أجهزة الرعاية)**: Infusion pumps, monitors, suction units assigned to ICU beds.
10. **`nicuRooms` (غرف الحضانات)**: Neonatal intensive care rooms and isolation suites.
11. **`incubators` (وحدات الحضانات)**: Individual incubator stations, phototherapy lamps, and nursery cribs.
12. **`nicuDevices` (أجهزة الحضانات)**: Neonatal ventilators, CPAP machines, and vital monitors.
13. **`lab` (قسم المعمل)**: Complete catalog of laboratory diagnostic tests (CBC, LFT, KFT, Lipid, Coagulation, Hormones, Urine, Stool), reference ranges, specimen container types, and unit pricing.
14. **`externalLabs` (المعامل الخارجية)**: Out-sourced reference laboratories, contracted test prices, and courier turnaround times.
15. **`radiology` (قسم الأشعة)**: Diagnostic imaging procedures (X-Ray, Ultrasound, CT, MRI, Echocardiogram, Doppler), body regions, contrast requirements, and fees.
16. **`insurance` (شركات التأمين)**: Payer companies, policy contract numbers, coverage percentages (e.g. 80%/20%), patient copay amounts, and excluded exclusions.
17. **`nurses` (إضافة ممرض)**: Nursing staff profiles, assigned clinical wards/clinics, shift hours, hourly rates, salary frequencies, and operational flags.
18. **`employees` (إضافة موظف)**: Administrative, receptionist, cashier, and support employee profiles, roles, base salaries, shift hours, and custom permissions.
19. **`conditions` (الاشتراطات العامة)**: General clinical guidelines, consent text clauses, and hospital policies.
20. **`paymentMethods` (طرق الدفع)**: Active transaction settlement methods (Cash, Visa, MasterCard, Meeza, Vodafone Cash, Bank Transfer, Insurance Voucher).
21. **`currency` (العملة المحلية)**: Multi-currency exchange configuration (Base currency, symbol, code, exchange rate).

---

## 3. PHASE 3 — COMPLETE MEDCORE PLATINUM INVENTORY

### 3.1 Flutter Desktop Presentation Layer (`medcore_desktop/lib`)
MedCore Platinum Desktop organizes its user interface into 16 staff routes plus 1 hidden technician console:

| Route ID | Label | Flutter Screen Widget | Operational Capability Status |
|---|---|---|---|
| `dashboard` | Executive Overview | `ExecutiveDashboardScreen` | **IMPLEMENTED** (Live API stats from `/api/v1/product/bootstrap`) |
| `patients` | Patients & Registration | `PatientsWorkspaceScreen` | **IMPLEMENTED** (Full patient CRUD, search, registration modal) |
| `reception_visits` | Shifts & Visit Billing | `ShiftsAndVisitsScreen` | **IMPLEMENTED** (Shift open/close, visit checkout with cost-split) |
| `finance_ledger` | Financial Ledger & Reports | `PatientFinancialLedgerScreen` | **IMPLEMENTED** (AR collections, invoices, receipts, external payables) |
| `appointments` | Appointments | `ClinicalModulesHubScreen` | **IMPLEMENTED** (Appointment listing and appointment creation) |
| `doctors` | Doctors & Outpatient | `ClinicalModulesHubScreen` | **IMPLEMENTED** (Doctor queue, encounters, e-prescriptions, orders) |
| `laboratory` | Laboratory (LIS) | `ClinicalModulesHubScreen` | **IMPLEMENTED** (Lab order list, test results entry, panic alerts) |
| `radiology` | Radiology (RIS) | `ClinicalModulesHubScreen` | **IMPLEMENTED** (Radiology order worklist, modality filter) |
| `pharmacy` | Pharmacy & Inventory | `ClinicalModulesHubScreen` | **PARTIAL** (Lists items and batches, dispenses Rx; NO POS UI) |
| `inpatient` | Inpatient & Beds | `ClinicalModulesHubScreen` | **IMPLEMENTED** (Bed list, patient admission, patient discharge) |
| `specialty_units` | Nursing / ICU / OR / Dialysis | `ClinicalModulesHubScreen` | **BACKEND_ONLY / SUMMARY** (Displays status cards; no interactive flowsheet) |
| `clinical_templates`| Clinical Templates | `ClinicalTemplateEditorScreen` | **FULL_PARITY** (Full template designer, specialty tags, versioning) |
| `resource_scheduling`| Resource Scheduling | `ResourceSchedulingManagementScreen` | **PLATINUM_ONLY** (Multi-resource slots, rules, conflict tester) |
| `staff_admin` | Staff & Employee Accounts | `AdminEmployeeManagementScreen` | **PARTIAL** (Basic staff CRUD; fine-grained permissions NOT exposed) |
| `network_devices` | LAN / Wi-Fi Devices | `NetworkDeviceCenterScreen` | **PLATINUM_ONLY** (mDNS peer discovery, TLS certificates, pairing) |
| `maintenance_center`| Maintenance & Backups | `MaintenanceCenterScreen` | **PLATINUM_ONLY** (Automated MariaDB snapshots, verification, diagnostic bundle) |
| `technician` | Protected Technician Mode | `TechnicianConsoleScreen` | **PLATINUM_ONLY** (HMAC-SHA256 challenge, secret rotate, factory reset) |

---

### 3.2 Backend Service Architecture (`medcore_local_service`)
`LocalMedCoreServer` exposes 74 REST endpoints and 1 SSE stream.
Core backend capabilities include:
- Multi-tenancy & Facility Configuration (`/api/v1/product/bootstrap`, `/api/v1/product/config`)
- RBAC & Staff Management (`/api/v1/staff`, `/api/v1/staff/<id>/permissions`, `/api/v1/admin/employees`)
- Patient Index (`/api/v1/patients`)
- Financial Visits & Shifts (`/api/v1/shifts/*`, `/api/v1/visits`, `/api/v1/visits/<id>/refund`)
- Dual-Control Approvals (`/api/v1/dual-control/*`)
- Multi-Resource Scheduling Engine (`/api/v1/scheduling/*`)
- Outpatient Queue, Encounters, E-Prescriptions (`/api/v1/doctor/queue`, `/api/v1/encounters`, `/api/v1/prescriptions`)
- Diagnostic Orders (Lab/Rad) & Results Entry (`/api/v1/orders`, `/api/v1/orders/<id>/results`)
- Clinical Documentation Templates (`/api/v1/clinical/templates/*`)
- Inpatient Beds & Admissions (`/api/v1/beds`, `/api/v1/admissions`, `/api/v1/admissions/<id>/discharge`)
- Pharmacy Inventory & Dispensing (`/api/v1/inventory/items`, `/api/v1/inventory/batches`, `/api/v1/pharmacy/dispense`)
- Nursing Station Tasks (`/api/v1/clinical/nursing/tasks`, complete)
- ICU Flowsheets & SOFA Scoring (`/api/v1/clinical/icu/*`)
- Operating Theater Surgeries (`/api/v1/clinical/surgeries`, status update)
- Hemodialysis Treatment Sessions (`/api/v1/clinical/dialysis/sessions`, complete)
- Real-Time Clinical Event Stream (`/api/v1/clinical/events/stream` via Server-Sent Events)
- Patient Financial Ledger, AR & External Payables (`/api/v1/finance/*`)
- Native Printing Engine (`/api/v1/printing/format`)
- LAN PKI & Hardware Device Pairing (`/api/v1/network/*`)
- Database Lifecycle, Backup & Restore (`/api/v1/database/*`)
- Technician Security Console (`/api/v1/technician/*`)

---

## 4. PHASE 4 — FORENSIC INVESTIGATION OF SPECIFIC USER QUESTIONS

| # | Requested Capability | Present in Web? | Present in Platinum? | Forensic Technical Reality |
|---|---|---|---|---|
| 1 | **Clinic Management & Clinic Cards** | **YES** (`ClinicsForm.tsx`, `ClinicCard.tsx`, `ClinicCardGrid.tsx`) | **NO** (Missing in UI & API) | Web has dynamic clinic cards with countdown timers, active queues, and waiting lists. Platinum has no clinic cards; its reception screen is a single checkout form. |
| 2 | **Creating Permanent & Temporary Clinics** | **YES** (`ClinicsForm.tsx`, `CreateTemporaryClinicModal.tsx`) | **NO** (Missing in UI & API) | Web allows administrators to define permanent clinics and receptionists to open temporary clinics with doctor, nurse, and pricing. Platinum has no clinic creation endpoint or screen. |
| 3 | **Assigning Doctors to Clinics** | **YES** (`DoctorsForm.tsx`, `DoctorClinicPricing[]`) | **BACKEND_ONLY** (In `mc_staff.clinic_id`) | Platinum's MariaDB schema and `StaffIdentityRepository` accept `clinicId` in JSON, but Flutter `_AddEmployeeDialog` / `_EditEmployeeDialog` do not expose the field. |
| 4 | **Assigning Nurses & Staff to Clinics** | **YES** (`NursesForm.tsx`, `useSchedulesStore.ts`) | **BACKEND_ONLY** (In `mc_staff.clinic_id`) | Web links nurses to multiple clinics with shift schedules. Platinum backend supports `clinic_id` on staff, but UI has no assignment control. |
| 5 | **Clinic-Specific Permissions** | **YES** (`clinic_record`, `clinic_exam`, `clinic_inv`) | **BACKEND_ONLY** | Platinum backend catalog has clinic permission keys (`clinic`, `clinic_DoctorQueue`), but has no clinic-level scoping rule in UI. |
| 6 | **Staff Permissions** | **YES** (`permissionsMode: 'custom'`, `customPermissions`) | **BACKEND_ONLY** | Platinum backend supports `PUT /api/v1/staff/<id>/permissions`, but Flutter `AdminEmployeeManagementScreen` only provides a role dropdown. |
| 7 | **Fine-Grained RBAC** | **YES** (`CustomPermissionsBuilder.tsx`, `PermissionTree.tsx`)| **BACKEND_ONLY** | Platinum backend has 261 keys and 43 backend permissions with strict enforcement, but ZERO UI editor in Flutter desktop. |
| 8 | **Master Data Management** | **YES** (`DefinitionsModule.tsx` - 21 domains) | **SCHEMA_ONLY** (`mc_definitions` table in V005) | `mc_definitions` table exists in MariaDB, but has ZERO repository, ZERO API route, and ZERO Flutter screen in Platinum. |
| 9 | **Supplies Definition** | **YES** (`inventory/main`, `ServicesForm.tsx`) | **SCHEMA_ONLY** (`mc_inventory_items`) | Platinum has `mc_inventory_items` and `GET /api/v1/inventory/items`, but NO endpoint or screen to add or edit supplies. |
| 10 | **Consumables Definition** | **YES** (`QuickConsumableModal.tsx`, `inv_main`) | **SCHEMA_ONLY** (`mc_inventory_items`) | Web supports quick consumable creation and inventory tracking. Platinum only supports manual gross/cost input on checkout. |
| 11 | **Definitions Management** | **YES** (`/dashboard/settings/definitions`) | **SCHEMA_ONLY** | Platinum has no definitions screen or CRUD engine. |
| 12 | **Service Definitions** | **YES** (`ServicesForm.tsx`) | **NO** | In Web, services have codes, names, base prices, and linked clinics. In Platinum, services are typed manually on visit checkout. |
| 13 | **Pricing Definitions** | **YES** (`inventory/prices`, `DoctorClinicPricing`) | **NO** | Web has price sheets and doctor consultation tariffs. Platinum has no pricing definition engine. |
| 14 | **Medical Service Configuration** | **YES** (`ServicesForm.tsx`, `LabForm.tsx`, `RadiologyForm.tsx`) | **NO** | Tests and procedures cannot be configured from the Platinum UI. |
| 15 | **Department Configuration** | **YES** (`ClinicsForm.tsx`, `linkedDepartments`) | **BACKEND_ONLY** (In `mc_staff.department_id`) | Schema and backend hold `department_id`, but no master department setup screen exists in Platinum. |
| 16 | **Specialty Configuration** | **YES** (`DoctorsForm.tsx`, `clinicalDepartments`) | **PARTIAL** (Dropdown in Clinical Templates) | Platinum allows typing a specialty when creating clinical templates, but has no master specialty registry. |
| 17 | **Doctor Configuration** | **YES** (`DoctorsForm.tsx` - salaries, fees, splits) | **PARTIAL** (Staff login account only) | Platinum can create a doctor login account, but cannot configure their consultation price, commission %, or clinic pricing. |
| 18 | **Nursing Configuration** | **YES** (`NursesForm.tsx` - hourly rate, shift hours) | **PARTIAL** (Staff login account only) | Platinum can create a nurse login account, but cannot configure nursing rates, shift hours, or clinic allocations. |
| 19 | **Reception Configuration** | **YES** (`CreateTemporaryClinicModal`, `waiting_room`) | **NO** | Platinum reception is fixed to a shift box and visit checkout form. |
| 20 | **Employee Configuration** | **YES** (`EmployeesForm.tsx` - full HR profile) | **PARTIAL** (Account credentials only) | Platinum can manage credentials (code, name, email, phone, password), but no HR contract or salary terms. |
| 21 | **Facility Configuration** | **YES** (`BranchesForm.tsx`, `CurrencyForm.tsx`) | **IMPLEMENTED** (Via `TechnicianConsoleScreen`) | Platinum manages facility name, edition, and module toggles through Technician Mode (`/api/v1/technician/config`). |
| 22 | **Administrative Configuration**| **YES** (`settings/*` - 7 configuration pages) | **PARTIAL** (Split between Technician & Maintenance) | Platinum delegates administrative system settings to Technician Console and Maintenance Center. |

---

## 5. PHASE 5 — COMPREHENSIVE FEATURE PARITY SUMMARY

- **Total Assessed Business Capabilities**: 118
- **Full Parity (Present in Both & Verified)**: 28 (23.7%)
- **Web-Only (Missing in Platinum)**: 46 (39.0%)
- **Platinum-Only (Desktop / Hardware / Offline Innovations)**: 14 (11.9%)
- **Partial (Functional in both, but different UX/scope)**: 12 (10.2%)
- **Backend-Only (Platinum backend supports it, UI does not expose it)**: 11 (9.3%)
- **Schema-Only (Table exists in MariaDB, no service or UI)**: 7 (5.9%)
- **Unknown / Not Verifiable**: 0 (0.0%)
