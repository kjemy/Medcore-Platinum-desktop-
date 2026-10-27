# MEDCORE DESKTOP — BATCH 1 P1 SECURITY REMEDIATION FINAL CLOSURE REPORT
**Document ID**: `MEDCORE-B1-P1-REMEDIATION-CLOSURE-20261027`  
**Target Workspace**: `C:\Users\hp\Desktop\project 4`  
**Execution Agent**: Main Agent Only (Gemini 3.8 High)  
**Status**: **HISTORICAL BUILDER REPORT — CLAIMS BELOW ARE NOT INDEPENDENTLY VERIFIED BY THIS DOCUMENT**  
**Database Runtime**: The original author reported MariaDB 10.11+ on `127.0.0.1:3307`; this gate could not authenticate to the live server to confirm its version or state.  

> **Evidence status (2026-10-27 pre-commit gate):** This file records claims made by its original implementation agent. The original raw test output and historical Project 2/Project 3 before/after manifests are not present in the current checkout. Treat detailed PASS labels and physical-database statements below as **AGENT REPORT / UNVERIFIED CLAIM**, not current independent findings. Current migration source contains V001–V014. Live MariaDB application state was not verified because the available legacy test credential was rejected and no approved DB credential is configured. The Zero-Touch result is **NOT HISTORICALLY PROVEN**. F-FIN-01 has a separate Codex acceptance scoped only to that finding; this document does not expand that acceptance.

### Evidence labels used for this reclassification

- **FACT:** This checkout contains migration source files V001–V014; the separate F-FIN-01 acceptance is limited to F-FIN-01.
- **EVIDENCE:** The report text is present, but its cited raw test logs and historical manifests are not attached here; this gate's live MariaDB login was denied.
- **AGENT REPORT:** The PASS labels, historical table counts, migration-application count, and printed hashes are statements made by the original author.
- **UNVERIFIED CLAIM:** The exact physical database state and Project 2/Project 3 before/after equality described below.

---

## 1. Executive Summary

The original builder report stated that the 16 causes for rejection had been remediated and checked against MariaDB. That statement is preserved as historical agent reporting; the current pre-commit gate did not independently reverify those claims against live MariaDB.

| Audit Gate | Scope | Status | Evidence |
| :--- | :--- | :--- | :--- |
| **P1-A** | Server-Side Monotonic Clock Guard & Keyed HMAC Integrity | **AGENT-REPORTED; NOT REVERIFIED HERE** | Original report cites 17/17; current historical raw output not attached |
| **P1-B** | Asymmetric Maintenance Recovery & Cryptographic Nonce Replay | **AGENT-REPORTED; NOT REVERIFIED HERE** | Original report describes concurrency and claim checks; no current DB proof |
| **Gate 1 & 2** | Full Batch 1 Core Persistence, 10-Role RBAC & Data Explorer | **AGENT-REPORTED; NOT REVERIFIED HERE** | Original report cites 9/9; current DB proof unavailable |
| **Zero-Touch** | Project 2 and Project 3 state | **NOT HISTORICALLY PROVEN** | Historical manifests are absent from the current checkout; printed hashes below remain unverified claims |

---

## 2. Original Builder's Claimed Resolution of 16 Rejection Points (Unverified Here)

### 1. Cross-Tenant Global MAX Clock State Elimination (P1-A Cause #1)
- **Defect**: `getGlobalMaxObservedUtc()` allowed a corrupt future clock in Tenant A to artificially advance Tenant B's high-water mark, leading to premature session expiration.
- **Remediation**: Completely eliminated `getGlobalMaxObservedUtc()` and cross-tenant `SELECT MAX(max_observed_utc)`. In accordance with **Principle 4 (Isolation Integrity)**, clock evaluation is strictly scoped to the authenticated tenant (`hospital_code`).
- **Verification**: Test 3 explicitly advanced Tenant A by +12 hours and verified Tenant B remained strictly at its normal host clock without any cross-boundary contamination.

### 2. Adversarial State Deletion Detection (P1-A Cause #2)
- **Defect**: If `mc_clock_guard` row was deleted out-of-band, the repository treated it as a clean first installation and re-seeded high-water mark to current wall clock.
- **Remediation**: Enforced **Principle 3 (Adversarial State Destruction)**. When `res.rows.isEmpty`, `evaluateAndUpdateClock()` queries `mc_auth_sessions` and `mc_staff (WHERE last_login_at IS NOT NULL)`. If prior operational history exists, row deletion is caught immediately and throws `ClockTamperException`, failing closed and returning HTTP 403 `CLOCK_TAMPER_DETECTED`.
- **Verification**: Test 4 established sessions, deleted the `mc_clock_guard` row directly from MariaDB, and verified that both service evaluations and HTTP requests fail closed.

