-- ============================================================================
-- V010: High-Frequency Composite Indexes & Relational Verification
-- ============================================================================

CREATE INDEX idx_mc_staff_hosp_active_role ON mc_staff (hospital_code, is_active, role);
CREATE INDEX idx_mc_patients_hosp_deleted_id ON mc_patients (hospital_code, is_deleted, id);
CREATE INDEX idx_mc_visits_hosp_status_created ON mc_visits (hospital_code, status, created_at);
CREATE INDEX idx_mc_finev_hosp_type_created ON mc_financial_events (hospital_code, event_type, created_at);
