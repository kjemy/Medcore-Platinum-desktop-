# MEDCORE — DATABASE MODEL (LOGICAL, CURRENT PHYSICAL & FUTURE OFFLINE MARIADB)
**Document ID**: `DOC-05` | **Source**: All 79 `CREATE TABLE` Definitions + 70 DBX Domains

> **Architectural Mandate (§10)**: This document separates the database extraction into three distinct parts:
> 1. **Part I — Logical Data Model** (Technology-agnostic domain entities, keys, classification: Source of Truth vs Derived vs Projection vs Snapshot vs Audit)
> 2. **Part II — Current Physical Implementation (`Project 3`)** (All 79 tables, columns, types, indexes, 4 orphan table references, and WordPress storage dependencies)
> 3. **Part III — Future Offline MariaDB Recommendation (`MedCore Desktop`)** (Normalized lowercase `snake_case` naming, explicit `InnoDB` foreign keys, removal of `wp_options` dependencies, and 6 new Desktop/Financial tables)

---

## PART I — LOGICAL DATA MODEL & DATA CLASSIFICATION

| Logical Entity | Physical Table(s) in P3 | Data Classification | Primary Key | Natural / Business Key | Tenant Scope | Mutability |
|---|---|---|---|---|---|---|
| `HospitalTenant` | `wp_mc_tenants`, `wp_mc_companies` | **Authoritative Source of Truth** | `id` | `hospital_code` (UNIQUE) | Root Tenant | Mutable (Admin) |
| `MasterDefinition` | `wp_mc_definitions` | **Authoritative Source of Truth** | `id` | `(hospital_code, type, code)` | `hospital_code` | Mutable (Versioned) |
| `DefinitionRule` | `wp_mc_definition_rules` | **Authoritative Source of Truth** | `id` | `rule_code` | `hospital_code` | Mutable (Effective-Dated) |
| `StaffMember` | `wp_mc_staff`, `wp_medcore_staff_directory` | **Authoritative Source of Truth** | `id` | `(hospital_code, email / staff_code)` | `hospital_code` | Mutable |
| `Patient` | `wp_mc_patients` | **Authoritative Source of Truth** | `id` | `(hospital_code, mrn / file_number)` | `hospital_code` | Mutable (Soft-Delete Only) |
| `Appointment` | `wp_mc_appointments` | **Authoritative Source of Truth** | `id` | `(hospital_code, appointment_number)` | `hospital_code` | State-Machine Mutable |
| `Visit` | `wp_mc_visits` | **Authoritative Source of Truth** | `id` | `(hospital_code, visit_number)` | `hospital_code` | Immutable Financials after Post (Adjust via Reversal) |
| `VisitItem` | `wp_mc_visit_items` | **Authoritative Source of Truth + Price Snapshot** | `id` | `(visit_id, line_no)` | `hospital_code` | Snapshot of `service_name`, `unit_price` at visit time |
| `FinancialEvent` | `wp_mc_financial_events` | **Authoritative Immutable Ledger** | `id` | `event_uuid`, `(hospital_code, idempotency_key)` | `hospital_code` | **APPEND-ONLY (Never Update/Delete)** |
| `FinancialPosting` | `wp_mc_financial_postings` | **Authoritative Sub-Ledger Legs** | `id` | `posting_uuid` | `hospital_code` | **APPEND-ONLY** (Status updates on settlement link only) |
| `InvoiceMirror` | `wp_mc_invoices`, `wp_mc_payments` | **Derived Projection / Legacy Mirror** | `id` | `invoice_number` | `hospital_code` | Derived from `Visit` & `FinancialEvent` |
| `CashierShift` | `wp_mc_shifts`, `wp_mc_shift_handovers` | **Authoritative Source of Truth** | `id` | `(hospital_code, shift_code)` | `hospital_code` | State-Machine (`OPEN -> CLOSED`) |
| `CommissionSettlement` | `wp_mc_commission_settlements` | **Authoritative Source of Truth** | `id` | `(hospital_code, settlement_number)` | `hospital_code` | State-Machine (`DRAFT -> APPROVED -> PAID`) |
| `DiagnosticOrder` | `wp_mc_orders` | **Authoritative Source of Truth** | `id` | `(hospital_code, order_number)` | `hospital_code` | State-Machine Mutable |
| `LabSpecimen` | `wp_mc_lab_specimens` | **Authoritative Source of Truth** | `id` | `barcode` | `hospital_code` | State-Machine Mutable |
| `LabResult` | `wp_mc_lab_results` | **Authoritative Clinical Record + Reference Range Snapshot** | `id` | `(order_id, parameter_code)` | `hospital_code` | Immutable once `VERIFIED` (Amended via Addendum) |
| `RadiologyReport` | `wp_mc_radiology_reports` | **Authoritative Clinical Record** | `id` | `order_id` | `hospital_code` | Immutable once `FINALIZED` |
| `InventoryItem` | `wp_mc_inventory_items` | **Authoritative Master** (`quantity` column is **Derived Cache**) | `id` | `(hospital_code, item_code)` | `hospital_code` | Master Mutable; stock derived from `StockBatch` |
| `StockBatch` | `wp_mc_inventory_StockBatch` | **Authoritative Source of Truth for On-Hand Qty & Unit Cost** | `id` | `(hospital_code, item_id, batch_number, warehouse_id)` | `hospital_code` | Mutated only via `StockMovement` inside DB transaction |
| `StockMovement` | `wp_mc_inventory_StockMovement` | **Authoritative Inventory Ledger** | `id` | `movement_uuid` | `hospital_code` | **APPEND-ONLY** |
| `Admission & Bed` | `wp_mc_admissions`, `wp_mc_beds` | **Authoritative Source of Truth** | `id` | `(hospital_code, admission_number)` | `hospital_code` | State-Machine Mutable |
| `SurgeryCase` | `wp_mc_surgeries`, `wp_mc_surgery_checklists`, `wp_mc_anesthesia_records`, `wp_mc_surgery_consumables` | **Authoritative Clinical Record** | `id` | `surgery_id` | `hospital_code` | State-Machine Mutable |
| `DialysisSession` | `wp_mc_dialysis_sessions`, `wp_mc_dialysis_machines`, `wp_mc_dialysis_consumables` | **Authoritative Clinical Record** | `id` | `session_id` | `hospital_code` | State-Machine Mutable |
| `IcuNicuFlow` | `wp_mc_icu_flows`, `wp_mc_clinical_scores` | **Authoritative Time-Series Clinical Record** | `id` | `(admission_id, recorded_at)` | `hospital_code` | Append-Only Clinical Observations |
| `AuditLog` | `wp_mc_audit_logs`, `wp_mc_security_logs` | **Audit Data (Append-Only)** | `id` | `(hospital_code, created_at, id)` | `hospital_code` | **STRICT APPEND-ONLY** |

