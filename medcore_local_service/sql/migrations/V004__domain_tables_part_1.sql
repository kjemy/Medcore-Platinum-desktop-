-- ============================================================================
-- V004: Extracted Domain Tables Batch 1 (12 Normalized InnoDB Tables)
-- ============================================================================

CREATE TABLE IF NOT EXISTS `mc_admissions` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `tenant_id` VARCHAR(50) NOT NULL,
    `public_id` VARCHAR(36) NOT NULL,
    `patient_id` VARCHAR(36) NOT NULL,
    `encounter_id` VARCHAR(36) NULL,
    `admission_type` VARCHAR(50) NOT NULL,
    `department_id` VARCHAR(36) NULL,
    `room_id` VARCHAR(36) NULL,
    `bed_id` VARCHAR(36) NULL,
    `admission_date` DATETIME NOT NULL,
    `expected_discharge_date` DATETIME NULL,
    `actual_discharge_date` DATETIME NULL,
    `discharge_date` DATETIME NULL,
    `discharge_reason` TEXT NULL,
    `attending_doctor_id` VARCHAR(36) NULL,
    `referring_doctor_id` VARCHAR(36) NULL,
    `diagnosis_json` LONGTEXT NULL,
    `clinical_notes_json` LONGTEXT NULL,
    `status` VARCHAR(50) NULL DEFAULT 'Admitted',
    `created_by` VARCHAR(100) NULL,
    `idempotency_key` VARCHAR(100) NULL,
    `created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_admissions_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_ai_transactions` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `timestamp` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    `actor_email` VARCHAR(100) NULL,
    `tenant_id` VARCHAR(50) NULL,
    `provider` VARCHAR(50) NULL,
    `model` VARCHAR(50) NULL,
    `token_amount` BIGINT(20) NULL,
    `action_type` VARCHAR(20) NULL,
    `balance_before` BIGINT(20) NULL,
    `balance_after` BIGINT(20) NULL,
    `request_id` VARCHAR(50) NULL,
    `status` VARCHAR(50) NULL,
    KEY `idx_mc_ai_transactions_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_ai_usage` (
    `id` VARCHAR(36) NOT NULL,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `operation_id` VARCHAR(100) NOT NULL,
    `wallet_id` VARCHAR(36) NOT NULL,
    `reserved_amount` BIGINT(20) NOT NULL DEFAULT '0',
    `status` VARCHAR(50) NOT NULL DEFAULT 'PENDING',
    `provider_operation_id` VARCHAR(100) NULL,
    `provider_reconciliation_id` VARCHAR(100) NULL,
    `created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_ai_usage_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_apgar_scores` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `tenant_id` VARCHAR(50) NOT NULL,
    `public_id` VARCHAR(36) NOT NULL,
    `admission_id` VARCHAR(36) NOT NULL,
    `min1_score` INT(11) NULL,
    `min5_score` INT(11) NULL,
    `min10_score` INT(11) NULL,
    `details_json` LONGTEXT NULL,
    `created_by` VARCHAR(100) NULL,
    `idempotency_key` VARCHAR(100) NULL,
    `created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_apgar_scores_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_appointments` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `public_id` VARCHAR(36) NOT NULL,
    `tenant_id` VARCHAR(50) NOT NULL,
    `appointment_number` VARCHAR(40) NOT NULL,
    `idempotency_key` VARCHAR(191) NULL,
    `source_device_id` VARCHAR(100) NULL,
    `local_sequence` BIGINT UNSIGNED NULL,
    `patient_id` BIGINT(20) UNSIGNED NOT NULL,
    `clinic_id` VARCHAR(100) NULL,
    `doctor_id` VARCHAR(100) NULL,
    `appointment_type` VARCHAR(40) NOT NULL DEFAULT 'CONSULTATION',
    `scheduled_at` DATETIME NOT NULL,
    `duration_minutes` INT UNSIGNED NULL,
    `status` VARCHAR(30) NOT NULL DEFAULT 'SCHEDULED',
    `reason` TEXT NULL,
    `notes` TEXT NULL,
    `cancellation_reason` TEXT NULL,
    `created_by` VARCHAR(100) NULL,
    `occurred_at` DATETIME NOT NULL,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    KEY `idx_mc_appointments_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_audit_log` (
    `event_id` BIGINT(20) NOT NULL,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `timestamp` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    `event_type` VARCHAR(100) NOT NULL,
    `actor_email` VARCHAR(100) NULL,
    `tenant_id` VARCHAR(50) NULL,
    `target_type` VARCHAR(50) NULL,
    `target_id` VARCHAR(100) NULL,
    `action` VARCHAR(50) NULL,
    `status` VARCHAR(50) NULL,
    `ip_address` VARCHAR(45) NULL,
    `user_agent` VARCHAR(255) NULL,
    `request_id` VARCHAR(50) NULL,
    PRIMARY KEY (`event_id`),
    KEY `idx_mc_audit_log_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_clinical_order_events` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `tenant_id` VARCHAR(50) NOT NULL,
    `order_id` BIGINT(20) UNSIGNED NOT NULL,
    `event_type` VARCHAR(40) NOT NULL,
    `from_status` VARCHAR(40) NULL,
    `to_status` VARCHAR(40) NULL,
    `actor_id` VARCHAR(100) NULL,
    `payload_json` LONGTEXT NULL,
    `occurred_at` DATETIME NOT NULL,
    KEY `idx_mc_clinical_order_events_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_clinical_order_items` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `public_id` VARCHAR(36) NOT NULL,
    `tenant_id` VARCHAR(50) NOT NULL,
    `order_id` BIGINT(20) UNSIGNED NOT NULL,
    `item_type` VARCHAR(30) NOT NULL,
    `definition_id` VARCHAR(36) NULL,
    `item_code` VARCHAR(100) NULL,
    `item_name` VARCHAR(190) NOT NULL,
    `quantity` DECIMAL(14,4) NOT NULL DEFAULT 1,
    `price` DECIMAL(14,4) NULL,
    `result_status` VARCHAR(30) NOT NULL DEFAULT 'PENDING',
    `payload_json` LONGTEXT NULL,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    KEY `idx_mc_clinical_order_items_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_clinical_orders` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `public_id` VARCHAR(36) NOT NULL,
    `tenant_id` VARCHAR(50) NOT NULL,
    `order_number` VARCHAR(40) NOT NULL,
    `idempotency_key` VARCHAR(191) NULL,
    `encounter_id` BIGINT(20) UNSIGNED NULL,
    `patient_id` BIGINT(20) UNSIGNED NOT NULL,
    `provider_id` VARCHAR(100) NULL,
    `clinic_id` VARCHAR(100) NULL,
    `order_type` VARCHAR(30) NOT NULL,
    `priority` VARCHAR(20) NOT NULL DEFAULT 'ROUTINE',
    `status` VARCHAR(40) NOT NULL DEFAULT 'ORDERED',
    `clinical_indication` TEXT NULL,
    `payload_json` LONGTEXT NULL,
    `occurred_at` DATETIME NOT NULL,
    `created_by` VARCHAR(100) NULL,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    KEY `idx_mc_clinical_orders_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_clinical_results` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `public_id` VARCHAR(36) NOT NULL,
    `tenant_id` VARCHAR(50) NOT NULL,
    `order_id` BIGINT(20) UNSIGNED NOT NULL,
    `item_id` BIGINT(20) UNSIGNED NULL,
    `result_type` VARCHAR(30) NOT NULL,
    `result_json` LONGTEXT NULL,
    `status` VARCHAR(30) NOT NULL DEFAULT 'DRAFT',
    `idempotency_key` VARCHAR(191) NULL,
    `entered_by` VARCHAR(100) NULL,
    `verified_by` VARCHAR(100) NULL,
    `entered_at` DATETIME NULL,
    `verified_at` DATETIME NULL,
    `delivered_at` DATETIME NULL,
    `critical_flag` TINYINT(1) NOT NULL DEFAULT 0,
    `critical_acknowledged_by` VARCHAR(100) NULL,
    `critical_acknowledged_at` DATETIME NULL,
    `notes` TEXT NULL,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    KEY `idx_mc_clinical_results_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_clinical_specimens` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `public_id` VARCHAR(36) NOT NULL,
    `tenant_id` VARCHAR(50) NOT NULL,
    `order_id` BIGINT(20) UNSIGNED NOT NULL,
    `item_id` BIGINT(20) UNSIGNED NULL,
    `barcode` VARCHAR(100) NOT NULL,
    `idempotency_key` VARCHAR(191) NULL,
    `specimen_type` VARCHAR(100) NULL,
    `container_type` VARCHAR(100) NULL,
    `status` VARCHAR(30) NOT NULL DEFAULT 'ORDERED',
    `collected_at` DATETIME NULL,
    `collected_by` VARCHAR(100) NULL,
    `received_at` DATETIME NULL,
    `rejection_reason` TEXT NULL,
    `payload_json` LONGTEXT NULL,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    KEY `idx_mc_clinical_specimens_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_clinical_template_usages` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `public_id` VARCHAR(36) NOT NULL,
    `tenant_id` VARCHAR(50) NOT NULL,
    `template_id` BIGINT(20) UNSIGNED NOT NULL,
    `template_version` INT UNSIGNED NOT NULL,
    `encounter_id` BIGINT(20) UNSIGNED NULL,
    `patient_id` BIGINT(20) UNSIGNED NULL,
    `provider_id` VARCHAR(100) NULL,
    `snapshot_json` LONGTEXT NULL,
    `used_at` DATETIME NOT NULL,
    `used_by` VARCHAR(100) NULL,
    KEY `idx_mc_clinical_template_usages_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
