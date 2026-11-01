# MEDCORE PLATINUM — READ-ONLY MASTER DATA & ENTITY PARITY
# WEB MASTER DATA vs PLATINUM ENTITY ARCHITECTURE AUDIT

- **AUDIT TYPE**: STRICTLY READ-ONLY FORENSIC AUDIT
- **GOVERNANCE AUTHORITY**: Khaled Universal Engineering Constitution (`Khaled All Rules`)
- **DATE OF EXECUTION**: 2026-11-01
- **CODE CHANGES**: 0
- **DATABASE MUTATIONS**: 0
- **GIT CHANGES**: 0
- **DEPLOYMENT**: 0

---

## 1. MASTER DATA & DEFINITIONS COMPARISON MATRIX

| Entity / Definition Domain | Web UI Implementation | Web Backend Persistence | Platinum UI Implementation | Platinum DB / Backend Reality | Parity Status | Forensic Technical Verdict |
|---|---|---|---|---|:---:|---|
| **Clinic** | `ClinicsForm.tsx` & `CreateTemporaryClinicModal.tsx` | `wp_mc_definitions` (`type='clinic'`) | **NONE** | **NONE** (No `mc_clinics` table; `clinic_id` is an untyped string in `mc_staff` and visits) | **WEB_ONLY** | Platinum cannot define, edit, list, or persist clinics. |
| **Doctor Profile** | `DoctorsForm.tsx` (Name, Degree, WhatsApp, Active) | `wp_mc_definitions` (`type='doctor'`) | `AdminEmployeeManagementScreen` (`_AddEmployeeDialog`) | `mc_staff` (`role='Doctor'`) | **PARTIAL** | Basic account creation exists; clinical profile details missing in Platinum. |
| **Doctor Clinic Tariffs** | `DoctorsForm.tsx` (`DoctorClinicPricing[]`) | `wp_mc_definitions.data_json` | **NONE** | **NONE** | **WEB_ONLY** | Platinum cannot define doctor consultation or examination prices per clinic. |
| **Doctor Commissions** | `DoctorsForm.tsx` (`flatServiceCommPercent`, `serviceExceptions`) | `wp_mc_definitions.data_json` | **NONE** | In `mc_visits.doctor_commission_rate` (Manual transaction rate) | **WEB_ONLY** | Master commission rule matrix is absent in Platinum. |
| **Doctor Diagnostic Exceptions** | `DoctorsForm.tsx` (`diagnosticExceptions[]`) | `wp_mc_definitions.data_json` | **NONE** | **NONE** | **WEB_ONLY** | Platinum has no exception pricing for lab/radiology referrals. |
| **Nurse Profile** | `NursesForm.tsx` (Name, Phone, WhatsApp, Specialty) | `wp_mc_definitions` (`type='nurse'`) | `AdminEmployeeManagementScreen` (`_AddEmployeeDialog`) | `mc_staff` (`role='Nurse'`) | **PARTIAL** | Basic account creation exists; nursing profile details missing in Platinum. |
| **Nurse Shift & Rates** | `NursesForm.tsx` (`hourlyRate`, `shiftHours`, `salaryFrequency`)| `wp_mc_definitions.data_json` | **NONE** | **NONE** | **WEB_ONLY** | Platinum does not define nurse compensation rates. |
| **Nurse Clinic Allocation** | `NursesForm.tsx` (`linkedClinics[]`) & `useSchedulesStore` | `wp_mc_definitions.data_json` | **NONE** | In `mc_staff.clinic_id` (Backend column only; no UI) | **BACKEND_ONLY** | Column exists in database; Flutter UI has no input field. |
| **Employee Profile** | `EmployeesForm.tsx` (Role, Name, Email, Phone) | `wp_mc_definitions` (`type='employee'`) | `AdminEmployeeManagementScreen` (`_AddEmployeeDialog`) | `mc_staff` (`role='Employee'`) | **FULL_PARITY** | Basic staff account creation is functional in both. |
| **Employee Salary Cycles** | `EmployeesForm.tsx` & `SalaryCyclePicker.tsx` | `wp_mc_definitions.data_json` | **NONE** | In `mc_external_payables` (Ad-hoc payable vouchers) | **WEB_ONLY** | Recurring employee salary cycle definition is absent in Platinum. |
| **Department** | `ClinicsForm.tsx` (`linkedDepartments[]`) | `wp_mc_definitions.data_json` | In `ResourceSchedulingManagementScreen` (Text field) | In `mc_staff.department_id` & `mc_scheduling_resources` | **PARTIAL** | Free-text string input; no dedicated master department catalog. |
| **Specialty** | `DoctorsForm.tsx` (`clinicalDepartments[]`) | `wp_mc_definitions.data_json` | In `ClinicalTemplateEditorScreen` (Category string) | In `mc_staff.specialty` & `mc_clinical_templates` | **PARTIAL** | Free-text / template field; no master specialty catalog. |
| **Medical Service** | `ServicesForm.tsx` (Code, Name, Price, Linked Clinics) | `wp_mc_definitions` (`type='service'`) | **NONE** | In `mc_visit_items` (Billed as raw string on checkout) | **WEB_ONLY** | Platinum has no catalog where billable services are defined. |
| **Consumable / Supply Item** | `inventory/main`, `QuickConsumableModal.tsx` | `wp_mc_inventory` relational table | **NONE** (Read-only list in Pharmacy) | `mc_inventory_items` (Table exists in V006; no insert API/UI) | **SCHEMA_ONLY** | Table exists in MariaDB; no API or UI to define items. |
| **Medicine / Drug Formulary** | `pharmacy/catalog` | `wp_mc_definitions` & inventory tables | `pharmacy` in `ClinicalModulesHubScreen` (Read-only) | `mc_inventory_items` & `mc_inventory_batches` | **PARTIAL** | Can view existing stock batches; cannot define new drugs. |
| **Insurance Provider & Plans** | `InsuranceForm.tsx` (Copay %, Default Coverage %, Exclusions) | `wp_mc_definitions` (`type='insurance'`) | **NONE** | In `mc_visits.insurance_amount` (Billed as raw decimal) | **WEB_ONLY** | Platinum cannot configure insurance policies or tariffs. |
| **Pricing Sheets** | `inventory/prices`, `finance/contracts` | `wp_mc_definitions.data_json` | **NONE** | In `mc_visit_item_cost_lines` (Transaction lines only) | **WEB_ONLY** | Platinum lacks a master pricing schedule table. |
| **Appointment Types** | `appointments/page.tsx` (Consultation, Follow-up, Procedure) | WordPress visit options | In `ResourceSchedulingManagementScreen` (`CONSULTATION` etc.)| `mc_scheduling_rules.appointment_type` | **FULL_PARITY** | Supported in scheduling rule engine. |
| **Clinical Documentation Templates**| `clinics/templates/page.tsx` | `wp_mc_definitions` & relational templates | `ClinicalTemplateEditorScreen` | `mc_clinical_templates` & `mc_clinical_template_usages` | **FULL_PARITY** | Full parity: designer, categories, versions, activation. |
| **Inpatient Room** | `RoomsForm.tsx` (Room Type, Daily Price, Deposit Amount) | `wp_mc_definitions` (`type='room'`) | In `ResourceSchedulingManagementScreen` (Resource `ROOM`) | `mc_scheduling_resources` (Resource record) | **PARTIAL** | Can define room for scheduling, but no room tariff/deposit. |
| **Inpatient Bed** | `RoomsForm.tsx` (`beds[]` with status available/occupied) | `wp_mc_definitions.data_json` | In `inpatient` workspace (`ClinicalModulesHubScreen`) | `mc_beds` (Table in V003; list & assign functional) | **FULL_PARITY** | Bed inventory status, admission, and discharge functional. |
| **Inpatient Ward** | `clinical/rooms/page.tsx` | `wp_mc_definitions` | In `specialty_units` | Relational ward mapping | **PARTIAL** | Functional bed management; no ward master catalog. |
| **Operating Room (OR)** | `OperatingRoomsForm.tsx` (OR Suite Name, Hourly Rate) | `wp_mc_definitions` (`type='or'`) | In `ResourceSchedulingManagementScreen` (Resource `THEATER`)| `mc_scheduling_resources` | **PARTIAL** | Can define theater for scheduling; no hourly rate tariff. |
| **ICU Unit & Devices** | `IcuForm.tsx` & `IcuDevicesForm.tsx` | `wp_mc_definitions` (`type='icu'`) | `specialty_units` (Summary Card) | `mc_icu_flowsheets`, `mc_icu_scores` | **BACKEND_ONLY** | Backend flowsheet tables exist; no physical ICU setup UI. |
| **NICU Rooms & Incubators** | `NicuRoomsForm.tsx`, `IncubatorsForm.tsx`, `NicuDevicesForm.tsx` | `wp_mc_definitions` (`type='nicu'`) | `specialty_units` (Summary Card) | In schema domain tables | **SCHEMA_ONLY** | Schema exists; no physical incubator station setup UI. |
| **Laboratory Test Definitions** | `LabForm.tsx` (Panels, Units, Normal Range Low/High, Price) | `wp_mc_definitions` (`type='lab'`) | **NONE** | In `mc_clinical_order_items` & `mc_clinical_results` | **WEB_ONLY** | Platinum records test orders and results, but no catalog. |
| **External Reference Labs** | `ExternalLabForm.tsx` (Contracted tests, turnaround times) | `wp_mc_definitions` (`type='external_lab'`) | **NONE** | In `mc_external_payables` (Payable vouchers only) | **WEB_ONLY** | No external lab catalog in Platinum. |
| **Radiology Procedures** | `RadiologyForm.tsx` (Modality, Body Region, Contrast, Price) | `wp_mc_definitions` (`type='radiology'`) | **NONE** | In `mc_clinical_order_items` | **WEB_ONLY** | No radiology procedure catalog in Platinum. |
| **Payment Methods** | `PaymentMethodsForm.tsx` (Cash, Card, Wallet, Transfer, Voucher)| `wp_mc_definitions` (`type='payment_method'`) | In `ShiftsAndVisitsScreen` (Free-text paymentMethod) | In `mc_financial_events.payment_method` | **PARTIAL** | Transactions record method; no master whitelist setup. |
| **Local Currency** | `CurrencyForm.tsx` (Code, Symbol, Exchange Rate, Base Currency) | `wp_mc_definitions` (`type='currency'`) | In `TechnicianConsoleScreen` & `FacilityConfigModel` | In `mc_facility_config.default_currency` | **PARTIAL** | Platinum supports fixed facility currency, not exchange table. |
| **General Consent Conditions** | `ConditionsForm.tsx` (Legal consent clauses) | `wp_mc_definitions` (`type='condition'`) | **NONE** | `mc_consent_events` (Schema table in V004; no UI) | **SCHEMA_ONLY** | Schema table exists; no condition definition UI. |

