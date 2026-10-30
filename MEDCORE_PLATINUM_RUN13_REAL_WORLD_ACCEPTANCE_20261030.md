# MEDCORE PLATINUM DESKTOP — RUN #13
# REAL-WORLD SELF-CONTAINED HOSPITAL ACCEPTANCE GATE REPORT

**Project:** MedCore Platinum Desktop  
**Evaluation Target:** Official Run #12 Windows Release Artifact  
**Repository:** `kjemy/Medcore-Platinum-desktop-`  
**Evaluated Commit SHA:** `3986088dfe67484185d348f9a16028b8a362cb9f`  
**GitHub Actions Run ID:** `41053207903`  
**Target Artifact File:** `medcore-platinum-windows-main-self-contained-eval-3986088.zip`  
**Target Artifact SHA-256:** `778858EFC43B60099319CF087133DB7C9A2645D960D5C9B68A55BF206B7A4E4A`  
**Date:** October 30, 2026  
**Governance:** Khaled Universal Engineering Constitution (Gates 0 - 14)  
**Execution Mode:** MAIN AGENT ONLY — Pure Adversarial Acceptance (Zero Product Code Modification)  

---

## 1. EXECUTIVE SUMMARY & VERDICT

In accordance with the mandatory rules of Run #13:
- **Zero product code modifications** were made.
- **Zero builds, commits, pushes, or deployments** were executed.
- The evaluation was conducted directly against the physical Windows host using the downloaded, cryptographic Run #12 artifact.

### Verdict:
```text
================================================================================
FINAL DECISION: RELEASE_CANDIDATE — BLOCKED
REASON: Fatal Runtime Type Cast Crash in medcore_local_service.exe (server.dart:99)
STATUS: UNFIT FOR HOSPITAL PRODUCTION DEPLOYMENT
================================================================================
```

While the **bundling of MariaDB 11.4 LTS**, **loopback port isolation (3307)**, **dynamic relocation across drives/paths**, **GPLv2 license compliance**, and **static credential hygiene** all passed with empirical proof, the live execution of `medcore_local_service.exe` encountered a **fatal unhandled exception at line 99 of `server.dart`**, crashing the backend service immediately upon startup.

As a result, Local Service port `8443` never enters `HEALTHY` status, the launcher aborts at Stage 9, and the hospital desktop application cannot operate.

---

## 2. BLOCKING DEFECT SPECIFICATION

### 2.1 Defect Identity
- **Subsystem:** MedCore Local Backend Service
- **Source File:** `medcore_local_service/bin/server.dart`
- **Source Line:** Line 99
- **Compiled Binary:** `service/medcore_local_service.exe`
- **Introduced In Commit:** `cfffe81201022ba04709324f3ebf737308810f2f` (`feat(security): Technician Credential Lifecycle...`)

### 2.2 Observed Crash Trace
Upon launching `start_medcore_system.bat` on a clean site (`C:\MedCore Test Site A`), the MariaDB data directory was initialized, the MariaDB daemon started on `127.0.0.1:3307`, authenticated DB connection succeeded, and all 17 migrations were verified.

Immediately following migration verification, `medcore_local_service.exe` crashed with exit code `255`:

```text
[MedCore Local Service] Applying migrations from C:\MedCore Test Site A\service\sql\migrations to medcore_local...
[MedCore Local Service] Applied/Verified 17 migrations.

Unhandled exception:
type 'String' is not a subtype of type 'num?' in type cast
#0      main (file:///d:/a/medcore-platinum-desktop-/medcore-platinum-desktop-/medcore_local_service/bin/server.dart:99)
<asynchronous suspension>
```

### 2.3 Root Cause Analysis
In `medcore_local_service/bin/server.dart`:
```dart
96:   // Ensure baseline tenant is provisioned if fresh installation
97:   final tenantResult = await db.execute('SELECT COUNT(*) as cnt FROM mc_tenants');
98:   final tenantCnt = tenantResult.rows.isNotEmpty
99:       ? (tenantResult.rows.first.assoc()['cnt'] as num?)?.toInt() ?? 0
100:       : 0;
101:   if (tenantCnt == 0) {
102:     stdout.writeln('[MedCore Local Service] Seeding baseline tenant and device configuration for HOSP_MAIN...');
103:     await server.databaseLifecycleService.seedBaselineSystemDataForTesting('HOSP_MAIN');
104:   }
```

1. **Protocol Reality:** Under the MySQL/MariaDB wire protocol and the `mysql_client` Dart package, aggregate expressions like `COUNT(*)` are returned in `row.assoc()` as a **`String`** (`'0'`), not a native Dart `num` or `int`.
2. **Type System Enforcement:** Dart's strong mode strictly rejects casting a `String` to `num?` via `as num?`. The expression `( '0' as num? )` throws `TypeError: type 'String' is not a subtype of type 'num?' in type cast`.
3. **Operational Consequence:** Because this statement executes prior to `server.start(address: '127.0.0.1', port: port)`, the server process terminates instantly. HTTP port `8443` is never bound. `start_medcore_system.bat` times out polling `/api/v1/health` and aborts at Stage 9.

