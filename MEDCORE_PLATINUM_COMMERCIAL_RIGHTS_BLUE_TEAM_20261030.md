# MEDCORE PLATINUM DESKTOP
# COMMERCIAL RIGHTS & OFFLINE LICENSING BLUE TEAM REPORT
## DEFENSIVE ENGINEERING CONTROLS & SECURITY ARCHITECTURE (RUN #14/15)

**Project:** MedCore Platinum Desktop  
**Date:** October 30, 2026  
**Governance:** Khaled Universal Engineering Constitution (Gate 4 & Gate 21)  

---

## 1. BLUE TEAM DEFENSE PHILOSOPHY

The MedCore Platinum defensive architecture is constructed upon the core Khaled engineering principles:
1. **Defense-in-Depth**: Multi-layered defense spanning OS permissions, filesystem encryption, database constraints, middleware gates, and cryptographic signature validation.
2. **Fail-Closed by Default**: If any cryptographic signature, hardware binding, timestamp, or database seal cannot be positively validated, the system fails closed (denies mutations, rejects imports, or locks sessions).
3. **Clinical Safety Primacy**: Commercial rights enforcement must never endanger patient lives. Expired subscriptions permit read access to patient clinical charts (`EXPIRED_READ_ONLY`), preventing diagnostic errors in emergency situations while completely protecting the commercial rights of Orbit Software by blocking data mutations.
4. **Epistemic Truth Hierarchy**:
   - **Level 1 (Highest Truth)**: Cryptographically signed offline license (`license.mclic`) verified via RSA-2048 PKCS#1 v1.5 with Orbit Software embedded public key.
   - **Level 2**: Authoritative database state (`mc_license_state` + HMAC-SHA256 seal) and Monotonic Clock Guard (`mc_clock_guard`).
   - **Level 3**: Shelf HTTP Middleware enforcing fail-closed verb filtering.
   - **Level 4**: Client UI representation.

---

## 2. DEFENSIVE ARCHITECTURAL CONTROLS MATRIX

### Layer 1: Operating System & Filesystem Security
- **Dynamic Credential Generation**: Root database credentials are generated using Dart/PowerShell CSPRNG (`[Security.Cryptography.RNGCryptoServiceProvider]`) producing 32-character high-entropy passwords.
- **Credential Storage Isolation**: Saved in `runtime/security/db_credentials.json` with restricted filesystem ACLs. The file is never committed to Git and is isolated from client bundles.
- **Hardware Identity Derivation**: Composite fingerprint combining:
  1. `Win32_ComputerSystemProduct.UUID` (SMBIOS UUID)
  2. `Win32_BaseBoard.SerialNumber` (Motherboard Serial)
  3. `Win32_DiskDrive.SerialNumber` (Primary Storage Serial)
  Hashed together with SHA-256 to produce an immutable 64-character hexadecimal machine fingerprint.

### Layer 2: Database Storage Engine & Schema Protection
- **Migration V018 Reification**:
  - `mc_license_state.ed25519_signature` enlarged to `VARCHAR(512)` to accommodate 342-character base64url RSA-2048 signatures without truncation.
  - `mc_license_state.hmac_seal` (`CHAR(64)`) ensures that direct SQL tampering with rows is detectable and rejected.
  - `mc_commercial_audit_log` records every license import, status transition, and security rejection in an append-only table.
- **Port & Network Isolation**: MariaDB daemon is configured with `--bind-address=127.0.0.1` and runs on non-standard port `3307`. External network interfaces cannot access the database port.

### Layer 3: Cryptographic Licensing & Anti-Tamper Engine
- **Asymmetric Signature Verification**:
  - Algorithm: RSA-2048 with PKCS#1 v1.5 padding and SHA-256 digest.
  - Authority: Orbit Software Licensing Authority.
  - Verification: Uses BigInt modular exponentiation (`M = S^e mod n`) comparing the decrypted PKCS#1 block with the SHA-256 digest of `MEDCORE_LIC_V1.<b64_payload>`.
  - Constant-time comparison ensures resistance against timing side-channel attacks.
- **Monotonic High-Water Mark Clock Guard**:
  - Evaluates system time against the maximum observed UTC timestamp stored in `mc_clock_guard.max_observed_utc`.
  - Detects backwards time shifts (`nowUtc < maxObservedUtc`).
  - Supports clean reboots by tracking `process_boot_id` UUIDs.

### Layer 4: HTTP Pipeline & Entitlement Middleware
- **Shelf Middleware Pipeline Interception**:
  - Injected before any domain or route handlers in `LocalMedCoreServer`.
  - Permits public bypass routes: `/api/v1/health`, `/api/v1/auth/login`, `/api/v1/product/bootstrap`.
  - When entitlement is `EXPIRED_READ_ONLY`, permits all `GET` and `HEAD` requests.
  - Intercepts and denies all `POST`, `PUT`, `PATCH`, and `DELETE` requests with HTTP 403:
    ```json
    {
      "ok": false,
      "error": {
        "code": "SUBSCRIPTION_EXPIRED",
        "status": "EXPIRED_READ_ONLY",
        "message": "Hospital subscription has expired. System is in EXPIRED_READ_ONLY mode. Patient records remain accessible, but data mutations are blocked."
      }
    }
    ```

### Layer 5: Technician Management & Commissioning Security
- **Dual-Mode Technician Authentication**:
  1. *Runtime Secret Mode*: Verified against PBKDF2 hash with 100,000 iterations.
  2. *Cryptographic Recovery Mode*: RSA authority challenge-response with trusted monotonic time evidence.
- **Mandatory Request Headers**: Technician endpoints require `X-Tenant-ID`, `X-MedCore-Device-ID`, and `X-MedCore-Tech-Token`. Missing or mismatched headers trigger immediate fail-closed denial.

---

## 3. AUDIT & TELEMETRY CONTROLS

All commercial license operations emit immutable structured audit events into `mc_commercial_audit_log`:

```sql
INSERT INTO mc_commercial_audit_log (hospital_code, license_id, event_type, severity, details_json)
VALUES (
    :hosp,
    :lic_id,
    'COMMERCIAL_LICENSE_IMPORTED',
    'INFO',
    '{"edition":"PLATINUM","expiresAt":"2027-10-30T10:00:00Z","maxDevices":50,"maxDoctors":100}'
);
```

Event types include:
- `COMMERCIAL_LICENSE_IMPORTED`
- `COMMERCIAL_STATUS_EVALUATED`
- `COMMERCIAL_HARDWARE_MISMATCH_LOCKED`
- `COMMERCIAL_CLOCK_TAMPER_LOCKED`
- `COMMERCIAL_EXPIRED_READ_ONLY_ENGAGED`

---

## 4. BLUE TEAM CONCLUSION

The defensive controls implemented in Run #14/15 provide complete, robust protection of commercial rights without compromising patient safety, system resilience, or offline autonomy.
