-- ============================================================================
-- V015: Product Layer Configuration, Technician Sessions, Device Metadata & Maintenance Reports
-- ============================================================================

CREATE TABLE IF NOT EXISTS mc_facility_config (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    hospital_code VARCHAR(64) NOT NULL,
    facility_name VARCHAR(191) NOT NULL,
    facility_type VARCHAR(64) NOT NULL DEFAULT 'GENERAL_HOSPITAL',
    branch_code VARCHAR(64) NOT NULL DEFAULT 'MAIN',
    installation_identity VARCHAR(128) NOT NULL,
    edition VARCHAR(64) NOT NULL DEFAULT 'PLATINUM',
    subscription_starts_utc DATETIME NULL,
    subscription_expires_utc DATETIME NULL,
    enabled_modules_json LONGTEXT NOT NULL,
    patient_fields_config_json LONGTEXT NOT NULL,
    branding_appearance_json LONGTEXT NOT NULL,
    network_config_json LONGTEXT NOT NULL,
    backup_config_json LONGTEXT NOT NULL,
    remote_hybrid_config_json LONGTEXT NOT NULL,
    config_version INT UNSIGNED NOT NULL DEFAULT 1,
    updated_by_tech_session VARCHAR(64) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mc_facility_cfg_hosp (hospital_code),
    CONSTRAINT fk_mc_facility_cfg_tenant FOREIGN KEY (hospital_code) REFERENCES mc_tenants (hospital_code) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS mc_technician_sessions (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    session_uuid VARCHAR(64) NOT NULL,
    token_sha256 CHAR(64) NOT NULL,
    hospital_code VARCHAR(64) NOT NULL,
    auth_method ENUM('AUTHORITY_RSA_TOKEN', 'INSTALLATION_TECH_SECRET') NOT NULL,
    authority_token_nonce VARCHAR(128) NULL,
    device_id VARCHAR(128) NOT NULL,
    ip_address VARCHAR(64) NULL,
    issued_at DATETIME(3) NOT NULL,
    expires_at DATETIME(3) NOT NULL,
    revoked_at DATETIME(3) NULL,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    UNIQUE KEY uq_mc_tech_sess_uuid (session_uuid),
    UNIQUE KEY uq_mc_tech_sess_token (token_sha256),
    KEY idx_mc_tech_sess_hosp_active (hospital_code, is_active, expires_at),
    CONSTRAINT fk_mc_tech_sess_tenant FOREIGN KEY (hospital_code) REFERENCES mc_tenants (hospital_code) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS mc_maintenance_reports (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    report_uuid VARCHAR(64) NOT NULL,
    hospital_code VARCHAR(64) NOT NULL,
    generated_by_mode ENUM('STAFF_AUTHORIZED', 'TECHNICIAN_SESSION') NOT NULL,
    generated_by_actor VARCHAR(128) NOT NULL,
    overall_status VARCHAR(32) NOT NULL DEFAULT 'HEALTHY',
    report_json LONGTEXT NOT NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    UNIQUE KEY uq_mc_maint_rep_uuid (report_uuid),
    KEY idx_mc_maint_rep_hosp_created (hospital_code, created_at),
    CONSTRAINT fk_mc_maint_rep_tenant FOREIGN KEY (hospital_code) REFERENCES mc_tenants (hospital_code) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE mc_devices ADD COLUMN IF NOT EXISTS connection_type ENUM('LOOPBACK', 'LAN', 'WIFI') NOT NULL DEFAULT 'LOOPBACK' AFTER platform;

ALTER TABLE mc_devices ADD COLUMN IF NOT EXISTS medcore_version VARCHAR(64) NOT NULL DEFAULT '1.0.0-rc.1' AFTER role_scope;

ALTER TABLE mc_devices ADD COLUMN IF NOT EXISTS pairing_code_sha256 CHAR(64) NULL AFTER approved_by;

ALTER TABLE mc_devices ADD COLUMN IF NOT EXISTS pairing_requested_at DATETIME NULL AFTER pairing_code_sha256;
