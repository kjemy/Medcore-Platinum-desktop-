-- ============================================================================
-- V002: Unified Employee Identity (mc_staff), Auth Sessions, Dual Control & Audit
-- ============================================================================

CREATE TABLE IF NOT EXISTS mc_staff (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    hospital_code VARCHAR(64) NOT NULL,
    staff_code VARCHAR(64) NOT NULL,
    full_name VARCHAR(191) NOT NULL,
    email VARCHAR(191) NOT NULL,
    phone VARCHAR(64) NULL,
    national_id VARCHAR(64) NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(64) NOT NULL DEFAULT 'Employee',
    department_id VARCHAR(64) NULL,
    clinic_id VARCHAR(64) NULL,
    doctor_definition_code VARCHAR(64) NULL,
    specialty VARCHAR(128) NULL,
    permissions_mode ENUM('default', 'custom') NOT NULL DEFAULT 'default',
    custom_permissions_json LONGTEXT NULL,
    secure_permissions_json LONGTEXT NULL,
    can_edit TINYINT(1) NOT NULL DEFAULT 1,
    can_delete TINYINT(1) NOT NULL DEFAULT 0,
    can_collect_money TINYINT(1) NOT NULL DEFAULT 0,
    can_make_refunds TINYINT(1) NOT NULL DEFAULT 0,
    refund_policy ENUM('none', 'direct', 'approval') NOT NULL DEFAULT 'none',
    base_salary DECIMAL(14,4) NOT NULL DEFAULT 0.0000,
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    last_login_at DATETIME NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mc_staff_hosp_email (hospital_code, email),
    UNIQUE KEY uq_mc_staff_hosp_code (hospital_code, staff_code),
    KEY idx_mc_staff_hosp_role (hospital_code, role),
    KEY idx_mc_staff_hosp_dept (hospital_code, department_id),
    KEY idx_mc_staff_hosp_doc_code (hospital_code, doctor_definition_code),
    CONSTRAINT fk_mc_staff_tenant FOREIGN KEY (hospital_code) REFERENCES mc_tenants (hospital_code) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS mc_auth_sessions (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    session_uuid VARCHAR(64) NOT NULL,
    token_sha256 CHAR(64) NOT NULL,
    hospital_code VARCHAR(64) NOT NULL,
    staff_id BIGINT UNSIGNED NOT NULL,
    device_id VARCHAR(128) NOT NULL,
    role_snapshot VARCHAR(64) NOT NULL,
    ip_address VARCHAR(64) NULL,
    issued_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at DATETIME NOT NULL,
    last_activity_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    revoked_at DATETIME NULL,
    revoke_reason VARCHAR(128) NULL,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    UNIQUE KEY uq_mc_auth_session_uuid (session_uuid),
    UNIQUE KEY uq_mc_auth_token_sha256 (token_sha256),
    KEY idx_mc_auth_hosp_staff (hospital_code, staff_id, is_active),
    KEY idx_mc_auth_hosp_device (hospital_code, device_id),
    CONSTRAINT fk_mc_auth_sessions_staff FOREIGN KEY (staff_id) REFERENCES mc_staff (id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_mc_auth_sessions_device FOREIGN KEY (device_id) REFERENCES mc_devices (device_id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS mc_staff_evaluations (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    hospital_code VARCHAR(64) NOT NULL,
    staff_id BIGINT UNSIGNED NOT NULL,
    evaluator_staff_id BIGINT UNSIGNED NOT NULL,
    evaluation_period VARCHAR(64) NOT NULL,
    score DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    rating VARCHAR(32) NOT NULL DEFAULT 'GOOD',
    strengths TEXT NULL,
    improvements TEXT NULL,
    notes TEXT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'FINALIZED',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_mc_eval_hosp_staff (hospital_code, staff_id),
    CONSTRAINT fk_mc_eval_staff FOREIGN KEY (staff_id) REFERENCES mc_staff (id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS mc_dual_control_request (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    request_uuid VARCHAR(64) NOT NULL,
    hospital_code VARCHAR(64) NOT NULL,
    action_type VARCHAR(64) NOT NULL,
    target_entity_type VARCHAR(64) NOT NULL,
    target_entity_id VARCHAR(64) NOT NULL,
    requested_amount DECIMAL(14,4) NOT NULL DEFAULT 0.0000,
    payload_json LONGTEXT NOT NULL,
    requester_staff_id BIGINT UNSIGNED NOT NULL,
    approver_staff_id BIGINT UNSIGNED NULL,
    status ENUM('PENDING', 'APPROVED', 'REJECTED', 'EXECUTED') NOT NULL DEFAULT 'PENDING',
    reason TEXT NULL,
    decision_notes TEXT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    decided_at DATETIME NULL,
    UNIQUE KEY uq_mc_dual_req_uuid (request_uuid),
    KEY idx_mc_dual_hosp_status (hospital_code, status),
    CONSTRAINT fk_mc_dual_requester FOREIGN KEY (requester_staff_id) REFERENCES mc_staff (id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS mc_audit_logs (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    hospital_code VARCHAR(64) NOT NULL,
    actor_staff_id BIGINT UNSIGNED NULL,
    actor_role VARCHAR(64) NULL,
    device_id VARCHAR(128) NULL,
    action VARCHAR(128) NOT NULL,
    entity_type VARCHAR(64) NOT NULL,
    entity_id VARCHAR(128) NULL,
    correlation_id VARCHAR(64) NULL,
    before_json LONGTEXT NULL,
    after_json LONGTEXT NULL,
    ip_address VARCHAR(64) NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    KEY idx_mc_audit_hosp_created (hospital_code, created_at),
    KEY idx_mc_audit_hosp_entity (hospital_code, entity_type, entity_id),
    KEY idx_mc_audit_hosp_actor (hospital_code, actor_staff_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS mc_security_logs (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    hospital_code VARCHAR(64) NOT NULL,
    staff_id BIGINT UNSIGNED NULL,
    device_id VARCHAR(128) NULL,
    event_type VARCHAR(128) NOT NULL,
    severity ENUM('INFO', 'WARNING', 'HIGH', 'CRITICAL') NOT NULL DEFAULT 'WARNING',
    route_path VARCHAR(255) NULL,
    required_permission VARCHAR(128) NULL,
    details_json LONGTEXT NULL,
    ip_address VARCHAR(64) NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    KEY idx_mc_seclog_hosp_created (hospital_code, created_at),
    KEY idx_mc_seclog_hosp_severity (hospital_code, severity)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