### 2.4 Why Automated Batch Tests Passed While the Packaged Artifact Failed
- In `batch17_bundled_mariadb_self_contained_offline_test.dart`, `LocalMedCoreServer` was instantiated and started directly via its class API (`server.start()`).
- The automated test suite instantiated `LocalMedCoreServer` without executing the standalone CLI entrypoint `main()` in `bin/server.dart`.
- The defective type cast was located solely in the binary entrypoint script `bin/server.dart:99`.
- This confirms **Khaled Principle 1: ACCEPTANCE SUPREMACY** ("Passing tests prove only what they assert, not the absence of unmodeled flaws") and **Principle 10: PASS != ACCEPTANCE**.

---

## 3. REAL-WORLD ACCEPTANCE GATE MATRIX

| Gate ID | Acceptance Gate | Result | Observable Evidence |
|:---:|---|:---:|---|
| **GATE-01** | **Artifact Identity** | **PASS** | ZIP SHA-256 `778858EFC43B60099319CF087133DB7C9A2645D960D5C9B68A55BF206B7A4E4A` matches Run #12. Inner zip `7DE2C798...` matches `release_manifest.json`. |
| **GATE-02** | **Fresh Machine Verification** | **PASS** | Host confirmed free of active MariaDB/MySQL dependencies; ports `3306`, `3307`, and `8443` free prior to test. |
| **GATE-03** | **No Host DB Dependency** | **PASS** | Package executes bundled `service/mariadb/bin/mariadbd.exe` (11.4.4 LTS Win64); no external DBMS accessed. |
| **GATE-04** | **MariaDB 127.0.0.1:3307** | **PASS** | `my.ini` generated with `bind-address=127.0.0.1` and `port=3307`. Daemon listened exclusively on loopback. |
| **GATE-05** | **Relocation & Path Robustness** | **PASS** | Package extracted and tested on `C:\MedCore Test Site A` and `D:\Hospital Apps\MedCore Platinum (Site B)` (spaces and parentheses supported). Dynamic relative path resolution verified. |
| **GATE-06** | **Credential Security Audit** | **PASS** | Zero embedded private keys, zero hardcoded JWTs, zero universal backdoor passwords. `runtime/security` is empty in fresh distribution. |
| **GATE-07** | **Technician First-Run Generation** | **PASS** | Fresh boot generated `FIRST_RUN_COMMISSIONING_SECRET.txt` and `technician_secret.json` in `service/runtime/security`. |
| **GATE-08** | **License Forensic Inventory** | **PASS** | Verified 83 bundled binaries/DLLs. GPLv2 `COPYING`, `CREDITS`, `README.md`, and `THIRDPARTY` notices included in `service/mariadb/licenses/`. |
| **GATE-09** | **Fail-Closed Basic Test** | **PASS** | Missing server binary triggered clean fail-closed abort at Stage 6 with zero misleading `READY` indicators. |
| **GATE-10** | **Local Service Daemon Launch** | **FAIL** | `medcore_local_service.exe` crashed with exit code 255 at `server.dart:99` (`String is not a subtype of num?`). Port `8443` never bound. |
| **GATE-11** | **Offline Internet-Disabled Operation** | **BLOCKED** | Blocked by Gate 10. (Service could not remain running). |
| **GATE-12** | **Database Persistence E2E** | **BLOCKED** | Blocked by Gate 10. (Schema initialized and migrations applied, but desktop/service unavailable for write/read). |
| **GATE-13** | **Backup Functionality** | **BLOCKED** | Blocked by Gate 10. |
| **GATE-14** | **Backup Restore & Integrity** | **BLOCKED** | Blocked by Gate 10. |
| **GATE-15** | **Technician Credential Lifecycle** | **BLOCKED** | Blocked by Gate 10. (Slip generated, but login gate unreachable). |
| **GATE-16** | **Factory Reset Safety** | **BLOCKED** | Blocked by Gate 10. |
| **GATE-17** | **Clean Shutdown / Restart** | **BLOCKED** | Blocked by Gate 10. |

---

## 4. CREDENTIAL FORENSIC AUDIT SUMMARY

Audited Artifact: `medcore-platinum-windows-main-self-contained-eval-3986088.zip`

| Category | Search Target | Status | Location / Details |
|---|---|:---:|---|
| **Private Keys** | `*.key`, `*.pem`, `*.pfx`, `BEGIN RSA PRIVATE KEY` | **NOT FOUND** | 0 occurrences across all text and binary resources. |
| **Static JWTs** | `eyJ...` bearer tokens | **NOT FOUND** | 0 occurrences. |
| **Hardcoded API Keys** | `api_key = "..."` | **NOT FOUND** | 0 occurrences. |
| **Universal Passwords** | `universal_password`, `master_password`, `backdoor` | **NOT FOUND** | 0 occurrences. |
| **Static Commissioning Secrets** | Hardcoded 32-char setup slips | **NOT FOUND** | Dynamically generated on first run. |
| **Pre-populated Security Cache** | `runtime/security` files in package | **NOT FOUND** | Directory is empty in fresh package (0 files). |
| **Database Root Password** | Configurable fallback in scripts | **CONFIGURABLE** | Defaults to `MedCoreLocalDb#2026` if `MEDCORE_DB_PASSWORD` env var not supplied. |

