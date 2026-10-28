# MEDCORE PLATINUM — LOCAL AREA NETWORK (LAN) SECURITY & PKI REPORT
**Execution Date:** 2026-10-28
**Authority:** Master Engineering Constitution (@Khaled All Rules)
**Status:** PASS (Fully Verified Against Live MariaDB 11.4.4)

---

## 1. EXECUTIVE SUMMARY
In hospital offline/air-gapped deployments, security must not depend on public cloud PKI or external internet Certificate Authorities. MedCore Platinum provides an authoritative, facility-scoped LAN PKI infrastructure with Root CA generation, device workstation certificate issuance, cryptographic SHA-256 fingerprint binding, and fail-closed certificate revocation.

---

## 2. DATABASE REIFICATION & PHYSICAL DDL
Authoritative schema migration `V016__employee_accounts_and_external_payables.sql`:
```sql
CREATE TABLE IF NOT EXISTS mc_lan_certificates (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    hospital_code VARCHAR(64) NOT NULL,
    cert_uuid VARCHAR(128) NOT NULL,
    cert_type ENUM('ROOT_CA', 'SERVER_CERT', 'CLIENT_CERT') NOT NULL,
    device_id VARCHAR(128) NULL,
    common_name VARCHAR(191) NOT NULL,
    cert_pem MEDIUMTEXT NOT NULL,
    fingerprint_sha256 CHAR(64) NOT NULL,
    expires_at DATETIME NOT NULL,
    revoked_at DATETIME NULL,
    revoke_reason VARCHAR(191) NULL,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mc_lan_cert_uuid (cert_uuid),
    KEY idx_mc_lan_cert_hosp_type (hospital_code, cert_type),
    KEY idx_mc_lan_cert_fingerprint (hospital_code, fingerprint_sha256),
    CONSTRAINT fk_mc_lan_cert_tenant FOREIGN KEY (hospital_code) REFERENCES mc_tenants (hospital_code) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

---

## 3. ARCHITECTURE & ZERO-TRUST CONTROLS
1. **Facility Root CA**:
   - Deterministically provisioned per hospital facility.
   - 10-year validity, self-signed root anchor for local mTLS.
2. **Workstation / Device Certificates**:
   - Issued to enrolled devices registered in `mc_devices`.
   - Fingerprint (SHA-256) bound to device identity and validated on incoming connections.
3. **Fail-Closed Revocation**:
   - Revoking a certificate sets `is_active = 0`, sets `revoked_at = CURRENT_TIMESTAMP`, and marks the associated device in `mc_devices` as `status = 'REVOKED'`, `is_trusted_secure_runtime = 0`.
   - Subsequent validation requests immediately fail closed.

---

## 4. VERIFICATION EVIDENCE
- Test Suite: `medcore_local_service/test/batch8_external_payables_and_lan_pki_test.dart`
- Results:
  - Test 3: Issue device certificate, verify SHA-256 fingerprint against database, verify PKI validity (`true`), revoke certificate, verify PKI validity (`false`), verify `mc_devices` revocation. **PASSED**.
