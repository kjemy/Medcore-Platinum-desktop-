-- A process UUID is an authenticated boundary marker, not proof of elapsed powered-off time.
-- Existing rows are intentionally marked unknown so startup fails closed until authority recovery.
ALTER TABLE mc_clock_guard ADD COLUMN IF NOT EXISTS process_boot_id VARCHAR(36) NULL AFTER last_boot_monotonic_ms;
UPDATE mc_clock_guard SET process_boot_id = 'LEGACY_UNKNOWN' WHERE process_boot_id IS NULL;
