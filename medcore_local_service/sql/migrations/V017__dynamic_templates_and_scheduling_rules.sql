-- ============================================================================
-- V017: Dynamic Clinical Templates & Multi-Resource Scheduling Rule Engine
-- ============================================================================

-- 1. Ensure composite indexes on existing mc_clinical_templates
ALTER TABLE `mc_clinical_templates`
    ADD KEY IF NOT EXISTS `idx_mc_templates_hosp_status` (`hospital_code`, `status`),
    ADD KEY IF NOT EXISTS `idx_mc_templates_hosp_spec` (`hospital_code`, `specialty`, `category`),
    ADD UNIQUE KEY IF NOT EXISTS `uniq_mc_templates_hosp_num_ver` (`hospital_code`, `template_number`, `version`);

-- 2. Ensure composite indexes on mc_clinical_template_usages
ALTER TABLE `mc_clinical_template_usages`
    ADD KEY IF NOT EXISTS `idx_mc_tmpl_usage_hosp_enc` (`hospital_code`, `encounter_id`),
    ADD KEY IF NOT EXISTS `idx_mc_tmpl_usage_hosp_pat` (`hospital_code`, `patient_id`);

-- 3. Dynamic Scheduling Resources Table (Doctors, Rooms, Theaters, Equipment, Devices)
CREATE TABLE IF NOT EXISTS `mc_scheduling_resources` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `public_id` VARCHAR(36) NOT NULL,
    `tenant_id` VARCHAR(50) NOT NULL,
    `resource_code` VARCHAR(50) NOT NULL,
    `name` VARCHAR(150) NOT NULL,
    `resource_type` ENUM('DOCTOR', 'ROOM', 'THEATER', 'EQUIPMENT', 'DEVICE', 'CHAIR') NOT NULL DEFAULT 'ROOM',
    `department_id` VARCHAR(64) NULL,
    `capacity` INT UNSIGNED NOT NULL DEFAULT 1,
    `is_active` TINYINT(1) NOT NULL DEFAULT 1,
    `metadata_json` LONGTEXT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY `uniq_mc_sched_res_code` (`hospital_code`, `resource_code`),
    KEY `idx_mc_sched_res_hosp_type` (`hospital_code`, `resource_type`, `is_active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 4. Multi-Resource Scheduling Rules Table (Rule Definitions, Required Co-Resources, Buffers)
CREATE TABLE IF NOT EXISTS `mc_scheduling_rules` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `public_id` VARCHAR(36) NOT NULL,
    `tenant_id` VARCHAR(50) NOT NULL,
    `rule_code` VARCHAR(50) NOT NULL,
    `name` VARCHAR(150) NOT NULL,
    `appointment_type` VARCHAR(50) NOT NULL DEFAULT 'CONSULTATION',
    `primary_resource_type` ENUM('DOCTOR', 'ROOM', 'THEATER', 'EQUIPMENT', 'DEVICE', 'CHAIR') NOT NULL DEFAULT 'DOCTOR',
    `required_co_resource_types_json` LONGTEXT NULL,
    `default_duration_minutes` INT UNSIGNED NOT NULL DEFAULT 30,
    `buffer_before_minutes` INT UNSIGNED NOT NULL DEFAULT 0,
    `buffer_after_minutes` INT UNSIGNED NOT NULL DEFAULT 0,
    `is_active` TINYINT(1) NOT NULL DEFAULT 1,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY `uniq_mc_sched_rules_code` (`hospital_code`, `rule_code`),
    KEY `idx_mc_sched_rules_hosp_type` (`hospital_code`, `appointment_type`, `is_active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 5. Multi-Resource Slot Allocations (Enforces Conflict Prevention & Buffer Isolation)
CREATE TABLE IF NOT EXISTS `mc_appointment_resource_allocations` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `public_id` VARCHAR(36) NOT NULL,
    `appointment_id` BIGINT UNSIGNED NOT NULL,
    `resource_id` BIGINT UNSIGNED NOT NULL,
    `allocated_start` DATETIME NOT NULL,
    `allocated_end` DATETIME NOT NULL,
    `status` ENUM('HELD', 'CONFIRMED', 'RELEASED') NOT NULL DEFAULT 'CONFIRMED',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY `idx_mc_alloc_res_time` (`hospital_code`, `resource_id`, `status`, `allocated_start`, `allocated_end`),
    KEY `idx_mc_alloc_apt` (`hospital_code`, `appointment_id`),
    CONSTRAINT `fk_mc_alloc_res` FOREIGN KEY (`resource_id`) REFERENCES `mc_scheduling_resources` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
