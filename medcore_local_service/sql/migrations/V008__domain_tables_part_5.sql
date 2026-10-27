-- ============================================================================
-- V008: Extracted Domain Tables Batch 5 (12 Normalized InnoDB Tables)
-- ============================================================================

CREATE TABLE IF NOT EXISTS `mc_nicu_telemetry` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `tenant_id` VARCHAR(50) NOT NULL,
    `public_id` VARCHAR(36) NOT NULL,
    `patient_id` VARCHAR(36) NULL,
    `incubator_id` VARCHAR(36) NOT NULL,
    `incubator_temp` DECIMAL(14,4) NULL,
    `humidity` DECIMAL(14,4) NULL,
    `o2_flow` DECIMAL(14,4) NULL,
    `spo2` DECIMAL(14,4) NULL,
    `heart_rate` INT(11) NULL,
    `recorded_by` VARCHAR(100) NULL,
    `occurred_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    `created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_nicu_telemetry_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_nursing_tasks` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `public_id` VARCHAR(36) NOT NULL,
    `tenant_id` VARCHAR(50) NOT NULL,
    `task_number` VARCHAR(40) NOT NULL,
    `patient_id` BIGINT UNSIGNED NULL,
    `encounter_id` BIGINT UNSIGNED NULL,
    `assigned_to` VARCHAR(100) NULL,
    `idempotency_key` VARCHAR(191) NULL,
    `assigned_by` VARCHAR(100) NULL,
    `task_type` VARCHAR(60) NOT NULL,
    `title` VARCHAR(190) NOT NULL,
    `instructions` TEXT NULL,
    `priority` VARCHAR(20) NOT NULL DEFAULT 'NORMAL',
    `status` VARCHAR(30) NOT NULL DEFAULT 'ASSIGNED',
    `due_at` DATETIME NULL,
    `started_at` DATETIME NULL,
    `completed_at` DATETIME NULL,
    `confirmed_at` DATETIME NULL,
    `confirmation_by` VARCHAR(100) NULL,
    `metadata_json` LONGTEXT NULL,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    KEY `idx_mc_nursing_tasks_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_operations` (
    `id` VARCHAR(36) NOT NULL,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `operation_type` VARCHAR(50) NOT NULL,
    `idempotency_key` VARCHAR(100) NOT NULL,
    `fingerprint` VARCHAR(64) NOT NULL,
    `status` VARCHAR(50) NOT NULL DEFAULT 'PENDING',
    `created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_operations_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_organizations` (
    `id` VARCHAR(36) NOT NULL,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `public_alias` VARCHAR(100) NOT NULL,
    `name` VARCHAR(255) NOT NULL,
    `status` VARCHAR(50) NULL DEFAULT 'ACTIVE',
    `timezone` VARCHAR(100) NULL DEFAULT 'UTC',
    `created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_organizations_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_patient_profiles` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `public_id` VARCHAR(36) NOT NULL,
    `tenant_id` VARCHAR(50) NOT NULL,
    `patient_id` BIGINT(20) UNSIGNED NOT NULL,
    `date_of_birth` DATE NULL,
    `emergency_contact_name` VARCHAR(190) NULL,
    `emergency_contact_phone` VARCHAR(50) NULL,
    `address` TEXT NULL,
    `insurance_provider_id` VARCHAR(36) NULL,
    `insurance_policy_number` VARCHAR(100) NULL,
    `chronic_conditions_json` LONGTEXT NULL,
    `allergies_json` LONGTEXT NULL,
    `medical_history_json` LONGTEXT NULL,
    `status` VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    KEY `idx_mc_patient_profiles_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_pharmacy_dispenses` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `public_id` VARCHAR(36) NOT NULL,
    `tenant_id` VARCHAR(50) NOT NULL,
    `prescription_id` BIGINT UNSIGNED NOT NULL,
    `prescription_item_id` BIGINT UNSIGNED NULL,
    `inventory_item_id` BIGINT UNSIGNED NULL,
    `batch_id` BIGINT UNSIGNED NULL,
    `quantity` DECIMAL(14,4) NOT NULL,
    `unit_cost` DECIMAL(14,4) NULL,
    `patient_id` BIGINT UNSIGNED NULL,
    `dispensed_by` VARCHAR(100) NULL,
    `idempotency_key` VARCHAR(191) NULL,
    `status` VARCHAR(30) NOT NULL DEFAULT 'POSTED',
    `occurred_at` DATETIME NOT NULL,
    `metadata_json` LONGTEXT NULL,
    KEY `idx_mc_pharmacy_dispenses_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_plan_features` (
    `id` VARCHAR(36) NOT NULL,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `plan_id` VARCHAR(36) NOT NULL,
    `feature_id` VARCHAR(36) NOT NULL,
    KEY `idx_mc_plan_features_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_plans` (
    `id` VARCHAR(36) NOT NULL,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `name` VARCHAR(255) NOT NULL,
    `status` VARCHAR(50) NULL DEFAULT 'ACTIVE',
    `created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_plans_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_prescription_items` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `public_id` VARCHAR(36) NOT NULL,
    `tenant_id` VARCHAR(50) NOT NULL,
    `prescription_id` BIGINT(20) UNSIGNED NOT NULL,
    `medication_definition_id` VARCHAR(36) NULL,
    `medication_code` VARCHAR(100) NULL,
    `medication_name` VARCHAR(190) NOT NULL,
    `dose` VARCHAR(100) NULL,
    `route` VARCHAR(100) NULL,
    `frequency` VARCHAR(100) NULL,
    `duration` VARCHAR(100) NULL,
    `quantity` DECIMAL(14,4) NULL,
    `instructions` TEXT NULL,
    `status` VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',
    `payload_json` LONGTEXT NULL,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    KEY `idx_mc_prescription_items_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_prescriptions` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(50) NOT NULL,
    `visit_id` BIGINT UNSIGNED NOT NULL,
    `patient_id` BIGINT UNSIGNED NOT NULL,
    `doctor_id` BIGINT UNSIGNED NOT NULL,
    `notes` TEXT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `doctor_name` VARCHAR(255) NULL,
    `medication` TEXT NULL,
    `status` VARCHAR(50) NULL DEFAULT 'PENDING',
    `payload_json` LONGTEXT NULL,
    KEY `idx_mc_prescriptions_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_radiology_orders` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(50) NOT NULL,
    `patient_id` BIGINT(20) NOT NULL,
    `doctor_name` VARCHAR(255) NULL,
    `scan_type` VARCHAR(255) NULL,
    `status` VARCHAR(50) NULL DEFAULT 'PENDING',
    `priority` VARCHAR(20) NULL DEFAULT 'ROUTINE',
    `payload_json` LONGTEXT NULL,
    `created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_radiology_orders_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_radiology_requests` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(50) NOT NULL,
    `visit_id` BIGINT UNSIGNED NOT NULL,
    `patient_id` BIGINT UNSIGNED NOT NULL,
    `doctor_id` BIGINT UNSIGNED NOT NULL,
    `type` VARCHAR(255) NOT NULL,
    `body_part` VARCHAR(255) NULL DEFAULT NULL,
    `findings` TEXT NULL,
    `impression` TEXT NULL,
    `image_url` VARCHAR(500) NULL DEFAULT NULL,
    `status` VARCHAR(191) NOT NULL DEFAULT 'pending',
    `is_external` TINYINT(1) NOT NULL DEFAULT 0,
    `requested_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `resulted_at` DATETIME NULL DEFAULT NULL,
    KEY `idx_mc_radiology_requests_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
