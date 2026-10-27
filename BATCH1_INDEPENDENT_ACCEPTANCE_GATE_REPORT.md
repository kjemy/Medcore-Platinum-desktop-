# MEDCORE DESKTOP — BATCH 1 INDEPENDENT ACCEPTANCE GATE REPORT

## 1. Executive Decision

**FAIL**

**FACT:** The mc_clock_guard table is created, but no service code reads or updates it. AuthService.verifySession decides expiry using DateTime.now().toUtc() directly. A local clock rollback can therefore extend an otherwise expired session, and the acceptance suite contains no rollback test. This leaves a required server-side device-security control unenforced and blocks Batch 2 readiness (P1).

**Recommendation:** BATCH 1 BLOCKED — FIX REQUIRED.

## 2. Test Run ID

MEDCORE-B1-INDEPENDENT-GATE-20261027-061805

## 3. Environment

- Project 4: C:\Users\hp\Desktop\project 4
- MariaDB binary: 11.4.4; configured port: 3307; configured data directory: runtime\mariadb_data
- Live database: unavailable. No listener on 127.0.0.1:3307 and no MariaDB process was running.
- Branch: main
- Current HEAD: 6fd6c431a731bd8c1b2a6e47d125b818855e1cdd
- Working tree before report creation: clean

## 4. Gate Results

| Gate | Result | Evidence |
|---|---|---|
| Database | PARTIAL | Static V001–V010 definitions contain 89 distinct tables: 88 application mc_* tables plus mc_schema_migrations. Static scan found 89 InnoDB definitions, 89 utf8mb4 declarations, and 67 DECIMAL(14,4) declarations. Live INFORMATION_SCHEMA, ledger, keys, indexes, FK actions, and stored monetary types could not be inspected. Test's table-count check is >=86; its Explorer check expects 89. |
| Transactions | PARTIAL | TransactionManager.runInTransaction sets REPEATABLE READ/SERIALIZABLE, commits on success, rolls back and rethrows on failure; savepoints and FOR UPDATE helpers exist. No live transaction test was run. Migration DDL is not wrapped atomically; errors propagate and the ledger row is written only after each migration completes. |
| Financial | PARTIAL | Source implements atomic visit creation and approval-only refund requests; test source asserts 600.0000 labor, 400.0000 consumables, 300.0000 commission, and 1550.0000 balanced postings. MariaDB read-back was not independently executed. |
| Authentication | PARTIAL | mc_staff is the service identity repository; password code uses PBKDF2-HMAC-SHA256, 16-byte secure salt, 32-byte key, encoded storage, and constant-time comparison. Iterations are configurable at hash creation and encoded per hash (default 20,000). Service session checks bind hospital and device in source. Live HTTP verification not run. |
| RBAC | PARTIAL | Source enforces route permissions, _all scope in repository SQL, _secure trusted-device checks, and operational flags server-side. Existing tests describe these cases but were not executed. |
| Tenant Isolation | PARTIAL | Source compares the session hospital to X-Tenant-ID; repository queries use hospital_code scoping. Existing cross-tenant tests were not executed against MariaDB. |
| Device Security | FAIL | Enrollment, device-bound sessions, and secure-device checks exist in source. Clock rollback protection is not implemented: mc_clock_guard appears only in migration DDL; verifySession uses wall-clock time directly. P1. |
| Explorer | PARTIAL | Service source provides schema/table/trace and CSV/TXT paths with privacy filtering. No live MariaDB records or output were inspected. No XLSX implementation found; Batch 1 closure describes CSV/TXT and marks later diagnostic-bundle capability as deferred. |
| Project 2 Integrity | UNVERIFIED | Specified path C:\Users\hp\Desktop\project 2 does not exist. No Project 2 files were touched. A separate Desktop folder named project2 exists, but its identity as the authorized Project 2 source is unverified and it was not inspected. |
| Project 3 Integrity | PARTIAL | Project 3 exists. All 3,720 paths in Project 4's before-snapshot were found with matching recorded size and timestamp (0 recorded metadata differences). This snapshot is not a content-hash manifest; a fresh 2,067-file SHA-256 parity check against Project 2 was not possible. No Project 3 files were touched. |
| Batch 2 Readiness | BLOCKED | P1 clock rollback gap blocks acceptance. Live schema/test evidence and Project 2 integrity also remain unverified. |

## 5. Findings

### P0

- None found in the bounded static review.

### P1

- **Unenforced clock rollback guard.** medcore_local_service/lib/src/security/auth_service.dart, AuthService.verifySession: expiration is checked against the host wall clock at DateTime.now().toUtc(). medcore_local_service/sql/migrations/V001__platform_governance_and_tenants.sql defines mc_clock_guard, but rg found no service reference to the table or its rollback fields. Impact: rolling back the server clock can make expired sessions appear valid (and undermines the device clock-tamper requirement). The acceptance test has no clock-rollback case. Minimal remediation: enforce a persisted monotonic/high-water clock guard in the service before session/expiry decisions, and add a real-database test. No source was changed in this audit.

### P2

- **Documentation naming/count conflicts.** The actual migration name and repository SQL use singular mc_dual_control_request; the closure report says mc_dual_control_requests. The closure report labels 13 extension tables but enumerates 14 names, including the migration ledger. Static total remains 89 definitions (88 non-ledger application tables plus the ledger); reconcile the classification and name in documentation.
- **Evidence gaps.** The live database was stopped. The requested test's setUpAll executes DROP DATABASE IF EXISTS medcore_test before recreating it; an existing runtime\mariadb_data\medcore_test directory is present. The test was not run to avoid deleting that database. Project 2's specified directory is absent, and Project 3's stored snapshot records sizes/timestamps rather than hashes.
- **Audit inputs absent.** No implementation_plan.md or walkthrough.md exists in the Project 4 tree. Closure report and canonical inventory were available and reviewed.

### P3

- None.

## 6. SHA / Documentation Consistency

- **Factual current HEAD:** 6fd6c431a731bd8c1b2a6e47d125b818855e1cdd on main (2026-10-27 06:04:58 +03:00).
- **Timeline:** d9215e95db44bfdc313569516c68cfa32c36a075 is the parent implementation commit (2026-10-27 06:00:48 +03:00); 6fd6c431... is the following documentation closure commit. Both SHAs exist in local history.
- **Documentation:** The closure report identifies d9215e95... as the initial implementation commit; current HEAD is 6fd6c431.... The current HEAD contains the service/migrations from its parent and the closure report. Thus the report and implementation are in the same current tree, across two commits.
- **Discrepancy:** The requested implementation_plan.md and walkthrough.md are absent, so their claimed SHA references and whether either was modified after the reported commit cannot be established. The provided SHA discrepancy is explained by the implementation commit followed by a docs-only closure commit, not by an unknown HEAD.

## 7. Final Recommendation

**BATCH 1 BLOCKED — FIX REQUIRED**

Resolve and verify the P1 clock rollback guard before Batch 1 can be accepted. Then run acceptance against an explicitly safe test database and verify Project 2/Project 3 integrity from the correct source paths. No Batch 2 work was started, and no Project 2/Project 3 or source files were modified.

