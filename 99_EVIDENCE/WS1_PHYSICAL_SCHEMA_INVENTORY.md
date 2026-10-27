# WS1 — Physical Database Schema Inventory (`Project 3`)

> **Classification**: `FACT` — Extracted statically from `Backend/MedCorePlugin/medcore.php`, `Backend/MedCorePlugin/includes/**/*.php`, and `Backend/medcore-database-explorer/api/class-dbx-api-router.php`.

## 1. Executive Summary of Physical Storage
- **Total `CREATE TABLE` DDL blocks extracted**: **79** tables (`78` prefixed `${wpdb->prefix}mc_*` + `1` legacy `${wpdb->prefix}medcore_staff_directory`).
- **Total distinct `mc_*` table names referenced in SQL queries**: **83**.
- **Orphan table references (queried/truncated in PHP but lacking `CREATE TABLE` DDL)**: **7** (`mc_activation_`, `mc_debug_log`, `mc_reset_`, `mc_storage_backup_20261021`, `mc_tables_count`, `mc_token_`, `mc_tpl_create_`).
- **Total `ALTER TABLE` schema patch blocks**: **12**.
- **Database Mirror Domain Registry (`medcore-database-explorer`)**: **70** logical domains mapped in `Backend/medcore-database-explorer/api/class-dbx-api-router.php:35-895`.

## 2. Summary Table of All 79 Defined Tables