### 3. Complete Security-State Authentication (P1-A Cause #3)
- **Defect**: HMAC was unkeyed SHA-256 and only covered 4 fields, leaving `rollback_delta_seconds`, `locked_at_utc`, `unlocked_by_maintenance_token_id`, and `last_event_uuid` vulnerable to out-of-band tampering.
- **Remediation**: Implemented v2 Keyed HMAC-SHA256 (`MC_CLOCK_KEYED_SEAL:v2:...`) covering all 8 functional security fields:
  `hospitalCode`, `maxObservedUtc`, `lastBootMonotonicMs`, `rollbackDetected`, `rollbackDeltaSeconds`, `lockedAtUtc`, `unlockedByMaintenanceTokenId`, `lastEventUuid`.
- **Verification**: Test 5 tampered individually with each of the 8 fields in MariaDB and verified that 100% of out-of-band mutations fail HMAC verification with `ClockTamperException`.

### 4. RSA Private Authority Key Removal from Desktop Tree (P1-B Cause #4)
- **Defect**: `runtime/security/authority_priv.json` was bundled inside Desktop product tree, allowing local attackers to forge maintenance tokens.
- **Remediation**: Enforced **Principle 6 (Key Separation)**. Permanently deleted `authority_priv.json` from the product tree. Desktop runtime contains strictly the public key (`authority_pub.json`). Signing capability exists exclusively in test support (`TestAuthoritySigner`) loaded outside distribution.
- **Verification**: Test 6 scanned the entire `project 4` directory tree and verified zero private keys or `.priv` files exist.

### 5. Mandatory Installation Binding (P1-B Cause #5)
- **Defect**: Maintenance token verification accepted arbitrary installation IDs or empty values.
- **Remediation**: `MaintenanceTokenService` strictly enforces that `expectedInstallationId` is non-empty and cryptographically matches the token's `inst` claim. Empty claim throws `EMPTY_INSTALLATION_CLAIM`; mismatch throws `INSTALLATION_MISMATCH`.
- **Verification**: Test 7 tested empty parameter, empty claim, and mismatched claim, proving 100% rejection.

### 6. Trusted Effective Security Time Expiration Authority (P1-B Cause #6)
- **Defect**: Maintenance token expiration was evaluated against caller-supplied wall time, allowing rolled-back wall clock to revive expired tokens.
- **Remediation**: Enforced **Principle 5 (Trusted Time)**. In `unlockWithMaintenanceToken()`, token expiration is evaluated against `effectiveSecurityTime = max(currentWallClock, record.maxObservedUtc)`.
- **Verification**: Test 8 rolled back host wall clock past token expiration while high-water mark remained in the future; token was strictly rejected as `TOKEN_EXPIRED`.

### 7. Strict Fail-Closed `exp <= now` Expiration Rule (P1-B Cause #7)
- **Defect**: Open boundary comparison (`exp < now`) allowed a token at `exp == now` to be accepted.
- **Remediation**: Enforced strict fail-closed boundary: `if (expUtc.isBefore(effectiveUtc) || expUtc.isAtSameMomentAs(effectiveUtc)) throw MaintenanceTokenException('TOKEN_EXPIRED')`.
- **Verification**: Test 9 tested exact boundary moment `expiresAt == effectiveSecurityTime` and confirmed rejection.

### 8. Real OS Process-Level Restart Verification (Cause #8)
- **Defect**: Reconstructing objects in-memory within the same process was claimed as restart proof.
- **Remediation**: Enforced **Principle 7 (Real Restart Verification)**. Created `test/support/clock_worker.dart`. Executed real operating system process termination and restart using `Process.run(Platform.executable, ...)`.
- **Verification**: Test 11 launched OS Process 1 to advance clock, terminated process, and launched OS Process 2 to read back and verify high-water mark and HMAC validity.

### 9. Monotonic Drift Precision Without Integer Truncation (Cause #9)
- **Defect**: Using `difference.inSeconds` truncated fractional seconds (e.g. 5.9s truncated to 5s, evading 5s tolerance).
- **Remediation**: Evaluated drift in millisecond precision: `highestObserved.difference(nowUtc).inMilliseconds > driftTolerance.inMilliseconds`.
- **Verification**: Test 10 tested a drift of 5001ms with 5s tolerance; rollback was detected immediately (`rollbackDetected = true`).

### 10. Concurrency Proof for Replay Protection (P1-B Cause #10)
- **Defect**: Replay protection was tested sequentially, not under concurrent execution.
- **Remediation**: Enforced **Principle 8 (Concurrency Proof)**. MariaDB table `mc_consumed_maintenance_tokens` enforces `UNIQUE KEY uq_maint_token_nonce (hospital_code, nonce)`. Duplicate inserts are caught and mapped to `NONCE_ALREADY_USED`.
- **Verification**: Test 12 fired 10 concurrent requests simultaneously with identical nonce via `Future.wait`. Exactly 1 succeeded, exactly 9 failed with `NONCE_ALREADY_USED`, and physical database read-back confirmed exactly 1 row.

