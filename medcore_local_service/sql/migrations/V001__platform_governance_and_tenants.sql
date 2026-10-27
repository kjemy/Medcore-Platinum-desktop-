-- ============================================================================
-- V001: Platform Governance, Tenants, Local Meta, Devices, License & Clock Guard
-- ============================================================================

CREATE TABLE IF NOT EXISTS mc_schema_migrations (
    version VARCHAR(64) NOT NULL PRIMARY KEY,
    description VARCHAR(255) NOT NULL,
    checksum_sha256 CHAR(64) NOT NULL,
    execution_ms INT UNSIGNED NOT NULL DEFAULT 0,
    applied_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS mc_tenants (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    hospital_code VARCHAR(64) NOT NULL,
    name VARCHAR(191) NOT NULL,
    name_en VARCHAR(191) NULL,
    edition VARCHAR(64) NOT NULL DEFAULT 'ENTERPRISE_LAN',
    default_currency VARCHAR(16) NOT NULL DEFAULT 'EGP',
    timezone VARCHAR(64) NOT NULL DEFAULT 'Africa/Cairo',
    enforce_screen_protection TINYINT(1) NOT NULL DEFAULT 1,
    require_open_shift TINYINT(1) NOT NULL DEFAULT 1,
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    settings_json LONGTEXT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mc_tenants_hospital_code (hospital_code),
    KEY idx_mc_tenants_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS mc_local_meta (
    meta_key VARCHAR(128) NOT NULL,
    hospital_code VARCHAR(64) NOT NULL DEFAULT 'GLOBAL',
    meta_value_json LONGTEXT NOT NULL,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (hospital_code, meta_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS mc_devices (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    hospital_code VARCHAR(64) NOT NULL,
    device_id VARCHAR(128) NOT NULL,
    device_name VARCHAR(191) NOT NULL,
    platform ENUM('WINDOWS', 'ANDROID', 'IPAD') NOT NULL DEFAULT 'WINDOWS',
    hw_fingerprint_sha256 CHAR(64) NOT NULL,
    device_public_key_ed25519 VARCHAR(128) NOT NULL,
    role_scope ENUM('SERVER_HOST', 'WORKSTATION', 'TABLET_CLINICAL', 'KIOSK') NOT NULL DEFAULT 'WORKSTATION',
    is_trusted_secure_runtime TINYINT(1) NOT NULL DEFAULT 1,
    status ENUM('PENDING', 'ACTIVE', 'REVOKED', 'SUSPENDED') NOT NULL DEFAULT 'ACTIVE',
    last_seen_at DATETIME NULL,
    last_ip VARCHAR(64) NULL,
    approved_by BIGINT UNSIGNED NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mc_devices_device_id (device_id),
    KEY idx_mc_devices_hosp_status (hospital_code, status),
    KEY idx_mc_devices_hosp_fp (hospital_code, hw_fingerprint_sha256),
    CONSTRAINT fk_mc_devices_tenant FOREIGN KEY (hospital_code) REFERENCES mc_tenants (hospital_code) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS mc_license_state (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    hospital_code VARCHAR(64) NOT NULL,
    license_id VARCHAR(128) NOT NULL,
    edition VARCHAR(64) NOT NULL DEFAULT 'ENTERPRISE_LAN',
    entitled_modules_json LONGTEXT NOT NULL,
    max_devices INT UNSIGNED NOT NULL DEFAULT 25,
    max_doctors INT UNSIGNED NOT NULL DEFAULT 50,
    ai_entitled TINYINT(1) NOT NULL DEFAULT 0,
    issued_at_utc DATETIME NOT NULL,
    expires_at_utc DATETIME NOT NULL,
    offline_grace_until_utc DATETIME NOT NULL,
    last_online_refresh_utc DATETIME NOT NULL,
    lease_payload_json LONGTEXT NOT NULL,
    ed25519_signature VARCHAR(256) NOT NULL,
    status ENUM('VALID', 'GRACE_PERIOD', 'EXPIRED_READ_ONLY', 'TAMPER_LOCKED') NOT NULL DEFAULT 'VALID',
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mc_license_state_hospital (hospital_code),
    CONSTRAINT fk_mc_license_tenant FOREIGN KEY (hospital_code) REFERENCES mc_tenants (hospital_code) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS mc_clock_guard (
    id TINYINT UNSIGNED NOT NULL PRIMARY KEY DEFAULT 1,
    hospital_code VARCHAR(64) NOT NULL,
    max_observed_utc DATETIME(3) NOT NULL,
    last_event_uuid VARCHAR(64) NULL,
    last_boot_monotonic_ms BIGINT UNSIGNED NOT NULL DEFAULT 0,
    rollback_detected TINYINT(1) NOT NULL DEFAULT 0,
    rollback_delta_seconds BIGINT NULL,
    locked_at_utc DATETIME NULL,
    unlocked_by_maintenance_token_id VARCHAR(128) NULL,
    hmac_seal CHAR(64) NOT NULL,
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS mc_backup_runs (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    backup_uuid VARCHAR(64) NOT NULL,
    hospital_code VARCHAR(64) NOT NULL,
    trigger_type ENUM('SCHEDULED', 'MANUAL_ADMIN', 'PRE_MIGRATION', 'SERVICE_TOOL') NOT NULL,
    archive_path VARCHAR(512) NOT NULL,
    archive_sha256 CHAR(64) NOT NULL,
    archive_size_bytes BIGINT UNSIGNED NOT NULL DEFAULT 0,
    schema_version VARCHAR(64) NOT NULL,
    max_financial_event_id BIGINT UNSIGNED NOT NULL DEFAULT 0,
    status ENUM('RUNNING', 'COMPLETED', 'VERIFIED', 'FAILED') NOT NULL DEFAULT 'RUNNING',
    created_by BIGINT UNSIGNED NULL,
    started_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at DATETIME NULL,
    UNIQUE KEY uq_mc_backup_uuid (backup_uuid),
    KEY idx_mc_backup_hosp_status (hospital_code, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