| # | Table Name | Defined In (`file:line`) | Columns | Primary Key | Unique Keys | Indexes | Tenant Column | Code Refs |
|---|---|---|---|---|---|---|---|---|
| 1 | `$table` | `Backend/MedCorePlugin/includes/core/class-medcore-debug-migration.php:L60-L74` | 12 | `id` | None | None | `tenant_id` | 0 |
| 2 | `$table_visits` | `Backend/MedCorePlugin/includes/core/class-medcore-visits-shift-migration.php:L84-L156` | 61 | `id` | UNIQUE KEY uq_public_id (public_id); UNIQUE KEY uq_visit_tenant_number (hospital_code, visit_number); UNIQUE KEY uq_command_id (hospital_code, command_id); UNIQUE KEY uq_tenant_appointment_visit (hospital_code, appointment_id) | KEY idx_visit_tenant_number (hospital_code, visit_number); KEY idx_tenant_clinic_date_queue (hospital_code, clinic_id, visit_date, queue_number); KEY idx_tenant_date_status (hospital_code, visit_date, status); KEY idx_tenant_patient (hospital_code, patient_id); KEY idx_tenant_doctor_date (hospital_code, doctor_id, visit_date) | `hospital_code` | 0 |
| 3 | `$wpdb->prefix` | `Backend/MedCorePlugin/includes/core/class-medcore-migration.php:L531-L549` | 14 | `id` | UNIQUE KEY uq_tenant_staff_email (hospital_code, staff_email) | KEY hospital_code (hospital_code) | `hospital_code` | 0 |
| 4 | `mc_admissions` | `Backend/MedCorePlugin/includes/core/class-medcore-admissions-migration.php:L12-L42` | 23 | `id` | UNIQUE KEY unique_admission_public (tenant_id, public_id); UNIQUE KEY unique_admission_idempotency (tenant_id, idempotency_key) | KEY idx_admission_patient (tenant_id, patient_id); KEY idx_admission_status (tenant_id, status); KEY idx_admission_type (tenant_id, admission_type) | `tenant_id` | 12 |
| 5 | `mc_ai_transactions` | `Backend/MedCorePlugin/includes/core/class-medcore-migration.php:L571-L586` | 12 | `id` | None | KEY tenant_idx (tenant_id) | `tenant_id` | 10 |
| 6 | `mc_ai_usage` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L116-L129` | 9 | `id` | UNIQUE KEY operation_id (operation_id) | KEY wallet_status (wallet_id, status) | `NONE (Global/Cross-Tenant)` | 16 |
| 7 | `mc_apgar_scores` | `Backend/MedCorePlugin/includes/core/class-medcore-icu-nicu-clinical-migration.php:L31-L46` | 11 | `id` | UNIQUE KEY `uniq_public` (`tenant_id`, `public_id`) | KEY `idx_adm` (`tenant_id`, `admission_id`) | `tenant_id` | 8 |
| 8 | `mc_appointments` | `Backend/MedCorePlugin/includes/core/class-medcore-patient-domain-migration.php:L43-L69` | 21 | `id` | UNIQUE KEY uq_appt_public (public_id); UNIQUE KEY uq_appt_number (tenant_id, appointment_number); UNIQUE KEY uq_appt_idempotency (tenant_id, idempotency_key), KEY idx_appt_patient (tenant_id, patient_id, scheduled_at), KEY idx_appt_doctor (tenant_id, doctor_id, scheduled_at), KEY idx_appt_status (tenant_id, status, scheduled_at) | None | `tenant_id` | 16 |
| 9 | `mc_audit_log` | `Backend/MedCorePlugin/includes/core/class-medcore-migration.php:L552-L568` | 12 | `event_id` | None | KEY tenant_idx (tenant_id); KEY event_type_idx (event_type) | `tenant_id` | 11 |
| 10 | `mc_clinical_order_events` | `Backend/MedCorePlugin/includes/core/class-medcore-clinical-orders-migration.php:L127-L139` | 9 | `id` | None | KEY idx_clin_evt_order (tenant_id,order_id,occurred_at) | `tenant_id` | 6 |
| 11 | `mc_clinical_order_items` | `Backend/MedCorePlugin/includes/core/class-medcore-clinical-orders-migration.php:L33-L52` | 14 | `id` | UNIQUE KEY uq_clin_item_public (public_id) | KEY idx_clin_item_order (tenant_id,order_id); KEY idx_clin_item_definition (tenant_id,definition_id) | `tenant_id` | 20 |
| 12 | `mc_clinical_orders` | `Backend/MedCorePlugin/includes/core/class-medcore-clinical-orders-migration.php:L6-L32` | 18 | `id` | UNIQUE KEY uq_clin_order_public (public_id); UNIQUE KEY uq_clin_order_number (tenant_id,order_number); UNIQUE KEY uq_clin_order_idem (tenant_id,idempotency_key) | KEY idx_clin_order_patient (tenant_id,patient_id,occurred_at); KEY idx_clin_order_encounter (tenant_id,encounter_id); KEY idx_clin_order_type_status (tenant_id,order_type,status) | `tenant_id` | 13 |
| 13 | `mc_clinical_results` | `Backend/MedCorePlugin/includes/core/class-medcore-clinical-orders-migration.php:L77-L103` | 20 | `id` | UNIQUE KEY uq_result_public (public_id); UNIQUE KEY uq_result_idem (tenant_id,idempotency_key) | KEY idx_result_order (tenant_id,order_id,status); KEY idx_result_item (tenant_id,item_id) | `tenant_id` | 14 |
| 14 | `mc_clinical_specimens` | `Backend/MedCorePlugin/includes/core/class-medcore-clinical-orders-migration.php:L53-L76` | 17 | `id` | UNIQUE KEY uq_spec_public (public_id); UNIQUE KEY uq_spec_barcode (tenant_id,barcode); UNIQUE KEY uq_spec_idem (tenant_id,idempotency_key) | KEY idx_spec_order (tenant_id,order_id,status) | `tenant_id` | 8 |
| 15 | `mc_clinical_template_usages` | `Backend/MedCorePlugin/includes/core/class-medcore-clinical-templates-migration.php:L26-L42` | 11 | `id` | UNIQUE KEY uq_template_usage (public_id) | KEY idx_template_usage (tenant_id,template_id,used_at); KEY idx_template_usage_enc (tenant_id,encounter_id) | `tenant_id` | 4 |
| 16 | `mc_clinical_templates` | `Backend/MedCorePlugin/includes/core/class-medcore-clinical-templates-migration.php:L5-L25` | 17 | `id` | UNIQUE KEY uq_template_public (public_id), UNIQUE KEY uq_template_number (tenant_id,template_number), KEY idx_template_scope (tenant_id,status,category,specialty), KEY idx_template_owner (tenant_id,owner_type,owner_id) | None | `tenant_id` | 12 |
| 17 | `mc_coa_accounts` | `Backend/MedCorePlugin/includes/core/class-medcore-accounting-migration.php:L11-L24` | 9 | `id` | UNIQUE KEY `uq_coa_public` (`public_id`); UNIQUE KEY `uq_coa_code` (`tenant_id`, `code`) | None | `tenant_id` | 6 |
| 18 | `mc_consent_events` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L209-L219` | 7 | `id` | None | KEY user_purpose (user_id, purpose) | `NONE (Global/Cross-Tenant)` | 3 |
| 19 | `mc_definition_links` | `Backend/MedCorePlugin/includes/core/class-medcore-definitions-migration.php:L71-L81` | 7 | `id` | UNIQUE KEY uq_definition_link (source_definition_id, relation_type, target_definition_id), KEY idx_link_source (tenant_id, source_definition_id, relation_type), KEY idx_link_target (tenant_id, target_definition_id, relation_type) | None | `tenant_id` | 2 |
| 20 | `mc_definition_rules` | `Backend/MedCorePlugin/includes/core/class-medcore-definitions-migration.php:L39-L68` | 25 | `id` | UNIQUE KEY uq_rule_public (public_id); UNIQUE KEY uq_rule_key_version (tenant_id, rule_key, version), KEY idx_rule_resolution (tenant_id, rule_type, subject_type, subject_id, target_type, target_id, status, precedence), KEY idx_rule_parent (tenant_id, parent_rule_id), KEY idx_rule_definition (tenant_id, definition_id), KEY idx_rule_validity (tenant_id, valid_from, valid_to) | None | `tenant_id` | 11 |
| 21 | `mc_definitions` | `Backend/MedCorePlugin/includes/core/class-medcore-definitions-migration.php:L17-L36` | 15 | `id` | UNIQUE KEY uq_definition_public (public_id); UNIQUE KEY uq_definition_version (tenant_id, definition_type, code, version), KEY idx_definition_lookup (tenant_id, definition_type, status, code), KEY idx_definition_validity (tenant_id, definition_type, valid_from, valid_to) | None | `tenant_id` | 42 |
| 22 | `mc_dialysis_sessions` | `Backend/MedCorePlugin/includes/core/class-medcore-dialysis-migration.php:L11-L34` | 17 | `id` | UNIQUE KEY unique_dialysis_public (tenant_id, public_id); UNIQUE KEY uq_dialysis_idempotency (tenant_id, idempotency_key) | KEY idx_dialysis_patient (tenant_id, patient_id); KEY idx_dialysis_status (tenant_id, status) | `tenant_id` | 13 |
| 23 | `mc_earning_lines` | `Backend/MedCorePlugin/includes/core/class-medcore-financial-migration.php:L45-L73` | 23 | `id` | UNIQUE KEY uq_earning_public (public_id); UNIQUE KEY uq_earning_line (financial_event_id,line_number); UNIQUE KEY uq_earning_idempotency (tenant_id,idempotency_key), KEY idx_earning_beneficiary (tenant_id,beneficiary_type,beneficiary_id,settlement_status), KEY idx_earning_event (tenant_id,financial_event_id), KEY idx_earning_provider (tenant_id,provider_id) | None | `tenant_id` | 22 |
| 24 | `mc_encounters` | `Backend/MedCorePlugin/includes/core/class-medcore-patient-domain-migration.php:L80-L113` | 28 | `id` | UNIQUE KEY uq_enc_public (public_id); UNIQUE KEY uq_enc_number (tenant_id, encounter_number); UNIQUE KEY uq_enc_idempotency (tenant_id, idempotency_key), KEY idx_enc_patient (tenant_id, patient_id, occurred_at), KEY idx_enc_provider (tenant_id, provider_id, occurred_at), KEY idx_enc_status (tenant_id, status, occurred_at) | None | `tenant_id` | 19 |
| 25 | `mc_entitlements` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L196-L206` | 7 | `id` | UNIQUE KEY target_feature (target_type, target_id, feature_id) | None | `NONE (Global/Cross-Tenant)` | 3 |
| 26 | `mc_error_log` | `Backend/MedCorePlugin/includes/core/class-medcore-migration.php:L589-L601` | 10 | `id` | None | None | `tenant_id` | 2 |
| 27 | `mc_fallback_quotas` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L102-L113` | 8 | `id` | UNIQUE KEY member_wallet (membership_id, wallet_id) | None | `NONE (Global/Cross-Tenant)` | 3 |
| 28 | `mc_features` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L177-L184` | 4 | `id` | UNIQUE KEY feature_key (feature_key) | None | `NONE (Global/Cross-Tenant)` | 3 |
| 29 | `mc_files` | `Backend/MedCorePlugin/includes/class-medcore-schema.php:L93-L105, Backend/MedCorePlugin/includes/core/class-medcore-files-migration.php:L4-L32` | 22 | `id` | UNIQUE KEY uq_file_public (public_id); UNIQUE KEY uq_file_number (tenant_id,file_number); UNIQUE KEY uq_file_idem (tenant_id,idempotency_key) | KEY idx_tenant (tenant_id); KEY idx_file_patient (tenant_id,patient_id,created_at); KEY idx_file_entity (tenant_id,entity_type,entity_id); KEY idx_file_storage (tenant_id,storage_provider,storage_key) | `tenant_id` | 16 |
| 30 | `mc_financial_events` | `Backend/MedCorePlugin/includes/core/class-medcore-financial-migration.php:L19-L42` | 18 | `id` | UNIQUE KEY uq_fin_event_public (public_id); UNIQUE KEY uq_fin_event_number (tenant_id,event_number); UNIQUE KEY uq_fin_event_idempotency (tenant_id,idempotency_key), KEY idx_fin_source (tenant_id,source_type,source_id), KEY idx_fin_patient (tenant_id,patient_id,occurred_at), KEY idx_fin_status (tenant_id,status,posted_at) | None | `tenant_id` | 25 |
| 31 | `mc_financial_postings` | `Backend/MedCorePlugin/includes/core/class-medcore-financial-transaction-migration.php:L11-L32` | 15 | `id` | UNIQUE KEY uq_fin_post_public (public_id); UNIQUE KEY uq_fin_post_idem (tenant_id, idempotency_key) | KEY idx_fin_post_event (tenant_id, financial_event_id); KEY idx_fin_post_account (tenant_id, account_type, account_id) | `tenant_id` | 18 |
| 32 | `mc_financial_settlements` | `Backend/MedCorePlugin/includes/core/class-medcore-financial-settlement-migration.php:L4-L31` | 21 | `id` | UNIQUE KEY uq_settle_public (public_id); UNIQUE KEY uq_settle_number (tenant_id,settlement_number); UNIQUE KEY uq_settle_idem (tenant_id,idempotency_key) | KEY idx_settle_beneficiary (tenant_id,beneficiary_type,beneficiary_id,status) | `tenant_id` | 12 |
| 33 | `mc_hospitals` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L27-L37` | 6 | `id` | UNIQUE KEY public_alias (public_alias) | KEY organization_id (organization_id) | `NONE (Global/Cross-Tenant)` | 3 |
| 34 | `mc_icu_apache2_scores` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L261-L275` | 9 | `id` | UNIQUE KEY public_id (public_id) | KEY tenant_admission (tenant_id, admission_id); KEY tenant_idem (tenant_id, idempotency_key) | `tenant_id` | 6 |
| 35 | `mc_icu_flowsheets` | `Backend/MedCorePlugin/includes/core/class-medcore-icu-nicu-clinical-migration.php:L11-L27` | 12 | `id` | UNIQUE KEY `uniq_public` (`tenant_id`, `public_id`) | KEY `idx_adm` (`tenant_id`, `admission_id`) | `tenant_id` | 8 |
| 36 | `mc_icu_sofa_scores` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L244-L258` | 9 | `id` | UNIQUE KEY public_id (public_id) | KEY tenant_admission (tenant_id, admission_id); KEY tenant_idem (tenant_id, idempotency_key) | `tenant_id` | 6 |
| 37 | `mc_identity_sequences` | `Backend/MedCorePlugin/includes/core/class-medcore-identity-migration.php:L178-L187` | 6 | `id` | UNIQUE KEY tenant_entity_year (tenant_id, entity_type, sequence_year) | None | `tenant_id` | 3 |
| 38 | `mc_inventory_balances` | `Backend/MedCorePlugin/includes/core/class-medcore-inventory-migration.php:L97-L109` | 9 | `id` | UNIQUE KEY uq_balance (tenant_id,item_id,location_id,batch_id), KEY idx_balance_location (tenant_id,location_id,item_id) | None | `tenant_id` | 11 |
| 39 | `mc_inventory_batches` | `Backend/MedCorePlugin/includes/core/class-medcore-inventory-migration.php:L50-L65` | 11 | `id` | UNIQUE KEY uq_batch_public (public_id); UNIQUE KEY uq_batch_idem (tenant_id,idempotency_key), KEY idx_batch_item (tenant_id,item_id,expiry_date) | None | `tenant_id` | 10 |
| 40 | `mc_inventory_items` | `Backend/MedCorePlugin/includes/core/class-medcore-inventory-migration.php:L30-L48` | 12 | `id` | UNIQUE KEY uq_item_public (public_id); UNIQUE KEY uq_item_number (tenant_id,item_number); UNIQUE KEY uq_item_code (tenant_id,item_code), KEY idx_item_definition (tenant_id,definition_id); UNIQUE KEY uq_item_idem (tenant_id,idempotency_key) | None | `tenant_id` | 19 |
| 41 | `mc_inventory_locations` | `Backend/MedCorePlugin/includes/core/class-medcore-inventory-migration.php:L10-L28` | 13 | `id` | UNIQUE KEY uq_location_public (public_id); UNIQUE KEY uq_location_number (tenant_id,location_number), KEY idx_location_type (tenant_id,location_type,status), KEY idx_location_parent (tenant_id,parent_location_id), KEY idx_location_owner (tenant_id,owner_type,owner_id); UNIQUE KEY uq_location_idem (tenant_id,idempotency_key) | None | `tenant_id` | 21 |
| 42 | `mc_inventory_movements` | `Backend/MedCorePlugin/includes/core/class-medcore-inventory-migration.php:L67-L95` | 23 | `id` | UNIQUE KEY uq_movement_public (public_id); UNIQUE KEY uq_movement_number (tenant_id,movement_number); UNIQUE KEY uq_movement_idempotency (tenant_id,idempotency_key), KEY idx_move_item_location (tenant_id,item_id,source_location_id,occurred_at), KEY idx_move_patient (tenant_id,patient_id,occurred_at), KEY idx_move_reference (tenant_id,source_reference_type,source_reference_id), KEY idx_move_custody (tenant_id,custody_type,custody_id) | None | `tenant_id` | 5 |
| 43 | `mc_inventory_requests` | `Backend/MedCorePlugin/includes/core/class-medcore-inventory-request-migration.php:L6-L41` | 24 | `id` | UNIQUE KEY uq_inv_req_public (public_id); UNIQUE KEY uq_inv_req_number (tenant_id,request_number); UNIQUE KEY uq_inv_req_idem (tenant_id,idempotency_key); UNIQUE KEY uq_inv_req_approve_idem (tenant_id,approve_idempotency_key); UNIQUE KEY uq_inv_req_reject_idem (tenant_id,reject_idempotency_key); UNIQUE KEY uq_inv_req_issue_idem (tenant_id,issue_idempotency_key) | KEY idx_inv_req_status (tenant_id,status,requested_at); KEY idx_inv_req_destination (tenant_id,destination_location_id,status); KEY idx_inv_req_item (tenant_id,item_id) | `tenant_id` | 10 |
| 44 | `mc_inventory_reservations` | `Backend/MedCorePlugin/includes/core/class-medcore-inventory-reservation-migration.php:L6-L29` | 16 | `id` | UNIQUE KEY uq_inv_res_public (public_id); UNIQUE KEY uq_inv_res_idem (tenant_id,idempotency_key) | KEY idx_inv_res_balance (tenant_id,item_id,location_id,batch_id,status); KEY idx_inv_res_request (tenant_id,request_id,status); KEY idx_inv_res_patient (tenant_id,patient_id,status) | `tenant_id` | 8 |
| 45 | `mc_journal_entries` | `Backend/MedCorePlugin/includes/core/class-medcore-accounting-migration.php:L27-L44` | 12 | `id` | UNIQUE KEY `uq_journal_public` (`public_id`); UNIQUE KEY `uq_journal_idem` (`tenant_id`, `idempotency_key`) | KEY `idx_journal_date` (`tenant_id`, `entry_date`) | `tenant_id` | 5 |
| 46 | `mc_journal_lines` | `Backend/MedCorePlugin/includes/core/class-medcore-accounting-migration.php:L47-L61` | 9 | `id` | UNIQUE KEY `uq_jline_public` (`public_id`) | KEY `idx_jline_entry` (`tenant_id`, `journal_entry_id`); KEY `idx_jline_account` (`tenant_id`, `account_id`) | `tenant_id` | 4 |
| 47 | `mc_lab_orders` | `Backend/MedCorePlugin/includes/core/class-medcore-migration.php:L489-L501` | 9 | `id` | None | KEY hospital_code (hospital_code) | `hospital_code` | 2 |
| 48 | `mc_lab_referrals` | `Backend/MedCorePlugin/includes/core/class-medcore-lab-referrals-migration.php:L6-L42` | 28 | `id` | UNIQUE KEY uq_lab_ref_public (public_id); UNIQUE KEY uq_lab_ref_number (tenant_id,referral_number); UNIQUE KEY uq_lab_ref_idem (tenant_id,idempotency_key) | KEY idx_lab_ref_source (tenant_id,source_order_id,source_item_id); KEY idx_lab_ref_destination (destination_tenant_id,status); KEY idx_lab_ref_status (tenant_id,status,requested_at) | `tenant_id` | 8 |
| 49 | `mc_lab_requests` | `Backend/MedCorePlugin/includes/class-medcore-schema.php:L41-L58` | 14 | `id` | None | KEY idx_hospital (hospital_code) | `hospital_code` | 2 |
| 50 | `mc_memberships` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L54-L66` | 8 | `id` | UNIQUE KEY user_hospital (user_id, hospital_id) | KEY hospital_id (hospital_id) | `NONE (Global/Cross-Tenant)` | 3 |
| 51 | `mc_migration_exceptions` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L231-L241` | 7 | `id` | None | KEY run_id (run_id) | `NONE (Global/Cross-Tenant)` | 3 |
| 52 | `mc_migration_runs` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L222-L228` | 4 | `id` | None | None | `NONE (Global/Cross-Tenant)` | 3 |
| 53 | `mc_nicu_growth_logs` | `Backend/MedCorePlugin/includes/core/class-medcore-icu-nicu-clinical-migration.php:L72-L91, Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L299-L318` | 14 | `id` | UNIQUE KEY `uniq_public` (`tenant_id`, `public_id`); UNIQUE KEY uniq_public (tenant_id, public_id) | KEY `idx_tenant_pat` (`tenant_id`, `patient_id`); KEY `idx_tenant_inc` (`tenant_id`, `incubator_id`); KEY idx_tenant_pat (tenant_id, patient_id); KEY idx_tenant_inc (tenant_id, incubator_id) | `tenant_id` | 9 |
| 54 | `mc_nicu_telemetry` | `Backend/MedCorePlugin/includes/core/class-medcore-icu-nicu-clinical-migration.php:L50-L68, Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L278-L296` | 13 | `id` | UNIQUE KEY `uniq_public` (`tenant_id`, `public_id`); UNIQUE KEY uniq_public (tenant_id, public_id) | KEY `idx_tenant_inc` (`tenant_id`, `incubator_id`); KEY `idx_tenant_pat` (`tenant_id`, `patient_id`); KEY idx_tenant_inc (tenant_id, incubator_id); KEY idx_tenant_pat (tenant_id, patient_id) | `tenant_id` | 9 |
| 55 | `mc_nursing_tasks` | `Backend/MedCorePlugin/includes/core/class-medcore-nursing-migration.php:L4-L33` | 22 | `id` | UNIQUE KEY uq_nurse_public (public_id); UNIQUE KEY uq_nurse_number (tenant_id,task_number); UNIQUE KEY uq_nurse_idem (tenant_id,idempotency_key) | KEY idx_nurse_assigned (tenant_id,assigned_to,status,due_at); KEY idx_nurse_patient (tenant_id,patient_id,created_at) | `tenant_id` | 10 |
| 56 | `mc_operations` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L132-L141` | 6 | `id` | UNIQUE KEY idempotency_key (idempotency_key) | None | `NONE (Global/Cross-Tenant)` | 6 |
| 57 | `mc_organizations` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L14-L24` | 7 | `id` | UNIQUE KEY public_alias (public_alias) | None | `NONE (Global/Cross-Tenant)` | 3 |
| 58 | `mc_patient_profiles` | `Backend/MedCorePlugin/includes/core/class-medcore-patient-domain-migration.php:L12-L32` | 16 | `id` | UNIQUE KEY uq_profile_public (public_id); UNIQUE KEY uq_profile_patient (tenant_id, patient_id) | None | `tenant_id` | 12 |
| 59 | `mc_patients` | `Backend/MedCorePlugin/includes/core/class-medcore-migration.php:L474-L487` | 10 | `id` | None | KEY hospital_code (hospital_code) | `hospital_code` | 27 |
| 60 | `mc_pharmacy_dispenses` | `Backend/MedCorePlugin/includes/core/class-medcore-pharmacy-migration.php:L4-L25` | 15 | `id` | UNIQUE KEY uq_pharm_public (public_id); UNIQUE KEY uq_pharm_idem (tenant_id,idempotency_key) | KEY idx_pharm_rx (tenant_id,prescription_id); KEY idx_pharm_patient (tenant_id,patient_id) | `tenant_id` | 9 |
| 61 | `mc_plan_features` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L187-L193` | 3 | `id` | UNIQUE KEY plan_feature (plan_id, feature_id) | None | `NONE (Global/Cross-Tenant)` | 3 |
| 62 | `mc_plans` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L144-L150` | 4 | `id` | None | None | `NONE (Global/Cross-Tenant)` | 3 |
| 63 | `mc_prescription_items` | `Backend/MedCorePlugin/includes/core/class-medcore-clinical-orders-migration.php:L104-L126` | 17 | `id` | UNIQUE KEY uq_rx_item_public (public_id) | KEY idx_rx_item_rx (tenant_id,prescription_id); KEY idx_rx_item_med (tenant_id,medication_definition_id) | `tenant_id` | 13 |
| 64 | `mc_prescriptions` | `Backend/MedCorePlugin/includes/class-medcore-schema.php:L81-L91, Backend/MedCorePlugin/includes/core/class-medcore-migration.php:L517-L528` | 11 | `id` | None | KEY idx_hospital (hospital_code); KEY hospital_code (hospital_code) | `hospital_code` | 17 |
| 65 | `mc_radiology_orders` | `Backend/MedCorePlugin/includes/core/class-medcore-migration.php:L503-L515` | 9 | `id` | None | KEY hospital_code (hospital_code) | `hospital_code` | 2 |
| 66 | `mc_radiology_requests` | `Backend/MedCorePlugin/includes/class-medcore-schema.php:L61-L78` | 14 | `id` | None | KEY idx_hospital (hospital_code) | `hospital_code` | 2 |
| 67 | `mc_shifts` | `Backend/MedCorePlugin/includes/core/class-medcore-visits-shift-migration.php:L209-L245` | 29 | `id` | UNIQUE KEY uq_shift_public (public_id); UNIQUE KEY uq_shift_number (tenant_id, shift_number); UNIQUE KEY uq_shift_idempotency (tenant_id, idempotency_key) | KEY idx_shift_cashier_status (tenant_id, cashier_user_id, status); KEY idx_shift_status_opened (tenant_id, status, opened_at) | `tenant_id` | 23 |
| 68 | `mc_storage` | `Backend/MedCorePlugin/includes/core/class-medcore-migration.php:L464-L472` | 5 | `id` | UNIQUE KEY unique_store (hospital_code, store_key) | None | `hospital_code` | 24 |
| 69 | `mc_subscription_events` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L166-L174` | 5 | `id` | None | KEY subscription_id (subscription_id) | `NONE (Global/Cross-Tenant)` | 4 |
| 70 | `mc_subscriptions` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L153-L163` | 7 | `id` | None | KEY organization_id (organization_id) | `NONE (Global/Cross-Tenant)` | 4 |
| 71 | `mc_surgeries` | `Backend/MedCorePlugin/includes/core/class-medcore-surgery-migration.php:L11-L46` | 29 | `id` | UNIQUE KEY unique_surgery_public (tenant_id, public_id); UNIQUE KEY uq_surgery_idempotency (tenant_id, idempotency_key) | KEY idx_surgery_patient (tenant_id, patient_id); KEY idx_surgery_status (tenant_id, status) | `tenant_id` | 13 |
| 72 | `mc_sync_commands` | `Backend/MedCorePlugin/includes/core/class-medcore-identity-migration.php:L159-L175` | 13 | `id` | UNIQUE KEY uq_sync_command (tenant_id, command_id), KEY idx_sync_status (tenant_id, status, received_at), KEY idx_sync_device (tenant_id, device_id, received_at) | None | `tenant_id` | 3 |
| 73 | `mc_tenants` | `Backend/MedCorePlugin/includes/core/class-medcore-migration.php:L441-L460` | 16 | `id` | UNIQUE KEY unique_tenant (tenant_id) | None | `tenant_id` | 25 |
| 74 | `mc_users` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L40-L51` | 8 | `id` | UNIQUE KEY normalized_email (normalized_email) | None | `NONE (Global/Cross-Tenant)` | 3 |
| 75 | `mc_visit_items` | `Backend/MedCorePlugin/includes/core/class-medcore-visits-shift-migration.php:L170-L196` | 21 | `id` | UNIQUE KEY uq_visit_item_public (public_id) | KEY idx_visit_items_visit (tenant_id, visit_id); KEY idx_visit_items_doctor (tenant_id, doctor_id) | `tenant_id` | 10 |
| 76 | `mc_visits` | `Backend/MedCorePlugin/includes/class-medcore-schema.php:L9-L38` | 25 | `id` | None | KEY idx_hospital (hospital_code); KEY idx_patient (patient_id) | `hospital_code` | 28 |
| 77 | `mc_wallet_ledger` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L86-L99` | 9 | `id` | UNIQUE KEY idempotency_key (idempotency_key) | KEY wallet_id (wallet_id) | `NONE (Global/Cross-Tenant)` | 5 |
| 78 | `mc_wallets` | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L69-L83` | 11 | `id` | UNIQUE KEY owner_wallet (owner_type, owner_id, wallet_type) | None | `NONE (Global/Cross-Tenant)` | 13 |
| 79 | `mc_ward_beds` | `Backend/MedCorePlugin/includes/core/class-medcore-admissions-migration.php:L47-L58` | 8 | `id` | UNIQUE KEY unique_bed_public (tenant_id, public_id) | None | `tenant_id` | 5 |

