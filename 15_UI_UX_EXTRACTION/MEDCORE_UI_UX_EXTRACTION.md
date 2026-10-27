# MEDCORE — UI/UX & NAVIGATION EXTRACTION (`UI DESIGN REFERENCE`)
**Document ID**: `DOC-14` | **Classification**: `UI DESIGN REFERENCE` (Extracted from `Frontend/src/lib/navigationConfig.ts`, `Sidebar.tsx`, `tailwind.config.ts`, `globals.css`, and 104 Pages)

---

## 1. Canonical 19-Section / 82-Node Navigation Architecture (`FACT`)
Extracted verbatim from `Frontend/src/lib/navigationConfig.ts:21-888`:

| Sec # | Section Key | Arabic Label | Child Subpages (`63` Total) & Canonical Paths |
|---|---|---|---|
| 1 | `dashboard` | لوحة القيادة | Standalone: `/dashboard` (`dashboard`) |
| 2 | `patients` | سجل المرضى | Standalone: `/patients` (`patients`) |
| 3 | `appointments` | المواعيد والحجوزات | Standalone: `/appointments` (`appointments`) |
| 4 | `HMS_summary` | الملخص العام للمستشفى | Standalone: `/summary` (`HMS_summary`) |
| 5 | `shifts` | الورديات والخزينة | Standalone: `/shifts` (`shifts`) |
| 6 | `reception` | الاستقبال والطوارئ | 1. `/reception/check-in` (`reception_QuickCheckIn`)<br>2. `/reception/patients` (`reception_PatientRegistration`)<br>3. `/reception/appointments` (`reception_Appointments`)<br>4. `/reception/queue` (`reception_QueueManagement`)<br>5. `/reception/emergency` (`reception_Emergency`) |
| 7 | `clinic` | العيادات الخارجية | 1. `/clinic/queue` (`clinic_DoctorQueue`)<br>2. `/clinic/appointments` (`clinic_Appointments`)<br>3. `/clinic/patients` (`clinic_PatientsList`)<br>4. `/clinic/prescriptions` (`clinic_Prescriptions`)<br>5. `/clinic/reports` (`clinic_ClinicReports`) |
| 8 | `CommandCenter` | مركز القيادة | 1. `/command-center/overview` (`CommandCenter_Overview`)<br>2. `/command-center/beds` (`CommandCenter_BedManagement`)<br>3. `/command-center/alerts` (`CommandCenter_Alerts`) |
| 9 | `doctor` | بوابة الطبيب | 1. `/doctor/workspace` (`doctor_ClinicalWorkspace`)<br>2. `/doctor/patients` (`doctor_MyPatients`)<br>3. `/doctor/schedule` (`doctor_Schedule`) |
| 10 | `nurse` | محطة التمريض | 1. `/nurse/station` (`nurse_NursingStation`)<br>2. `/nurse/triage` (`nurse_Triage`)<br>3. `/nurse/vitals` (`nurse_VitalsMonitoring`)<br>4. `/nurse/medications` (`nurse_MedicationAdmin`)<br>5. `/nurse/handover` (`nurse_ShiftHandover`) |
| 11 | `inpatient` | القسم الداخلي والتنويم | 1. `/inpatient/admissions` (`inpatient_Admissions`)<br>2. `/inpatient/beds` (`inpatient_BedMap`)<br>3. `/inpatient/rounds` (`inpatient_WardRounds`)<br>4. `/inpatient/discharge` (`inpatient_Discharge`) |
| 12 | `icu_nicu` | العناية المركزة والحضانات | 1. `/icu-nicu/dashboard` (`icu_nicu_Dashboard`)<br>2. `/icu-nicu/icu` (`icu_nicu_ICUMonitoring`)<br>3. `/icu-nicu/nicu` (`icu_nicu_NICUIncubators`)<br>4. `/icu-nicu/ventilators` (`icu_nicu_Ventilators`) |
| 13 | `surgery` | العمليات الجراحية | 1. `/surgery/schedule` (`surgery_OTSchedule`)<br>2. `/surgery/theaters` (`surgery_OperatingTheaters`)<br>3. `/surgery/post-op` (`surgery_PostOpRecovery`) |
| 14 | `dialysis` | وحدة الغسيل الكلوي | 1. `/dialysis/sessions` (`dialysis_Sessions`)<br>2. `/dialysis/machines` (`dialysis_Machines`)<br>3. `/dialysis/patients` (`dialysis_Patients`)<br>4. `/dialysis/consumables` (`dialysis_Consumables`) |
| 15 | `lab` | المختبر والتحاليل | 1. `/lab/dashboard` (`lab_Dashboard`)<br>2. `/lab/samples` (`lab_SampleTracking`)<br>3. `/lab/results` (`lab_ResultsEntry`)<br>4. `/lab/verification` (`lab_Verification`)<br>5. `/lab/blood-bank` (`lab_BloodBank`)<br>6. `/lab/reagents` (`lab_Reagents`) |
| 16 | `rad` | الأشعة والتصوير | 1. `/rad/worklist` (`rad_Worklist`)<br>2. `/rad/reporting` (`rad_Reporting`)<br>3. `/rad/consumables` (`rad_ContrastConsumables`) |
| 17 | `pharmacy_inventory` | الصيدلية والمخازن | 1. `/pharmacy-inventory/dispensing` (`pharmacy_Dispensing`)<br>2. `/pharmacy-inventory/items` (`inventory_ItemsCatalog`)<br>3. `/pharmacy-inventory/batches` (`inventory_StockBatches`)<br>4. `/pharmacy-inventory/purchases` (`inventory_PurchaseReceipts`)<br>5. `/pharmacy-inventory/transfers` (`inventory_Transfers`)<br>6. `/pharmacy-inventory/stocktake` (`inventory_Stocktake`) |
| 18 | `finance` | الإدارة المالية والحسابات | 1. `/finance/revenue` (`finance_Revenue`)<br>2. `/finance/invoices` (`finance_Invoices`)<br>3. `/finance/settlements` (`finance_Settlements`)<br>4. `/finance/insurance` (`finance_InsuranceClaims`)<br>5. `/finance/treasury` (`finance_TreasuryExpenses`) |
| 19 | `hr_settings` | الموارد البشرية والإعدادات | 1. `/hr/employees` (`hr_Employees`)<br>2. `/hr/attendance` (`hr_Attendance`)<br>3. `/hr/payroll` (`hr_Payroll`)<br>4. `/settings/definitions` (`settings_Definitions`)<br>5. `/settings/permissions` (`settings_Permissions`)<br>6. `/settings/hospital` (`settings_HospitalProfile`)<br>7. `/security` (`security_Center`) |

---

## 2. Design System Tokens (`UI DESIGN REFERENCE` for Flutter `ThemeData`)
- **Directionality & Typography**:
  - Primary locale: **Arabic (`ar`, RTL)**; Secondary locale: **English (`en`, LTR)**.
  - Font Family: `Cairo` / `Tajawal` / `IBM Plex Sans Arabic` for Arabic; `Inter` for English and tabular numerals (`font-variant-numeric: tabular-nums` mandatory for all financial and lab tables).
- **Color Palette (Medical Slate & Emerald/Teal Accent)**:
  - Primary Brand: `#0F766E` (`Teal 700`) / `#0D9488` (`Teal 600`).
  - Clinical Status Semantic Colors:
    - Critical / Emergency / Panic Result: `#DC2626` (`Red 600`, background `#FEF2F2`).
    - Warning / Abnormal Result / Pending Approval: `#D97706` (`Amber 600`, background `#FFFBEB`).
    - Normal / Verified / Completed / Paid: `#16A34A` (`Green 600`, background `#F0FDF4`).
    - In Consultation / Active Shift / Reserved Bed: `#2563EB` (`Blue 600`, background `#EFF6FF`).
