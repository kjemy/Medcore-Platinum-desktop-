# WS4 — Clinical Core Workflows & State Machines (`Project 3`)

> **Classification**: `FACT` — Extracted from `Backend/MedCorePlugin/includes/core/class-medcore-visit-service.php` (1,753 lines), `class-medcore-admissions-service.php` (185 lines), `class-medcore-surgery-service.php` (167 lines), `class-medcore-dialysis-service.php` (236 lines), `class-medcore-icu-nicu-clinical-service.php` (214 lines), and `includes/api/class-api-*.php`.

## 1. Atomic Visit Creation 12-Step Pipeline (`CLN-001` — `FACT`)
- **Source**: `MedCore_Visit_Service::create_visit` (`class-medcore-visit-service.php:130-690`).
- **Execution Sequence inside `START TRANSACTION` .. `COMMIT`**:
  1. **Tenant & Idempotency Guard**: Verifies `hospital_code` and checks `wp_mc_visits` / `wp_mc_financial_events` for existing `idempotency_key`.
  2. **Shift Enforcement**: Calls `MedCore_Shift_Service::require_open_shift` (`line 225`) whenever `$paid > 0` or `$require_open_shift` is enabled.
  3. **Patient Validation**: Verifies `patient_id` exists in `wp_mc_patients` for `hospital_code` (`SELECT ... FOR UPDATE`).
  4. **Appointment Lock & Promotion**: If `appointment_id` is passed, locks row in `wp_mc_appointments FOR UPDATE`, verifies status is not `CANCELLED` or already linked to an active visit, and updates appointment status to `COMPLETED` / `CHECKED_IN`.
  5. **Monetary Validation**: Normalizes item lines (`unit_price * quantity`) and validates `Discount + Paid + InsuranceCovered + Balance == Gross`.
  6. **Insert `wp_mc_visits` Master Record**: Generates sequential/formatted `visit_number` and `invoice_number`, sets `status = 'ACTIVE'`, `clinical_status = 'WAITING'`.
  7. **Insert `wp_mc_visit_items` Line Records**: Persists each service/lab/rad/procedure item (`item_type`, `service_code`, `service_name`, `unit_price`, `quantity`, `discount_amount`, `net_amount`, `doctor_id`).
  8. **Downstream Diagnostic Order Routing**: Automatically creates rows in `wp_mc_orders` (`category = 'LAB'` or `'RAD'`) when visit items represent diagnostic tests.
  9. **Financial Event & Sub-Ledger Postings**: Calls `MedCore_Financial_Transaction_Service::post_visit_transaction` to write `wp_mc_financial_events` and `wp_mc_financial_postings` (including `COMMISSION_ACCRUAL`).
  10. **Invoice Mirror Sync**: Inserts/updates `wp_mc_invoices` and `wp_mc_payments` for backward compatibility with legacy reporting views.
  11. **Patient Balance Rollup**: Updates `wp_mc_patients` balance/visit counters if applicable.
  12. **Audit Log**: Writes immutable entry to `wp_mc_audit_logs` (`action = 'visit.create'`).

## 2. Visit Cancellation / Refund / Adjustment (`CLN-002` — `FACT`)
- **Source**: `MedCore_Visit_Service::cancel_visit` (`lines 750-1050`), `refund_visit` (`lines 1052-1350`), `adjust_visit` (`lines 1352-1700`).
- **Clinical Execution Guard**: `cancel_visit` checks whether downstream clinical execution has completed (e.g., verified lab result in `wp_mc_lab_results`, completed radiology report in `wp_mc_radiology_reports`, dispensed prescription in `wp_mc_pharmacy_dispenses`). If executed, full cancellation is blocked or requires override.
- **Financial Reversal**: Calls `MedCore_Financial_Transaction_Service::reverse_visit_transaction` which creates a compensating `VISIT_REVERSAL` event and flips `DEBIT`/`CREDIT` on every original posting (including reversing `COMMISSION_ACCRUAL`).

## 3. Laboratory & Radiology State Machines (`CLN-003` & `CLN-004` — `FACT`)
- **Source**: `Backend/MedCorePlugin/includes/api/class-api-clinical.php`, `class-api-lab-rad.php`, `medcore.php` (`wp_mc_orders`, `wp_mc_lab_specimens`, `wp_mc_lab_results`, `wp_mc_radiology_reports`).
- **Lab Lifecycle**: `ORDERED` (`wp_mc_orders`) -> `SAMPLE_COLLECTED` (`wp_mc_lab_specimens` barcode/tube tracking) -> `PROCESSING` -> `PRELIMINARY_RESULT` (`wp_mc_lab_results`, `abnormal_flag`, `critical_flag`) -> `VERIFIED` / `APPROVED` (`verified_by`, `verified_at`). Critical results write to `wp_mc_critical_notifications`.
- **Radiology Lifecycle**: `ORDERED` -> `SCHEDULED` -> `IN_PROGRESS` (Modality/Study performed) -> `REPORT_DRAFTED` (`wp_mc_radiology_reports`, findings/impression) -> `FINALIZED` (`radiologist_id`, `finalized_at`).

## 4. Inpatient Admissions, Beds, ICU/NICU, Surgery & Dialysis (`CLN-005`..`CLN-008` — `FACT`)
- **Admissions & Bed Locking (`MedCore_Admissions_Service`, `class-medcore-admissions-service.php:15-185`)**:
  - Locks target bed in `wp_mc_beds FOR UPDATE`, verifies `status = 'AVAILABLE'`, transitions bed to `'OCCUPIED'`, and inserts `wp_mc_admissions` (`status = 'ADMITTED'`).
  - Discharge (`discharge_patient`) transitions `wp_mc_admissions.status = 'DISCHARGED'` and bed to `'CLEANING'` or `'AVAILABLE'`.
- **Surgery (`MedCore_Surgery_Service`, `class-medcore-surgery-service.php:15-167`)**:
  - Manages `wp_mc_surgeries` (`SCHEDULED` -> `PRE_OP` -> `IN_THEATER` -> `RECOVERY` -> `COMPLETED` / `CANCELLED`), WHO Surgical Safety Checklist (`wp_mc_surgery_checklists`), anesthesia records (`wp_mc_anesthesia_records`), and theater consumables (`wp_mc_surgery_consumables`).
- **Dialysis (`MedCore_Dialysis_Service`, `class-medcore-dialysis-service.php:15-236`)**:
  - Enforces strict state machine on `wp_mc_dialysis_sessions`: `SCHEDULED` -> `CHECKED_IN` -> `IN_PROGRESS` (pre-weight, BP, heparin, machine assignment in `wp_mc_dialysis_machines`) -> `COMPLETED` (post-weight, ultrafiltration volume, consumables) or `ABORTED`.
- **ICU / NICU (`MedCore_ICU_NICU_Clinical_Service`, `class-medcore-icu-nicu-clinical-service.php:15-214`)**:
  - Tracks hourly vitals/ventilator parameters (`wp_mc_icu_flows`), fluid intake/output balance, incubator parameters (NICU), and Apache/SOFA/neonatal scoring (`wp_mc_clinical_scores`).