## 3. Detailed Column-Level DDL Specifications (All 79 Tables)

### 3.1 `$table` (`Backend/MedCorePlugin/includes/core/class-medcore-debug-migration.php:L60-L74`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `tenant_id` | `varchar(50)` | `True` | `None` | `NULL` |
| `request_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `level` | `varchar(20)` | `False` | `'INFO'` | `NOT NULL DEFAULT 'INFO'` |
| `component` | `varchar(100)` | `False` | `None` | `NOT NULL` |
| `stage` | `varchar(100)` | `False` | `None` | `NOT NULL` |
| `entity_type` | `varchar(100)` | `True` | `None` | `NULL` |
| `entity_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `message` | `text` | `True` | `None` | `NULL` |
| `payload_json` | `longtext` | `True` | `None` | `NULL` |
| `duration_ms` | `decimal(14` | `True` | `None` | `,3) NULL` |
| `created_at` | `datetime` | `False` | `None` | `NOT NULL` |

### 3.2 `$table_visits` (`Backend/MedCorePlugin/includes/core/class-medcore-visits-shift-migration.php:L84-L156`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `hospital_code` | `varchar(50)` | `False` | `'default'` | `NOT NULL DEFAULT 'default'` |
| `tenant_id` | `varchar(50)` | `True` | `None` | `NULL` |
| `visit_number` | `varchar(30)` | `False` | `None` | `NOT NULL` |
| `patient_id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL` |
| `appointment_id` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `encounter_id` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `financial_event_id` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `shift_id` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `clinic_id` | `varchar(100)` | `False` | `'general'` | `NOT NULL DEFAULT 'general'` |
| `department_id` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `doctor_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `visit_type` | `varchar(40)` | `False` | `'exam'` | `NOT NULL DEFAULT 'exam'` |
| `entry_mode` | `varchar(30)` | `False` | `'direct_in'` | `NOT NULL DEFAULT 'direct_in'` |
| `visit_date` | `date` | `False` | `None` | `NOT NULL` |
| `visit_time` | `time` | `True` | `None` | `NULL` |
| `chief_complaint` | `text` | `True` | `None` | `NULL` |
| `examination` | `text` | `True` | `None` | `NULL` |
| `history` | `text` | `True` | `None` | `NULL` |
| `diagnosis` | `text` | `True` | `None` | `NULL` |
| `queue_number` | `int(10) unsigned` | `False` | `1` | `NOT NULL DEFAULT 1` |
| `priority` | `varchar(20)` | `False` | `'normal'` | `NOT NULL DEFAULT 'normal'` |
| `status` | `varchar(30)` | `False` | `'WAITING'` | `NOT NULL DEFAULT 'WAITING'` |
| `payment_method` | `varchar(64)` | `False` | `'cash'` | `NOT NULL DEFAULT 'cash'` |
| `payments` | `longtext` | `True` | `None` | `NULL` |
| `payment_status` | `varchar(30)` | `False` | `'paid'` | `NOT NULL DEFAULT 'paid'` |
| `insurance_company_id` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `policy_number` | `varchar(100)` | `True` | `None` | `NULL` |
| `coverage_percentage` | `decimal(5` | `True` | `0.00` | `,2) NULL DEFAULT 0.00` |
| `copay_amount` | `decimal(14` | `False` | `0.0000` | `,4) NOT NULL DEFAULT 0.0000` |
| `gross_amount` | `decimal(14` | `False` | `0.0000` | `,4) NOT NULL DEFAULT 0.0000` |
| `discount_amount` | `decimal(14` | `False` | `0.0000` | `,4) NOT NULL DEFAULT 0.0000` |
| `insurance_covered_amount` | `decimal(14` | `False` | `0.0000` | `,4) NOT NULL DEFAULT 0.0000` |
| `net_amount` | `decimal(14` | `False` | `0.0000` | `,4) NOT NULL DEFAULT 0.0000` |
| `paid_amount` | `decimal(14` | `False` | `0.0000` | `,4) NOT NULL DEFAULT 0.0000` |
| `balance_amount` | `decimal(14` | `False` | `0.0000` | `,4) NOT NULL DEFAULT 0.0000` |
| `total_amount` | `decimal(14` | `False` | `0.0000` | `,4) NOT NULL DEFAULT 0.0000` |
| `total_paid` | `decimal(14` | `False` | `0.0000` | `,4) NOT NULL DEFAULT 0.0000` |
| `total_balance` | `decimal(14` | `False` | `0.0000` | `,4) NOT NULL DEFAULT 0.0000` |
| `doctor_earning_amount` | `decimal(14` | `False` | `0.0000` | `,4) NOT NULL DEFAULT 0.0000` |
| `hospital_share_amount` | `decimal(14` | `False` | `0.0000` | `,4) NOT NULL DEFAULT 0.0000` |
| `currency` | `varchar(20)` | `False` | `'EGP'` | `NOT NULL DEFAULT 'EGP'` |
| `notes` | `text` | `True` | `None` | `NULL` |
| `cancellation_reason` | `text` | `True` | `None` | `NULL` |
| `command_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `payload_hash` | `char(64)` | `True` | `None` | `NULL` |
| `source_device_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `local_sequence` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `occurred_at` | `datetime` | `True` | `None` | `NULL` |
| `synced_at` | `datetime` | `True` | `None` | `NULL` |
| `checked_in_at` | `datetime` | `True` | `None` | `NULL` |
| `called_at` | `datetime` | `True` | `None` | `NULL` |
| `completed_at` | `datetime` | `True` | `None` | `NULL` |
| `cancelled_at` | `datetime` | `True` | `None` | `NULL` |
| `closed_at` | `datetime` | `True` | `None` | `NULL` |
| `created_by` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `updated_by` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `closed_by` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `created_at` | `datetime` | `False` | `CURRENT_TIMESTAMP` | `NOT NULL DEFAULT CURRENT_TIMESTAMP` |
| `updated_at` | `datetime` | `False` | `CURRENT_TIMESTAMP` | `NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP` |

### 3.3 `$wpdb->prefix` (`Backend/MedCorePlugin/includes/core/class-medcore-migration.php:L531-L549`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20)` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `hospital_code` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `staff_email` | `varchar(100)` | `False` | `None` | `NOT NULL` |
| `password` | `varchar(255)` | `False` | `None` | `NOT NULL` |
| `staff_name` | `varchar(255)` | `False` | `None` | `NOT NULL` |
| `role` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `specialty` | `varchar(100)` | `True` | `None` | `` |
| `phone` | `varchar(50)` | `True` | `None` | `` |
| `license_number` | `varchar(100)` | `True` | `None` | `` |
| `status` | `varchar(20)` | `True` | `'active'` | `DEFAULT 'active'` |
| `ai_personal_tokens` | `bigint(20)` | `False` | `'0'` | `NOT NULL DEFAULT '0'` |
| `marketing_consent` | `varchar(20)` | `True` | `'NOT_REQUESTED'` | `DEFAULT 'NOT_REQUESTED'` |
| `updated_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP` |
| `created_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |

### 3.4 `mc_admissions` (`Backend/MedCorePlugin/includes/core/class-medcore-admissions-migration.php:L12-L42`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20)` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `patient_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `encounter_id` | `varchar(36)` | `True` | `None` | `NULL` |
| `admission_type` | `varchar(50)` | `False` | `None` | `NOT NULL, -- WARD, ICU, NICU` |
| `department_id` | `varchar(36)` | `True` | `None` | `NULL` |
| `room_id` | `varchar(36)` | `True` | `None` | `NULL` |
| `bed_id` | `varchar(36)` | `True` | `None` | `NULL` |
| `admission_date` | `datetime` | `False` | `None` | `NOT NULL` |
| `expected_discharge_date` | `datetime` | `True` | `None` | `NULL` |
| `actual_discharge_date` | `datetime` | `True` | `None` | `NULL` |
| `discharge_date` | `datetime` | `True` | `None` | `NULL` |
| `discharge_reason` | `text` | `True` | `None` | `NULL` |
| `attending_doctor_id` | `varchar(36)` | `True` | `None` | `NULL` |
| `referring_doctor_id` | `varchar(36)` | `True` | `None` | `NULL` |
| `diagnosis_json` | `longtext` | `True` | `None` | `NULL` |
| `clinical_notes_json` | `longtext` | `True` | `None` | `NULL` |
| `status` | `varchar(50)` | `True` | `'Admitted'` | `DEFAULT 'Admitted', -- Admitted, Discharged, Transferred` |
| `created_by` | `varchar(100)` | `True` | `None` | `NULL` |
| `idempotency_key` | `varchar(100)` | `True` | `None` | `NULL` |
| `created_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |
| `updated_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP` |

### 3.5 `mc_ai_transactions` (`Backend/MedCorePlugin/includes/core/class-medcore-migration.php:L571-L586`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20)` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `timestamp` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |
| `actor_email` | `varchar(100)` | `True` | `None` | `` |
| `tenant_id` | `varchar(50)` | `True` | `None` | `` |
| `provider` | `varchar(50)` | `True` | `None` | `` |
| `model` | `varchar(50)` | `True` | `None` | `` |
| `token_amount` | `bigint(20)` | `True` | `None` | `` |
| `action_type` | `varchar(20)` | `True` | `None` | `` |
| `balance_before` | `bigint(20)` | `True` | `None` | `` |
| `balance_after` | `bigint(20)` | `True` | `None` | `` |
| `request_id` | `varchar(50)` | `True` | `None` | `` |
| `status` | `varchar(50)` | `True` | `None` | `` |

### 3.6 `mc_ai_usage` (`Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L116-L129`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `operation_id` | `varchar(100)` | `False` | `None` | `NOT NULL` |
| `wallet_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `reserved_amount` | `bigint(20)` | `False` | `'0'` | `NOT NULL DEFAULT '0'` |
| `status` | `varchar(50)` | `False` | `'PENDING'` | `NOT NULL DEFAULT 'PENDING'` |
| `provider_operation_id` | `varchar(100)` | `True` | `None` | `` |
| `provider_reconciliation_id` | `varchar(100)` | `True` | `None` | `` |
| `created_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |
| `updated_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP` |

### 3.7 `mc_apgar_scores` (`Backend/MedCorePlugin/includes/core/class-medcore-icu-nicu-clinical-migration.php:L31-L46`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20)` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `admission_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `min1_score` | `int(11)` | `True` | `None` | `NULL` |
| `min5_score` | `int(11)` | `True` | `None` | `NULL` |
| `min10_score` | `int(11)` | `True` | `None` | `NULL` |
| `details_json` | `longtext` | `True` | `None` | `NULL` |
| `created_by` | `varchar(100)` | `True` | `None` | `NULL` |
| `idempotency_key` | `varchar(100)` | `True` | `None` | `NULL` |
| `created_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |

### 3.8 `mc_appointments` (`Backend/MedCorePlugin/includes/core/class-medcore-patient-domain-migration.php:L43-L69`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `appointment_number` | `varchar(40)` | `False` | `None` | `NOT NULL` |
| `idempotency_key` | `varchar(191)` | `True` | `None` | `NULL` |
| `source_device_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `local_sequence` | `bigint unsigned` | `True` | `None` | `NULL` |
| `patient_id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL` |
| `clinic_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `doctor_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `appointment_type` | `varchar(40)` | `False` | `'CONSULTATION'` | `NOT NULL DEFAULT 'CONSULTATION'` |
| `scheduled_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `duration_minutes` | `int unsigned` | `True` | `None` | `NULL` |
| `status` | `varchar(30)` | `False` | `'SCHEDULED'` | `NOT NULL DEFAULT 'SCHEDULED'` |
| `reason` | `text` | `True` | `None` | `NULL` |
| `notes` | `text` | `True` | `None` | `NULL` |
| `cancellation_reason` | `text` | `True` | `None` | `NULL` |
| `created_by` | `varchar(100)` | `True` | `None` | `NULL` |
| `occurred_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `created_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `updated_at` | `datetime` | `False` | `None` | `NOT NULL` |

### 3.9 `mc_audit_log` (`Backend/MedCorePlugin/includes/core/class-medcore-migration.php:L552-L568`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `event_id` | `bigint(20)` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `timestamp` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |
| `event_type` | `varchar(100)` | `False` | `None` | `NOT NULL` |
| `actor_email` | `varchar(100)` | `True` | `None` | `` |
| `tenant_id` | `varchar(50)` | `True` | `None` | `` |
| `target_type` | `varchar(50)` | `True` | `None` | `` |
| `target_id` | `varchar(100)` | `True` | `None` | `` |
| `action` | `varchar(50)` | `True` | `None` | `` |
| `status` | `varchar(50)` | `True` | `None` | `` |
| `ip_address` | `varchar(45)` | `True` | `None` | `` |
| `user_agent` | `varchar(255)` | `True` | `None` | `` |
| `request_id` | `varchar(50)` | `True` | `None` | `` |

### 3.10 `mc_clinical_order_events` (`Backend/MedCorePlugin/includes/core/class-medcore-clinical-orders-migration.php:L127-L139`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `order_id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL` |
| `event_type` | `varchar(40)` | `False` | `None` | `NOT NULL` |
| `from_status` | `varchar(40)` | `True` | `None` | `NULL` |
| `to_status` | `varchar(40)` | `True` | `None` | `NULL` |
| `actor_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `payload_json` | `longtext` | `True` | `None` | `NULL` |
| `occurred_at` | `datetime` | `False` | `None` | `NOT NULL` |

