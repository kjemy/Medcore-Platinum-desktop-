-- V019__master_definitions_and_clinic_extensions.sql
-- MedCore Platinum Additive Parity Schema: Definitions Indexes, Doctor Commissions & Internal Notes.

CREATE TABLE IF NOT EXISTS `mc_doctor_commission_profiles` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `tenant_id` VARCHAR(50) NOT NULL,
    `public_id` VARCHAR(36) NOT NULL,
    `doctor_id` BIGINT UNSIGNED NOT NULL,
    `doctor_code` VARCHAR(64) NOT NULL,
    `commission_mode` VARCHAR(30) NOT NULL DEFAULT 'PERCENTAGE',
    `consultation_share_pct` DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    `procedure_share_pct` DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    `fixed_consultation_cut` DECIMAL(14,4) NOT NULL DEFAULT 0.0000,
    `status` VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',
    `created_by` VARCHAR(64) NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY `idx_doc_comm_hosp` (`hospital_code`),
    UNIQUE KEY `uk_doc_comm_tenant_doc` (`hospital_code`, `doctor_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mc_internal_notes` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `tenant_id` VARCHAR(50) NOT NULL,
    `public_id` VARCHAR(36) NOT NULL,
    `author_staff_id` BIGINT UNSIGNED NOT NULL,
    `author_staff_name` VARCHAR(120) NOT NULL,
    `category` VARCHAR(50) NOT NULL DEFAULT 'GENERAL',
    `subject` VARCHAR(255) NOT NULL,
    `content` TEXT NOT NULL,
    `is_pinned` TINYINT(1) NOT NULL DEFAULT 0,
    `status` VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY `idx_mc_internal_notes_hosp` (`hospital_code`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
