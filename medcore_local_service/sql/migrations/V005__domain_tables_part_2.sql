-- ============================================================================
-- V005: Extracted Domain Tables Batch 2 (12 Normalized InnoDB Tables)
-- ============================================================================

CREATE TABLE IF NOT EXISTS `mc_clinical_templates` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `public_id` VARCHAR(36) NOT NULL,
    `tenant_id` VARCHAR(50) NOT NULL,
    `template_number` VARCHAR(40) NOT NULL,
    `code` VARCHAR(100) NULL,
    `title` VARCHAR(190) NOT NULL,
    `specialty` VARCHAR(120) NULL,
    `category` VARCHAR(60) NOT NULL,
    `owner_type` VARCHAR(30) NOT NULL DEFAULT 'STAFF',
    `owner_id` VARCHAR(100) NULL,
    `version` INT UNSIGNED NOT NULL DEFAULT 1,
    `status` VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',
    `content_json` LONGTEXT NULL,
    `created_by` VARCHAR(100) NULL,
    `updated_by` VARCHAR(100) NULL,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    KEY `idx_mc_clinical_templates_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_coa_accounts` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `tenant_id` VARCHAR(50) NOT NULL,
    `public_id` VARCHAR(36) NOT NULL,
    `code` VARCHAR(20) NOT NULL,
    `name` VARCHAR(150) NOT NULL,
    `type` VARCHAR(20) NOT NULL,
    `parent_id` BIGINT(20) UNSIGNED NULL,
    `status` VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    `created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_coa_accounts_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_consent_events` (
    `id` VARCHAR(36) NOT NULL,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `user_id` VARCHAR(36) NOT NULL,
    `purpose` VARCHAR(100) NOT NULL,
    `status` VARCHAR(50) NOT NULL,
    `timestamp` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    `source` VARCHAR(100) NULL,
    `ip_address` VARCHAR(45) NULL,
    KEY `idx_mc_consent_events_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_definition_links` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `tenant_id` VARCHAR(50) NOT NULL,
    `source_definition_id` BIGINT(20) UNSIGNED NOT NULL,
    `relation_type` VARCHAR(50) NOT NULL,
    `target_definition_id` BIGINT(20) UNSIGNED NOT NULL,
    `metadata_json` LONGTEXT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_definition_links_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_definition_rules` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `public_id` VARCHAR(36) NOT NULL,
    `tenant_id` VARCHAR(50) NOT NULL,
    `definition_id` BIGINT(20) UNSIGNED NULL,
    `rule_type` VARCHAR(50) NOT NULL,
    `rule_key` VARCHAR(100) NOT NULL,
    `subject_type` VARCHAR(50) NULL,
    `subject_id` VARCHAR(100) NULL,
    `target_type` VARCHAR(50) NULL,
    `target_id` VARCHAR(100) NULL,
    `parent_rule_id` BIGINT(20) UNSIGNED NULL,
    `precedence` INT(10) NOT NULL DEFAULT 0,
    `calc_mode` VARCHAR(20) NULL,
    `percent` DECIMAL(14,4) NULL,
    `fixed_amount` DECIMAL(14,4) NULL,
    `price` DECIMAL(14,4) NULL,
    `conditions_json` LONGTEXT NULL,
    `status` VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',
    `version` INT(10) UNSIGNED NOT NULL DEFAULT 1,
    `valid_from` DATETIME NULL,
    `valid_to` DATETIME NULL,
    `created_by` VARCHAR(36) NULL,
    `updated_by` VARCHAR(36) NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_definition_rules_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_definitions` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `public_id` VARCHAR(36) NOT NULL,
    `tenant_id` VARCHAR(50) NOT NULL,
    `definition_type` VARCHAR(50) NOT NULL,
    `code` VARCHAR(100) NOT NULL,
    `name` VARCHAR(255) NOT NULL,
    `status` VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',
    `version` INT(10) UNSIGNED NOT NULL DEFAULT 1,
    `data_json` LONGTEXT NULL,
    `valid_from` DATETIME NULL,
    `valid_to` DATETIME NULL,
    `created_by` VARCHAR(36) NULL,
    `updated_by` VARCHAR(36) NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_definitions_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_dialysis_sessions` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `tenant_id` VARCHAR(50) NOT NULL,
    `public_id` VARCHAR(36) NOT NULL,
    `patient_id` VARCHAR(36) NOT NULL,
    `encounter_id` VARCHAR(36) NULL,
    `machine_id` VARCHAR(36) NULL,
    `session_date` DATETIME NOT NULL,
    `pre_weight` DECIMAL(14,4) NULL,
    `post_weight` DECIMAL(14,4) NULL,
    `duration_minutes` INT(11) NULL,
    `clinical_notes` TEXT NULL,
    `telemetry_json` LONGTEXT NULL,
    `status` VARCHAR(50) NULL DEFAULT 'Scheduled',
    `created_by` VARCHAR(100) NULL,
    `idempotency_key` VARCHAR(100) NULL,
    `created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_dialysis_sessions_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_earning_lines` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `public_id` VARCHAR(36) NOT NULL,
    `tenant_id` VARCHAR(50) NOT NULL,
    `financial_event_id` BIGINT(20) UNSIGNED NOT NULL,
    `line_number` INT(10) UNSIGNED NOT NULL,
    `beneficiary_type` VARCHAR(30) NOT NULL,
    `beneficiary_id` VARCHAR(100) NOT NULL,
    `beneficiary_scope` VARCHAR(20) NOT NULL DEFAULT 'INTERNAL',
    `provider_id` VARCHAR(100) NULL,
    `earning_type` VARCHAR(50) NOT NULL,
    `basis_type` VARCHAR(30) NOT NULL,
    `basis_amount` DECIMAL(14,4) NOT NULL DEFAULT 0,
    `amount` DECIMAL(14,4) NOT NULL DEFAULT 0,
    `currency` VARCHAR(20) NOT NULL,
    `calc_mode` VARCHAR(20) NULL,
    `rule_id` BIGINT(20) UNSIGNED NULL,
    `rule_public_id` VARCHAR(36) NULL,
    `rule_version` INT(10) UNSIGNED NULL,
    `rule_snapshot_json` LONGTEXT NULL,
    `settlement_status` VARCHAR(30) NOT NULL DEFAULT 'PENDING',
    `settled_at` DATETIME NULL,
    `idempotency_key` VARCHAR(120) NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_earning_lines_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_encounters` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `public_id` VARCHAR(36) NOT NULL,
    `tenant_id` VARCHAR(50) NOT NULL,
    `encounter_number` VARCHAR(40) NOT NULL,
    `idempotency_key` VARCHAR(191) NULL,
    `source_device_id` VARCHAR(100) NULL,
    `local_sequence` BIGINT UNSIGNED NULL,
    `patient_id` BIGINT(20) UNSIGNED NOT NULL,
    `appointment_id` BIGINT(20) UNSIGNED NULL,
    `visit_id` BIGINT(20) UNSIGNED NULL,
    `clinic_id` VARCHAR(100) NULL,
    `provider_id` VARCHAR(100) NULL,
    `encounter_type` VARCHAR(40) NOT NULL DEFAULT 'OUTPATIENT',
    `status` VARCHAR(30) NOT NULL DEFAULT 'OPEN',
    `chief_complaint` TEXT NULL,
    `history_json` LONGTEXT NULL,
    `vitals_json` LONGTEXT NULL,
    `examination_json` LONGTEXT NULL,
    `assessment_json` LONGTEXT NULL,
    `plan_json` LONGTEXT NULL,
    `diagnoses_json` LONGTEXT NULL,
    `notes` TEXT NULL,
    `started_at` DATETIME NULL,
    `completed_at` DATETIME NULL,
    `occurred_at` DATETIME NOT NULL,
    `created_by` VARCHAR(100) NULL,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    KEY `idx_mc_encounters_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_entitlements` (
    `id` VARCHAR(36) NOT NULL,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `target_type` VARCHAR(50) NOT NULL,
    `target_id` VARCHAR(36) NOT NULL,
    `feature_id` VARCHAR(36) NOT NULL,
    `status` VARCHAR(50) NULL DEFAULT 'ACTIVE',
    `entitlement_type` VARCHAR(50) NOT NULL,
    `created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_entitlements_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_error_log` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `timestamp` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    `severity` VARCHAR(20) NULL,
    `module` VARCHAR(100) NULL,
    `error_code` VARCHAR(50) NULL,
    `endpoint` VARCHAR(255) NULL,
    `request_id` VARCHAR(50) NULL,
    `actor_email` VARCHAR(100) NULL,
    `tenant_id` VARCHAR(50) NULL,
    `safe_message` TEXT NULL,
    KEY `idx_mc_error_log_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_fallback_quotas` (
    `id` VARCHAR(36) NOT NULL,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `membership_id` VARCHAR(36) NOT NULL,
    `wallet_id` VARCHAR(36) NOT NULL,
    `max_spend` BIGINT(20) NOT NULL DEFAULT '0',
    `consumed` BIGINT(20) NOT NULL DEFAULT '0',
    `period` VARCHAR(50) NULL DEFAULT 'MONTHLY',
    `created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_fallback_quotas_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