---

## 2. SUMMARY OF MASTER DATA CAPABILITY FINDINGS

1. **The Core Architectural Divergence**:
   - In **MedCore Web**, master data is centralized in a dynamic polymorphic schema (`wp_mc_definitions`) with typed JSON schemas and hydrated through a unified Zustand store (`useDefinitionsStore.ts`). Any administrator can define a new clinic, service, lab test, doctor fee, or room rate without database migrations.
   - In **MedCore Platinum Desktop**, master data was decoupled during extraction. While the MariaDB schema includes table `mc_definitions` (`V005`), **no backend repository, no API endpoint, and no Flutter UI screen** were implemented to connect to it.

2. **The "Free-Text" Transaction Pattern in Platinum**:
   - Because master services, clinics, and tariffs are not defined in Platinum, transactional screens (such as `ShiftsAndVisitsScreen`) currently require the operator to enter raw codes and names (e.g., `serviceCode = 'SRV-001'`, `serviceName = 'Outpatient Consultation'`, `laborGross = '250.00'`).
   - In MedCore Web, these values are populated automatically from the master clinic and service catalogs.

3. **Re-purposed Architectural Equivalents in Platinum**:
   - Platinum introduced `ResourceSchedulingManagementScreen`, which partially serves as a master data catalog for appointment scheduling resources (Doctors, Rooms, Theaters, Equipment, Devices, Chairs). However, this catalog does not hold pricing, commissions, clinical tariffs, or reception queue configurations.
