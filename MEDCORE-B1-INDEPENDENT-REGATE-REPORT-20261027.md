# MEDCORE DESKTOP — BATCH 1 FINAL INDEPENDENT RE-GATE REPORT

## 1. Executive Decision

**FAIL — BATCH 1 BLOCKED**

The monotonic high-water check prevents an ordinary wall-clock rollback from reviving a session while the persisted clock row remains trustworthy. However, two P1 security controls claimed by the remediation are not actually enforced: the “HMAC” is an unkeyed SHA-256 digest that the guard never verifies, and the public maintenance-unlock method accepts an arbitrary token ID while lowering the persisted high-water mark. The clock test suite passes, but does not test either condition.

## 2. FACT

- Current source contains ClockGuardRepository and calls clock evaluation from login and session verification.
- Session issuance uses the returned effective time; session checks reject at or after expires_at and revoke the session.
- The isolated MariaDB test suite ran 6/6 clock tests successfully.
- The live isolated test schema has 89 InnoDB tables with utf8mb4_unicode_ci, 10 migration rows, and 67 DECIMAL(14,4) columns.
- Dart static analysis completed with “No issues found.”
- No source files were changed in this re-gate. The test suite reset only its named isolated database, medcore_clock_test.

## 3. INFERENCE

- If a local actor can alter the MariaDB clock row, the current digest supplies no secret-based integrity protection, and code does not validate it. A forged lower max_observed_utc can make effective time fall back to a rolled-back wall clock, potentially accepting a still-active session that had already expired according to the former high-water time.
- Calling unlockWithMaintenanceToken with a lower wall-clock value similarly resets max_observed_utc and clears rollback_detected. If invoked before an expired-but-active session is checked, it can remove the high-water condition that would have expired that session.
- A global maximum across tenants is consistent with a single host clock, but couples tenants: an anomalously future tenant value can force early expiry or denial for other tenants.

## 4. ASSUMPTION

- The remediation’s declared threat model includes local clock tampering and out-of-band edits to the local MariaDB clock row. If it excludes actors with local database access, the unkeyed digest has less practical exposure; the report’s explicit claim that it detects database-row tampering is still unsupported.
- The first-launch RTC limitation is accepted only for a new installation with no prior sessions/high-water state and with the documented later trusted time synchronization. It does not provide a trusted initial time anchor.

## 5. Git Evidence

- Git root: C:/Users/hp/Desktop/project 4
- Branch: main
- Current HEAD: 2b5bcc03a3f068a239e08bc9d0e11db7dd122806
- Working tree before this report: clean.
- 2b5bcc0 is the current HEAD and is a documentation-only child of ae0b300.
- ae0b300 is the implementation commit, parented by 6fd6c431. It adds the clock repository and clock tests and modifies auth/session wiring and exports.
- Exact 2b5bcc0 change: only BATCH1_P1_CLOCK_ROLLBACK_REMEDIATION_REPORT.md.
- Thus ae0b300 is the remediation; 2b5bcc0 is documentation closure, not a second implementation.
- The only new working-tree file from this re-gate is this requested report.

## 6. P1 Clock Guard Verification

- Persistent high-water: **FACT — present.** ClockGuardRepository reads and updates mc_clock_guard.max_observed_utc in MariaDB.
- Transaction and row lock: **FACT — present for evaluation.** AuthService calls evaluation within TransactionManager; existing tenant row query ends in FOR UPDATE. TransactionManager uses REPEATABLE READ and commits/rolls back the operation.
- Effective time: **FACT — max(current wall UTC, tenant/global persisted high-water).** Login timestamps and session expiry are based on this effective time. Ordinary rollback cannot reduce it while the row is intact.
- OS monotonic source: **FACT — not an effective-time source.** A static Stopwatch elapsed value is stored in last_boot_monotonic_ms, but effective-time computation does not read/use that value. It also resets with a new OS process. The persisted wall-clock high-water, not a persisted monotonic timer, provides the observed protection.
- Tenant/global behavior: **FACT — both are used.** A tenant row is locked; then an unscoped SELECT MAX(max_observed_utc) across all tenants is used. This is shared-host time coupling and can propagate one tenant’s future value to others.
- Threshold: **FACT — approximately five seconds, with rounding.** Code uses difference.inSeconds > driftTolerance.inSeconds. Since inSeconds truncates, a rollback between 5 and 6 seconds is treated as within a five-second tolerance. The tests cover 2 seconds and 60 seconds, not the 5/6-second boundary.
- Fail-closed behavior: database exceptions propagate through the transaction; no fallback to a local in-memory clock is present.

