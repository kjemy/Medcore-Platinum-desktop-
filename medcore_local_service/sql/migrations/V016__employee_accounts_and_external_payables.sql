-- ============================================================================
-- V016: Employee Accounts Hardening, External Payables & LAN Certificates
-- ============================================================================

-- 1. Employee Account Governance & Force Password Change
ALTER TABLE mc_staff ADD COLUMN IF NOT EXISTS force_password_change TINYINT(1) NOT NULL DEFAULT 0 AFTER is_active;
ALTER TABLE mc_staff ADD COLUMN IF NOT EXISTS password_changed_at DATETIME NULL AFTER force_password_change;
ALTER TABLE mc_staff ADD COLUMN IF NOT EXISTS failed_login_count INT UNSIGNED NOT NULL DEFAULT 0 AFTER password_changed_at;
ALTER TABLE mc_staff ADD COLUMN IF NOT EXISTS locked_until DATETIME NULL AFTER failed_login_count;

-- 2. External Laboratory & Clinic Payables (FIN-GAP-LAB-CLINIC-PAYABLE-RULES)
CREATE TABLE IF NOT EXISTS mc_external_payables (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    hospital_code VARCHAR(64) NOT NULL,
    payable_uuid VARCHAR(64) NOT NULL,
    party_type ENUM('LAB', 'CLINIC', 'CONSULTANT', 'REFERRAL') NOT NULL,
    party_code VARCHAR(64) NOT NULL,
    party_name VARCHAR(191) NOT NULL,
    source_visit_id BIGINT UNSIGNED NOT NULL,
    source_event_id BIGINT UNSIGNED NOT NULL,
    gross_amount DECIMAL(14,4) NOT NULL DEFAULT 0.0000,
    allocated_amount DECIMAL(14,4) NOT NULL DEFAULT 0.0000,
    paid_amount DECIMAL(14,4) NOT NULL DEFAULT 0.0000,
    balance_amount DECIMAL(14,4) NOT NULL DEFAULT 0.0000,
    status ENUM('PENDING', 'PARTIAL', 'SETTLED', 'REVERSED') NOT NULL DEFAULT 'PENDING',
    notes TEXT NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    UNIQUE KEY uq_mc_extpay_uuid (payable_uuid),
    KEY idx_mc_extpay_hosp_party (hospital_code, party_type, party_code),
    KEY idx_mc_extpay_hosp_visit (hospital_code, source_visit_id),
    KEY idx_mc_extpay_hosp_event (hospital_code, source_event_id),
    CONSTRAINT fk_mc_extpay_tenant FOREIGN KEY (hospital_code) REFERENCES mc_tenants (hospital_code) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_mc_extpay_visit FOREIGN KEY (source_visit_id) REFERENCES mc_visits (id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_mc_extpay_event FOREIGN KEY (source_event_id) REFERENCES mc_financial_events (id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 3. LAN Certificate Hierarchy & Device Identity (NET-GAP-LAN-MTLS-CERTS)
CREATE TABLE IF NOT EXISTS mc_lan_certificates (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    hospital_code VARCHAR(64) NOT NULL,
    cert_uuid VARCHAR(64) NOT NULL,
    cert_type ENUM('ROOT_CA', 'SERVER_CERT', 'CLIENT_CERT') NOT NULL,
    device_id VARCHAR(128) NULL,
    common_name VARCHAR(191) NOT NULL,
    cert_pem LONGTEXT NOT NULL,
    fingerprint_sha256 CHAR(64) NOT NULL,
    expires_at DATETIME NOT NULL,
    revoked_at DATETIME NULL,
    revoke_reason VARCHAR(128) NULL,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mc_lan_cert_uuid (cert_uuid),
    UNIQUE KEY uq_mc_lan_cert_fp (fingerprint_sha256),
    KEY idx_mc_lan_cert_hosp_dev (hospital_code, device_id, is_active),
    CONSTRAINT fk_mc_lan_cert_tenant FOREIGN KEY (hospital_code) REFERENCES mc_tenants (hospital_code) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