### 3.11 `mc_clinical_order_items` (`Backend/MedCorePlugin/includes/core/class-medcore-clinical-orders-migration.php:L33-L52`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `order_id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL` |
| `item_type` | `varchar(30)` | `False` | `None` | `NOT NULL` |
| `definition_id` | `varchar(36)` | `True` | `None` | `NULL` |
| `item_code` | `varchar(100)` | `True` | `None` | `NULL` |
| `item_name` | `varchar(190)` | `False` | `None` | `NOT NULL` |
| `quantity` | `decimal(12` | `False` | `1` | `,3) NOT NULL DEFAULT 1` |
| `price` | `decimal(18` | `True` | `None` | `,4) NULL` |
| `result_status` | `varchar(30)` | `False` | `'PENDING'` | `NOT NULL DEFAULT 'PENDING'` |
| `payload_json` | `longtext` | `True` | `None` | `NULL` |
| `created_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `updated_at` | `datetime` | `False` | `None` | `NOT NULL` |

### 3.12 `mc_clinical_orders` (`Backend/MedCorePlugin/includes/core/class-medcore-clinical-orders-migration.php:L6-L32`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `order_number` | `varchar(40)` | `False` | `None` | `NOT NULL` |
| `idempotency_key` | `varchar(191)` | `True` | `None` | `NULL` |
| `encounter_id` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `patient_id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL` |
| `provider_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `clinic_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `order_type` | `varchar(30)` | `False` | `None` | `NOT NULL` |
| `priority` | `varchar(20)` | `False` | `'ROUTINE'` | `NOT NULL DEFAULT 'ROUTINE'` |
| `status` | `varchar(40)` | `False` | `'ORDERED'` | `NOT NULL DEFAULT 'ORDERED'` |
| `clinical_indication` | `text` | `True` | `None` | `NULL` |
| `payload_json` | `longtext` | `True` | `None` | `NULL` |
| `occurred_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `created_by` | `varchar(100)` | `True` | `None` | `NULL` |
| `created_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `updated_at` | `datetime` | `False` | `None` | `NOT NULL` |

### 3.13 `mc_clinical_results` (`Backend/MedCorePlugin/includes/core/class-medcore-clinical-orders-migration.php:L77-L103`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `order_id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL` |
| `item_id` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `result_type` | `varchar(30)` | `False` | `None` | `NOT NULL` |
| `result_json` | `longtext` | `False` | `None` | `NOT NULL` |
| `status` | `varchar(30)` | `False` | `'DRAFT'` | `NOT NULL DEFAULT 'DRAFT'` |
| `idempotency_key` | `varchar(191)` | `True` | `None` | `NULL` |
| `entered_by` | `varchar(100)` | `True` | `None` | `NULL` |
| `verified_by` | `varchar(100)` | `True` | `None` | `NULL` |
| `entered_at` | `datetime` | `True` | `None` | `NULL` |
| `verified_at` | `datetime` | `True` | `None` | `NULL` |
| `delivered_at` | `datetime` | `True` | `None` | `NULL` |
| `critical_flag` | `tinyint(1)` | `False` | `0` | `NOT NULL DEFAULT 0` |
| `critical_acknowledged_by` | `varchar(100)` | `True` | `None` | `NULL` |
| `critical_acknowledged_at` | `datetime` | `True` | `None` | `NULL` |
| `notes` | `text` | `True` | `None` | `NULL` |
| `created_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `updated_at` | `datetime` | `False` | `None` | `NOT NULL` |

### 3.14 `mc_clinical_specimens` (`Backend/MedCorePlugin/includes/core/class-medcore-clinical-orders-migration.php:L53-L76`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `order_id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL` |
| `item_id` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `barcode` | `varchar(100)` | `False` | `None` | `NOT NULL` |
| `idempotency_key` | `varchar(191)` | `True` | `None` | `NULL` |
| `specimen_type` | `varchar(100)` | `True` | `None` | `NULL` |
| `container_type` | `varchar(100)` | `True` | `None` | `NULL` |
| `status` | `varchar(30)` | `False` | `'ORDERED'` | `NOT NULL DEFAULT 'ORDERED'` |
| `collected_at` | `datetime` | `True` | `None` | `NULL` |
| `collected_by` | `varchar(100)` | `True` | `None` | `NULL` |
| `received_at` | `datetime` | `True` | `None` | `NULL` |
| `rejection_reason` | `text` | `True` | `None` | `NULL` |
| `payload_json` | `longtext` | `True` | `None` | `NULL` |
| `created_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `updated_at` | `datetime` | `False` | `None` | `NOT NULL` |

### 3.15 `mc_clinical_template_usages` (`Backend/MedCorePlugin/includes/core/class-medcore-clinical-templates-migration.php:L26-L42`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `template_id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL` |
| `template_version` | `int unsigned` | `False` | `None` | `NOT NULL` |
| `encounter_id` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `patient_id` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `provider_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `snapshot_json` | `longtext` | `False` | `None` | `NOT NULL` |
| `used_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `used_by` | `varchar(100)` | `True` | `None` | `NULL` |

### 3.16 `mc_clinical_templates` (`Backend/MedCorePlugin/includes/core/class-medcore-clinical-templates-migration.php:L5-L25`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `template_number` | `varchar(40)` | `False` | `None` | `NOT NULL` |
| `code` | `varchar(100)` | `True` | `None` | `NULL` |
| `title` | `varchar(190)` | `False` | `None` | `NOT NULL` |
| `specialty` | `varchar(120)` | `True` | `None` | `NULL` |
| `category` | `varchar(60)` | `False` | `None` | `NOT NULL` |
| `owner_type` | `varchar(30)` | `False` | `'STAFF'` | `NOT NULL DEFAULT 'STAFF'` |
| `owner_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `version` | `int unsigned` | `False` | `1` | `NOT NULL DEFAULT 1` |
| `status` | `varchar(30)` | `False` | `'ACTIVE'` | `NOT NULL DEFAULT 'ACTIVE'` |
| `content_json` | `longtext` | `False` | `None` | `NOT NULL` |
| `created_by` | `varchar(100)` | `True` | `None` | `NULL` |
| `updated_by` | `varchar(100)` | `True` | `None` | `NULL` |
| `created_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `updated_at` | `datetime` | `False` | `None` | `NOT NULL` |

### 3.17 `mc_coa_accounts` (`Backend/MedCorePlugin/includes/core/class-medcore-accounting-migration.php:L11-L24`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `code` | `varchar(20)` | `False` | `None` | `NOT NULL` |
| `name` | `varchar(150)` | `False` | `None` | `NOT NULL` |
| `type` | `varchar(20)` | `False` | `None` | `NOT NULL, /* ASSET, LIABILITY, EQUITY, REVENUE, EXPENSE */` |
| `parent_id` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `status` | `varchar(20)` | `False` | `'ACTIVE'` | `NOT NULL DEFAULT 'ACTIVE'` |
| `created_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |

### 3.18 `mc_consent_events` (`Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L209-L219`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `user_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `purpose` | `varchar(100)` | `False` | `None` | `NOT NULL` |
| `status` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `timestamp` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |
| `source` | `varchar(100)` | `True` | `None` | `` |
| `ip_address` | `varchar(45)` | `True` | `None` | `` |

### 3.19 `mc_definition_links` (`Backend/MedCorePlugin/includes/core/class-medcore-definitions-migration.php:L71-L81`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `source_definition_id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL` |
| `relation_type` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `target_definition_id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL` |
| `metadata_json` | `longtext` | `True` | `None` | `NULL` |
| `created_at` | `datetime` | `False` | `CURRENT_TIMESTAMP` | `NOT NULL DEFAULT CURRENT_TIMESTAMP` |

### 3.20 `mc_definition_rules` (`Backend/MedCorePlugin/includes/core/class-medcore-definitions-migration.php:L39-L68`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `definition_id` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `rule_type` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `rule_key` | `varchar(100)` | `False` | `None` | `NOT NULL` |
| `subject_type` | `varchar(50)` | `True` | `None` | `NULL` |
| `subject_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `target_type` | `varchar(50)` | `True` | `None` | `NULL` |
| `target_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `parent_rule_id` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `precedence` | `int(10)` | `False` | `0` | `NOT NULL DEFAULT 0` |
| `calc_mode` | `varchar(20)` | `True` | `None` | `NULL` |
| `percent` | `decimal(8` | `True` | `None` | `,4) NULL` |
| `fixed_amount` | `decimal(14` | `True` | `None` | `,4) NULL` |
| `price` | `decimal(14` | `True` | `None` | `,4) NULL` |
| `conditions_json` | `longtext` | `True` | `None` | `NULL` |
| `status` | `varchar(30)` | `False` | `'ACTIVE'` | `NOT NULL DEFAULT 'ACTIVE'` |
| `version` | `int(10) unsigned` | `False` | `1` | `NOT NULL DEFAULT 1` |
| `valid_from` | `datetime` | `True` | `None` | `NULL` |
| `valid_to` | `datetime` | `True` | `None` | `NULL` |
| `created_by` | `varchar(36)` | `True` | `None` | `NULL` |
| `updated_by` | `varchar(36)` | `True` | `None` | `NULL` |
| `created_at` | `datetime` | `False` | `CURRENT_TIMESTAMP` | `NOT NULL DEFAULT CURRENT_TIMESTAMP` |
| `updated_at` | `datetime` | `False` | `CURRENT_TIMESTAMP` | `NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP` |

### 3.21 `mc_definitions` (`Backend/MedCorePlugin/includes/core/class-medcore-definitions-migration.php:L17-L36`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `definition_type` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `code` | `varchar(100)` | `False` | `None` | `NOT NULL` |
| `name` | `varchar(255)` | `False` | `None` | `NOT NULL` |
| `status` | `varchar(30)` | `False` | `'ACTIVE'` | `NOT NULL DEFAULT 'ACTIVE'` |
| `version` | `int(10) unsigned` | `False` | `1` | `NOT NULL DEFAULT 1` |
| `data_json` | `longtext` | `True` | `None` | `NULL` |
| `valid_from` | `datetime` | `True` | `None` | `NULL` |
| `valid_to` | `datetime` | `True` | `None` | `NULL` |
| `created_by` | `varchar(36)` | `True` | `None` | `NULL` |
| `updated_by` | `varchar(36)` | `True` | `None` | `NULL` |
| `created_at` | `datetime` | `False` | `CURRENT_TIMESTAMP` | `NOT NULL DEFAULT CURRENT_TIMESTAMP` |
| `updated_at` | `datetime` | `False` | `CURRENT_TIMESTAMP` | `NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP` |

### 3.22 `mc_dialysis_sessions` (`Backend/MedCorePlugin/includes/core/class-medcore-dialysis-migration.php:L11-L34`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20)` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `patient_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `encounter_id` | `varchar(36)` | `True` | `None` | `NULL` |
| `machine_id` | `varchar(36)` | `True` | `None` | `NULL` |
| `session_date` | `datetime` | `False` | `None` | `NOT NULL` |
| `pre_weight` | `decimal(10` | `True` | `None` | `,2) NULL` |
| `post_weight` | `decimal(10` | `True` | `None` | `,2) NULL` |
| `duration_minutes` | `int(11)` | `True` | `None` | `NULL` |
| `clinical_notes` | `text` | `True` | `None` | `NULL` |
| `telemetry_json` | `longtext` | `True` | `None` | `NULL` |
| `status` | `varchar(50)` | `True` | `'Scheduled'` | `DEFAULT 'Scheduled'` |
| `created_by` | `varchar(100)` | `True` | `None` | `NULL` |
| `idempotency_key` | `varchar(100)` | `True` | `None` | `NULL` |
| `created_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |
| `updated_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP` |

### 3.23 `mc_earning_lines` (`Backend/MedCorePlugin/includes/core/class-medcore-financial-migration.php:L45-L73`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `financial_event_id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL` |
| `line_number` | `int(10) unsigned` | `False` | `None` | `NOT NULL` |
| `beneficiary_type` | `varchar(30)` | `False` | `None` | `NOT NULL` |
| `beneficiary_id` | `varchar(100)` | `False` | `None` | `NOT NULL` |
| `beneficiary_scope` | `varchar(20)` | `False` | `'INTERNAL'` | `NOT NULL DEFAULT 'INTERNAL'` |
| `provider_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `earning_type` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `basis_type` | `varchar(30)` | `False` | `None` | `NOT NULL` |
| `basis_amount` | `decimal(14` | `False` | `0` | `,4) NOT NULL DEFAULT 0` |
| `amount` | `decimal(14` | `False` | `0` | `,4) NOT NULL DEFAULT 0` |
| `currency` | `varchar(20)` | `False` | `None` | `NOT NULL` |
| `calc_mode` | `varchar(20)` | `True` | `None` | `NULL` |
| `rule_id` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `rule_public_id` | `varchar(36)` | `True` | `None` | `NULL` |
| `rule_version` | `int(10) unsigned` | `True` | `None` | `NULL` |
| `rule_snapshot_json` | `longtext` | `True` | `None` | `NULL` |
| `settlement_status` | `varchar(30)` | `False` | `'PENDING'` | `NOT NULL DEFAULT 'PENDING'` |
| `settled_at` | `datetime` | `True` | `None` | `NULL` |
| `idempotency_key` | `varchar(120)` | `True` | `None` | `NULL` |
| `created_at` | `datetime` | `False` | `CURRENT_TIMESTAMP` | `NOT NULL DEFAULT CURRENT_TIMESTAMP` |

