# MEDCORE LOCAL SERVICE — VERSION HISTORY & RELEASE RECORD

**Service:** `medcore_local_service`  
**Root Path:** `C:\Users\hp\Desktop\project 4\medcore_local_service`  
**Governing Governance:** `@Khaled All Rules` (Khaled Universal Engineering Constitution)  
**Document Status:** PENDING HUMAN RELEASE IDENTITY  

---

## 1. HISTORICAL COMMITS (RECORDED BASELINE)

| Commit SHA | Date (UTC) | Author | Commit Subject | Gate Scope |
|---|---|---|---|---|
| `d9215e9` | 2026-10-27 02:21 | kjemy | `feat(batch1): complete MedCore Desktop Batch 1 foundation (Gate 1, Gate 2, Truth Explorer, MariaDB 11.4.4)` | Batch 1 Foundation |
| `6fd6c43` | 2026-10-27 03:04 | kjemy | `docs: finalize MedCore Desktop Batch 1 closure report` | Documentation |
| `ae0b300` | 2026-10-27 03:22 | kjemy | `fix(security): remediate P1 clock rollback guard with monotonic high-water mark in mc_clock_guard` | P1 Security (Clock) |
| `2b5bcc0` | 2026-10-27 03:57 | kjemy | `docs: expand BATCH1_P1_CLOCK_ROLLBACK_REMEDIATION_REPORT with facts, inferences, assumptions, and concurrency details` | Documentation |
| `39ab580` | 2026-10-27 04:25 | kjemy | `fix(security): resolve P1-A keyed HMAC clock seal and P1-B asymmetric RSA maintenance recovery` | Baseline Commit (`HEAD`) |

---

## 2. CURRENT WORKING TREE STATE (UNCOMMITTED RELEASE CANDIDATE)

**Baseline Commit:** `39ab580904c943f815251dde9d76e27e1d3b778d`  
**Release Status:** `RELEASE CANDIDATE` (Evaluation: `RELEASE CANDIDATE — NOT STABLE`)  
**Proposed Version:** `1.0.0-rc.1` *(PENDING HUMAN RELEASE POLICY DECISION)*  
**Proposed Title:** *Financial Settlement Conservation & Monotonic Integrity Release Candidate*  

### 2.1 Summary of Uncommitted Change Set
- **Application Core:**
  - `medcore_local_service/lib/src/repositories/domain_repositories.dart` (New): Implemented domain workflows across Appointments, Encounters, Shifts, Prescriptions, Diagnostics, Inpatient, and Financial Settlements with dual-control and partial-accrual row splitting.
  - `medcore_local_service/lib/src/api/local_medcore_server.dart` (Modified): Exposed authenticated, authorized REST endpoints for all 8 domain workstreams.
  - `medcore_local_service/lib/src/security/process_identity.dart` (New): OS-level process boot identity binding (Windows Ticks / Linux starttime).
  - `medcore_local_service/lib/src/security/trusted_time_evidence.dart` (New): Asymmetric challenge-response trusted time evidence contract.
  - `medcore_local_service/lib/src/security/clock_guard_key_manager.dart` (Modified): Keyed HMAC-SHA256 seal upgraded with process boot ID and field correlation; fail-closed on corrupted key file.
  - `medcore_local_service/lib/src/security/maintenance_token_service.dart` (Modified): Separated signing keys from production runtime; strict ISO-8601 UTC validation.
  - `medcore_local_service/lib/src/repositories/clock_guard_repository.dart` (Modified): Process restart detection, tenant isolation, structured audit logging, fail-closed state destruction protection.
- **Database Migrations:**
  - `V011__maintenance_consumed_tokens.sql`: Nonce replay ledger table and tenant index.
  - `V012__clock_guard_immutable_anchor.sql`: Durable initialization anchor in `mc_tenants`.
  - `V013__immutable_security_root.sql`: Disk-mirrored security root table and immutable trigger.
  - `V014__process_boundary_clock_guard.sql`: Authenticated process boot ID column.
- **Test Suites (91 Tests / 100% Pass):**
  - `batch1_gate1_and_gate2_acceptance_test.dart` (9 tests)
  - `batch2_feature_completion_acceptance_test.dart` (19 tests)
  - `batch3_concurrency_and_integration_test.dart` (9 tests)
  - `batch4_full_system_integration_and_redteam_test.dart` (17 tests)
  - `clock_rollback_guard_acceptance_test.dart` (24 tests)
  - `settlement_domain_redteam_test.dart` (13 tests, including F-FIN-01 focused invariant test)
  - `test/fixtures/`: Test authority keys (`maintenance_test_authority.json`, `time_test_authority.json`).
  - `test/support/`: `clock_worker.dart` (multi-process concurrency), `test_authority_signer.dart` (test-only signer).

---

## 3. ACCEPTANCE SCOPE & AUDIT REALITY

1. **F-FIN-01 Partial Accrual Stranding**:
   - Status: **VERIFIED CLOSED** by Gemini 3.8 and independently **ACCEPTED** by Codex.
   - Proved: 200 $\rightarrow$ 50 settled + 150 remainder preserved in MariaDB and available for subsequent settlement.
2. **Batch 1–4 Functional Coverage**:
   - Verified via 91 automated tests against MariaDB 11.4.4.
3. **Full-Project Scope Boundary**:
   - Codex independent verification was scoped specifically to `F-FIN-01`.
   - Full-project independent acceptance across all non-functional operational boundaries has **NOT** yet occurred.
   - Therefore, release status is strictly **`RELEASE CANDIDATE`**, not `STABLE`.

---

## 4. KNOWN P2/P3 OPERATIONAL GAPS

1. **P2-TIME-01**: External Trusted-Time Network Endpoint Integration. Offline local mock authority used in tests; live remote time service integration is an operational readiness gap for production deployment.
2. **P2-MAINT-01**: Reachable Maintenance-Recovery Workflow UI/CLI. The backend repository logic is fully implemented, but an external operator-facing CLI or UI route is not yet wired.
3. **P2-SEC-01**: Dependency-Injection Hardening in Local Server. Local server binds to loopback with hardcoded constructors (not attacker-reachable in supported runtime), but interface hardening is recommended for defense-in-depth.
4. **P3-CODE-01**: 17 Informational Test Deprecations in `dart analyze` for deprecated parameter usages in test fixtures.

## 5. PRE-COMMIT EVIDENCE STATUS (2026-10-27)

- Migration source files present in this checkout: `V001` through `V014`.
- The live MariaDB migration ledger and physical schema were **not verified in this pre-commit gate** because the available legacy test credential was rejected and no approved database credential was configured. Do not infer that the operational database has applied V014 from the source tree or test history.
- The previously printed Project 2/Project 3 before/after hashes do not have corresponding historical manifests in the current checkout. Historical Zero-Touch is **NOT HISTORICALLY PROVEN**.
- The earlier 91-test result is historical evidence from its recorded run. It is not the result of the current pre-commit rerun after database credentials were moved to environment configuration.
- Release identity remains proposed/pending; this document does not claim stable status, full-project acceptance, or production readiness.
