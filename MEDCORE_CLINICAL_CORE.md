# MEDCORE — CLINICAL CORE SPECIFICATION (`CATEGORY E`)
**Document ID**: `DOC-07` | **Source**: `class-medcore-visit-service.php`, `class-medcore-admissions-service.php`, `class-medcore-surgery-service.php`, `class-medcore-dialysis-service.php`, `class-medcore-icu-nicu-clinical-service.php`, and 19 Clinical Frontend Modules

---

## 1. Clinical Modules & End-to-End Workflows

### 1.1 Patient Master Index (`MPI`) & Reception (`wp_mc_patients`, `wp_mc_appointments`, `wp_mc_visits`)
- **Patient Identification**: Unique `mrn` / `file_number` per `hospital_code`, national ID / passport validation, phone lookup, age/DOB calculation, blood group, chronic diseases, allergies (`wp_mc_allergies`), insurance policy binding (`insurance_company_id`, `policy_number`, `coverage_percent`, `copay_max`).
- **Quick Check-In (`reception_QuickCheckIn`)**: Single-screen workflow allowing patient lookup/creation + service/clinic selection + doctor selection + instant payment collection + thermal receipt & queue token printing.
- **Emergency Triage (`reception_Emergency`, `nurse_Triage`)**: Assigns Canadian Triage & Acuity Scale (CTAS Levels 1–5), records vital signs (`BP`, `HR`, `RR`, `Temp`, `SpO2`, `GCS`, `Pain Score` in `wp_mc_vitals`), and routes critical patients immediately to ER resuscitation beds.

### 1.2 Outpatient Clinics & Doctor Portal (`doctor_ClinicalWorkspace`, `clinic_*`)
- **Doctor Queue (`clinic_DoctorQueue`)**: Real-time queue filtered by assigned `doctor_id` (unless user holds `clinic_DoctorQueue_all`).
- **Clinical Encounter Workspace (`wp_mc_clinical_notes`, `wp_mc_diagnoses`, `wp_mc_prescriptions`)**:
  - SOAP Note entry (`Chief Complaint`, `History of Present Illness`, `Physical Examination`, `Assessment Plan`).
  - ICD-10 Primary & Secondary Diagnosis coding (`wp_mc_diagnoses`).
  - Electronic Prescription (`e-Rx` in `wp_mc_prescriptions` & `wp_mc_prescription_items`) with dosage, frequency, route, duration, and drug-allergy/drug-interaction alerts.
  - One-click Diagnostic Order placement (`LAB` panels, `RAD` imaging studies) and Procedure orders.

### 1.3 Laboratory Information System (`LIS` — `lab_*`, `wp_mc_orders`, `wp_mc_lab_specimens`, `wp_mc_lab_results`, `wp_mc_blood_bank`)
- **6 Sub-Modules**:
  1. `lab_Dashboard`: Pending orders, TAT (Turnaround Time) metrics, critical results queue.
  2. `lab_SampleTracking`: Phlebotomy worklist, specimen tube barcode generation (`wp_mc_lab_specimens`), sample rejection with mandatory reason.
  3. `lab_ResultsEntry`: Parameter-by-parameter numeric/qualitative entry with gender/age-specific normal reference ranges, automatic `L` / `H` / `LL` / `HH` abnormal & panic flagging.
  4. `lab_Verification`: Pathologist/Senior Technologist secondary verification (`verified_by`, `verified_at`) locking the report for printing/portal release.
  5. `lab_BloodBank`: Donor registry, blood bag inventory (`A+`, `A-`, `B+`, `B-`, `AB+`, `AB-`, `O+`, `O-`), cross-matching, transfusion reactions (`wp_mc_blood_bank`).
  6. `lab_Reagents`: Lab reagent stock & analyzer calibration tracking (`wp_mc_lab_reagents`).

### 1.4 Radiology Information System (`RIS` — `rad_*`, `wp_mc_orders`, `wp_mc_radiology_reports`)
- **3 Sub-Modules**:
  1. `rad_Worklist`: Modality worklist (`X-Ray`, `CT`, `MRI`, `Ultrasound`, `Mammography`, `Fluoroscopy`).
  2. `rad_Reporting`: Structured radiologist report editor (`Technique`, `Findings`, `Impression`, `Recommendations`, BI-RADS/TI-RADS scoring) + PACS study UID / local image attachment link.
  3. `rad_ContrastConsumables`: Tracks contrast media, films, and syringes consumed per study (linked to `FIN-004` FIFO inventory deduction).

### 1.5 Pharmacy & Multi-Warehouse Inventory (`pharmacy_inventory_*`, `wp_mc_inventory_*`, `wp_mc_pharmacy_dispenses`)
- **6 Sub-Modules**:
  1. `pharmacy_Dispensing`: Inpatient & Outpatient prescription dispensing against `wp_mc_prescriptions`, enforcing FIFO batch selection and expiry date blocks.
  2. `inventory_ItemsCatalog`: Master item catalog (`Drug`, `Medical Consumable`, `Surgical Supply`, `Lab Reagent`, `Asset`), reorder levels, barcode/GTIN.
  3. `inventory_StockBatches`: Per-warehouse batch tracking (`batch_number`, `expiry_date`, `unit_cost`, `selling_price`, `quantity_available`).
  4. `inventory_PurchaseReceipts`: Supplier GRN (`Goods Received Note` in `wp_mc_inventory_PurchaseReceipt`), bonus quantities, supplier invoice posting.
  5. `inventory_Transfers`: Inter-warehouse and department requisition transfers (`Main Store -> OR Store / ER Store / Pharmacy`).
  6. `inventory_Stocktake`: Physical inventory count & variance adjustment (`wp_mc_DualControlRequest` required for write-offs).

### 1.6 Inpatient Wards, Nursing, ICU/NICU, Surgery & Dialysis
- **Inpatient & Bed Map (`inpatient_*`, `wp_mc_admissions`, `wp_mc_beds`, `wp_mc_ward_rounds`)**: Interactive visual bed map by Ward/Room, admission deposit collection, daily room & nursing charge accrual, doctor ward round notes, discharge summary (`wp_mc_discharge_summaries`).
- **Nursing Station (`nurse_*`, `wp_mc_nursing_assessments`, `wp_mc_mar`)**: Medication Administration Record (`e-MAR` — scheduled dose verification), vital signs charting, fall-risk (Morse) & pressure-ulcer (Braden) assessments, shift nursing handover (SBAR).
- **ICU & NICU (`icu_nicu_*`, `wp_mc_icu_flows`, `wp_mc_clinical_scores`)**: Ventilator flowsheet (`Mode`, `FiO2`, `PEEP`, `Tidal Volume`), arterial blood gas (ABG) log, vasoactive infusion titration, NICU incubator temperature/humidity/phototherapy/daily weight in grams, APACHE II / SOFA / Ballard scores.
- **Surgery & Operating Theater (`surgery_*`, `wp_mc_surgeries`, `wp_mc_surgery_checklists`, `wp_mc_anesthesia_records`, `wp_mc_surgery_consumables`)**: OT room scheduling, surgeon/anesthesiologist/scrub nurse team assignment, WHO 3-phase safety checklist, intra-operative anesthesia vitals graph, implant & consumable barcode scanning.
- **Dialysis Unit (`dialysis_*`, `wp_mc_dialysis_machines`, `wp_mc_dialysis_sessions`, `wp_mc_dialysis_consumables`)**: Serology-isolated chair/machine allocation (`Hep B+`, `Hep C+`, `HIV`, `Negative`), dry weight & target ultrafiltration (UF) calculation, dialyzer filter & bloodline consumable tracking, nephrologist monthly review.