### 11. Concurrency Proof for Recovery Transactions (Cause #11)
- **Defect**: Concurrent evaluations risked race conditions or lost updates.
- **Remediation**: `evaluateAndUpdateClock` and `unlockWithMaintenanceToken` acquire row-level locking via `SELECT ... FOR UPDATE` inside ACID transactions.
- **Verification**: Verified under concurrent test execution without deadlocks.

### 12. Claim Tampering Matrix (P1-B Cause #12)
- **Defect**: Tampering with individual token claims was not comprehensively tested.
- **Remediation**: Enforced cryptographic RSA-2048 PKCS#1 v1.5 digest over canonical JSON representation of claims.
- **Verification**: Test 13 systematically mutated `hosp`, `inst`, `act`, `exp`, and `nonce`, asserting `INVALID_SIGNATURE` on 100% of mutations.

### 13. Session Revocation on Backward Clock Reset (Cause #13)
- **Defect**: Resetting clock backwards could theoretically resurrect a session that expired at the higher time.
- **Remediation**: In `unlockWithMaintenanceToken`, when `nowUtc < record.maxObservedUtc`, the service atomically executes:
  `UPDATE mc_auth_sessions SET is_active = 0, revoked_at = CURRENT_TIMESTAMP, revoke_reason = 'MAINTENANCE_CLOCK_RESET' WHERE hospital_code = :hosp AND is_active = 1`.
- **Verification**: Test 15 created an active session, reset clock backwards, and verified that the active session was permanently revoked. Test 16 verified that revoked session cannot be reused.

### 14. Formal Schema Migration V011 (Cause #14)
- **Defect**: `mc_consumed_maintenance_tokens` table was created dynamically via runtime `CREATE TABLE IF NOT EXISTS`.
- **Remediation**: Enforced **Principle 11 (Database Truth)**. Created formal migration `sql/migrations/V011__maintenance_consumed_tokens.sql` creating `mc_consumed_maintenance_tokens` and adding `UNIQUE KEY uq_mc_clock_guard_hosp (hospital_code)`.
- **Verification**: Test 17 inspected `information_schema.TABLES` and `SHOW INDEX`, verifying table exists via migration with InnoDB engine and utf8mb4 collation.

### 15. Historical Zero-Touch Hash Claim (Cause #15)
- **Original report claim**: Recursive SHA-256 before/after manifests were calculated for Project 2 and Project 3.
- **Evidence currently available**: The report contains four printed count/hash pairs, but the corresponding before/after manifests, file lists, and generation procedure are not present in the current checkout. The same printed root for both projects is not independently explained by available evidence.
- **Current classification**: **AGENT REPORT / UNVERIFIED CLAIM**. Historical Zero-Touch is **NOT HISTORICALLY PROVEN**. The printed values are retained only as a record of what the original report asserted; they are not proof and must not be cited as verified.

### 16. Comprehensive Acceptance Verification Without Mocks (Cause #16)
- **Defect**: Previous tests lacked negative boundary cases and direct physical MariaDB read-backs.
- **Remediation**: All 26 acceptance tests execute against real MariaDB 10.11+ on port 3307 with direct SQL read-backs and negative assertion coverage.
- **Verification**:
  - `clock_rollback_guard_acceptance_test.dart`: 17/17 PASSED.
  - `batch1_gate1_and_gate2_acceptance_test.dart`: 9/9 PASSED.
  - `dart analyze`: 0 issues found.

---

## 3. Historical Physical Database Claims — Not Reverified in This Gate

- **Schema Migration Table Count**: 90 InnoDB tables in `utf8mb4_unicode_ci`.
- **Original report claim**: 11 migrations (`V001` through `V011`) had been applied at the time of that report. The current filesystem contains migration source V001–V014. Current live MariaDB application state is unverified in this gate; do not treat the historical V001–V011 statement as the current schema version.
- **DECIMAL(14,4) Financial Columns**: 67 columns across financial tables.
- **Clock Guard & Maintenance Tables**:
  - `mc_clock_guard`: 10 columns, `UNIQUE KEY uq_mc_clock_guard_hosp (hospital_code)`.
  - `mc_consumed_maintenance_tokens`: 6 columns, `UNIQUE KEY uq_maint_token_nonce (hospital_code, nonce)`.

---

## 4. Original Builder's Final Verdict (Historical Claim)

**Historical builder conclusion (preserved, not an independent acceptance):** the original author reported Batch 1 P1 remediation as passed. This report alone does not establish current release readiness or full-project acceptance.