### 3.24 `mc_encounters` (`Backend/MedCorePlugin/includes/core/class-medcore-patient-domain-migration.php:L80-L113`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `encounter_number` | `varchar(40)` | `False` | `None` | `NOT NULL` |
| `idempotency_key` | `varchar(191)` | `True` | `None` | `NULL` |
| `source_device_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `local_sequence` | `bigint unsigned` | `True` | `None` | `NULL` |
| `patient_id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL` |
| `appointment_id` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `visit_id` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `clinic_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `provider_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `encounter_type` | `varchar(40)` | `False` | `'OUTPATIENT'` | `NOT NULL DEFAULT 'OUTPATIENT'` |
| `status` | `varchar(30)` | `False` | `'OPEN'` | `NOT NULL DEFAULT 'OPEN'` |
| `chief_complaint` | `text` | `True` | `None` | `NULL` |
| `history_json` | `longtext` | `True` | `None` | `NULL` |
| `vitals_json` | `longtext` | `True` | `None` | `NULL` |
| `examination_json` | `longtext` | `True` | `None` | `NULL` |
| `assessment_json` | `longtext` | `True` | `None` | `NULL` |
| `plan_json` | `longtext` | `True` | `None` | `NULL` |
| `diagnoses_json` | `longtext` | `True` | `None` | `NULL` |
| `notes` | `text` | `True` | `None` | `NULL` |
| `started_at` | `datetime` | `True` | `None` | `NULL` |
| `completed_at` | `datetime` | `True` | `None` | `NULL` |
| `occurred_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `created_by` | `varchar(100)` | `True` | `None` | `NULL` |
| `created_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `updated_at` | `datetime` | `False` | `None` | `NOT NULL` |

### 3.25 `mc_entitlements` (`Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L196-L206`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `target_type` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `target_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `feature_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `status` | `varchar(50)` | `True` | `'ACTIVE'` | `DEFAULT 'ACTIVE'` |
| `entitlement_type` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `created_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |

### 3.26 `mc_error_log` (`Backend/MedCorePlugin/includes/core/class-medcore-migration.php:L589-L601`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20)` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `timestamp` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |
| `severity` | `varchar(20)` | `True` | `None` | `` |
| `module` | `varchar(100)` | `True` | `None` | `` |
| `error_code` | `varchar(50)` | `True` | `None` | `` |
| `endpoint` | `varchar(255)` | `True` | `None` | `` |
| `request_id` | `varchar(50)` | `True` | `None` | `` |
| `actor_email` | `varchar(100)` | `True` | `None` | `` |
| `tenant_id` | `varchar(50)` | `True` | `None` | `` |
| `safe_message` | `text` | `True` | `None` | `` |

### 3.27 `mc_fallback_quotas` (`Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L102-L113`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `membership_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `wallet_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `max_spend` | `bigint(20)` | `False` | `'0'` | `NOT NULL DEFAULT '0'` |
| `consumed` | `bigint(20)` | `False` | `'0'` | `NOT NULL DEFAULT '0'` |
| `period` | `varchar(50)` | `True` | `'MONTHLY'` | `DEFAULT 'MONTHLY'` |
| `created_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |
| `updated_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP` |

### 3.28 `mc_features` (`Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L177-L184`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `feature_key` | `varchar(100)` | `False` | `None` | `NOT NULL` |
| `name` | `varchar(255)` | `False` | `None` | `NOT NULL` |
| `status` | `varchar(50)` | `True` | `'ACTIVE'` | `DEFAULT 'ACTIVE'` |

### 3.29 `mc_files` (`Backend/MedCorePlugin/includes/class-medcore-schema.php:L93-L105, Backend/MedCorePlugin/includes/core/class-medcore-files-migration.php:L4-L32`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `BIGINT UNSIGNED` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `tenant_id` | `VARCHAR(50)` | `False` | `None` | `NOT NULL` |
| `object_key` | `VARCHAR(1000)` | `False` | `None` | `NOT NULL` |
| `filename` | `VARCHAR(500)` | `False` | `None` | `NOT NULL` |
| `mime_type` | `VARCHAR(100)` | `False` | `None` | `NOT NULL` |
| `size_bytes` | `BIGINT UNSIGNED` | `False` | `None` | `NOT NULL` |
| `uploaded_by` | `VARCHAR(255)` | `False` | `None` | `NOT NULL` |
| `status` | `ENUM('pending'` | `False` | `'active'` | `,'active','deleted') NOT NULL DEFAULT 'active'` |
| `created_at` | `DATETIME` | `False` | `CURRENT_TIMESTAMP` | `NOT NULL DEFAULT CURRENT_TIMESTAMP` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `file_number` | `varchar(40)` | `False` | `None` | `NOT NULL` |
| `patient_id` | `bigint unsigned` | `True` | `None` | `NULL` |
| `entity_type` | `varchar(50)` | `True` | `None` | `NULL` |
| `entity_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `file_type` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `original_name` | `varchar(255)` | `False` | `None` | `NOT NULL` |
| `storage_provider` | `varchar(30)` | `False` | `None` | `NOT NULL` |
| `storage_key` | `varchar(500)` | `False` | `None` | `NOT NULL` |
| `idempotency_key` | `varchar(191)` | `True` | `None` | `NULL` |
| `checksum_sha256` | `char(64)` | `True` | `None` | `NULL` |
| `deleted_at` | `datetime` | `True` | `None` | `NULL` |
| `metadata_json` | `longtext` | `True` | `None` | `NULL` |

### 3.30 `mc_financial_events` (`Backend/MedCorePlugin/includes/core/class-medcore-financial-migration.php:L19-L42`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `event_number` | `varchar(40)` | `False` | `None` | `NOT NULL` |
| `event_type` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `source_type` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `source_id` | `varchar(100)` | `False` | `None` | `NOT NULL` |
| `patient_id` | `varchar(36)` | `True` | `None` | `NULL` |
| `encounter_id` | `varchar(36)` | `True` | `None` | `NULL` |
| `gross_amount` | `decimal(14` | `False` | `0` | `,4) NOT NULL DEFAULT 0` |
| `net_amount` | `decimal(14` | `False` | `0` | `,4) NOT NULL DEFAULT 0` |
| `currency` | `varchar(20)` | `False` | `None` | `NOT NULL` |
| `occurred_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `posted_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `status` | `varchar(30)` | `False` | `'POSTED'` | `NOT NULL DEFAULT 'POSTED'` |
| `idempotency_key` | `varchar(120)` | `True` | `None` | `NULL` |
| `metadata_json` | `longtext` | `True` | `None` | `NULL` |
| `created_by` | `varchar(36)` | `True` | `None` | `NULL` |

### 3.31 `mc_financial_postings` (`Backend/MedCorePlugin/includes/core/class-medcore-financial-transaction-migration.php:L11-L32`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `financial_event_id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL` |
| `posting_type` | `varchar(30)` | `False` | `None` | `NOT NULL` |
| `amount` | `decimal(14` | `False` | `None` | `,4) NOT NULL` |
| `currency` | `varchar(20)` | `False` | `None` | `NOT NULL` |
| `account_type` | `varchar(50)` | `True` | `None` | `NULL` |
| `account_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `reference_type` | `varchar(50)` | `True` | `None` | `NULL` |
| `reference_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `status` | `varchar(20)` | `False` | `'POSTED'` | `NOT NULL DEFAULT 'POSTED'` |
| `idempotency_key` | `varchar(120)` | `True` | `None` | `NULL` |
| `occurred_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `created_at` | `datetime` | `False` | `None` | `NOT NULL` |

### 3.32 `mc_financial_settlements` (`Backend/MedCorePlugin/includes/core/class-medcore-financial-settlement-migration.php:L4-L31`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `earning_line_id` | `bigint unsigned` | `False` | `None` | `NOT NULL` |
| `settlement_number` | `varchar(40)` | `False` | `None` | `NOT NULL` |
| `settlement_type` | `varchar(30)` | `False` | `'WITHDRAWAL'` | `NOT NULL DEFAULT 'WITHDRAWAL'` |
| `amount` | `decimal(18` | `False` | `None` | `,4) NOT NULL` |
| `currency` | `varchar(20)` | `False` | `None` | `NOT NULL` |
| `beneficiary_type` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `beneficiary_id` | `varchar(100)` | `False` | `None` | `NOT NULL` |
| `status` | `varchar(30)` | `False` | `'REQUESTED'` | `NOT NULL DEFAULT 'REQUESTED'` |
| `requested_by` | `varchar(100)` | `True` | `None` | `NULL` |
| `approved_by` | `varchar(100)` | `True` | `None` | `NULL` |
| `delivered_by` | `varchar(100)` | `True` | `None` | `NULL` |
| `received_by` | `varchar(100)` | `True` | `None` | `NULL` |
| `requested_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `approved_at` | `datetime` | `True` | `None` | `NULL` |
| `delivered_at` | `datetime` | `True` | `None` | `NULL` |
| `received_at` | `datetime` | `True` | `None` | `NULL` |
| `idempotency_key` | `varchar(191)` | `True` | `None` | `NULL` |
| `metadata_json` | `longtext` | `True` | `None` | `NULL` |

### 3.33 `mc_hospitals` (`Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L27-L37`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `organization_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `public_alias` | `varchar(100)` | `False` | `None` | `NOT NULL` |
| `status` | `varchar(50)` | `True` | `'ACTIVE'` | `DEFAULT 'ACTIVE'` |
| `created_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |
| `updated_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP` |

### 3.34 `mc_icu_apache2_scores` (`Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L261-L275`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `tenant_id` | `varchar(64)` | `False` | `None` | `NOT NULL` |
| `admission_id` | `varchar(64)` | `False` | `None` | `NOT NULL` |
| `score` | `int` | `False` | `None` | `NOT NULL` |
| `details_json` | `longtext` | `True` | `None` | `` |
| `recorded_by` | `varchar(255)` | `True` | `None` | `` |
| `recorded_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |
| `idempotency_key` | `varchar(128)` | `True` | `None` | `` |

### 3.35 `mc_icu_flowsheets` (`Backend/MedCorePlugin/includes/core/class-medcore-icu-nicu-clinical-migration.php:L11-L27`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20)` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `admission_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `bed_id` | `varchar(36)` | `True` | `None` | `NULL` |
| `entry_time` | `datetime` | `False` | `None` | `NOT NULL` |
| `vitals_json` | `longtext` | `True` | `None` | `NULL` |
| `fluids_json` | `longtext` | `True` | `None` | `NULL` |
| `notes` | `text` | `True` | `None` | `NULL` |
| `created_by` | `varchar(100)` | `True` | `None` | `NULL` |
| `idempotency_key` | `varchar(100)` | `True` | `None` | `NULL` |
| `created_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |

### 3.36 `mc_icu_sofa_scores` (`Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L244-L258`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `tenant_id` | `varchar(64)` | `False` | `None` | `NOT NULL` |
| `admission_id` | `varchar(64)` | `False` | `None` | `NOT NULL` |
| `score` | `int` | `False` | `None` | `NOT NULL` |
| `details_json` | `longtext` | `True` | `None` | `` |
| `recorded_by` | `varchar(255)` | `True` | `None` | `` |
| `recorded_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |
| `idempotency_key` | `varchar(128)` | `True` | `None` | `` |

### 3.37 `mc_identity_sequences` (`Backend/MedCorePlugin/includes/core/class-medcore-identity-migration.php:L178-L187`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `entity_type` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `sequence_year` | `smallint(5) unsigned` | `False` | `None` | `NOT NULL` |
| `next_value` | `bigint(20) unsigned` | `False` | `1` | `NOT NULL DEFAULT 1` |
| `updated_at` | `datetime` | `False` | `CURRENT_TIMESTAMP` | `NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP` |

### 3.38 `mc_inventory_balances` (`Backend/MedCorePlugin/includes/core/class-medcore-inventory-migration.php:L97-L109`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `item_id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL` |
| `location_id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL` |
| `batch_id` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `quantity` | `decimal(14` | `False` | `0` | `,4) NOT NULL DEFAULT 0` |
| `reserved_quantity` | `decimal(14` | `False` | `0` | `,4) NOT NULL DEFAULT 0` |
| `average_cost` | `decimal(14` | `False` | `0` | `,4) NOT NULL DEFAULT 0` |
| `updated_at` | `datetime` | `False` | `CURRENT_TIMESTAMP` | `NOT NULL DEFAULT CURRENT_TIMESTAMP` |

### 3.39 `mc_inventory_batches` (`Backend/MedCorePlugin/includes/core/class-medcore-inventory-migration.php:L50-L65`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `item_id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL` |
| `batch_number` | `varchar(100)` | `True` | `None` | `NULL` |
| `expiry_date` | `date` | `True` | `None` | `NULL` |
| `unit_cost` | `decimal(14` | `False` | `0` | `,4) NOT NULL DEFAULT 0` |
| `currency` | `varchar(20)` | `False` | `None` | `NOT NULL` |
| `received_at` | `datetime` | `True` | `None` | `NULL` |
| `idempotency_key` | `varchar(191)` | `True` | `None` | `NULL` |
| `created_at` | `datetime` | `False` | `CURRENT_TIMESTAMP` | `NOT NULL DEFAULT CURRENT_TIMESTAMP` |

### 3.40 `mc_inventory_items` (`Backend/MedCorePlugin/includes/core/class-medcore-inventory-migration.php:L30-L48`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `item_number` | `varchar(40)` | `False` | `None` | `NOT NULL` |
| `definition_id` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `item_code` | `varchar(100)` | `False` | `None` | `NOT NULL` |
| `name` | `varchar(190)` | `False` | `None` | `NOT NULL` |
| `unit` | `varchar(30)` | `False` | `None` | `NOT NULL` |
| `tracking_type` | `varchar(30)` | `False` | `'NONE'` | `NOT NULL DEFAULT 'NONE'` |
| `status` | `varchar(20)` | `False` | `'ACTIVE'` | `NOT NULL DEFAULT 'ACTIVE'` |
| `idempotency_key` | `varchar(191)` | `True` | `None` | `NULL` |
| `created_at` | `datetime` | `False` | `CURRENT_TIMESTAMP` | `NOT NULL DEFAULT CURRENT_TIMESTAMP` |

