-- ============================================================================
-- V018: Commercial Entitlement, Hardware Binding & Cryptographic Seal Integrity
-- ============================================================================

-- 1. Extend mc_license_state with hardware binding, installation ID, signature length, and HMAC seal
ALTER TABLE mc_license_state
    MODIFY COLUMN ed25519_signature VARCHAR(512) NOT NULL,
    ADD COLUMN IF NOT EXISTS installation_id VARCHAR(128) NOT NULL DEFAULT '' AFTER license_id,
    ADD COLUMN IF NOT EXISTS hardware_fingerprint_sha256 VARCHAR(64) NOT NULL DEFAULT '' AFTER installation_id,
    ADD COLUMN IF NOT EXISTS maintenance_expires_at_utc DATETIME NOT NULL DEFAULT '2026-12-31 23:59:59' AFTER offline_grace_until_utc,
    ADD COLUMN IF NOT EXISTS hmac_seal CHAR(64) NOT NULL DEFAULT '' AFTER ed25519_signature;

-- 2. Extend mc_facility_config with authoritative license link, status, and HMAC seal
ALTER TABLE mc_facility_config
    ADD COLUMN IF NOT EXISTS license_id VARCHAR(128) NULL AFTER branch_code,
    ADD COLUMN IF NOT EXISTS entitlement_status VARCHAR(32) NOT NULL DEFAULT 'VALID' AFTER edition,
    ADD COLUMN IF NOT EXISTS hmac_seal CHAR(64) NOT NULL DEFAULT '' AFTER remote_hybrid_config_json;

-- 3. Dedicated immutable audit log for commercial entitlement & licensing events
CREATE TABLE IF NOT EXISTS mc_commercial_audit_log (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    hospital_code VARCHAR(64) NOT NULL,
    license_id VARCHAR(128) NULL,
    event_type VARCHAR(64) NOT NULL,
    severity VARCHAR(32) NOT NULL DEFAULT 'INFO',
    details_json LONGTEXT NOT NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    INDEX idx_mc_comm_audit_hosp_event (hospital_code, event_type),
    INDEX idx_mc_comm_audit_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
