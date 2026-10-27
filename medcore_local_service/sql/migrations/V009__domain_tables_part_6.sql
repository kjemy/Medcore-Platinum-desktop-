-- ============================================================================
-- V009: Extracted Domain Tables Batch 6 (9 Normalized InnoDB Tables)
-- ============================================================================

CREATE TABLE IF NOT EXISTS `mc_storage` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(50) NOT NULL,
    `store_key` VARCHAR(100) NOT NULL,
    `store_value` LONGTEXT NULL,
    `updated_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_storage_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_subscription_events` (
    `id` VARCHAR(36) NOT NULL,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `subscription_id` VARCHAR(36) NOT NULL,
    `event_type` VARCHAR(50) NOT NULL,
    `timestamp` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    `actor_id` VARCHAR(100) NULL,
    KEY `idx_mc_subscription_events_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_subscriptions` (
    `id` VARCHAR(36) NOT NULL,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `organization_id` VARCHAR(36) NOT NULL,
    `plan_id` VARCHAR(36) NOT NULL,
    `status` VARCHAR(50) NULL DEFAULT 'PENDING',
    `start_at` DATETIME NOT NULL,
    `end_at` DATETIME NOT NULL,
    `created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_subscriptions_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_surgeries` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `tenant_id` VARCHAR(50) NOT NULL,
    `public_id` VARCHAR(36) NOT NULL,
    `patient_id` VARCHAR(36) NOT NULL,
    `encounter_id` VARCHAR(36) NULL,
    `or_room_id` VARCHAR(36) NULL,
    `procedure_name` VARCHAR(255) NOT NULL,
    `planned_date` DATE NOT NULL,
    `planned_time` TIME NULL,
    `estimated_duration` VARCHAR(50) NULL,
    `urgency` VARCHAR(20) NULL DEFAULT 'Elective',
    `laterality` VARCHAR(20) NULL DEFAULT 'N/A',
    `anesthesia_type` VARCHAR(50) NULL,
    `diagnosis` TEXT NULL,
    `allergies` TEXT NULL,
    `chronic_diseases` TEXT NULL,
    `infection_status` VARCHAR(100) NULL,
    `team_json` LONGTEXT NULL,
    `nursing_team_json` LONGTEXT NULL,
    `support_staff_json` LONGTEXT NULL,
    `companion_json` LONGTEXT NULL,
    `allowed_persons_json` LONGTEXT NULL,
    `requirements_json` LONGTEXT NULL,
    `readiness_json` LONGTEXT NULL,
    `status` VARCHAR(50) NULL DEFAULT 'Pending',
    `created_by` VARCHAR(100) NULL,
    `idempotency_key` VARCHAR(100) NULL,
    `created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_surgeries_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_sync_commands` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `tenant_id` VARCHAR(50) NOT NULL,
    `command_id` VARCHAR(100) NOT NULL,
    `device_id` VARCHAR(100) NOT NULL,
    `actor_id` VARCHAR(36) NULL,
    `entity_type` VARCHAR(80) NOT NULL,
    `operation` VARCHAR(40) NOT NULL,
    `payload` LONGTEXT NULL,
    `occurred_at` DATETIME NOT NULL,
    `received_at` DATETIME NOT NULL,
    `synced_at` DATETIME NULL,
    `status` VARCHAR(20) NOT NULL DEFAULT 'RECEIVED',
    `result` LONGTEXT NULL,
    KEY `idx_mc_sync_commands_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_users` (
    `id` VARCHAR(36) NOT NULL,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `email` VARCHAR(255) NOT NULL,
    `normalized_email` VARCHAR(255) NOT NULL,
    `status` VARCHAR(50) NULL DEFAULT 'ACTIVE',
    `password_hash` VARCHAR(255) NULL,
    `created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    `last_login_at` DATETIME NULL,
    KEY `idx_mc_users_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_wallet_ledger` (
    `id` VARCHAR(36) NOT NULL,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `wallet_id` VARCHAR(36) NOT NULL,
    `transaction_type` VARCHAR(50) NOT NULL,
    `amount` BIGINT(20) NOT NULL,
    `balance_after` BIGINT(20) NOT NULL,
    `reference_id` VARCHAR(100) NULL,
    `idempotency_key` VARCHAR(100) NULL,
    `actor_id` VARCHAR(100) NULL,
    `timestamp` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_wallet_ledger_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_wallets` (
    `id` VARCHAR(36) NOT NULL,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `wallet_type` VARCHAR(50) NOT NULL,
    `owner_type` VARCHAR(50) NOT NULL,
    `owner_id` VARCHAR(36) NOT NULL,
    `status` VARCHAR(50) NULL DEFAULT 'ACTIVE',
    `currency` VARCHAR(20) NULL DEFAULT 'TOKENS',
    `ledger_balance` BIGINT(20) NOT NULL DEFAULT '0',
    `reserved_balance` BIGINT(20) NOT NULL DEFAULT '0',
    `available_balance` BIGINT(20) NOT NULL DEFAULT '0',
    `created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_wallets_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_ward_beds` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `tenant_id` VARCHAR(50) NOT NULL,
    `public_id` VARCHAR(36) NOT NULL,
    `department_id` VARCHAR(36) NOT NULL,
    `room_id` VARCHAR(36) NOT NULL,
    `bed_number` VARCHAR(50) NOT NULL,
    `status` VARCHAR(50) NULL DEFAULT 'Available',
    `created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_mc_ward_beds_hosp` (`hospital_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