### 3.41 `mc_inventory_locations` (`Backend/MedCorePlugin/includes/core/class-medcore-inventory-migration.php:L10-L28`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `location_number` | `varchar(40)` | `False` | `None` | `NOT NULL` |
| `location_type` | `varchar(30)` | `False` | `None` | `NOT NULL` |
| `name` | `varchar(190)` | `False` | `None` | `NOT NULL` |
| `clinic_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `owner_type` | `varchar(30)` | `True` | `None` | `NULL` |
| `owner_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `parent_location_id` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `status` | `varchar(20)` | `False` | `'ACTIVE'` | `NOT NULL DEFAULT 'ACTIVE'` |
| `idempotency_key` | `varchar(191)` | `True` | `None` | `NULL` |
| `created_at` | `datetime` | `False` | `CURRENT_TIMESTAMP` | `NOT NULL DEFAULT CURRENT_TIMESTAMP` |

### 3.42 `mc_inventory_movements` (`Backend/MedCorePlugin/includes/core/class-medcore-inventory-migration.php:L67-L95`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `movement_number` | `varchar(40)` | `False` | `None` | `NOT NULL` |
| `movement_type` | `varchar(40)` | `False` | `None` | `NOT NULL` |
| `item_id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL` |
| `batch_id` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `source_location_id` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `destination_location_id` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `quantity` | `decimal(14` | `False` | `None` | `,4) NOT NULL` |
| `unit_cost` | `decimal(14` | `False` | `0` | `,4) NOT NULL DEFAULT 0` |
| `patient_id` | `varchar(36)` | `True` | `None` | `NULL` |
| `beneficiary_type` | `varchar(30)` | `True` | `None` | `NULL` |
| `beneficiary_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `custody_type` | `varchar(30)` | `True` | `None` | `NULL` |
| `custody_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `reason_code` | `varchar(50)` | `True` | `None` | `NULL` |
| `source_reference_type` | `varchar(50)` | `True` | `None` | `NULL` |
| `source_reference_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `idempotency_key` | `varchar(120)` | `True` | `None` | `NULL` |
| `occurred_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `created_by` | `varchar(36)` | `True` | `None` | `NULL` |
| `metadata_json` | `longtext` | `True` | `None` | `NULL` |

### 3.43 `mc_inventory_requests` (`Backend/MedCorePlugin/includes/core/class-medcore-inventory-request-migration.php:L6-L41`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `request_number` | `varchar(40)` | `False` | `None` | `NOT NULL` |
| `item_id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL` |
| `batch_id` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `source_location_id` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `destination_location_id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL` |
| `requested_quantity` | `decimal(14` | `False` | `None` | `,4) NOT NULL` |
| `approved_quantity` | `decimal(14` | `True` | `None` | `,4) NULL` |
| `issued_quantity` | `decimal(14` | `False` | `0` | `,4) NOT NULL DEFAULT 0` |
| `status` | `varchar(30)` | `False` | `'PENDING'` | `NOT NULL DEFAULT 'PENDING'` |
| `requested_by` | `varchar(100)` | `True` | `None` | `NULL` |
| `approved_by` | `varchar(100)` | `True` | `None` | `NULL` |
| `source_reference_type` | `varchar(50)` | `True` | `None` | `NULL` |
| `source_reference_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `idempotency_key` | `varchar(120)` | `True` | `None` | `NULL` |
| `approve_idempotency_key` | `varchar(191)` | `True` | `None` | `NULL` |
| `reject_idempotency_key` | `varchar(191)` | `True` | `None` | `NULL` |
| `issue_idempotency_key` | `varchar(191)` | `True` | `None` | `NULL` |
| `requested_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `approved_at` | `datetime` | `True` | `None` | `NULL` |
| `issued_at` | `datetime` | `True` | `None` | `NULL` |
| `metadata_json` | `longtext` | `True` | `None` | `NULL` |

### 3.44 `mc_inventory_reservations` (`Backend/MedCorePlugin/includes/core/class-medcore-inventory-reservation-migration.php:L6-L29`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `item_id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL` |
| `batch_id` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `location_id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL` |
| `request_id` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `patient_id` | `varchar(36)` | `True` | `None` | `NULL` |
| `quantity` | `decimal(14` | `False` | `None` | `,4) NOT NULL` |
| `status` | `varchar(20)` | `False` | `'RESERVED'` | `NOT NULL DEFAULT 'RESERVED'` |
| `expires_at` | `datetime` | `True` | `None` | `NULL` |
| `created_by` | `varchar(100)` | `True` | `None` | `NULL` |
| `created_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `released_at` | `datetime` | `True` | `None` | `NULL` |
| `metadata_json` | `longtext` | `True` | `None` | `NULL` |
| `idempotency_key` | `varchar(191)` | `True` | `None` | `NULL` |

### 3.45 `mc_journal_entries` (`Backend/MedCorePlugin/includes/core/class-medcore-accounting-migration.php:L27-L44`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `journal_number` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `entry_date` | `datetime` | `False` | `None` | `NOT NULL` |
| `description` | `text` | `True` | `None` | `NULL` |
| `reference_type` | `varchar(50)` | `True` | `None` | `NULL` |
| `reference_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `status` | `varchar(20)` | `False` | `'POSTED'` | `NOT NULL DEFAULT 'POSTED'` |
| `idempotency_key` | `varchar(120)` | `True` | `None` | `NULL` |
| `created_by` | `varchar(100)` | `True` | `None` | `NULL` |
| `created_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |

### 3.46 `mc_journal_lines` (`Backend/MedCorePlugin/includes/core/class-medcore-accounting-migration.php:L47-L61`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `journal_entry_id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL` |
| `account_id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL` |
| `debit` | `decimal(14` | `False` | `0.0000` | `,4) NOT NULL DEFAULT 0.0000` |
| `credit` | `decimal(14` | `False` | `0.0000` | `,4) NOT NULL DEFAULT 0.0000` |
| `description` | `varchar(255)` | `True` | `None` | `NULL` |
| `created_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |

### 3.47 `mc_lab_orders` (`Backend/MedCorePlugin/includes/core/class-medcore-migration.php:L489-L501`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20)` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `hospital_code` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `patient_id` | `bigint(20)` | `False` | `None` | `NOT NULL` |
| `doctor_name` | `varchar(255)` | `True` | `None` | `` |
| `priority` | `varchar(20)` | `True` | `'ROUTINE'` | `DEFAULT 'ROUTINE'` |
| `status` | `varchar(50)` | `True` | `'PENDING'` | `DEFAULT 'PENDING'` |
| `barcode` | `varchar(100)` | `True` | `None` | `` |
| `payload_json` | `LONGTEXT` | `True` | `None` | `` |
| `created_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |

### 3.48 `mc_lab_referrals` (`Backend/MedCorePlugin/includes/core/class-medcore-lab-referrals-migration.php:L6-L42`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `referral_number` | `varchar(40)` | `False` | `None` | `NOT NULL` |
| `referral_type` | `varchar(30)` | `False` | `'LAB_TO_LAB'` | `NOT NULL DEFAULT 'LAB_TO_LAB'` |
| `source_order_id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL` |
| `source_item_id` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `source_patient_id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL` |
| `source_encounter_id` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `destination_tenant_id` | `varchar(50)` | `True` | `None` | `NULL` |
| `external_provider_code` | `varchar(100)` | `True` | `None` | `NULL` |
| `external_provider_name` | `varchar(190)` | `True` | `None` | `NULL` |
| `external_reference` | `varchar(190)` | `True` | `None` | `NULL` |
| `status` | `varchar(40)` | `False` | `'REQUESTED'` | `NOT NULL DEFAULT 'REQUESTED'` |
| `requested_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `accepted_at` | `datetime` | `True` | `None` | `NULL` |
| `rejected_at` | `datetime` | `True` | `None` | `NULL` |
| `sent_at` | `datetime` | `True` | `None` | `NULL` |
| `received_at` | `datetime` | `True` | `None` | `NULL` |
| `completed_at` | `datetime` | `True` | `None` | `NULL` |
| `result_reference` | `varchar(190)` | `True` | `None` | `NULL` |
| `rejection_reason` | `text` | `True` | `None` | `NULL` |
| `idempotency_key` | `varchar(191)` | `True` | `None` | `NULL` |
| `payload_json` | `longtext` | `True` | `None` | `NULL` |
| `created_by` | `varchar(100)` | `True` | `None` | `NULL` |
| `updated_by` | `varchar(100)` | `True` | `None` | `NULL` |
| `created_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `updated_at` | `datetime` | `False` | `None` | `NOT NULL` |

### 3.49 `mc_lab_requests` (`Backend/MedCorePlugin/includes/class-medcore-schema.php:L41-L58`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `BIGINT UNSIGNED` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `hospital_code` | `VARCHAR(50)` | `False` | `None` | `NOT NULL` |
| `visit_id` | `BIGINT UNSIGNED` | `False` | `None` | `NOT NULL` |
| `patient_id` | `BIGINT UNSIGNED` | `False` | `None` | `NOT NULL` |
| `doctor_id` | `BIGINT UNSIGNED` | `False` | `None` | `NOT NULL` |
| `test_name` | `VARCHAR(255)` | `False` | `None` | `NOT NULL` |
| `result` | `TEXT` | `True` | `NULL` | `DEFAULT NULL` |
| `normal_range` | `VARCHAR(255)` | `True` | `NULL` | `DEFAULT NULL` |
| `unit` | `VARCHAR(50)` | `True` | `NULL` | `DEFAULT NULL` |
| `status` | `ENUM('pending'` | `False` | `'pending'` | `,'done') NOT NULL DEFAULT 'pending'` |
| `is_external` | `TINYINT(1)` | `False` | `0` | `NOT NULL DEFAULT 0` |
| `lab_name` | `VARCHAR(255)` | `True` | `NULL` | `DEFAULT NULL` |
| `requested_at` | `DATETIME` | `False` | `CURRENT_TIMESTAMP` | `NOT NULL DEFAULT CURRENT_TIMESTAMP` |
| `resulted_at` | `DATETIME` | `True` | `NULL` | `DEFAULT NULL` |

### 3.50 `mc_memberships` (`Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L54-L66`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `user_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `hospital_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `role` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `status` | `varchar(50)` | `True` | `'ACTIVE'` | `DEFAULT 'ACTIVE'` |
| `created_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |
| `revoked_at` | `datetime` | `True` | `None` | `` |
| `revoked_by` | `varchar(36)` | `True` | `None` | `` |

### 3.51 `mc_migration_exceptions` (`Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L231-L241`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `run_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `source_id` | `varchar(255)` | `False` | `None` | `NOT NULL` |
| `exception_type` | `varchar(100)` | `False` | `None` | `NOT NULL` |
| `reason` | `text` | `True` | `None` | `` |
| `status` | `varchar(50)` | `True` | `'MANUAL_REVIEW_REQUIRED'` | `DEFAULT 'MANUAL_REVIEW_REQUIRED'` |
| `created_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |

### 3.52 `mc_migration_runs` (`Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L222-L228`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `started_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |
| `status` | `varchar(50)` | `True` | `'RUNNING'` | `DEFAULT 'RUNNING'` |
| `checksum` | `varchar(255)` | `True` | `None` | `` |

### 3.53 `mc_nicu_growth_logs` (`Backend/MedCorePlugin/includes/core/class-medcore-icu-nicu-clinical-migration.php:L72-L91, Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L299-L318`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20)` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `patient_id` | `varchar(36)` | `True` | `None` | `NULL` |
| `incubator_id` | `varchar(36)` | `True` | `None` | `NULL` |
| `weight_grams` | `decimal(8` | `False` | `None` | `,2) NOT NULL` |
| `head_circumference_cm` | `decimal(5` | `True` | `None` | `,2) NULL` |
| `length_cm` | `decimal(5` | `True` | `None` | `,2) NULL` |
| `feeding_ml` | `decimal(8` | `True` | `None` | `,2) NULL` |
| `day_of_life` | `int(11)` | `True` | `None` | `NULL` |
| `details_json` | `longtext` | `True` | `None` | `NULL` |
| `logged_by` | `varchar(100)` | `True` | `None` | `NULL` |
| `logged_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |
| `created_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |

### 3.54 `mc_nicu_telemetry` (`Backend/MedCorePlugin/includes/core/class-medcore-icu-nicu-clinical-migration.php:L50-L68, Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L278-L296`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20)` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `patient_id` | `varchar(36)` | `True` | `None` | `NULL` |
| `incubator_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `incubator_temp` | `decimal(5` | `True` | `None` | `,2) NULL` |
| `humidity` | `decimal(5` | `True` | `None` | `,2) NULL` |
| `o2_flow` | `decimal(5` | `True` | `None` | `,2) NULL` |
| `spo2` | `decimal(5` | `True` | `None` | `,2) NULL` |
| `heart_rate` | `int(11)` | `True` | `None` | `NULL` |
| `recorded_by` | `varchar(100)` | `True` | `None` | `NULL` |
| `occurred_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |
| `created_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |

### 3.55 `mc_nursing_tasks` (`Backend/MedCorePlugin/includes/core/class-medcore-nursing-migration.php:L4-L33`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `task_number` | `varchar(40)` | `False` | `None` | `NOT NULL` |
| `patient_id` | `bigint unsigned` | `True` | `None` | `NULL` |
| `encounter_id` | `bigint unsigned` | `True` | `None` | `NULL` |
| `assigned_to` | `varchar(100)` | `True` | `None` | `NULL` |
| `idempotency_key` | `varchar(191)` | `True` | `None` | `NULL` |
| `assigned_by` | `varchar(100)` | `True` | `None` | `NULL` |
| `task_type` | `varchar(60)` | `False` | `None` | `NOT NULL` |
| `title` | `varchar(190)` | `False` | `None` | `NOT NULL` |
| `instructions` | `text` | `True` | `None` | `NULL` |
| `priority` | `varchar(20)` | `False` | `'NORMAL'` | `NOT NULL DEFAULT 'NORMAL'` |
| `status` | `varchar(30)` | `False` | `'ASSIGNED'` | `NOT NULL DEFAULT 'ASSIGNED'` |
| `due_at` | `datetime` | `True` | `None` | `NULL` |
| `started_at` | `datetime` | `True` | `None` | `NULL` |
| `completed_at` | `datetime` | `True` | `None` | `NULL` |
| `confirmed_at` | `datetime` | `True` | `None` | `NULL` |
| `confirmation_by` | `varchar(100)` | `True` | `None` | `NULL` |
| `metadata_json` | `longtext` | `True` | `None` | `NULL` |
| `created_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `updated_at` | `datetime` | `False` | `None` | `NOT NULL` |

