-- ============================================================================
-- V012: Durable Tenant Clock Guard Initialization Anchor
-- Eliminates F-02: Deletion of mc_clock_guard cannot recreate a fresh baseline.
-- ============================================================================

ALTER TABLE mc_tenants ADD COLUMN clock_guard_initialized_at DATETIME(3) NULL;

UPDATE mc_tenants t
INNER JOIN mc_clock_guard g ON t.hospital_code = g.hospital_code
SET t.clock_guard_initialized_at = g.max_observed_utc
WHERE t.clock_guard_initialized_at IS NULL;
