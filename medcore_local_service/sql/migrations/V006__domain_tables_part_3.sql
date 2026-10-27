-- ============================================================================
-- V006: Extracted Domain Tables Batch 3 (12 Normalized InnoDB Tables)
-- ============================================================================

CREATE TABLE IF NOT EXISTS `mc_features` (
    `id` VARCHAR(36) NOT NULL,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `feature_key` VARCHAR(100) NOT NULL,
    `name` VARCHAR(255) NOT NULL,
    `status` VARCHAR(50) NULL DEFAULT 'ACTIVE',
    KEY `idx_mc_features_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_files` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `tenant_id` VARCHAR(50) NOT NULL,
    `object_key` VARCHAR(1000) NOT NULL,
    `filename` VARCHAR(500) NOT NULL,
    `mime_type` VARCHAR(100) NOT NULL,
    `size_bytes` BIGINT UNSIGNED NOT NULL,
    `uploaded_by` VARCHAR(255) NOT NULL,
    `status` VARCHAR(191) NOT NULL DEFAULT 'active',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `public_id` VARCHAR(36) NOT NULL,
    `file_number` VARCHAR(40) NOT NULL,
    `patient_id` BIGINT UNSIGNED NULL,
    `entity_type` VARCHAR(50) NULL,
    `entity_id` VARCHAR(100) NULL,
    `file_type` VARCHAR(50) NOT NULL,
    `original_name` VARCHAR(255) NOT NULL,
    `storage_provider` VARCHAR(30) NOT NULL,
    `storage_key` VARCHAR(500) NOT NULL,
    `idempotency_key` VARCHAR(191) NULL,
    `checksum_sha256` CHAR(64) NULL,
    `deleted_at` DATETIME NULL,
    `metadata_json` LONGTEXT NULL,
    KEY `idx_mc_files_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_financial_settlements` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `public_id` VARCHAR(36) NOT NULL,
    `tenant_id` VARCHAR(50) NOT NULL,
    `earning_line_id` BIGINT UNSIGNED NOT NULL,
    `settlement_number` VARCHAR(40) NOT NULL,
    `settlement_type` VARCHAR(30) NOT NULL DEFAULT 'WITHDRAWAL',
    `amount` DECIMAL(14,4) NOT NULL,
    `currency` VARCHAR(20) NOT NULL,
    `beneficiary_type` VARCHAR(50) NOT NULL,
    `beneficiary_id` VARCHAR(100) NOT NULL,
    `status` VARCHAR(30) NOT NULL DEFAULT 'REQUESTED',
    `requested_by` VARCHAR(100) NULL,
    `approved_by` VARCHAR(100) NULL,
    `delivered_by` VARCHAR(100) NULL,
    `received_by` VARCHAR(100) NULL,
    `requested_at` DATETIME NOT NULL,
    `approved_at` DATETIME NULL,
    `delivered_at` DATETIME NULL,
    `received_at` DATETIME NULL,
    `idempotency_key` VARCHAR(191) NULL,
    `metadata_json` LONGTEXT NULL,
    KEY `idx_mc_financial_settlements_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_hospitals` (
    `id` VARCHAR(36) NOT NULL,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `organization_id` VARCHAR(36) NOT NULL,
    `public_alias` VARCHAR(100) NOT NULL,
    `status` VARCHAR(50) NULL DEFAULT 'ACTIVE',
    `created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_hospitals_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_icu_apache2_scores` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `public_id` VARCHAR(36) NOT NULL,
    `tenant_id` VARCHAR(64) NOT NULL,
    `admission_id` VARCHAR(64) NOT NULL,
    `score` INT NOT NULL,
    `details_json` LONGTEXT NULL,
    `recorded_by` VARCHAR(255) NULL,
    `recorded_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    `idempotency_key` VARCHAR(128) NULL,
    KEY `idx_mc_icu_apache2_scores_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_icu_flowsheets` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `tenant_id` VARCHAR(50) NOT NULL,
    `public_id` VARCHAR(36) NOT NULL,
    `admission_id` VARCHAR(36) NOT NULL,
    `bed_id` VARCHAR(36) NULL,
    `entry_time` DATETIME NOT NULL,
    `vitals_json` LONGTEXT NULL,
    `fluids_json` LONGTEXT NULL,
    `notes` TEXT NULL,
    `created_by` VARCHAR(100) NULL,
    `idempotency_key` VARCHAR(100) NULL,
    `created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_icu_flowsheets_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_icu_sofa_scores` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `public_id` VARCHAR(36) NOT NULL,
    `tenant_id` VARCHAR(64) NOT NULL,
    `admission_id` VARCHAR(64) NOT NULL,
    `score` INT NOT NULL,
    `details_json` LONGTEXT NULL,
    `recorded_by` VARCHAR(255) NULL,
    `recorded_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    `idempotency_key` VARCHAR(128) NULL,
    KEY `idx_mc_icu_sofa_scores_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_identity_sequences` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `tenant_id` VARCHAR(50) NOT NULL,
    `entity_type` VARCHAR(50) NOT NULL,
    `sequence_year` SMALLINT(5) UNSIGNED NOT NULL,
    `next_value` BIGINT(20) UNSIGNED NOT NULL DEFAULT 1,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_identity_sequences_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_inventory_balances` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `tenant_id` VARCHAR(50) NOT NULL,
    `item_id` BIGINT(20) UNSIGNED NOT NULL,
    `location_id` BIGINT(20) UNSIGNED NOT NULL,
    `batch_id` BIGINT(20) UNSIGNED NULL,
    `quantity` DECIMAL(14,4) NOT NULL DEFAULT 0,
    `reserved_quantity` DECIMAL(14,4) NOT NULL DEFAULT 0,
    `average_cost` DECIMAL(14,4) NOT NULL DEFAULT 0,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_inventory_balances_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_inventory_batches` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `public_id` VARCHAR(36) NOT NULL,
    `tenant_id` VARCHAR(50) NOT NULL,
    `item_id` BIGINT(20) UNSIGNED NOT NULL,
    `batch_number` VARCHAR(100) NULL,
    `expiry_date` DATE NULL,
    `unit_cost` DECIMAL(14,4) NOT NULL DEFAULT 0,
    `currency` VARCHAR(20) NOT NULL,
    `received_at` DATETIME NULL,
    `idempotency_key` VARCHAR(191) NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_inventory_batches_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_inventory_items` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `public_id` VARCHAR(36) NOT NULL,
    `tenant_id` VARCHAR(50) NOT NULL,
    `item_number` VARCHAR(40) NOT NULL,
    `definition_id` BIGINT(20) UNSIGNED NULL,
    `item_code` VARCHAR(100) NOT NULL,
    `name` VARCHAR(190) NOT NULL,
    `unit` VARCHAR(30) NOT NULL,
    `tracking_type` VARCHAR(30) NOT NULL DEFAULT 'NONE',
    `status` VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    `idempotency_key` VARCHAR(191) NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_inventory_items_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_inventory_locations` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `public_id` VARCHAR(36) NOT NULL,
    `tenant_id` VARCHAR(50) NOT NULL,
    `location_number` VARCHAR(40) NOT NULL,
    `location_type` VARCHAR(30) NOT NULL,
    `name` VARCHAR(190) NOT NULL,
    `clinic_id` VARCHAR(100) NULL,
    `owner_type` VARCHAR(30) NULL,
    `owner_id` VARCHAR(100) NULL,
    `parent_location_id` BIGINT(20) UNSIGNED NULL,
    `status` VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    `idempotency_key` VARCHAR(191) NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_inventory_locations_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
