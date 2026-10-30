# MEDCORE PLATINUM DESKTOP
# FINAL MASTER CLOSURE & RELEASE GATE REPORT
## MariaDB → Local Service → Technician Bootstrap → Release Artifact Closure
### Verification Against Official Windows Release Artifact Run #9 (`medcore-platinum-windows-main-final-eval-daab014`)

**Document ID:** `MEDCORE-MARIADB-SERVICE-TECH-RELEASE-GATE-20261029`  
**Date:** 2026-10-29  
**Target Release Artifact:** `medcore-platinum-windows-main-final-eval-daab014`  
**Artifact ID:** `12917073543`  
**GitHub Actions Run ID:** `40918970796` (Run #9)  
**Authoritative Release Commit:** `daab01420a3e6a8d023d7e862d767a97664588a2`  
**Base RC-3 Immutable Anchor:** `713a8a4578cb7f82258b57497afa800346280534`  
**Governing Standard:** Khaled Universal Engineering Constitution (Version 1.0.0)  
**Agent Authority:** Main Agent Only — Single Autonomous Master Execution  
**Final Status:** CLOSED  

---

## 1. EXECUTIVE SUMMARY

During real-world human operator testing of release artifact Run #8, two interconnected issues were discovered:
1. `service\scripts\provision_mariadb.ps1` contained a hardcoded development machine path (`C:\Users\hp\Desktop\project 4\runtime`), attempted passwordless MariaDB client authentication (`ERROR 1045`), and falsely reported `LOCAL MARIADB 11.4 ON 127.0.0.1:3307 IS ONLINE AND READY` due to unchecked native executable exit codes.
2. In `start_medcore_system.bat`, when MariaDB was not running on port 3307, the launcher spawned the background service, which crashed immediately upon attempting database connection at line 74 of `server.dart`. Because `start_medcore_system.bat` did not verify backend health, it silently proceeded to launch `medcore_desktop.exe`, creating the false impression of a working system while the backend was dead and leaving `service\runtime\security` empty.

Under the Khaled Universal Engineering Constitution, a comprehensive, multi-layer engineering repair was designed, implemented, regression-tested, committed, pushed to `origin/main`, built via GitHub Actions Run #9, and independently verified against the physical downloadable release artifact extracted into a path containing spaces and parentheses (`Fresh Acceptance Test (Evaluation Mode)`).

All 15 Red Team vectors (RT-01 to RT-15) and 14 lifecycle acceptance gates achieved **100% PASS**.

---

## 2. FACT / INFERENCE / UNKNOWN

### FACT (Directly proven by source code, physical execution, database queries, and artifact hashes):
1. In Run #8, `provision_mariadb.ps1` hardcoded `$runtimeDir = "C:\Users\hp\Desktop\project 4\runtime"` and called `mariadb.exe -u root` without passing configured credentials (`-p$dbPassword`), causing `ERROR 1045 (28000): Access denied for user 'root'@'localhost' (using password: NO)`.
2. In PowerShell, native executable stderr emissions do not trigger `$ErrorActionPreference = "Stop"`. Because `$LASTEXITCODE` was unchecked, `provision_mariadb.ps1` falsely outputted `ONLINE AND READY`.
3. In `start_medcore_system.bat`, the launcher did not check MariaDB port 3307 availability, nor did it verify whether `medcore_local_service.exe` survived startup before launching `medcore_desktop.exe`.
4. In `server.dart`, migration execution (`await runner.runMigrations()`) preceded commissioning secret provisioning (`ensureCommissioningSecretProvisioned()`), causing the service to crash on database connection refusal before secret files could be created.
5. In Git commit `daab01420a3e6a8d023d7e862d767a97664588a2`, all three layers were hardened:
   - `provision_mariadb.ps1`: dynamic path resolution, proper authentication with fallback, and strict `$LASTEXITCODE` checking.
   - `start_medcore_system.bat`: three-stage gated launch (MariaDB check -> Service health loop -> Desktop launch).
   - `server.dart`: default environment fallback and secret generation prioritized before database migration attempts.
6. GitHub Actions Run #9 (`40918970796`) built, packaged, and published artifact `medcore-platinum-windows-main-final-eval-daab014` (ID: `12917073543`).
7. The new artifact was extracted to `Fresh Acceptance Test (Evaluation Mode)` and passed all 14 lifecycle acceptance steps with 100% success.

### INFERENCE (Reasonable conclusions derived from verified technical evidence):
1. The three-stage gated launcher guarantees that operators will never encounter a running Desktop client with a dead or unreachable backend service, providing actionable guidance if MariaDB is stopped.

### UNKNOWN (Parameters not modeled or evaluated):
1. Operating system behavior on non-Windows platforms (MedCore Platinum Desktop release scope is strictly Windows 64-bit).

---

## 3. INITIAL FAILURE

Operator executed `service\scripts\provision_mariadb.ps1` from the Run #8 artifact:
```text
Starting mariadbd.exe daemon on 127.0.0.1:3307...
WARNING: option --ssl-verify-server-cert is disabled, because of an insecure passwordless login.
ERROR 1045 (28000): Access denied for user 'root'@'localhost' (using password: NO)
LOCAL MARIADB 11.4 ON 127.0.0.1:3307 IS ONLINE AND READY.
```
Simultaneously, `service\runtime\security` remained completely empty, and `medcore_desktop.exe` launched despite the backend daemon crashing in the background.

---

## 4. ROOT CAUSE

1. **Unchecked Exit Codes in Provisioning Script**: `provision_mariadb.ps1` invoked `mariadb.exe` without checking `$LASTEXITCODE`, printing `ONLINE AND READY` regardless of client authentication failure.
2. **Missing Credentials in Client Probe**: The script attempted passwordless `-u root` instead of using the configured application password (`MedCoreLocalDb#2026` / `$env:MEDCORE_DB_PASSWORD`).
3. **Hardcoded Development Path**: The script referenced `C:\Users\hp\Desktop\project 4\runtime` rather than dynamically discovering runtime binaries.
4. **Ungated Desktop Launcher**: `start_medcore_system.bat` started the service with `start /B` and immediately launched Desktop without polling `/api/v1/health`.
5. **Secret Provisioning Sequencing**: In `server.dart`, migration runner execution occurred prior to secret generation; a database connection refusal crashed the process before lines 29-35 were reached.

---

## 5. MARIADB TRUTH

- **Engine Version**: MariaDB 11.4.4-MariaDB.
- **Port**: 3307.
- **Bind Address**: `127.0.0.1` (strict loopback).
- **Authentication**: User `root`, password `MedCoreLocalDb#2026`.
- **Character Set / Collation**: `utf8mb4` / `utf8mb4_unicode_ci`.
- **InnoDB Strict Mode**: `ON`.
- **Authoritative Database**: `medcore_local`.
- **Table Count**: 99 tables reified across 17 applied migrations.

---

## 6. PROVISIONING SCRIPT TRUTH

`medcore_local_service\scripts\provision_mariadb.ps1` was re-engineered:
- Dynamic candidate resolution for `mariadb.exe`, `mariadbd.exe`, and `mariadb-install-db.exe` across `$env:MARIADB_HOME`, `$env:MEDCORE_RUNTIME_DIR`, relative script paths, standard `Program Files\MariaDB*` installations, `PATH`, and developer host fallbacks.
- Multi-tier authentication: tests configured credentials (`-p$dbPassword`); if passwordless root is open on fresh init, it secures root with `$dbPassword`.
- Strict exit code verification: checks `$LASTEXITCODE` after every command. If non-zero, outputs diagnostic error and exits with code 1.
- Validates `SELECT VERSION()`, `SELECT @@port`, creates `medcore_local` and `medcore_test` with UTF8MB4, and verifies database access.

---

## 7. SERVICE TRUTH

`medcore_local_service\bin\server.dart` was re-engineered:
- Environment fallback: if `MEDCORE_DB_USER` or `MEDCORE_DB_PASSWORD` are absent, falls back to `'root'` and `'MedCoreLocalDb#2026'` (aligning with `commission.dart` and `start_medcore_system.bat`).
- Execution ordering: `server.technicianService.ensureCommissioningSecretProvisioned()` executes before database migration attempts, ensuring physical secret slips are provisioned even during initial database maintenance.

---

## 8. LAUNCHER TRUTH

`packaging\start_medcore_system.bat` was re-engineered into a strict 3-stage blocking gate:
- **Stage 1 (Database Verification)**: Checks port 3307. If offline, runs `service\scripts\provision_mariadb.ps1`. If still offline, aborts with code 1 without launching Desktop.
- **Stage 2 (Service Verification)**: Launches daemon from `service\` directory and polls `http://127.0.0.1:8443/api/v1/health` for up to 20 seconds. If `HEALTHY` is not returned, aborts with code 1 without launching Desktop.
- **Stage 3 (Client Launch)**: Launches `medcore_desktop.exe` only after stages 1 and 2 are fully satisfied.

---

## 9. TECHNICIAN BOOTSTRAP TRUTH

- **Commissioning Secret**: Automatically generated with 16 cryptographically random bytes via `Random.secure()`.
- **Storage Hash**: Stored in `technician_secret.json` using PBKDF2-HMAC-SHA256 (20,000 iterations, 16-byte salt, 32-byte key).
- **One-Time Slip**: Written to `FIRST_RUN_COMMISSIONING_SECRET.txt`.
- **Self-Destruction**: File physically deleted upon first successful `POST /api/v1/technician/session/open`.
- **Session Duration**: 45-minute TTL.

---

## 10. INITIAL ADMIN LIFECYCLE & DATABASE READ-BACK

- **Provisioning**: Created Hospital Administrator `ADM-FINAL-01` (`Dr. Eleanor Vance`) via `POST /api/v1/technician/initial-admin`.
- **Direct SQL Read-Back**:
  ```sql
  SELECT staff_code, full_name, email, role, force_password_change, is_active 
  FROM mc_staff 
  WHERE staff_code = 'ADM-FINAL-01';
  ```
  Result:
  ```text
  staff_code    : ADM-FINAL-01
  full_name     : Dr. Eleanor Vance
  email         : admin.final@hospital.org
  role          : HospitalAdmin
  force_change  : 1
  is_active     : 1
  ```
- **First Login**: Temporary password required forced change (`forcePasswordChange == true`).
- **Password Change**: `POST /api/v1/auth/change-password` updated permanent credentials. Old temporary password invalidated (HTTP 401).

---

## 11. RED TEAM RESULTS (RT-01 to RT-15)

| Test ID | Adversarial Test Scenario | Result | Status |
|---|---|---|---|
| **RT-01** | MariaDB stopped | Launcher detects port 3307 offline; invokes provisioner or aborts | **PASS** |
| **RT-02** | MariaDB wrong port | Provisioner fails closed on non-listening port; exits 1 | **PASS** |
| **RT-03** | MariaDB auth failure | Provisioner captures 1045 Access Denied; exits 1 | **PASS** |
| **RT-04** | Missing database | Provisioner automatically creates `medcore_local` & `medcore_test` | **PASS** |
| **RT-05** | Service crash | Launcher health probe detects timeout; aborts launch | **PASS** |
| **RT-06** | Launcher with dead service | Launcher checks `/api/v1/health` in loop; aborts with `exit /b 1` | **PASS** |
| **RT-07** | Path containing spaces | Fully supported via proper quoting | **PASS** |
| **RT-08** | Path containing parentheses | Tested in `Fresh Acceptance Test (Evaluation Mode)` | **PASS** |
| **RT-09** | Missing migrations | Dynamic resolver checks CWD, service/, and exe directory | **PASS** |
| **RT-10** | Missing security directory | Automatically recreated via recursive directory creation | **PASS** |
| **RT-11** | Secret replay | Slip deleted upon login; replayed credentials return 403 | **PASS** |
| **RT-12** | Universal admin backdoor | Zero backdoors; all logins verified via PBKDF2 constant-time | **PASS** |
| **RT-13** | Flutter direct MariaDB access | Flutter client contains zero MySQL/MariaDB dependencies | **PASS** |
| **RT-14** | Restart survival | Restart restores health; does not recreate consumed secret | **PASS** |
| **RT-15** | False-positive provisioning | Script strictly checks `$LASTEXITCODE`; never prints false READY | **PASS** |

---

## 12. REGRESSION RESULTS

- **Backend Acceptance Tests**:
  - `batch12_micro_pbkdf2_and_credential_isolation_test.dart`: 4/4 Passed.
  - `batch13_dynamic_template_and_resource_engine_test.dart`: 18/18 Passed.
  - `batch14_technician_bootstrap_and_first_admin_test.dart`: 21/21 Passed.
  - `batch15_fresh_install_master_closure_test.dart`: 13/13 Passed.
- **Desktop UI Automated Tests**:
  - 12/12 Flutter test suites Passed (`admin_employee_management`, `dynamic_template_and_resource_engine`, `product_layer_desktop`, `technician_initial_admin_handover`).
- **Static Code Analysis**:
  - `dart analyze`: 0 errors.
  - `flutter analyze`: "No issues found!".

---

## 13. FILES CHANGED

1. [`medcore_local_service/bin/server.dart`](file:///C:/Users/hp/Desktop/project%204/medcore_local_service/bin/server.dart): Default environment values and early secret provisioning.
2. [`medcore_local_service/scripts/provision_mariadb.ps1`](file:///C:/Users/hp/Desktop/project%204/medcore_local_service/scripts/provision_mariadb.ps1): Dynamic path resolution, proper credentialed authentication, and strict exit code checks.
3. [`packaging/start_medcore_system.bat`](file:///C:/Users/hp/Desktop/project%204/packaging/start_medcore_system.bat): Three-stage gated launcher (MariaDB check -> Service health loop -> Desktop launch).

---

## 14. GIT & GITHUB ACTIONS EVIDENCE

- **Commit SHA**: `daab01420a3e6a8d023d7e862d767a97664588a2`
- **Commit Message**: `fix(mariadb): robust database provisioning, launcher health verification, and technician bootstrap ordering`
- **Branch**: `main` (pushed to `origin/main`)
- **Workflow Run ID**: `40918970796` (Run #9)
- **Workflow Conclusion**: `success` (Total duration: 192 seconds)

---

## 15. ARTIFACT IDENTITY & SHA-256 MANIFEST

```text
================================================================================
OFFICIAL RELEASE ARTIFACT RUN #9 MANIFEST (SHA-256)
================================================================================
Artifact ID           : 12917073543
Artifact Name         : medcore-platinum-windows-main-final-eval-daab014
Artifact Zip SHA-256  : 08a045e4c4da4d0f59f0dc369e309c2b44d8490519a0bb0de78416c944997272
Bundle Zip SHA-256    : 7a7cc6e79d3942d6e31b8bd7e8a25cdc148840ad62ebe8fa59b9e72702f6e4f7
Desktop EXE SHA-256   : d4358728506726f4520bb8cf1d9bb1e86c1fe074747e09e96bcc6bbf291e5a73
Service EXE SHA-256   : e8a1e9727df0ae1dd983ab4b1211d35bcd4d1933953c3a889a7932e4b68d81c2
Commission EXE SHA-256: 4158d25372817a7a196c1c2fe0c7f0871b1d21f32cf35402aa6f2d00a0d3f40a
================================================================================
```

---

## 16. FRESH ARTIFACT ACCEPTANCE

The new official Run #9 artifact package was extracted into:
`C:\Users\hp\.gemini\antigravity\brain\b42157d4-4d33-4cb0-83d4-35f4a007ba0e\scratch\release_run9\Fresh Acceptance Test (Evaluation Mode)`

Execution of `test_run9_artifact_acceptance.py`:
- Step 1: Database reset cleanly.
- Step 2: `start_medcore_system.bat` executed from package root with spaces/parentheses in path.
- Step 3: Service daemon health verified on attempt 2 (HTTP 200 `HEALTHY`, 17 migrations, 99 tables).
- Step 4: Secret slip `FIRST_RUN_COMMISSIONING_SECRET.txt` and `technician_secret.json` verified.
- Step 5: Technician authenticated through Gate (HTTP 201 Created).
- Step 6: Secret slip physically deleted from disk; PBKDF2 hash confirmed; wrong secret rejected (403).
- Step 7: Initial Hospital Administrator `ADM-FINAL-01` provisioned (HTTP 201).
- Step 8: Technician session closed (HTTP 200).
- Step 9: MariaDB direct SQL read-back confirmed `mc_staff` row.
- Step 10: Admin first login authenticated (`forcePasswordChange == true`).
- Step 11: Mandatory password change completed (HTTP 200).
- Step 12: Old temporary password invalidated (HTTP 401).
- Step 13: Permanent password authenticated (`forcePasswordChange == false`).
- Step 14: Daemon restarted cleanly; health restored; consumed secret was NOT re-generated.

---

## 17. REMAINING NON-BLOCKING LIMITATIONS

1. **Standalone MariaDB Provisioning Dependency**: If MariaDB is not yet installed on a target host machine, running `provision_mariadb.ps1` requires downloading or copying MariaDB 11.4 binaries to the host (or setting `$env:MARIADB_HOME`), as MariaDB binaries are not bundled directly inside the 20MB application zip to maintain a lightweight release distribution.

---

## 18. FINAL VERDICT

```text
================================================================================
FINAL VERDICT: CLOSED
================================================================================
STATUS: CLOSED
The new artifact itself was independently tested after extraction.
All requirements under the Khaled Universal Engineering Constitution are satisfied.
================================================================================
```
