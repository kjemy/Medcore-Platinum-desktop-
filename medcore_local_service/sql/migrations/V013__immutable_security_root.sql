-- Durable, installation-bound security initialization root. Its seal is also mirrored
-- in runtime/security/tenant_roots and authenticated with the installation key.
CREATE TABLE IF NOT EXISTS mc_security_root (
  hospital_code VARCHAR(64) NOT NULL PRIMARY KEY,
  installation_id CHAR(32) NOT NULL,
  initialization_id CHAR(36) NOT NULL,
  initialized_at_utc DATETIME(3) NOT NULL,
  state VARCHAR(16) NOT NULL,
  hmac_seal CHAR(64) NOT NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  CONSTRAINT chk_mc_security_root_state CHECK (state IN ('ACTIVE'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TRIGGER trg_mc_tenants_clock_anchor_immutable
BEFORE UPDATE ON mc_tenants
FOR EACH ROW
SET NEW.clock_guard_initialized_at = IF(OLD.clock_guard_initialized_at IS NOT NULL, OLD.clock_guard_initialized_at, NEW.clock_guard_initialized_at);