### 3.56 `mc_operations` (`Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L132-L141`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `operation_type` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `idempotency_key` | `varchar(100)` | `False` | `None` | `NOT NULL` |
| `fingerprint` | `varchar(64)` | `False` | `None` | `NOT NULL` |
| `status` | `varchar(50)` | `False` | `'PENDING'` | `NOT NULL DEFAULT 'PENDING'` |
| `created_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |

### 3.57 `mc_organizations` (`Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L14-L24`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `public_alias` | `varchar(100)` | `False` | `None` | `NOT NULL` |
| `name` | `varchar(255)` | `False` | `None` | `NOT NULL` |
| `status` | `varchar(50)` | `True` | `'ACTIVE'` | `DEFAULT 'ACTIVE'` |
| `timezone` | `varchar(100)` | `True` | `'UTC'` | `DEFAULT 'UTC'` |
| `created_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |
| `updated_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP` |

### 3.58 `mc_patient_profiles` (`Backend/MedCorePlugin/includes/core/class-medcore-patient-domain-migration.php:L12-L32`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `patient_id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL` |
| `date_of_birth` | `date` | `True` | `None` | `NULL` |
| `emergency_contact_name` | `varchar(190)` | `True` | `None` | `NULL` |
| `emergency_contact_phone` | `varchar(50)` | `True` | `None` | `NULL` |
| `address` | `text` | `True` | `None` | `NULL` |
| `insurance_provider_id` | `varchar(36)` | `True` | `None` | `NULL` |
| `insurance_policy_number` | `varchar(100)` | `True` | `None` | `NULL` |
| `chronic_conditions_json` | `longtext` | `True` | `None` | `NULL` |
| `allergies_json` | `longtext` | `True` | `None` | `NULL` |
| `medical_history_json` | `longtext` | `True` | `None` | `NULL` |
| `status` | `varchar(30)` | `False` | `'ACTIVE'` | `NOT NULL DEFAULT 'ACTIVE'` |
| `created_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `updated_at` | `datetime` | `False` | `None` | `NOT NULL` |

### 3.59 `mc_patients` (`Backend/MedCorePlugin/includes/core/class-medcore-migration.php:L474-L487`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20)` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `hospital_code` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `patient_name` | `varchar(255)` | `False` | `None` | `NOT NULL` |
| `phone` | `varchar(50)` | `True` | `None` | `` |
| `national_id` | `varchar(100)` | `True` | `None` | `` |
| `age` | `int(11)` | `True` | `None` | `` |
| `gender` | `varchar(20)` | `True` | `None` | `` |
| `blood_group` | `varchar(10)` | `True` | `None` | `` |
| `payload_json` | `LONGTEXT` | `True` | `None` | `` |
| `created_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |

### 3.60 `mc_pharmacy_dispenses` (`Backend/MedCorePlugin/includes/core/class-medcore-pharmacy-migration.php:L4-L25`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `prescription_id` | `bigint unsigned` | `False` | `None` | `NOT NULL` |
| `prescription_item_id` | `bigint unsigned` | `True` | `None` | `NULL` |
| `inventory_item_id` | `bigint unsigned` | `True` | `None` | `NULL` |
| `batch_id` | `bigint unsigned` | `True` | `None` | `NULL` |
| `quantity` | `decimal(12` | `False` | `None` | `,3) NOT NULL` |
| `unit_cost` | `decimal(18` | `True` | `None` | `,4) NULL` |
| `patient_id` | `bigint unsigned` | `True` | `None` | `NULL` |
| `dispensed_by` | `varchar(100)` | `True` | `None` | `NULL` |
| `idempotency_key` | `varchar(191)` | `True` | `None` | `NULL` |
| `status` | `varchar(30)` | `False` | `'POSTED'` | `NOT NULL DEFAULT 'POSTED'` |
| `occurred_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `metadata_json` | `longtext` | `True` | `None` | `NULL` |

### 3.61 `mc_plan_features` (`Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L187-L193`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `plan_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `feature_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |

### 3.62 `mc_plans` (`Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L144-L150`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `name` | `varchar(255)` | `False` | `None` | `NOT NULL` |
| `status` | `varchar(50)` | `True` | `'ACTIVE'` | `DEFAULT 'ACTIVE'` |
| `created_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |

### 3.63 `mc_prescription_items` (`Backend/MedCorePlugin/includes/core/class-medcore-clinical-orders-migration.php:L104-L126`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `prescription_id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL` |
| `medication_definition_id` | `varchar(36)` | `True` | `None` | `NULL` |
| `medication_code` | `varchar(100)` | `True` | `None` | `NULL` |
| `medication_name` | `varchar(190)` | `False` | `None` | `NOT NULL` |
| `dose` | `varchar(100)` | `True` | `None` | `NULL` |
| `route` | `varchar(100)` | `True` | `None` | `NULL` |
| `frequency` | `varchar(100)` | `True` | `None` | `NULL` |
| `duration` | `varchar(100)` | `True` | `None` | `NULL` |
| `quantity` | `decimal(12` | `True` | `None` | `,3) NULL` |
| `instructions` | `text` | `True` | `None` | `NULL` |
| `status` | `varchar(30)` | `False` | `'ACTIVE'` | `NOT NULL DEFAULT 'ACTIVE'` |
| `payload_json` | `longtext` | `True` | `None` | `NULL` |
| `created_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `updated_at` | `datetime` | `False` | `None` | `NOT NULL` |

### 3.64 `mc_prescriptions` (`Backend/MedCorePlugin/includes/class-medcore-schema.php:L81-L91, Backend/MedCorePlugin/includes/core/class-medcore-migration.php:L517-L528`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `BIGINT UNSIGNED` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `hospital_code` | `VARCHAR(50)` | `False` | `None` | `NOT NULL` |
| `visit_id` | `BIGINT UNSIGNED` | `False` | `None` | `NOT NULL` |
| `patient_id` | `BIGINT UNSIGNED` | `False` | `None` | `NOT NULL` |
| `doctor_id` | `BIGINT UNSIGNED` | `False` | `None` | `NOT NULL` |
| `notes` | `TEXT` | `True` | `NULL` | `DEFAULT NULL` |
| `created_at` | `DATETIME` | `False` | `CURRENT_TIMESTAMP` | `NOT NULL DEFAULT CURRENT_TIMESTAMP` |
| `doctor_name` | `varchar(255)` | `True` | `None` | `` |
| `medication` | `text` | `True` | `None` | `` |
| `status` | `varchar(50)` | `True` | `'PENDING'` | `DEFAULT 'PENDING'` |
| `payload_json` | `LONGTEXT` | `True` | `None` | `` |

### 3.65 `mc_radiology_orders` (`Backend/MedCorePlugin/includes/core/class-medcore-migration.php:L503-L515`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20)` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `hospital_code` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `patient_id` | `bigint(20)` | `False` | `None` | `NOT NULL` |
| `doctor_name` | `varchar(255)` | `True` | `None` | `` |
| `scan_type` | `varchar(255)` | `True` | `None` | `` |
| `status` | `varchar(50)` | `True` | `'PENDING'` | `DEFAULT 'PENDING'` |
| `priority` | `varchar(20)` | `True` | `'ROUTINE'` | `DEFAULT 'ROUTINE'` |
| `payload_json` | `LONGTEXT` | `True` | `None` | `` |
| `created_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |

### 3.66 `mc_radiology_requests` (`Backend/MedCorePlugin/includes/class-medcore-schema.php:L61-L78`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `BIGINT UNSIGNED` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `hospital_code` | `VARCHAR(50)` | `False` | `None` | `NOT NULL` |
| `visit_id` | `BIGINT UNSIGNED` | `False` | `None` | `NOT NULL` |
| `patient_id` | `BIGINT UNSIGNED` | `False` | `None` | `NOT NULL` |
| `doctor_id` | `BIGINT UNSIGNED` | `False` | `None` | `NOT NULL` |
| `type` | `VARCHAR(255)` | `False` | `None` | `NOT NULL` |
| `body_part` | `VARCHAR(255)` | `True` | `NULL` | `DEFAULT NULL` |
| `findings` | `TEXT` | `True` | `NULL` | `DEFAULT NULL` |
| `impression` | `TEXT` | `True` | `NULL` | `DEFAULT NULL` |
| `image_url` | `VARCHAR(500)` | `True` | `NULL` | `DEFAULT NULL` |
| `status` | `ENUM('pending'` | `False` | `'pending'` | `,'done') NOT NULL DEFAULT 'pending'` |
| `is_external` | `TINYINT(1)` | `False` | `0` | `NOT NULL DEFAULT 0` |
| `requested_at` | `DATETIME` | `False` | `CURRENT_TIMESTAMP` | `NOT NULL DEFAULT CURRENT_TIMESTAMP` |
| `resulted_at` | `DATETIME` | `True` | `NULL` | `DEFAULT NULL` |

### 3.67 `mc_shifts` (`Backend/MedCorePlugin/includes/core/class-medcore-visits-shift-migration.php:L209-L245`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `shift_number` | `varchar(40)` | `False` | `None` | `NOT NULL` |
| `cashier_user_id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL` |
| `cashier_email` | `varchar(191)` | `True` | `None` | `NULL` |
| `cashier_name` | `varchar(191)` | `True` | `None` | `NULL` |
| `shift_type` | `varchar(30)` | `False` | `'MORNING'` | `NOT NULL DEFAULT 'MORNING'` |
| `clinic_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `status` | `varchar(30)` | `False` | `'OPEN'` | `NOT NULL DEFAULT 'OPEN'` |
| `auto_opened` | `tinyint(1)` | `False` | `0` | `NOT NULL DEFAULT 0` |
| `opened_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `closed_at` | `datetime` | `True` | `None` | `NULL` |
| `audited_at` | `datetime` | `True` | `None` | `NULL` |
| `audited_by` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `opening_cash_balance` | `decimal(14` | `False` | `0.0000` | `,4) NOT NULL DEFAULT 0.0000` |
| `system_cash_in` | `decimal(14` | `False` | `0.0000` | `,4) NOT NULL DEFAULT 0.0000` |
| `system_cash_out` | `decimal(14` | `False` | `0.0000` | `,4) NOT NULL DEFAULT 0.0000` |
| `system_card_in` | `decimal(14` | `False` | `0.0000` | `,4) NOT NULL DEFAULT 0.0000` |
| `system_transfer_in` | `decimal(14` | `False` | `0.0000` | `,4) NOT NULL DEFAULT 0.0000` |
| `system_net_cash` | `decimal(14` | `False` | `0.0000` | `,4) NOT NULL DEFAULT 0.0000` |
| `declared_cash_amount` | `decimal(14` | `True` | `None` | `,4) NULL` |
| `variance_amount` | `decimal(14` | `True` | `None` | `,4) NULL` |
| `handover_to_user_id` | `bigint(20) unsigned` | `True` | `None` | `NULL` |
| `notes` | `text` | `True` | `None` | `NULL` |
| `audit_notes` | `text` | `True` | `None` | `NULL` |
| `idempotency_key` | `varchar(191)` | `True` | `None` | `NULL` |
| `created_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `updated_at` | `datetime` | `False` | `None` | `NOT NULL` |

### 3.68 `mc_storage` (`Backend/MedCorePlugin/includes/core/class-medcore-migration.php:L464-L472`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20)` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `hospital_code` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `store_key` | `varchar(100)` | `False` | `None` | `NOT NULL` |
| `store_value` | `LONGTEXT` | `True` | `None` | `` |
| `updated_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP` |

### 3.69 `mc_subscription_events` (`Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L166-L174`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `subscription_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `event_type` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `timestamp` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |
| `actor_id` | `varchar(100)` | `True` | `None` | `` |

### 3.70 `mc_subscriptions` (`Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L153-L163`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `organization_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `plan_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `status` | `varchar(50)` | `True` | `'PENDING'` | `DEFAULT 'PENDING'` |
| `start_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `end_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `created_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |

### 3.71 `mc_surgeries` (`Backend/MedCorePlugin/includes/core/class-medcore-surgery-migration.php:L11-L46`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20)` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `patient_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `encounter_id` | `varchar(36)` | `True` | `None` | `NULL` |
| `or_room_id` | `varchar(36)` | `True` | `None` | `NULL` |
| `procedure_name` | `varchar(255)` | `False` | `None` | `NOT NULL` |
| `planned_date` | `date` | `False` | `None` | `NOT NULL` |
| `planned_time` | `time` | `True` | `None` | `NULL` |
| `estimated_duration` | `varchar(50)` | `True` | `None` | `NULL` |
| `urgency` | `varchar(20)` | `True` | `'Elective'` | `DEFAULT 'Elective'` |
| `laterality` | `varchar(20)` | `True` | `'N/A'` | `DEFAULT 'N/A'` |
| `anesthesia_type` | `varchar(50)` | `True` | `None` | `NULL` |
| `diagnosis` | `text` | `True` | `None` | `NULL` |
| `allergies` | `text` | `True` | `None` | `NULL` |
| `chronic_diseases` | `text` | `True` | `None` | `NULL` |
| `infection_status` | `varchar(100)` | `True` | `None` | `NULL` |
| `team_json` | `longtext` | `True` | `None` | `NULL` |
| `nursing_team_json` | `longtext` | `True` | `None` | `NULL` |
| `support_staff_json` | `longtext` | `True` | `None` | `NULL` |
| `companion_json` | `longtext` | `True` | `None` | `NULL` |
| `allowed_persons_json` | `longtext` | `True` | `None` | `NULL` |
| `requirements_json` | `longtext` | `True` | `None` | `NULL` |
| `readiness_json` | `longtext` | `True` | `None` | `NULL` |
| `status` | `varchar(50)` | `True` | `'Pending'` | `DEFAULT 'Pending'` |
| `created_by` | `varchar(100)` | `True` | `None` | `NULL` |
| `idempotency_key` | `varchar(100)` | `True` | `None` | `NULL` |
| `created_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |
| `updated_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP` |