---

## PART II — CURRENT PHYSICAL IMPLEMENTATION (`PROJECT 3` — ALL 79 TABLES)

> Full column-by-column DDL for every one of the 79 tables is also preserved in [`WS1_PHYSICAL_SCHEMA_INVENTORY.md`](file:///C:/Users/hp/Desktop/project%204/99_EVIDENCE/WS1_PHYSICAL_SCHEMA_INVENTORY.md). Below is the complete 79-table physical catalog with column counts, primary keys, unique constraints, indexes, and code reference counts.

| # | Physical Table Name (`${wpdb->prefix}`) | Defined In (`file:line`) | Cols | Primary Key | Unique Constraints | Indexes | SQL Refs |
|---|---|---|---|---|---|---|---:|
| 1 | `$table` | `Backend/MedCorePlugin/includes/core/class-medcore-debug-migration.php:L60-L74` | 12 | `id` | None | None | 0 |
| 2 | `$table_visits` | `Backend/MedCorePlugin/includes/core/class-medcore-visits-shift-migration.php:L84-L156` | 61 | `id` | UNIQUE KEY uq_public_id (public_id); UNIQUE KEY uq_visit_tenant_number (hospital_code, visit_number); UNIQUE KEY uq_command_id (hospital_code, command_id); UNIQUE KEY uq_tenant_appointment_visit (hospital_code, appointment_id) | KEY idx_visit_tenant_number (hospital_code, visit_number); KEY idx_tenant_clinic_date_queue (hospital_code, clinic_id, visit_date, queue_number); KEY idx_tenant_date_status (hospital_code, visit_date, status); KEY idx_tenant_patient (hospital_code, patient_id); KEY idx_tenant_doctor_date (hospital_code, doctor_id, visit_date) | 0 |
| 3 | `$wpdb->prefix` | `Backend/MedCorePlugin/includes/core/class-medcore-migration.php:L531-L549` | 14 | `id` | UNIQUE KEY uq_tenant_staff_email (hospital_code, staff_email) | KEY hospital_code (hospital_code) | 0 |
| 4 | `mc_admissions` | `Backend/MedCorePlugin/includes/core/class-medcore-admissions-migration.php:L12-L42` | 23 | `id` | UNIQUE KEY unique_admission_public (tenant_id, public_id); UNIQUE KEY unique_admission_idempotency (tenant_id, idempotency_key) | KEY idx_admission_patient (tenant_id, patient_id); KEY idx_admission_status (tenant_id, status); KEY idx_admission_type (tenant_id, admission_type) | 12 |
| 5 | `mc_ai_transactions` | `Backend/MedCorePlugin/includes/core/class-medcore-migration.php:L571-L586` | 12 | `id` | None | KEY tenant_idx (tenant_id) | 10 |
| 6 | `mc_ai_usage` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L116-L129` | 9 | `id` | UNIQUE KEY operation_id (operation_id) | KEY wallet_status (wallet_id, status) | 16 |
| 7 | `mc_apgar_scores` | `Backend/MedCorePlugin/includes/core/class-medcore-icu-nicu-clinical-migration.php:L31-L46` | 11 | `id` | UNIQUE KEY `uniq_public` (`tenant_id`, `public_id`) | KEY `idx_adm` (`tenant_id`, `admission_id`) | 8 |
| 8 | `mc_appointments` | `Backend/MedCorePlugin/includes/core/class-medcore-patient-domain-migration.php:L43-L69` | 21 | `id` | UNIQUE KEY uq_appt_public (public_id); UNIQUE KEY uq_appt_number (tenant_id, appointment_number); UNIQUE KEY uq_appt_idempotency (tenant_id, idempotency_key), KEY idx_appt_patient (tenant_id, patient_id, scheduled_at), KEY idx_appt_doctor (tenant_id, doctor_id, scheduled_at), KEY idx_appt_status (tenant_id, status, scheduled_at) | None | 16 |
| 9 | `mc_audit_log` | `Backend/MedCorePlugin/includes/core/class-medcore-migration.php:L552-L568` | 12 | `event_id` | None | KEY tenant_idx (tenant_id); KEY event_type_idx (event_type) | 11 |
| 10 | `mc_clinical_order_events` | `Backend/MedCorePlugin/includes/core/class-medcore-clinical-orders-migration.php:L127-L139` | 9 | `id` | None | KEY idx_clin_evt_order (tenant_id,order_id,occurred_at) | 6 |
| 11 | `mc_clinical_order_items` | `Backend/MedCorePlugin/includes/core/class-medcore-clinical-orders-migration.php:L33-L52` | 14 | `id` | UNIQUE KEY uq_clin_item_public (public_id) | KEY idx_clin_item_order (tenant_id,order_id); KEY idx_clin_item_definition (tenant_id,definition_id) | 20 |
| 12 | `mc_clinical_orders` | `Backend/MedCorePlugin/includes/core/class-medcore-clinical-orders-migration.php:L6-L32` | 18 | `id` | UNIQUE KEY uq_clin_order_public (public_id); UNIQUE KEY uq_clin_order_number (tenant_id,order_number); UNIQUE KEY uq_clin_order_idem (tenant_id,idempotency_key) | KEY idx_clin_order_patient (tenant_id,patient_id,occurred_at); KEY idx_clin_order_encounter (tenant_id,encounter_id); KEY idx_clin_order_type_status (tenant_id,order_type,status) | 13 |
| 13 | `mc_clinical_results` | `Backend/MedCorePlugin/includes/core/class-medcore-clinical-orders-migration.php:L77-L103` | 20 | `id` | UNIQUE KEY uq_result_public (public_id); UNIQUE KEY uq_result_idem (tenant_id,idempotency_key) | KEY idx_result_order (tenant_id,order_id,status); KEY idx_result_item (tenant_id,item_id) | 14 |
| 14 | `mc_clinical_specimens` | `Backend/MedCorePlugin/includes/core/class-medcore-clinical-orders-migration.php:L53-L76` | 17 | `id` | UNIQUE KEY uq_spec_public (public_id); UNIQUE KEY uq_spec_barcode (tenant_id,barcode); UNIQUE KEY uq_spec_idem (tenant_id,idempotency_key) | KEY idx_spec_order (tenant_id,order_id,status) | 8 |
| 15 | `mc_clinical_template_usages` | `Backend/MedCorePlugin/includes/core/class-medcore-clinical-templates-migration.php:L26-L42` | 11 | `id` | UNIQUE KEY uq_template_usage (public_id) | KEY idx_template_usage (tenant_id,template_id,used_at); KEY idx_template_usage_enc (tenant_id,encounter_id) | 4 |
| 16 | `mc_clinical_templates` | `Backend/MedCorePlugin/includes/core/class-medcore-clinical-templates-migration.php:L5-L25` | 17 | `id` | UNIQUE KEY uq_template_public (public_id), UNIQUE KEY uq_template_number (tenant_id,template_number), KEY idx_template_scope (tenant_id,status,category,specialty), KEY idx_template_owner (tenant_id,owner_type,owner_id) | None | 12 |
| 17 | `mc_coa_accounts` | `Backend/MedCorePlugin/includes/core/class-medcore-accounting-migration.php:L11-L24` | 9 | `id` | UNIQUE KEY `uq_coa_public` (`public_id`); UNIQUE KEY `uq_coa_code` (`tenant_id`, `code`) | None | 6 |
| 18 | `mc_consent_events` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L209-L219` | 7 | `id` | None | KEY user_purpose (user_id, purpose) | 3 |
| 19 | `mc_definition_links` | `Backend/MedCorePlugin/includes/core/class-medcore-definitions-migration.php:L71-L81` | 7 | `id` | UNIQUE KEY uq_definition_link (source_definition_id, relation_type, target_definition_id), KEY idx_link_source (tenant_id, source_definition_id, relation_type), KEY idx_link_target (tenant_id, target_definition_id, relation_type) | None | 2 |
| 20 | `mc_definition_rules` | `Backend/MedCorePlugin/includes/core/class-medcore-definitions-migration.php:L39-L68` | 25 | `id` | UNIQUE KEY uq_rule_public (public_id); UNIQUE KEY uq_rule_key_version (tenant_id, rule_key, version), KEY idx_rule_resolution (tenant_id, rule_type, subject_type, subject_id, target_type, target_id, status, precedence), KEY idx_rule_parent (tenant_id, parent_rule_id), KEY idx_rule_definition (tenant_id, definition_id), KEY idx_rule_validity (tenant_id, valid_from, valid_to) | None | 11 |
| 21 | `mc_definitions` | `Backend/MedCorePlugin/includes/core/class-medcore-definitions-migration.php:L17-L36` | 15 | `id` | UNIQUE KEY uq_definition_public (public_id); UNIQUE KEY uq_definition_version (tenant_id, definition_type, code, version), KEY idx_definition_lookup (tenant_id, definition_type, status, code), KEY idx_definition_validity (tenant_id, definition_type, valid_from, valid_to) | None | 42 |
| 22 | `mc_dialysis_sessions` | `Backend/MedCorePlugin/includes/core/class-medcore-dialysis-migration.php:L11-L34` | 17 | `id` | UNIQUE KEY unique_dialysis_public (tenant_id, public_id); UNIQUE KEY uq_dialysis_idempotency (tenant_id, idempotency_key) | KEY idx_dialysis_patient (tenant_id, patient_id); KEY idx_dialysis_status (tenant_id, status) | 13 |
| 23 | `mc_earning_lines` | `Backend/MedCorePlugin/includes/core/class-medcore-financial-migration.php:L45-L73` | 23 | `id` | UNIQUE KEY uq_earning_public (public_id); UNIQUE KEY uq_earning_line (financial_event_id,line_number); UNIQUE KEY uq_earning_idempotency (tenant_id,idempotency_key), KEY idx_earning_beneficiary (tenant_id,beneficiary_type,beneficiary_id,settlement_status), KEY idx_earning_event (tenant_id,financial_event_id), KEY idx_earning_provider (tenant_id,provider_id) | None | 22 |
| 24 | `mc_encounters` | `Backend/MedCorePlugin/includes/core/class-medcore-patient-domain-migration.php:L80-L113` | 28 | `id` | UNIQUE KEY uq_enc_public (public_id); UNIQUE KEY uq_enc_number (tenant_id, encounter_number); UNIQUE KEY uq_enc_idempotency (tenant_id, idempotency_key), KEY idx_enc_patient (tenant_id, patient_id, occurred_at), KEY idx_enc_provider (tenant_id, provider_id, occurred_at), KEY idx_enc_status (tenant_id, status, occurred_at) | None | 19 |
| 25 | `mc_entitlements` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L196-L206` | 7 | `id` | UNIQUE KEY target_feature (target_type, target_id, feature_id) | None | 3 |
| 26 | `mc_error_log` | `Backend/MedCorePlugin/includes/core/class-medcore-migration.php:L589-L601` | 10 | `id` | None | None | 2 |
| 27 | `mc_fallback_quotas` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L102-L113` | 8 | `id` | UNIQUE KEY member_wallet (membership_id, wallet_id) | None | 3 |
| 28 | `mc_features` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L177-L184` | 4 | `id` | UNIQUE KEY feature_key (feature_key) | None | 3 |
| 29 | `mc_files` | `Backend/MedCorePlugin/includes/class-medcore-schema.php:L93-L105, Backend/MedCorePlugin/includes/core/class-medcore-files-migration.php:L4-L32` | 22 | `id` | UNIQUE KEY uq_file_public (public_id); UNIQUE KEY uq_file_number (tenant_id,file_number); UNIQUE KEY uq_file_idem (tenant_id,idempotency_key) | KEY idx_tenant (tenant_id); KEY idx_file_patient (tenant_id,patient_id,created_at); KEY idx_file_entity (tenant_id,entity_type,entity_id); KEY idx_file_storage (tenant_id,storage_provider,storage_key) | 16 |
| 30 | `mc_financial_events` | `Backend/MedCorePlugin/includes/core/class-medcore-financial-migration.php:L19-L42` | 18 | `id` | UNIQUE KEY uq_fin_event_public (public_id); UNIQUE KEY uq_fin_event_number (tenant_id,event_number); UNIQUE KEY uq_fin_event_idempotency (tenant_id,idempotency_key), KEY idx_fin_source (tenant_id,source_type,source_id), KEY idx_fin_patient (tenant_id,patient_id,occurred_at), KEY idx_fin_status (tenant_id,status,posted_at) | None | 25 |
| 31 | `mc_financial_postings` | `Backend/MedCorePlugin/includes/core/class-medcore-financial-transaction-migration.php:L11-L32` | 15 | `id` | UNIQUE KEY uq_fin_post_public (public_id); UNIQUE KEY uq_fin_post_idem (tenant_id, idempotency_key) | KEY idx_fin_post_event (tenant_id, financial_event_id); KEY idx_fin_post_account (tenant_id, account_type, account_id) | 18 |
| 32 | `mc_financial_settlements` | `Backend/MedCorePlugin/includes/core/class-medcore-financial-settlement-migration.php:L4-L31` | 21 | `id` | UNIQUE KEY uq_settle_public (public_id); UNIQUE KEY uq_settle_number (tenant_id,settlement_number); UNIQUE KEY uq_settle_idem (tenant_id,idempotency_key) | KEY idx_settle_beneficiary (tenant_id,beneficiary_type,beneficiary_id,status) | 12 |
| 33 | `mc_hospitals` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L27-L37` | 6 | `id` | UNIQUE KEY public_alias (public_alias) | KEY organization_id (organization_id) | 3 |
| 34 | `mc_icu_apache2_scores` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L261-L275` | 9 | `id` | UNIQUE KEY public_id (public_id) | KEY tenant_admission (tenant_id, admission_id); KEY tenant_idem (tenant_id, idempotency_key) | 6 |
| 35 | `mc_icu_flowsheets` | `Backend/MedCorePlugin/includes/core/class-medcore-icu-nicu-clinical-migration.php:L11-L27` | 12 | `id` | UNIQUE KEY `uniq_public` (`tenant_id`, `public_id`) | KEY `idx_adm` (`tenant_id`, `admission_id`) | 8 |
| 36 | `mc_icu_sofa_scores` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L244-L258` | 9 | `id` | UNIQUE KEY public_id (public_id) | KEY tenant_admission (tenant_id, admission_id); KEY tenant_idem (tenant_id, idempotency_key) | 6 |
| 37 | `mc_identity_sequences` | `Backend/MedCorePlugin/includes/core/class-medcore-identity-migration.php:L178-L187` | 6 | `id` | UNIQUE KEY tenant_entity_year (tenant_id, entity_type, sequence_year) | None | 3 |
| 38 | `mc_inventory_balances` | `Backend/MedCorePlugin/includes/core/class-medcore-inventory-migration.php:L97-L109` | 9 | `id` | UNIQUE KEY uq_balance (tenant_id,item_id,location_id,batch_id), KEY idx_balance_location (tenant_id,location_id,item_id) | None | 11 |
| 39 | `mc_inventory_batches` | `Backend/MedCorePlugin/includes/core/class-medcore-inventory-migration.php:L50-L65` | 11 | `id` | UNIQUE KEY uq_batch_public (public_id); UNIQUE KEY uq_batch_idem (tenant_id,idempotency_key), KEY idx_batch_item (tenant_id,item_id,expiry_date) | None | 10 |
| 40 | `mc_inventory_items` | `Backend/MedCorePlugin/includes/core/class-medcore-inventory-migration.php:L30-L48` | 12 | `id` | UNIQUE KEY uq_item_public (public_id); UNIQUE KEY uq_item_number (tenant_id,item_number); UNIQUE KEY uq_item_code (tenant_id,item_code), KEY idx_item_definition (tenant_id,definition_id); UNIQUE KEY uq_item_idem (tenant_id,idempotency_key) | None | 19 |
| 41 | `mc_inventory_locations` | `Backend/MedCorePlugin/includes/core/class-medcore-inventory-migration.php:L10-L28` | 13 | `id` | UNIQUE KEY uq_location_public (public_id); UNIQUE KEY uq_location_number (tenant_id,location_number), KEY idx_location_type (tenant_id,location_type,status), KEY idx_location_parent (tenant_id,parent_location_id), KEY idx_location_owner (tenant_id,owner_type,owner_id); UNIQUE KEY uq_location_idem (tenant_id,idempotency_key) | None | 21 |
| 42 | `mc_inventory_movements` | `Backend/MedCorePlugin/includes/core/class-medcore-inventory-migration.php:L67-L95` | 23 | `id` | UNIQUE KEY uq_movement_public (public_id); UNIQUE KEY uq_movement_number (tenant_id,movement_number); UNIQUE KEY uq_movement_idempotency (tenant_id,idempotency_key), KEY idx_move_item_location (tenant_id,item_id,source_location_id,occurred_at), KEY idx_move_patient (tenant_id,patient_id,occurred_at), KEY idx_move_reference (tenant_id,source_reference_type,source_reference_id), KEY idx_move_custody (tenant_id,custody_type,custody_id) | None | 5 |
| 43 | `mc_inventory_requests` | `Backend/MedCorePlugin/includes/core/class-medcore-inventory-request-migration.php:L6-L41` | 24 | `id` | UNIQUE KEY uq_inv_req_public (public_id); UNIQUE KEY uq_inv_req_number (tenant_id,request_number); UNIQUE KEY uq_inv_req_idem (tenant_id,idempotency_key); UNIQUE KEY uq_inv_req_approve_idem (tenant_id,approve_idempotency_key); UNIQUE KEY uq_inv_req_reject_idem (tenant_id,reject_idempotency_key); UNIQUE KEY uq_inv_req_issue_idem (tenant_id,issue_idempotency_key) | KEY idx_inv_req_status (tenant_id,status,requested_at); KEY idx_inv_req_destination (tenant_id,destination_location_id,status); KEY idx_inv_req_item (tenant_id,item_id) | 10 |
| 44 | `mc_inventory_reservations` | `Backend/MedCorePlugin/includes/core/class-medcore-inventory-reservation-migration.php:L6-L29` | 16 | `id` | UNIQUE KEY uq_inv_res_public (public_id); UNIQUE KEY uq_inv_res_idem (tenant_id,idempotency_key) | KEY idx_inv_res_balance (tenant_id,item_id,location_id,batch_id,status); KEY idx_inv_res_request (tenant_id,request_id,status); KEY idx_inv_res_patient (tenant_id,patient_id,status) | 8 |
| 45 | `mc_journal_entries` | `Backend/MedCorePlugin/includes/core/class-medcore-accounting-migration.php:L27-L44` | 12 | `id` | UNIQUE KEY `uq_journal_public` (`public_id`); UNIQUE KEY `uq_journal_idem` (`tenant_id`, `idempotency_key`) | KEY `idx_journal_date` (`tenant_id`, `entry_date`) | 5 |
| 46 | `mc_journal_lines` | `Backend/MedCorePlugin/includes/core/class-medcore-accounting-migration.php:L47-L61` | 9 | `id` | UNIQUE KEY `uq_jline_public` (`public_id`) | KEY `idx_jline_entry` (`tenant_id`, `journal_entry_id`); KEY `idx_jline_account` (`tenant_id`, `account_id`) | 4 |
| 47 | `mc_lab_orders` | `Backend/MedCorePlugin/includes/core/class-medcore-migration.php:L489-L501` | 9 | `id` | None | KEY hospital_code (hospital_code) | 2 |
| 48 | `mc_lab_referrals` | `Backend/MedCorePlugin/includes/core/class-medcore-lab-referrals-migration.php:L6-L42` | 28 | `id` | UNIQUE KEY uq_lab_ref_public (public_id); UNIQUE KEY uq_lab_ref_number (tenant_id,referral_number); UNIQUE KEY uq_lab_ref_idem (tenant_id,idempotency_key) | KEY idx_lab_ref_source (tenant_id,source_order_id,source_item_id); KEY idx_lab_ref_destination (destination_tenant_id,status); KEY idx_lab_ref_status (tenant_id,status,requested_at) | 8 |
| 49 | `mc_lab_requests` | `Backend/MedCorePlugin/includes/class-medcore-schema.php:L41-L58` | 14 | `id` | None | KEY idx_hospital (hospital_code) | 2 |
| 50 | `mc_memberships` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L54-L66` | 8 | `id` | UNIQUE KEY user_hospital (user_id, hospital_id) | KEY hospital_id (hospital_id) | 3 |
| 51 | `mc_migration_exceptions` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L231-L241` | 7 | `id` | None | KEY run_id (run_id) | 3 |
| 52 | `mc_migration_runs` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L222-L228` | 4 | `id` | None | None | 3 |
| 53 | `mc_nicu_growth_logs` | `Backend/MedCorePlugin/includes/core/class-medcore-icu-nicu-clinical-migration.php:L72-L91, Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L299-L318` | 14 | `id` | UNIQUE KEY `uniq_public` (`tenant_id`, `public_id`); UNIQUE KEY uniq_public (tenant_id, public_id) | KEY `idx_tenant_pat` (`tenant_id`, `patient_id`); KEY `idx_tenant_inc` (`tenant_id`, `incubator_id`); KEY idx_tenant_pat (tenant_id, patient_id); KEY idx_tenant_inc (tenant_id, incubator_id) | 9 |
| 54 | `mc_nicu_telemetry` | `Backend/MedCorePlugin/includes/core/class-medcore-icu-nicu-clinical-migration.php:L50-L68, Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L278-L296` | 13 | `id` | UNIQUE KEY `uniq_public` (`tenant_id`, `public_id`); UNIQUE KEY uniq_public (tenant_id, public_id) | KEY `idx_tenant_inc` (`tenant_id`, `incubator_id`); KEY `idx_tenant_pat` (`tenant_id`, `patient_id`); KEY idx_tenant_inc (tenant_id, incubator_id); KEY idx_tenant_pat (tenant_id, patient_id) | 9 |
| 55 | `mc_nursing_tasks` | `Backend/MedCorePlugin/includes/core/class-medcore-nursing-migration.php:L4-L33` | 22 | `id` | UNIQUE KEY uq_nurse_public (public_id); UNIQUE KEY uq_nurse_number (tenant_id,task_number); UNIQUE KEY uq_nurse_idem (tenant_id,idempotency_key) | KEY idx_nurse_assigned (tenant_id,assigned_to,status,due_at); KEY idx_nurse_patient (tenant_id,patient_id,created_at) | 10 |
| 56 | `mc_operations` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L132-L141` | 6 | `id` | UNIQUE KEY idempotency_key (idempotency_key) | None | 6 |
| 57 | `mc_organizations` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L14-L24` | 7 | `id` | UNIQUE KEY public_alias (public_alias) | None | 3 |
| 58 | `mc_patient_profiles` | `Backend/MedCorePlugin/includes/core/class-medcore-patient-domain-migration.php:L12-L32` | 16 | `id` | UNIQUE KEY uq_profile_public (public_id); UNIQUE KEY uq_profile_patient (tenant_id, patient_id) | None | 12 |
| 59 | `mc_patients` | `Backend/MedCorePlugin/includes/core/class-medcore-migration.php:L474-L487` | 10 | `id` | None | KEY hospital_code (hospital_code) | 27 |
| 60 | `mc_pharmacy_dispenses` | `Backend/MedCorePlugin/includes/core/class-medcore-pharmacy-migration.php:L4-L25` | 15 | `id` | UNIQUE KEY uq_pharm_public (public_id); UNIQUE KEY uq_pharm_idem (tenant_id,idempotency_key) | KEY idx_pharm_rx (tenant_id,prescription_id); KEY idx_pharm_patient (tenant_id,patient_id) | 9 |
| 61 | `mc_plan_features` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L187-L193` | 3 | `id` | UNIQUE KEY plan_feature (plan_id, feature_id) | None | 3 |
| 62 | `mc_plans` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L144-L150` | 4 | `id` | None | None | 3 |
| 63 | `mc_prescription_items` | `Backend/MedCorePlugin/includes/core/class-medcore-clinical-orders-migration.php:L104-L126` | 17 | `id` | UNIQUE KEY uq_rx_item_public (public_id) | KEY idx_rx_item_rx (tenant_id,prescription_id); KEY idx_rx_item_med (tenant_id,medication_definition_id) | 13 |
| 64 | `mc_prescriptions` | `Backend/MedCorePlugin/includes/class-medcore-schema.php:L81-L91, Backend/MedCorePlugin/includes/core/class-medcore-migration.php:L517-L528` | 11 | `id` | None | KEY idx_hospital (hospital_code); KEY hospital_code (hospital_code) | 17 |
| 65 | `mc_radiology_orders` | `Backend/MedCorePlugin/includes/core/class-medcore-migration.php:L503-L515` | 9 | `id` | None | KEY hospital_code (hospital_code) | 2 |
| 66 | `mc_radiology_requests` | `Backend/MedCorePlugin/includes/class-medcore-schema.php:L61-L78` | 14 | `id` | None | KEY idx_hospital (hospital_code) | 2 |
| 67 | `mc_shifts` | `Backend/MedCorePlugin/includes/core/class-medcore-visits-shift-migration.php:L209-L245` | 29 | `id` | UNIQUE KEY uq_shift_public (public_id); UNIQUE KEY uq_shift_number (tenant_id, shift_number); UNIQUE KEY uq_shift_idempotency (tenant_id, idempotency_key) | KEY idx_shift_cashier_status (tenant_id, cashier_user_id, status); KEY idx_shift_status_opened (tenant_id, status, opened_at) | 23 |
| 68 | `mc_storage` | `Backend/MedCorePlugin/includes/core/class-medcore-migration.php:L464-L472` | 5 | `id` | UNIQUE KEY unique_store (hospital_code, store_key) | None | 24 |
| 69 | `mc_subscription_events` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L166-L174` | 5 | `id` | None | KEY subscription_id (subscription_id) | 4 |
| 70 | `mc_subscriptions` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L153-L163` | 7 | `id` | None | KEY organization_id (organization_id) | 4 |
| 71 | `mc_surgeries` | `Backend/MedCorePlugin/includes/core/class-medcore-surgery-migration.php:L11-L46` | 29 | `id` | UNIQUE KEY unique_surgery_public (tenant_id, public_id); UNIQUE KEY uq_surgery_idempotency (tenant_id, idempotency_key) | KEY idx_surgery_patient (tenant_id, patient_id); KEY idx_surgery_status (tenant_id, status) | 13 |
| 72 | `mc_sync_commands` | `Backend/MedCorePlugin/includes/core/class-medcore-identity-migration.php:L159-L175` | 13 | `id` | UNIQUE KEY uq_sync_command (tenant_id, command_id), KEY idx_sync_status (tenant_id, status, received_at), KEY idx_sync_device (tenant_id, device_id, received_at) | None | 3 |
| 73 | `mc_tenants` | `Backend/MedCorePlugin/includes/core/class-medcore-migration.php:L441-L460` | 16 | `id` | UNIQUE KEY unique_tenant (tenant_id) | None | 25 |
| 74 | `mc_users` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L40-L51` | 8 | `id` | UNIQUE KEY normalized_email (normalized_email) | None | 3 |
| 75 | `mc_visit_items` | `Backend/MedCorePlugin/includes/core/class-medcore-visits-shift-migration.php:L170-L196` | 21 | `id` | UNIQUE KEY uq_visit_item_public (public_id) | KEY idx_visit_items_visit (tenant_id, visit_id); KEY idx_visit_items_doctor (tenant_id, doctor_id) | 10 |
| 76 | `mc_visits` | `Backend/MedCorePlugin/includes/class-medcore-schema.php:L9-L38` | 25 | `id` | None | KEY idx_hospital (hospital_code); KEY idx_patient (patient_id) | 28 |
| 77 | `mc_wallet_ledger` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L86-L99` | 9 | `id` | UNIQUE KEY idempotency_key (idempotency_key) | KEY wallet_id (wallet_id) | 5 |
| 78 | `mc_wallets` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L69-L83` | 11 | `id` | UNIQUE KEY owner_wallet (owner_type, owner_id, wallet_type) | None | 13 |
| 79 | `mc_ward_beds` | `Backend/MedCorePlugin/includes/core/class-medcore-admissions-migration.php:L47-L58` | 8 | `id` | UNIQUE KEY unique_bed_public (tenant_id, public_id) | None | 5 |

---

## PART III — FUTURE OFFLINE MARIADB RECOMMENDATION (`MEDCORE DESKTOP`)

### 3.1 Structural Upgrades Required for Local MariaDB (`MedCore Desktop`)
1. **Drop `${wpdb->prefix}` (`wp_`) and Standardize to Lowercase `snake_case`**:
   - Rename all `wp_mc_*` tables to `mc_*`.
   - Rename the 4 mixed-case tables (`mc_inventory_StockBatch` → `mc_inventory_stock_batches`, `mc_inventory_StockMovement` → `mc_inventory_stock_movements`, `mc_inventory_PurchaseReceipt` → `mc_inventory_purchase_receipts`, `mc_inventory_SupplierReturn` → `mc_inventory_supplier_returns`, `mc_DualControlRequest` → `mc_dual_control_requests`) so Windows (`lower_case_table_names=1`) and Linux (`lower_case_table_names=0`) behave identically.
2. **Create Missing `mc_staff_evaluations` Table & Remove Legacy Orphan References**:
   - Add formal DDL for `mc_staff_evaluations` (currently queried in `class-api-hr.php:209-250` without `CREATE TABLE`).
   - Remove dead references to `mc_expenses`, `mc_lab_orders`, and `mc_radiology_orders`.
3. **Enforce `InnoDB` Foreign Keys & Monetary Precision**:
   - Standardize all monetary columns across `mc_visits`, `mc_visit_items`, `mc_invoices`, `mc_payments`, `mc_financial_events`, `mc_financial_postings`, and `mc_shifts` to `DECIMAL(14,4) NOT NULL DEFAULT 0.0000`.
   - Add `FOREIGN KEY` constraints with `ON DELETE RESTRICT` on all clinical and financial child tables.

### 3.2 Six New Authoritative Tables Required for `MedCore Desktop`

```sql
-- 1. Service & Consumable Cost Split Ledger (Solves FIN-GAP-01)
CREATE TABLE mc_visit_item_cost_lines (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    hospital_code VARCHAR(64) NOT NULL,
    visit_id BIGINT UNSIGNED NOT NULL,
    visit_item_id BIGINT UNSIGNED NOT NULL,
    component_type ENUM('SERVICE_LABOR', 'CONSUMABLE_MATERIAL', 'EQUIPMENT_FEE') NOT NULL,
    inventory_item_id BIGINT UNSIGNED NULL,
    stock_batch_id BIGINT UNSIGNED NULL,
    stock_movement_id BIGINT UNSIGNED NULL,
    quantity DECIMAL(12,4) NOT NULL DEFAULT 1.0000,
    unit_cost_fifo DECIMAL(14,4) NOT NULL DEFAULT 0.0000,
    total_cost_fifo DECIMAL(14,4) NOT NULL DEFAULT 0.0000,
    billed_gross_amount DECIMAL(14,4) NOT NULL DEFAULT 0.0000,
    billed_net_amount DECIMAL(14,4) NOT NULL DEFAULT 0.0000,
    is_commissionable TINYINT(1) NOT NULL DEFAULT 1,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_hospital_visit (hospital_code, visit_id),
    KEY idx_visit_item (visit_item_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 2. Local System Metadata (Replaces WordPress wp_options)
CREATE TABLE mc_local_meta (
    meta_key VARCHAR(128) NOT NULL PRIMARY KEY,
    hospital_code VARCHAR(64) NOT NULL DEFAULT 'GLOBAL',
    meta_value_json LONGTEXT NOT NULL,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 3. Cryptographic Device Registry & Binding (Solves SEC-FLAW-05)
CREATE TABLE mc_devices (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    hospital_code VARCHAR(64) NOT NULL,
    device_id VARCHAR(128) NOT NULL UNIQUE,
    device_name VARCHAR(191) NOT NULL,
    platform ENUM('WINDOWS', 'ANDROID', 'IPAD') NOT NULL,
    hw_fingerprint_sha256 CHAR(64) NOT NULL,
    device_public_key_ed25519 CHAR(64) NOT NULL,
    role_scope ENUM('SERVER_HOST', 'WORKSTATION', 'TABLET_CLINICAL', 'KIOSK') NOT NULL DEFAULT 'WORKSTATION',
    status ENUM('PENDING', 'ACTIVE', 'REVOKED', 'SUSPENDED') NOT NULL DEFAULT 'PENDING',
    last_seen_at DATETIME NULL,
    last_ip VARCHAR(64) NULL,
    approved_by BIGINT UNSIGNED NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_hosp_status (hospital_code, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 4. Signed Offline License Lease State
CREATE TABLE mc_license_state (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    hospital_code VARCHAR(64) NOT NULL UNIQUE,
    license_id VARCHAR(128) NOT NULL,
    edition VARCHAR(64) NOT NULL,
    entitled_modules_json TEXT NOT NULL,
    max_devices INT UNSIGNED NOT NULL DEFAULT 5,
    max_doctors INT UNSIGNED NOT NULL DEFAULT 10,
    ai_entitled TINYINT(1) NOT NULL DEFAULT 0,
    issued_at_utc DATETIME NOT NULL,
    expires_at_utc DATETIME NOT NULL,
    offline_grace_until_utc DATETIME NOT NULL,
    last_online_refresh_utc DATETIME NOT NULL,
    lease_payload_json LONGTEXT NOT NULL,
    ed25519_signature CHAR(128) NOT NULL,
    status ENUM('VALID', 'GRACE_PERIOD', 'EXPIRED_READ_ONLY', 'TAMPER_LOCKED') NOT NULL DEFAULT 'VALID'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 5. Anti-Clock-Rollback Monotonic High-Water Mark Guard
CREATE TABLE mc_clock_guard (
    id TINYINT UNSIGNED NOT NULL PRIMARY KEY DEFAULT 1,
    max_observed_utc DATETIME(3) NOT NULL,
    last_event_uuid VARCHAR(64) NULL,
    last_boot_monotonic_ms BIGINT UNSIGNED NOT NULL DEFAULT 0,
    rollback_detected TINYINT(1) NOT NULL DEFAULT 0,
    rollback_delta_seconds BIGINT NULL,
    locked_at_utc DATETIME NULL,
    unlocked_by_maintenance_token_id VARCHAR(128) NULL,
    hmac_seal CHAR(64) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 6. Encrypted Local Backup & Restore Ledger
CREATE TABLE mc_backup_runs (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    backup_uuid VARCHAR(64) NOT NULL UNIQUE,
    hospital_code VARCHAR(64) NOT NULL,
    trigger_type ENUM('SCHEDULED', 'MANUAL_ADMIN', 'PRE_MIGRATION', 'SERVICE_TOOL') NOT NULL,
    archive_path VARCHAR(512) NOT NULL,
    archive_sha256 CHAR(64) NOT NULL,
    archive_size_bytes BIGINT UNSIGNED NOT NULL,
    schema_version VARCHAR(32) NOT NULL,
    max_financial_event_id BIGINT UNSIGNED NOT NULL DEFAULT 0,
    status ENUM('RUNNING', 'COMPLETED', 'VERIFIED', 'FAILED') NOT NULL,
    created_by BIGINT UNSIGNED NULL,
    started_at DATETIME NOT NULL,
    completed_at DATETIME NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```