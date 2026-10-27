-- ============================================================================
-- V007: Extracted Domain Tables Batch 4 (12 Normalized InnoDB Tables)
-- ============================================================================

CREATE TABLE IF NOT EXISTS `mc_inventory_movements` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `public_id` VARCHAR(36) NOT NULL,
    `tenant_id` VARCHAR(50) NOT NULL,
    `movement_number` VARCHAR(40) NOT NULL,
    `movement_type` VARCHAR(40) NOT NULL,
    `item_id` BIGINT(20) UNSIGNED NOT NULL,
    `batch_id` BIGINT(20) UNSIGNED NULL,
    `source_location_id` BIGINT(20) UNSIGNED NULL,
    `destination_location_id` BIGINT(20) UNSIGNED NULL,
    `quantity` DECIMAL(14,4) NOT NULL,
    `unit_cost` DECIMAL(14,4) NOT NULL DEFAULT 0,
    `patient_id` VARCHAR(36) NULL,
    `beneficiary_type` VARCHAR(30) NULL,
    `beneficiary_id` VARCHAR(100) NULL,
    `custody_type` VARCHAR(30) NULL,
    `custody_id` VARCHAR(100) NULL,
    `reason_code` VARCHAR(50) NULL,
    `source_reference_type` VARCHAR(50) NULL,
    `source_reference_id` VARCHAR(100) NULL,
    `idempotency_key` VARCHAR(120) NULL,
    `occurred_at` DATETIME NOT NULL,
    `created_by` VARCHAR(36) NULL,
    `metadata_json` LONGTEXT NULL,
    KEY `idx_mc_inventory_movements_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_inventory_requests` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `public_id` VARCHAR(36) NOT NULL,
    `tenant_id` VARCHAR(50) NOT NULL,
    `request_number` VARCHAR(40) NOT NULL,
    `item_id` BIGINT(20) UNSIGNED NOT NULL,
    `batch_id` BIGINT(20) UNSIGNED NULL,
    `source_location_id` BIGINT(20) UNSIGNED NULL,
    `destination_location_id` BIGINT(20) UNSIGNED NOT NULL,
    `requested_quantity` DECIMAL(14,4) NOT NULL,
    `approved_quantity` DECIMAL(14,4) NULL,
    `issued_quantity` DECIMAL(14,4) NOT NULL DEFAULT 0,
    `status` VARCHAR(30) NOT NULL DEFAULT 'PENDING',
    `requested_by` VARCHAR(100) NULL,
    `approved_by` VARCHAR(100) NULL,
    `source_reference_type` VARCHAR(50) NULL,
    `source_reference_id` VARCHAR(100) NULL,
    `idempotency_key` VARCHAR(120) NULL,
    `approve_idempotency_key` VARCHAR(191) NULL,
    `reject_idempotency_key` VARCHAR(191) NULL,
    `issue_idempotency_key` VARCHAR(191) NULL,
    `requested_at` DATETIME NOT NULL,
    `approved_at` DATETIME NULL,
    `issued_at` DATETIME NULL,
    `metadata_json` LONGTEXT NULL,
    KEY `idx_mc_inventory_requests_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_inventory_reservations` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `public_id` VARCHAR(36) NOT NULL,
    `tenant_id` VARCHAR(50) NOT NULL,
    `item_id` BIGINT(20) UNSIGNED NOT NULL,
    `batch_id` BIGINT(20) UNSIGNED NULL,
    `location_id` BIGINT(20) UNSIGNED NOT NULL,
    `request_id` BIGINT(20) UNSIGNED NULL,
    `patient_id` VARCHAR(36) NULL,
    `quantity` DECIMAL(14,4) NOT NULL,
    `status` VARCHAR(20) NOT NULL DEFAULT 'RESERVED',
    `expires_at` DATETIME NULL,
    `created_by` VARCHAR(100) NULL,
    `created_at` DATETIME NOT NULL,
    `released_at` DATETIME NULL,
    `metadata_json` LONGTEXT NULL,
    `idempotency_key` VARCHAR(191) NULL,
    KEY `idx_mc_inventory_reservations_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_journal_entries` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `tenant_id` VARCHAR(50) NOT NULL,
    `public_id` VARCHAR(36) NOT NULL,
    `journal_number` VARCHAR(50) NOT NULL,
    `entry_date` DATETIME NOT NULL,
    `description` TEXT NULL,
    `reference_type` VARCHAR(50) NULL,
    `reference_id` VARCHAR(100) NULL,
    `status` VARCHAR(20) NOT NULL DEFAULT 'POSTED',
    `idempotency_key` VARCHAR(120) NULL,
    `created_by` VARCHAR(100) NULL,
    `created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_journal_entries_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_journal_lines` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `tenant_id` VARCHAR(50) NOT NULL,
    `public_id` VARCHAR(36) NOT NULL,
    `journal_entry_id` BIGINT(20) UNSIGNED NOT NULL,
    `account_id` BIGINT(20) UNSIGNED NOT NULL,
    `debit` DECIMAL(14,4) NOT NULL DEFAULT 0.0000,
    `credit` DECIMAL(14,4) NOT NULL DEFAULT 0.0000,
    `description` VARCHAR(255) NULL,
    `created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_journal_lines_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_lab_orders` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(50) NOT NULL,
    `patient_id` BIGINT(20) NOT NULL,
    `doctor_name` VARCHAR(255) NULL,
    `priority` VARCHAR(20) NULL DEFAULT 'ROUTINE',
    `status` VARCHAR(50) NULL DEFAULT 'PENDING',
    `barcode` VARCHAR(100) NULL,
    `payload_json` LONGTEXT NULL,
    `created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_lab_orders_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_lab_referrals` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `public_id` VARCHAR(36) NOT NULL,
    `tenant_id` VARCHAR(50) NOT NULL,
    `referral_number` VARCHAR(40) NOT NULL,
    `referral_type` VARCHAR(30) NOT NULL DEFAULT 'LAB_TO_LAB',
    `source_order_id` BIGINT(20) UNSIGNED NOT NULL,
    `source_item_id` BIGINT(20) UNSIGNED NULL,
    `source_patient_id` BIGINT(20) UNSIGNED NOT NULL,
    `source_encounter_id` BIGINT(20) UNSIGNED NULL,
    `destination_tenant_id` VARCHAR(50) NULL,
    `external_provider_code` VARCHAR(100) NULL,
    `external_provider_name` VARCHAR(190) NULL,
    `external_reference` VARCHAR(190) NULL,
    `status` VARCHAR(40) NOT NULL DEFAULT 'REQUESTED',
    `requested_at` DATETIME NOT NULL,
    `accepted_at` DATETIME NULL,
    `rejected_at` DATETIME NULL,
    `sent_at` DATETIME NULL,
    `received_at` DATETIME NULL,
    `completed_at` DATETIME NULL,
    `result_reference` VARCHAR(190) NULL,
    `rejection_reason` TEXT NULL,
    `idempotency_key` VARCHAR(191) NULL,
    `payload_json` LONGTEXT NULL,
    `created_by` VARCHAR(100) NULL,
    `updated_by` VARCHAR(100) NULL,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    KEY `idx_mc_lab_referrals_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_lab_requests` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(50) NOT NULL,
    `visit_id` BIGINT UNSIGNED NOT NULL,
    `patient_id` BIGINT UNSIGNED NOT NULL,
    `doctor_id` BIGINT UNSIGNED NOT NULL,
    `test_name` VARCHAR(255) NOT NULL,
    `result` TEXT NULL,
    `normal_range` VARCHAR(255) NULL DEFAULT NULL,
    `unit` VARCHAR(50) NULL DEFAULT NULL,
    `status` VARCHAR(191) NOT NULL DEFAULT 'pending',
    `is_external` TINYINT(1) NOT NULL DEFAULT 0,
    `lab_name` VARCHAR(255) NULL DEFAULT NULL,
    `requested_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `resulted_at` DATETIME NULL DEFAULT NULL,
    KEY `idx_mc_lab_requests_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_memberships` (
    `id` VARCHAR(36) NOT NULL,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `user_id` VARCHAR(36) NOT NULL,
    `hospital_id` VARCHAR(36) NOT NULL,
    `role` VARCHAR(50) NOT NULL,
    `status` VARCHAR(50) NULL DEFAULT 'ACTIVE',
    `created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    `revoked_at` DATETIME NULL,
    `revoked_by` VARCHAR(36) NULL,
    KEY `idx_mc_memberships_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_migration_exceptions` (
    `id` VARCHAR(36) NOT NULL,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `run_id` VARCHAR(36) NOT NULL,
    `source_id` VARCHAR(255) NOT NULL,
    `exception_type` VARCHAR(100) NOT NULL,
    `reason` TEXT NULL,
    `status` VARCHAR(50) NULL DEFAULT 'MANUAL_REVIEW_REQUIRED',
    `created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_migration_exceptions_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_migration_runs` (
    `id` VARCHAR(36) NOT NULL,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `started_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    `status` VARCHAR(50) NULL DEFAULT 'RUNNING',
    `checksum` VARCHAR(255) NULL,
    KEY `idx_mc_migration_runs_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_nicu_growth_logs` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `tenant_id` VARCHAR(50) NOT NULL,
    `public_id` VARCHAR(36) NOT NULL,
    `patient_id` VARCHAR(36) NULL,
    `incubator_id` VARCHAR(36) NULL,
    `weight_grams` DECIMAL(14,4) NOT NULL,
    `head_circumference_cm` DECIMAL(14,4) NULL,
    `length_cm` DECIMAL(14,4) NULL,
    `feeding_ml` DECIMAL(14,4) NULL,
    `day_of_life` INT(11) NULL,
    `details_json` LONGTEXT NULL,
    `logged_by` VARCHAR(100) NULL,
    `logged_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    `created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_nicu_growth_logs_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