## 7. MariaDB Evidence

- MariaDB 11.4.4 is listening on 127.0.0.1:3307.
- The live database medcore_clock_test reported 89 tables, all InnoDB with utf8mb4_unicode_ci; mc_schema_migrations contains 10 rows and the schema has 67 DECIMAL(14,4) columns.
- The clock test’s MariaDB row for HOSP_CLOCK_A persisted max_observed_utc 2026-10-27 14:05:00.000, rollback_detected 0 after the test’s recovery path.
- No query or test touched medcore_local.
- The full Batch 1 regression test was not run: its setUpAll drops and recreates medcore_test, which is a separate existing runtime database, rather than using medcore_clock_test. The reported 9/9 regression claim therefore remains unverified in this re-gate.

## 8. Session Expiration Verification

- **FACT:** The 6/6 clock suite passed expired-session rollback and a service-instance restart scenario. Effective expiry uses the persisted high-water and an expired token is revoked.
- **FACT:** Login also evaluates the clock guard before creating the session and passes effective time to createSession.
- **Evidence limit:** The restart case stops and creates a new LocalMedCoreServer object inside the same Dart test process. It does not terminate and relaunch the OS process. It does prove database high-water persistence across service-object restart, not process-level restart.
- **FACT:** No test corrupts max_observed_utc or hmac_seal and then proves the verifier rejects the row.

## 9. Restart Verification

- Service-object restart with the same MariaDB database: passed in the clock suite.
- Full operating-system process restart: not executed.
- The stored Stopwatch value is not used in effective time, so its reset at process restart does not improve or undermine the high-water calculation itself.

## 10. Concurrency Verification

- **FACT:** Existing tenant rows are selected FOR UPDATE inside a transaction, serializing updates to that tenant’s row.
- **Evidence gap:** No concurrent clock-evaluation test exists in the six-case suite.
- **FACT:** First initialization has no existing row to lock; it derives an ID from MAX(id)+1 before insert. The unique constraints can reject a collision, but successful concurrent initialization was not demonstrated.
- **P2:** Concurrency claims exceed tested evidence; behavior is only partially established from source.

## 11. HMAC Verification

**P1 finding.**

- computeHmacSeal constructs a public string containing a fixed label and row fields, then calls PasswordHasher.sha256Hex. There is no secret key and no keyed HMAC operation. This is an unkeyed SHA-256 checksum, not an HMAC.
- verifyHmacSeal only recomputes that checksum. Evaluation/read paths do not call it; it is called by the test to compare a row with the same public algorithm.
- No tampered-row test exists. A database writer can edit the row and recompute the public digest, and the service would not check the digest in any case.
- Severity: **P1** because the remediation claims a tamper-detection seal for the persisted high-water state, which is part of the session anti-rollback security boundary.

## 12. Maintenance Unlock Verification

**P1 finding.**

- unlockWithMaintenanceToken accepts hospitalCode, tokenId, and currentWallClock. It does not validate a secret, signature, challenge/response, expiration, installation binding, device binding, or authorization.
- Any string, including the test value MNT-TOKEN-2026-RELEASE, is stored as unlocked_by_maintenance_token_id.
- The method sets max_observed_utc to currentWallClock and clears rollback state; it can lower the high-water mark.
- ClockGuardRepository is exported, and TenantGovernanceRepository exposes a public forwarding method. No HTTP route for unlock was found, so remote network reachability is not established; invoking the library method currently requires internal code access.
- Severity: **P1** because the exposed recovery operation accepts no proof and can remove the exact high-water condition used to reject an expired-but-active session. The acceptance test proves only that an arbitrary token ID is recorded, not that a technician token is authenticated.