---

## 5. LICENSE FORENSIC INVENTORY

A complete inventory of the 83 executable and dynamic library files in the distribution was conducted:

| Subsystem | Component Count | Governing License | Compliance Notice File | Status |
|---|:---:|---|---|:---:|
| **MedCore Desktop Client** | 2 (`medcore_desktop.exe`, `flutter_windows.dll`) | Proprietary / BSD 3-Clause (Flutter Engine) | Embedded in client binary & Flutter release notices | `COMPLIANT` |
| **MedCore Local Service** | 2 (`medcore_local_service.exe`, `medcore_commission.exe`) | Proprietary / BSD 3-Clause (Dart SDK) | Embedded Dart runtime notices | `COMPLIANT` |
| **MariaDB Community Server** | 79 binaries (`mariadbd.exe`, `mariadb.exe`, storage engine DLLs, auth plugins) | GNU General Public License v2 (GPLv2) / LGPLv2.1 (`libmariadb.dll`) | `service/mariadb/licenses/COPYING`, `CREDITS`, `README.md`, `THIRDPARTY` | `COMPLIANT` |

---

## 6. MARIADB VERSION STATUS & PATCH LEVEL DECISION

1. **Current Bundled Version:** `11.4.4-MariaDB` Win64 (`mariadbd.exe` SHA-256: `92DA590AC33516F0B95494325C143A5918C7BA3B3E081B467CF80B1A7370E693`).
2. **Release Channel:** MariaDB 11.4 LTS (supported through May 2029).
3. **Upstream Status:**
   - MariaDB 11.4.4 was released on October 30, 2024.
   - MariaDB 11.4.5 was released in February 2025.
4. **Decision:**
   - **DO NOT UPGRADE in this run.**
   - Upstream 11.4.4 is fully functional, binds securely to `127.0.0.1:3307`, and successfully executes all 17 migrations.
   - MariaDB 11.4.5 patch upgrade can be scheduled as a normal maintenance release once the local service startup crash is resolved.

---

## 7. STARTUP & PERFORMANCE TIMINGS (SITE A OBSERVATION)

| Lifecycle Stage | Measured Duration | Status |
|---|:---:|:---:|
| **Stage 1 (Package Root Resolution)** | < 10 ms | Verified |
| **Stage 2-4 (Binary & Directory Verification)** | < 50 ms | Verified |
| **Stage 5-6 (MariaDB Tablespace Init & Daemon Startup)** | 14,200 ms | Verified (Tablespace initialized from scratch) |
| **Stage 7 (Authenticated MariaDB Health Probe)** | 350 ms | Verified (`SELECT 1` on 3307) |
| **Stage 8 (Service Daemon Launch & Migrations V001..V017)** | 1,800 ms | Verified (17 migrations applied in 1.8s) |
| **Stage 9 (Local Service Health Probe)** | 25,000 ms (Timeout) | **FAILED (Service crashed at line 99)** |

---

## 8. REQUIRED RESOLUTION FOR RUN #14

In strict adherence to the **"DO NOT MODIFY PRODUCT CODE"** instruction of Run #13, this defect was not patched during this run.

For the next iteration (**Run #14**), the required fix is:

In `medcore_local_service/bin/server.dart` (around line 99):
```dart
// Change from:
final tenantCnt = tenantResult.rows.isNotEmpty
    ? (tenantResult.rows.first.assoc()['cnt'] as num?)?.toInt() ?? 0
    : 0;

// To safe type parsing:
final rawCnt = tenantResult.rows.isNotEmpty ? tenantResult.rows.first.assoc()['cnt'] : null;
final tenantCnt = rawCnt is num 
    ? rawCnt.toInt() 
    : int.tryParse(rawCnt?.toString() ?? '') ?? 0;
```

Once this single-line type-safe parsing is applied:
1. `medcore_local_service.exe` will proceed to line 106 (`server.start(address: '127.0.0.1', port: port)`).
2. Port `8443` will report `HEALTHY`.
3. Launcher Stage 9 will succeed, and MedCore Desktop Client will open for complete hospital workflow acceptance.

---

## 9. CONCLUSION

Run #12 successfully produced a structurally self-contained Windows package containing MariaDB 11.4 LTS and complete schema migrations.

However, real-world deployment acceptance on Run #13 **must reject this candidate** due to the fatal startup crash in `medcore_local_service.exe`.

**Final Status:** `RELEASE_CANDIDATE — BLOCKED`

<!-- GOAL_COMPLETE -->