### 3.72 `mc_sync_commands` (`Backend/MedCorePlugin/includes/core/class-medcore-identity-migration.php:L159-L175`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `command_id` | `varchar(100)` | `False` | `None` | `NOT NULL` |
| `device_id` | `varchar(100)` | `False` | `None` | `NOT NULL` |
| `actor_id` | `varchar(36)` | `True` | `None` | `NULL` |
| `entity_type` | `varchar(80)` | `False` | `None` | `NOT NULL` |
| `operation` | `varchar(40)` | `False` | `None` | `NOT NULL` |
| `payload` | `longtext` | `False` | `None` | `NOT NULL` |
| `occurred_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `received_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `synced_at` | `datetime` | `True` | `None` | `NULL` |
| `status` | `varchar(20)` | `False` | `'RECEIVED'` | `NOT NULL DEFAULT 'RECEIVED'` |
| `result` | `longtext` | `True` | `None` | `NULL` |

### 3.73 `mc_tenants` (`Backend/MedCorePlugin/includes/core/class-medcore-migration.php:L441-L460`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20)` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `hospital_name` | `varchar(255)` | `False` | `None` | `NOT NULL` |
| `contact_name` | `varchar(255)` | `True` | `None` | `` |
| `contact_email` | `varchar(255)` | `False` | `None` | `NOT NULL` |
| `phone` | `varchar(50)` | `True` | `None` | `` |
| `country` | `varchar(100)` | `True` | `None` | `` |
| `timezone` | `varchar(100)` | `True` | `None` | `` |
| `currency` | `varchar(10)` | `True` | `None` | `` |
| `status` | `varchar(50)` | `True` | `'Pending'` | `DEFAULT 'Pending'` |
| `plan_id` | `varchar(50)` | `True` | `None` | `` |
| `subscription_start` | `datetime` | `True` | `None` | `` |
| `subscription_end` | `datetime` | `True` | `None` | `` |
| `hospital_token_balance` | `bigint(20)` | `True` | `0` | `DEFAULT 0` |
| `created_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |
| `updated_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP` |

### 3.74 `mc_users` (`Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L40-L51`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `email` | `varchar(255)` | `False` | `None` | `NOT NULL` |
| `normalized_email` | `varchar(255)` | `False` | `None` | `NOT NULL` |
| `status` | `varchar(50)` | `True` | `'ACTIVE'` | `DEFAULT 'ACTIVE'` |
| `password_hash` | `varchar(255)` | `True` | `None` | `` |
| `created_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |
| `updated_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP` |
| `last_login_at` | `datetime` | `True` | `None` | `` |

### 3.75 `mc_visit_items` (`Backend/MedCorePlugin/includes/core/class-medcore-visits-shift-migration.php:L170-L196`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `visit_id` | `bigint(20) unsigned` | `False` | `None` | `NOT NULL` |
| `service_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `service_code` | `varchar(64)` | `True` | `None` | `NULL` |
| `service_name` | `varchar(191)` | `False` | `None` | `NOT NULL` |
| `service_category` | `varchar(64)` | `False` | `'consultation'` | `NOT NULL DEFAULT 'consultation'` |
| `doctor_id` | `varchar(100)` | `True` | `None` | `NULL` |
| `quantity` | `decimal(10` | `False` | `1.00` | `,2) NOT NULL DEFAULT 1.00` |
| `unit_price` | `decimal(14` | `False` | `0.0000` | `,4) NOT NULL DEFAULT 0.0000` |
| `discount_amount` | `decimal(14` | `False` | `0.0000` | `,4) NOT NULL DEFAULT 0.0000` |
| `insurance_covered_amount` | `decimal(14` | `False` | `0.0000` | `,4) NOT NULL DEFAULT 0.0000` |
| `net_amount` | `decimal(14` | `False` | `0.0000` | `,4) NOT NULL DEFAULT 0.0000` |
| `doctor_commission_type` | `varchar(30)` | `False` | `'percentage'` | `NOT NULL DEFAULT 'percentage'` |
| `doctor_commission_rate` | `decimal(10` | `False` | `0.0000` | `,4) NOT NULL DEFAULT 0.0000` |
| `doctor_earning_amount` | `decimal(14` | `False` | `0.0000` | `,4) NOT NULL DEFAULT 0.0000` |
| `hospital_share_amount` | `decimal(14` | `False` | `0.0000` | `,4) NOT NULL DEFAULT 0.0000` |
| `status` | `varchar(30)` | `False` | `'ACTIVE'` | `NOT NULL DEFAULT 'ACTIVE'` |
| `created_at` | `datetime` | `False` | `None` | `NOT NULL` |
| `updated_at` | `datetime` | `False` | `None` | `NOT NULL` |

### 3.76 `mc_visits` (`Backend/MedCorePlugin/includes/class-medcore-schema.php:L9-L38`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `BIGINT UNSIGNED` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `hospital_code` | `VARCHAR(50)` | `False` | `None` | `NOT NULL` |
| `branch_id` | `BIGINT UNSIGNED` | `True` | `NULL` | `DEFAULT NULL` |
| `appointment_id` | `BIGINT UNSIGNED` | `True` | `NULL` | `DEFAULT NULL` |
| `patient_id` | `BIGINT UNSIGNED` | `False` | `None` | `NOT NULL` |
| `doctor_id` | `BIGINT UNSIGNED` | `False` | `None` | `NOT NULL` |
| `visit_number` | `VARCHAR(50)` | `False` | `None` | `NOT NULL` |
| `visit_date` | `DATE` | `False` | `None` | `NOT NULL` |
| `visit_time` | `TIME` | `True` | `NULL` | `DEFAULT NULL` |
| `chief_complaint` | `TEXT` | `True` | `NULL` | `DEFAULT NULL` |
| `history` | `TEXT` | `True` | `NULL` | `DEFAULT NULL` |
| `examination` | `TEXT` | `True` | `NULL` | `DEFAULT NULL` |
| `diagnosis` | `TEXT` | `True` | `NULL` | `DEFAULT NULL` |
| `notes` | `TEXT` | `True` | `NULL` | `DEFAULT NULL` |
| `status` | `ENUM('open'` | `False` | `'open'` | `,'completed','cancelled') NOT NULL DEFAULT 'open'` |
| `total_amount` | `DECIMAL(12` | `False` | `0` | `,2) NOT NULL DEFAULT 0` |
| `total_paid` | `DECIMAL(12` | `False` | `0` | `,2) NOT NULL DEFAULT 0` |
| `total_balance` | `DECIMAL(12` | `False` | `0` | `,2) NOT NULL DEFAULT 0` |
| `payment_method` | `ENUM('cash'` | `True` | `'cash'` | `,'card','insurance','cheque','deferred','mixed') DEFAULT 'cash'` |
| `insurance_id` | `BIGINT UNSIGNED` | `True` | `NULL` | `DEFAULT NULL` |
| `insurance_card` | `VARCHAR(100)` | `True` | `NULL` | `DEFAULT NULL` |
| `copay_amount` | `DECIMAL(10` | `False` | `0` | `,2) NOT NULL DEFAULT 0` |
| `created_by` | `BIGINT UNSIGNED` | `True` | `NULL` | `DEFAULT NULL` |
| `created_at` | `DATETIME` | `False` | `CURRENT_TIMESTAMP` | `NOT NULL DEFAULT CURRENT_TIMESTAMP` |
| `updated_at` | `DATETIME` | `False` | `CURRENT_TIMESTAMP` | `NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP` |

### 3.77 `mc_wallet_ledger` (`Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L86-L99`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `wallet_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `transaction_type` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `amount` | `bigint(20)` | `False` | `None` | `NOT NULL` |
| `balance_after` | `bigint(20)` | `False` | `None` | `NOT NULL` |
| `reference_id` | `varchar(100)` | `True` | `None` | `` |
| `idempotency_key` | `varchar(100)` | `True` | `None` | `` |
| `actor_id` | `varchar(100)` | `True` | `None` | `` |
| `timestamp` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |

### 3.78 `mc_wallets` (`Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L69-L83`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `wallet_type` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `owner_type` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `owner_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `status` | `varchar(50)` | `True` | `'ACTIVE'` | `DEFAULT 'ACTIVE'` |
| `currency` | `varchar(20)` | `True` | `'TOKENS'` | `DEFAULT 'TOKENS'` |
| `ledger_balance` | `bigint(20)` | `False` | `'0'` | `NOT NULL DEFAULT '0'` |
| `reserved_balance` | `bigint(20)` | `False` | `'0'` | `NOT NULL DEFAULT '0'` |
| `available_balance` | `bigint(20)` | `False` | `'0'` | `NOT NULL DEFAULT '0'` |
| `created_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |
| `updated_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP` |

### 3.79 `mc_ward_beds` (`Backend/MedCorePlugin/includes/core/class-medcore-admissions-migration.php:L47-L58`)

| Column | Type | Nullable | Default | Extra / Constraints |
|---|---|---|---|---|
| `id` | `bigint(20)` | `False` | `None` | `NOT NULL AUTO_INCREMENT` |
| `tenant_id` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `public_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `department_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `room_id` | `varchar(36)` | `False` | `None` | `NOT NULL` |
| `bed_number` | `varchar(50)` | `False` | `None` | `NOT NULL` |
| `status` | `varchar(50)` | `True` | `'Available'` | `DEFAULT 'Available', -- Available, Occupied, Maintenance` |
| `created_at` | `datetime` | `True` | `CURRENT_TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` |

## 4. Orphan Table References (Referenced in PHP Queries Without `CREATE TABLE`)

| Orphan Table Name | Query Reference Count | Explanation & Impact |
|---|---|---|
| `mc_expenses` | 1 | Referenced in `class-dbx-api-router.php` / legacy purge list; superseded by `mc_treasury_vouchers` (`voucher_type = 'OUT'`) and `mc_financial_postings` (`EXPENSE_OUT`). |
| `mc_lab_orders` | 2 | Legacy table name referenced in purge/cleanup; authoritative lab orders live in `mc_orders` (`category = 'LAB'`) and `mc_lab_results`. |
| `mc_radiology_orders` | 1 | Legacy table name referenced in purge/cleanup; authoritative radiology orders live in `mc_orders` (`category = 'RAD'`) and `mc_radiology_reports`. |
| `mc_staff_evaluations` | 5 | Referenced in `Backend/MedCorePlugin/includes/api/class-api-hr.php:209-250` (`GET/POST /medcore/v1/hr/evaluations`). Fails on fresh DB install unless manually created! |

## 5. `ALTER TABLE` Runtime Migration Blocks

| # | File:Line | Table | SQL Snippet |
|---|---|---|---|
| 1 | `Backend/MedCorePlugin/includes/core/class-medcore-debug-migration.php:50` | `` | `// Check ordered columns AND uniqueness if ( $index_cols[ $idx_name ]['columns'] !== $req['columns'] \|\| $index_cols[ $idx_name ]['non_unique'] !== $req['non_unique'] ) { $wpdb->q` |
| 2 | `Backend/MedCorePlugin/includes/core/class-medcore-identity-migration.php:80` | `` | `if ( ! self::column_exists( $table, $column ) ) { $wpdb->last_error = ''; $result = $wpdb->query( "ALTER TABLE {$table} ADD COLUMN {$column} {$definition}" ); if ( $result === fals` |
| 3 | `Backend/MedCorePlugin/includes/core/class-medcore-identity-migration.php:96` | `` | `if ( ! self::index_matches( $table, $index, $definition, false ) ) { $wpdb->last_error = ''; $result = $wpdb->query( "ALTER TABLE {$table} ADD KEY {$index} {$definition}" ); if ( $` |
| 4 | `Backend/MedCorePlugin/includes/core/class-medcore-identity-migration.php:112` | `` | `if ( ! self::index_matches( $table, $index, $definition, true ) ) { $wpdb->last_error = ''; $result = $wpdb->query( "ALTER TABLE {$table} ADD UNIQUE KEY {$index} {$definition}" ); ` |
| 5 | `Backend/MedCorePlugin/includes/core/class-medcore-patient-domain-migration.php:146` | `` | `if ( isset( $index_cols[ $idx_name ] ) ) { if ( $index_cols[ $idx_name ]['columns'] !== $req['columns'] \|\| $index_cols[ $idx_name ]['non_unique'] !== $req['non_unique'] ) { $wpdb` |
| 6 | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:325` | `` | `$fk_queries = [ "ALTER TABLE {$wpdb->prefix}mc_wallet_ledger ADD CONSTRAINT fk_wallet_ledger_wallet FOREIGN KEY (wallet_id) REFERENCES {$wpdb->prefix}mc_wallets(id) ON DELETE RESTR` |
| 7 | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:326` | `` | `$fk_queries = [ "ALTER TABLE {$wpdb->prefix}mc_wallet_ledger ADD CONSTRAINT fk_wallet_ledger_wallet FOREIGN KEY (wallet_id) REFERENCES {$wpdb->prefix}mc_wallets(id) ON DELETE RESTR` |
| 8 | `Backend/MedCorePlugin/includes/core/class-medcore-visits-shift-migration.php:570` | `` | `$index_cols[ $idx_key ]['non_unique'] !== (string) $req['non_unique'] ) { self::exec_query( "ALTER TABLE {$table} DROP INDEX {$idx_name}", "drop mismatched index {$table}.{$idx_nam` |
| 9 | `Backend/MedCorePlugin/includes/core/class-medcore-visits-shift-migration.php:716` | `` | `} } self::exec_query( "ALTER TABLE {$table} ADD COLUMN {$column} {$definition}", "add column {$table}.{$column}" ); } } private static function modify_column( $table, $column, $def` |
| 10 | `Backend/MedCorePlugin/includes/core/class-medcore-visits-shift-migration.php:722` | `` | `private static function modify_column( $table, $column, $definition ) { if ( self::column_exists( $table, $column ) ) { self::exec_query( "ALTER TABLE {$table} MODIFY COLUMN {$colu` |
| 11 | `Backend/MedCorePlugin/includes/core/class-medcore-visits-shift-migration.php:759` | `` | `} if ( ! empty( $existing ) ) { self::exec_query( "ALTER TABLE {$table} DROP INDEX {$index_name}", "drop mismatched index {$table}.{$index_name}" ); } $kind = $unique ? 'UNIQUE KEY` |
| 12 | `Backend/MedCorePlugin/includes/core/class-medcore-visits-shift-migration.php:762` | `` | `} $kind = $unique ? 'UNIQUE KEY' : 'KEY'; self::exec_query( "ALTER TABLE {$table} ADD {$kind} {$index_name} ({$cols_sql})", "add index {$table}.{$index_name}" ); } private static f` |