## 13. Regression Results

- Clock rollback acceptance: **6/6 PASS** on MariaDB 11.4.4, isolated database medcore_clock_test.
- Static analysis: **PASS**, no issues.
- Batch 1 regression groups: **NOT RUN** in this re-gate. The suite would DROP and recreate medcore_test, which is outside the isolated database used here. Remediation report’s 9/9 statement was not independently rerun.
- The clock suite does not test HMAC tampering, maintenance token validation, fractional threshold boundaries, concurrent requests, or an OS process restart.

## 14. Project 2 Boundary

- Expected path: C:/Users/hp/Desktop/project2 exists; it is not a Git repository.
- Its root last-write time is 2026-10-25 15:36:55.
- Remediation Git diff contains only Project 4 paths. No Project 2 path was accessed for writing in this re-gate.
- **Evidence limit:** No before-remediation content-hash manifest is supplied here, so a zero-hash-difference claim across the whole folder cannot be independently established from the Git diff alone.

## 15. Project 3 Boundary

- Expected path: C:/Users/hp/Desktop/project 3 exists; it is not a Git repository.
- Its root last-write time is 2026-10-27 03:17:56.
- Remediation Git diff contains only Project 4 paths. No Project 3 path was accessed for writing in this re-gate.
- **Evidence limit:** The earlier Project 4 snapshot records file sizes/timestamps, not per-file SHA-256 values; the remediation report provides no before/after hash manifest. Zero content changes during remediation are not independently hash-proven here.

## 16. Findings

1. **P1 — Clock high-water tamper integrity is not enforced.** Digest is unkeyed SHA-256; verifier is not used during evaluation.
2. **P1 — Maintenance unlock is unauthenticated and can lower the high-water mark.** Any tokenId is accepted; no signed or expiring proof is checked.
3. **P2 — Five-second boundary uses truncated integer seconds.** Rollback from 5.0 to under 6.0 seconds does not trigger the >5-second alarm.
4. **P2 — Monotonic timer and process restart claims are overstated.** Stopwatch is persisted as metadata but not used for effective time; restart test is same OS process.
5. **P2 — Tenant-wide global maximum couples tenant clocks.** A future value in one tenant can deny or prematurely expire other tenants.
6. **P2 — Full Batch 1 regression claim is not independently verified in this run.** The existing suite resets medcore_test; only the isolated clock suite was run.

## 17. Severity

- **P0:** None found.
- **P1:** Unkeyed/unverified clock seal; unauthenticated maintenance unlock that can lower high-water.
- **P2:** Threshold truncation, overstated monotonic/restart claims, cross-tenant clock coupling, full regression evidence gap.
- **P3:** None.

## 18. Remaining Limitations

- First-launch BIOS/RTC rollback remains documented: without a previously persisted high-water or trusted external time anchor, first initialization anchors to the local clock. This is a limitation, not independently proven prevention. It does not revive a pre-existing session on a fresh install because no prior local session/high-water exists.
- No authenticated maintenance challenge flow is present in the inspected service path.
- Full 9-group regression and OS process restart remain unverified.

## 19. Final Acceptance Decision

**FAIL — BATCH 1 BLOCKED**

The normal rollback protection is exercised successfully, but the seal and unlock paths leave ways for an actor with internal/library or local database access to invalidate the persisted high-water control. The claimed HMAC and authenticated maintenance recovery are not established by code or tests.

## 20. Test Run ID

MEDCORE-B1-INDEPENDENT-REGATE-20261027-065629

## 21. Final HEAD SHA

2b5bcc03a3f068a239e08bc9d0e11db7dd122806
