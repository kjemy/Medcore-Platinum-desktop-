-- ============================================================================
-- V011: Consumed Maintenance Tokens Replay Ledger & Clock Guard Tenant Index
-- ============================================================================

CREATE TABLE IF NOT EXISTS mc_consumed_maintenance_tokens (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    hospital_code VARCHAR(64) NOT NULL,
    installation_id VARCHAR(128) NOT NULL,
    nonce VARCHAR(128) NOT NULL,
    action VARCHAR(64) NOT NULL,
    consumed_at_utc DATETIME(3) NOT NULL,
    UNIQUE KEY uq_maint_token_nonce (hospital_code, nonce),
    KEY idx_maint_token_inst (installation_id),
    CONSTRAINT fk_mc_maint_tokens_tenant FOREIGN KEY (hospital_code) REFERENCES mc_tenants (hospital_code) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE mc_clock_guard ADD UNIQUE KEY uq_mc_clock_guard_hosp (hospital_code);
