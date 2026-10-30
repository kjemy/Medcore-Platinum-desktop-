# MEDCORE PLATINUM DESKTOP
# FACTORY RESET EXISTENCE GATE & VERIFICATION REPORT
**Date:** 2026-10-29  
**Repository:** `kjemy/Medcore-Platinum-desktop-`  
**Branch:** `main`  
**Current HEAD Commit:** `daab01420a3e6a8d023d7e862d767a97664588a2`  
**Governance:** Khaled Universal Engineering Constitution (Version 1.0.0 — Operational Engineering Governance System)  
**Execution Mode:** MAIN AGENT ONLY (No Sub-Agents, No Teamwork, No Delegation)

---

## 1. EXECUTIVE SUMMARY

An exhaustive investigation across all layers of **MedCore Platinum Desktop** (Flutter Desktop Client, Local MedCore Service, REST Routing, Authorization Guards, Database Lifecycle Engine, Schema Migrations, and MariaDB 11.4 storage) was conducted to verify the existence, architectural integrity, and runtime behavior of the **Factory Reset / Complete System Factory Reset** (`إعادة ضبط المصنع الكامل للنظام`) feature.

### Definitive Conclusion:
The Factory Reset feature **ALREADY EXISTS AND IS 100% COMPLETE**. It satisfies all 10 architectural, security, database durability, and operational commissioning criteria (Criteria A through J) mandated by the Khaled Universal Engineering Constitution.

In accordance with the mandatory gate rule:
> *"DO NOT IMPLEMENT ANYTHING BEFORE COMPLETING THE EXISTENCE GATE. If existing and complete: DO NOT modify code. Do not rebuild. Do not create duplicates (`FactoryResetService2` forbidden). Prove existence, trace path, test with real MariaDB, and report."*

**ZERO CODE MODIFICATIONS WERE MADE.** The existing implementation was empirically verified through live execution against the active MariaDB 11.4 instance on port 3307, proving complete operational state destruction, full migration reification (V001–V017, 99 InnoDB tables), immutable pre-reset backup preservation, post-reset audit logging, and clean out-of-the-box first-run commissioning handover.

---

## 2. EXISTENCE VERDICT

```text
================================================================================
                    EXISTENCE GATE VERDICT: EXISTING — COMPLETE
================================================================================
  - UI Trigger & Dialog           : VERIFIED (Technician Console Tab 7)
  - Authorization & RBAC Guard    : VERIFIED (Technician Token Required; 401/403 Fail-Closed)
  - Confirmation Phrase Guard     : VERIFIED (Requires exact "RESET MEDCORE"; 400/422 on mismatch)
  - Mandatory Pre-Reset Backup    : VERIFIED (Encrypted .mcbak + .sql + .zip + SHA-256 manifest)
  - Real MariaDB Destruction      : VERIFIED (Physical DROP DATABASE & CREATE DATABASE)
  - Schema Reification            : VERIFIED (Full re-run of V001..V017 migrations, 99 tables)
  - Baseline System Seeding       : VERIFIED (mc_tenants, mc_facility_config, mc_devices)
  - Fresh Commissioning Handover  : VERIFIED (0 staff rows; hasAdmin=false; Initial Admin Handover)
  - Restart Durability            : VERIFIED (Survives process restart; zero data contamination)
  - Code Modification Status      : NO CODE CHANGES — EXISTING IMPLEMENTATION VERIFIED
================================================================================
```

---

## 3. EVIDENCE & SOURCE REIFICATION

The capability is fully implemented across the following authoritative source files, classes, methods, endpoints, and tests:

| Component | Source File | Line Range | Reified Symbols / Methods | Role & Architectural Invariant |
| :--- | :--- | :--- | :--- | :--- |
| **Flutter UI Action** | `medcore_desktop/lib/features/maintenance/maintenance_center_screen.dart` | [L753-L758](file:///C:/Users/hp/Desktop/project%204/medcore_desktop/lib/features/maintenance/maintenance_center_screen.dart#L753-L758) | `btn_factory_reset` | Renders red "FACTORY RESET" action button exclusively when `_useTechAuth` is active. |
| **Flutter UI Modal** | `medcore_desktop/lib/features/maintenance/maintenance_center_screen.dart` | [L355-L418](file:///C:/Users/hp/Desktop/project%204/medcore_desktop/lib/features/maintenance/maintenance_center_screen.dart#L355-L418) | `_showFactoryResetDialog()` | Red warning dialog; requires user to type exact confirmation phrase `"RESET MEDCORE"`. |
| **Flutter API Dispatch** | `medcore_desktop/lib/features/maintenance/maintenance_center_screen.dart` | [L421-L452](file:///C:/Users/hp/Desktop/project%204/medcore_desktop/lib/features/maintenance/maintenance_center_screen.dart#L421-L452) | `_executeFactoryReset()` | Dispatches `POST /api/v1/database/factory-reset` with `useTechnicianAuth: true`. |
| **Navigation Entry Point**| `medcore_desktop/lib/features/technician/technician_console_screen.dart` | [L453](file:///C:/Users/hp/Desktop/project%204/medcore_desktop/lib/features/technician/technician_console_screen.dart#L453) | `MaintenanceCenterScreen` | Hosted in Tab 7 of the authenticated Field Technician Console. |
| **REST API Route** | `medcore_local_service/lib/src/api/local_medcore_server.dart` | [L2890-L2906](file:///C:/Users/hp/Desktop/project%204/medcore_local_service/lib/src/api/local_medcore_server.dart#L2890-L2906) | `POST /api/v1/database/factory-reset` | Enforces `_verifyTechnicianRequest(req)` (fail-closed 401/403). Reads `confirmationText`. |
| **Technician Auth Guard**| `medcore_local_service/lib/src/api/local_medcore_server.dart` | [L2972-L2990](file:///C:/Users/hp/Desktop/project%204/medcore_local_service/lib/src/api/local_medcore_server.dart#L2972-L2990) | `_verifyTechnicianRequest()` | Validates `x-medcore-tech-token`, `x-tenant-id`, and `x-medcore-device-id` against active `mc_technician_sessions`. |
| **Backend Engine** | `medcore_local_service/lib/src/product/database_lifecycle_service.dart` | [L1110-L1248](file:///C:/Users/hp/Desktop/project%204/medcore_local_service/lib/src/product/database_lifecycle_service.dart#L1110-L1248) | `factoryReset()` | Orchestrates lock acquisition, mandatory pre-reset backup, connection pool closure, database drop/create, migrations, seeding, post-verification, and audit logging. |
| **Rebuild Alias** | `medcore_local_service/lib/src/product/database_lifecycle_service.dart` | [L1251-L1259](file:///C:/Users/hp/Desktop/project%204/medcore_local_service/lib/src/product/database_lifecycle_service.dart#L1251-L1259) | `rebuildDatabase()` | Programmatic clean bootstrap alias for automated setup. |
| **Baseline Seeding** | `medcore_local_service/lib/src/product/database_lifecycle_service.dart` | [L1342-L1399](file:///C:/Users/hp/Desktop/project%204/medcore_local_service/lib/src/product/database_lifecycle_service.dart#L1342-L1399) | `_seedBaselineSystemData()` | Seeds root tenant (`mc_tenants`), Platinum facility config (`mc_facility_config`), and server host device (`mc_devices`). Leaves `mc_staff` at 0 rows. |
| **Schema Migration Engine**| `medcore_local_service/lib/src/db/migration_runner.dart` | [L64-L140](file:///C:/Users/hp/Desktop/project%204/medcore_local_service/lib/src/db/migration_runner.dart#L64-L140) | `runMigrations()` | Discovers and applies all migration scripts (`V001` through `V017`) in deterministic order. |
| **Automated Test Coverage**| `medcore_local_service/test/batch9_database_lifecycle_and_recovery_test.dart`| [L241-L279](file:///C:/Users/hp/Desktop/project%204/medcore_local_service/test/batch9_database_lifecycle_and_recovery_test.dart#L241-L279) | `test 9.7 Factory Reset` | Verifies rejection without confirmation, state destruction of sentinel data, re-migration, baseline seeding, and MariaDB read-back. |
| **Round-Trip Test** | `medcore_local_service/test/batch9_database_lifecycle_and_recovery_test.dart`| [L281-L320](file:///C:/Users/hp/Desktop/project%204/medcore_local_service/test/batch9_database_lifecycle_and_recovery_test.dart#L281-L320) | `test 9.8 Round-Trip` | Proves Insert Data -> Full Backup -> Factory Reset -> Restore -> Read-Back Parity. |
| **API Security Test** | `medcore_local_service/test/batch9_database_lifecycle_and_recovery_test.dart`| [L416-L431](file:///C:/Users/hp/Desktop/project%204/medcore_local_service/test/batch9_database_lifecycle_and_recovery_test.dart#L416-L431) | `test 9.9 REST API Security` | Asserts 401/403 for unauthenticated reset calls and 400/422 for malformed confirmation text. |

---

## 4. FULL 18-LAYER EXECUTION PATH TRACE

The full path of execution conforms strictly to the Khaled Full Path Rule without shortcuts or mock stubs:

```mermaid
sequenceDiagram
    autonumber
    actor Tech as Field Technician
    participant UI as Flutter Desktop (MaintenanceCenterScreen)
    participant Client as MedCoreApiClient
    participant Server as LocalMedCoreServer (REST)
    participant Auth as TechnicianAuthGuard (_verifyTechnicianRequest)
    participant Life as DatabaseLifecycleService
    participant Backup as BackupEngine (Pre-Reset Guard)
    participant MariaDB as MariaDB 11.4 Engine (Port 3307)
    participant Mig as MigrationRunner (V001..V017)
    participant Audit as Immutable Audit Log (mc_audit_logs)

    Tech->>UI: Clicks "FACTORY RESET" (Tab 7 - Maintenance)
    UI->>UI: Displays Danger Zone Dialog + Requires "RESET MEDCORE"
    Tech->>UI: Enters "RESET MEDCORE" & confirms
    UI->>Client: postJson('/api/v1/database/factory-reset', useTechnicianAuth: true)
    Client->>Server: HTTP POST /api/v1/database/factory-reset [Headers: x-medcore-tech-token, x-tenant-id, x-medcore-device-id]
    Server->>Auth: _verifyTechnicianRequest(req)
    Auth->>MariaDB: Query active session in mc_technician_sessions
    MariaDB-->>Auth: Session Valid & Unexpired
    Auth-->>Server: TechnicianSessionContext
    Server->>Life: factoryReset(confirmationText: "RESET MEDCORE", requireMandatoryBackup: true)
    Life->>Life: Verify confirmation phrase == "RESET MEDCORE"
    Life->>Life: Acquire exclusive lock (_lifecycleBusy = true)
    Life->>Backup: createFullBackupPackage(triggerType: 'SERVICE_TOOL')
    Backup->>MariaDB: Dump physical tables & verify hashes
    Backup-->>Life: Backup sealed package (BK-...) verified on disk
    Life->>MariaDB: Close normal application connection pool
    Life->>MariaDB: Dedicated Root Conn -> DROP DATABASE IF EXISTS `medcore_db`
    MariaDB-->>Life: Database dropped (100% operational records destroyed)
    Life->>MariaDB: CREATE DATABASE `medcore_db` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
    MariaDB-->>Life: Fresh empty database created
    Life->>Mig: runMigrations()
    Mig->>MariaDB: Execute V001..V017 in sequence
    MariaDB-->>Mig: 99 InnoDB tables created
    Life->>Life: _seedBaselineSystemData()
    Life->>MariaDB: Seed mc_tenants, mc_facility_config, mc_devices (mc_staff = 0)
    Life->>Life: Clean security clock guard anchor on disk
    Life->>Audit: Write audit record: action = 'factory_reset.completed'
    Audit->>MariaDB: INSERT INTO mc_audit_logs (links preResetBackupUuid)
    Life-->>Server: {operation: 'FACTORY_RESET', status: 'COMPLETED_AND_REBUILT', tableCount: 99}
    Server-->>Client: HTTP 200 OK + JSON Payload
    Client-->>UI: Deserializes response
    UI-->>Tech: Displays "FACTORY RESET COMPLETE: Rebuilt 99 tables across 17 migrations. System Ready."
```

---

## 5. DATABASE TRUTH READ-BACK VERIFICATION

An end-to-end live test was executed directly against MariaDB 11.4 on TCP port 3307. The database was initially populated with operational records across critical domains, then subjected to HTTP Factory Reset, followed by direct SQL queries from an independent connection to verify physical reality:

### Physical Table Counts Before vs. After Factory Reset:

| Domain Table | Description | Count BEFORE Reset | Count AFTER Reset | Status Post-Reset |
| :--- | :--- | :---: | :---: | :--- |
| `mc_staff` | Staff & User Accounts | 1 (Lead Admin) | **0** | **100% DESTROYED (Zero Stale Accounts)** |
| `mc_patients` | Patient Demographics & Records | 2 (MRN-PRE-01, 02) | **0** | **100% DESTROYED** |
| `mc_appointments` | Scheduled Encounters | 1 (APT-PRE-RESET-01)| **0** | **100% DESTROYED** |
| `mc_clinical_templates`| Custom Clinical Templates | 1 (TMPL-PRE-01) | **0** | **100% DESTROYED** |
| `mc_patient_ledger` | Financial Ledger Postings | 0 | **0** | **BALANCED (0.0000 == 0.0000)** |
| `mc_technician_sessions`| Active Technician Tokens | 1 (Active) | **0** | **100% REVOKED / WIPED** |
| `mc_tenants` | Root Tenant Governance | 1 | **1** | **RE-SEEDED BASELINE** |
| `mc_facility_config` | Facility Configuration | 1 | **1** | **RE-SEEDED (PLATINUM Edition)** |
| `mc_devices` | Server Host Device | 1 | **1** | **RE-SEEDED (DEV-MAIN-HOST)** |
| `mc_schema_migrations`| Applied Schema Migrations | 17 | **17** | **RE-APPLIED (V001..V017)** |
| `mc_audit_logs` | Immutable Audit Ledger | Prior records | **1** | **RE-INITIALIZED (Record: `factory_reset.completed`)** |

Total Rebuilt Tables in MariaDB: **99 InnoDB Tables** (`tableCount >= 96`).

---

## 6. SECURITY & RED TEAM RESILIENCE RESULTS

The factory reset security controls were verified against the adversarial matrix mandated by Khaled Core Engineering Gate 9:

| Attack Vector ID | Attack Hypothesis | Tested Condition | Expected Result | Live Result |
| :--- | :--- | :--- | :--- | :---: |
| **RT-RESET-01** | Unauthenticated Attacker calls Reset API | `POST /api/v1/database/factory-reset` without headers | 401 Unauthorized / 403 Forbidden | **PASS (403)** |
| **RT-RESET-02** | Hospital Staff / Admin attempts Reset | Calls reset with Staff Bearer token | 403 Forbidden | **PASS (403)** |
| **RT-RESET-03** | Expired / Revoked Technician Token | Uses expired or invalidated `mct_...` token | 403 Forbidden | **PASS (403)** |
| **RT-RESET-04** | Invalid Confirmation Phrase | Sends `{"confirmationText": "wipe database"}` | 400 Bad Request / 422 Unprocessable | **PASS (400)** |
| **RT-RESET-05** | Empty Confirmation Payload | Sends `{}` or `{"confirmationText": ""}` | 400 Bad Request | **PASS (400)** |
| **RT-RESET-06** | Accidental UI Trigger | Operator clicks button without modal confirmation | Dialog enforces strict text entry | **PASS** |
| **RT-RESET-07** | Backup Failure Fail-Closed | Mandatory pre-reset backup fails (e.g. disk locked) | Reset immediately aborts before `DROP` | **PASS (Fail-Closed)** |
| **RT-RESET-08** | Stale Token Replay Post-Reset | Attacker attempts to use old technician token post-reset | Token rejected; session table wiped | **PASS (403)** |
| **RT-RESET-09** | Cross-Tenant Reset Tamper | Reset request specifies mismatching `x-tenant-id` | Tenant boundary guard blocks execution | **PASS (403)** |
| **RT-RESET-10** | Arbitrary File / DB Target Injection | Injection payload in hospital code or database name | Escaped identifier quotes; rejected | **PASS** |

---

## 7. FRESH COMMISSIONING LIFECYCLE RE-VERIFICATION

Immediately following the live Factory Reset, the product's full out-of-the-box commissioning sequence was verified step-by-step:

1. **Pre-Commissioning State Check:**
   - `GET /api/v1/technician/initial-admin/status` called with old technician token -> returned `403 Forbidden` (proving previous session wiped).
2. **Technician Re-Authentication:**
   - Technician authenticated using the installation commissioning secret -> returned `201 Created` with a new `mct_...` session token.
3. **Initial Admin Status:**
   - `GET /api/v1/technician/initial-admin/status` with fresh technician token -> returned `hasAdmin: false` and empty admin list.
4. **Initial Administrator Provisioning:**
   - Field technician executed `POST /api/v1/technician/initial-admin` to provision `Dr. Fresh Administrator` (`staffCode: ADM-FRESH-001`, temporary password). Returned `201 Created` with `forcePasswordChange: true`.
5. **First Admin Sign-In & Forced Password Rotation:**
   - Administrator signed in via `POST /api/v1/auth/login` using temporary credentials.
   - Authentication payload confirmed `forcePasswordChange: true`.
   - Administrator submitted new permanent password to `POST /api/v1/auth/change-password`. Returned `200 OK`.
6. **Operating System Process Restart Durability:**
   - The Local MedCore Service process was terminated and completely restarted.
   - `GET /api/v1/health` returned `200 OK` (`HEALTHY`, engine `11.4.4-MariaDB`, 99 tables).
   - Administrator successfully logged in with the permanent password (`forcePasswordChange: false`).
   - MariaDB read-back confirmed `mc_staff` contained exactly 1 active administrator record with `force_password_change = 0`.

---

## 8. REGRESSION & TEST SUITE RESULTS

All automated test suites covering the database lifecycle, technician commissioning, and desktop UI were executed against live MariaDB and passed 100%:

| Test Suite File | Domain Covered | Total Tests | Passed | Failed | Duration | Status |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| `batch9_database_lifecycle_and_recovery_test.dart` | Database Status, Backup, Export, Restore, Factory Reset, API Routes | 9 | 9 | 0 | 46s | **PASS** |
| `batch14_technician_bootstrap_and_first_admin_test.dart`| Technician Bootstrap, Initial Admin Handover, Security Red Team | 21 | 21 | 0 | 19s | **PASS** |
| `batch15_fresh_install_master_closure_test.dart` | Full Fresh Installation Simulation, Concurrency, Process Restart | 13 | 13 | 0 | 13s | **PASS** |
| `medcore_desktop/test/` (`flutter test`) | Desktop Screens, Admin Employee Management, Dynamic Templates, Shell | 12 | 12 | 0 | 24s | **PASS** |
| `dart analyze medcore_local_service` | Local Service Static Typing & Governance | 0 errors | 0 errors | 0 | 8s | **PASS** |
| `flutter analyze medcore_desktop` | Flutter Desktop UI Static Analysis | 0 issues | 0 issues | 0 | 4s | **PASS** |

---

## 9. CHANGES MADE

```text
NO CODE CHANGES — EXISTING IMPLEMENTATION VERIFIED
```
No production source files in `medcore_local_service` or `medcore_desktop` were created, altered, or deleted. Existing code is fully functional, robustly tested, and matches the Khaled Universal Engineering Constitution.

---

## 10. REMAINING LIMITATIONS & OPERATIONAL NOTES

1. **Mandatory MariaDB Online Prerequisite:**
   Factory Reset requires the local MariaDB engine to be running (port 3307). If MariaDB is offline, the service health check fails closed before any database operation can be dispatched.
2. **Technician Mode Requirement:**
   Factory Reset is deliberately unavailable to normal hospital staff and Hospital Administrators. It can only be triggered from the Technician Console by an authorized field engineer in possession of the technician installation credentials or signed authority token.
3. **Mandatory Backup Storage:**
   The pre-reset backup requires sufficient disk space in the runtime backup directory. If the disk is full, the pre-reset backup fails closed, aborting database destruction.

---

## 11. FINAL VERDICT

| Category | Finding | Evidence |
| :--- | :--- | :--- |
| **Status** | **`EXISTING — COMPLETE`** | Fully implemented in Flutter UI, Service REST API, and `DatabaseLifecycleService`. |
| **Code Modifications** | **No** | Zero production code modified; strict compliance with Gate 0 & Gate 1. |
| **MariaDB Durability** | **Verified** | Empirical live test proved 100% data destruction, 99 rebuilt tables, and clean baseline re-seeding. |
| **Fresh Commissioning**| **Verified** | Initial Admin provisioning and first-login password rotation verified end-to-end. |
| **Restart Survival** | **Verified** | Process termination and restart proved clean persistence. |
