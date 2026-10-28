# MEDCORE PLATINUM DESKTOP
# DATABASE LIFECYCLE, BACKUP, EXPORT, RESTORE & FACTORY RESET
# GATE 0: READ-ONLY TRUTH AUDIT
**Document ID:** `MEDCORE-DB-LIFECYCLE-GATE0-20261028`  
**Execution Timestamp:** `2026-10-28T22:35:00Z`  
**Governance Authority:** Master Engineering Constitution (`@Khaled All Rules` Gates 0–14)  
**Execution Agent:** `MAIN AGENT ONLY` (Zero sub-agents, zero delegation, zero parallel agents)  
**Working Directory:** `C:\Users\hp\Desktop\project 4`  
**Target Capability:** Database Lifecycle + Backup + Export + Restore + Factory Reset + Rebuild + Verification + Release Completion  

---

## 1. RECONNAISSANCE & TRUTH HIERARCHY AUDIT

In accordance with Gate 0 rules, this audit is strictly **READ-ONLY**. No application source code has been altered during this reconnaissance.

### 1.1 Authoritative System State
- **Flutter Client:** `medcore_desktop` (Dart 3.4+, Flutter 3.x). Communicates strictly via HTTP REST to Local MedCore Service. `mysql_client` is verified ABSENT from Flutter (`dependencies` only include `http`, `decimal`, `crypto`, `cupertino_icons`).
- **Local Service Boundary:** `medcore_local_service` (Dart 3.0+). Built on `shelf` / `shelf_router`. Owns all business logic, RBAC evaluation, transactions, migrations, and database operations.
- **Authoritative Persistence:** MariaDB 11.4.4 running on `127.0.0.1:3307` (`runtime/mariadb_data`).
- **Schema Truth:** Exactly 16 versioned migrations (`V001` through `V016`) creating exactly 96 InnoDB tables (`utf8mb4_unicode_ci`).
- **Baseline Test Suite:** Exactly 124 / 124 tests passing (117 backend across 10 test files + 7 Flutter Desktop tests across 2 test files).

---

## 2. COMPREHENSIVE CAPABILITY CLASSIFICATION

Every required capability in the Database Lifecycle Program has been audited against physical files and runtime endpoints:

| Capability Domain | Sub-Capability | Current Status | Physical Source / Location | Audit Finding & Gap Description |
|---|---|---|---|---|
| **Database Status** | Storage & DB Telemetry | `PARTIAL` | `MaintenanceCenterService.getOverview()`, `local_medcore_server.dart:1514` | Exists within `/api/v1/maintenance/overview`. Lacks a dedicated, structured `/api/v1/database/status` contract returning storage engine, charset, collation, last backup run, last restore, and last reset metadata. |
| **Database Location** | Physical Paths Disclosure | `MISSING` | N/A | No endpoint or contract currently exposes runtime directory, MariaDB data directory, backup directory, and export directory safely to authorized technicians. |
| **Database Explorer** | Schema Introspection | `IMPLEMENTED` | `DataExplorerService.getDatabaseStructure()`, `local_medcore_server.dart:1264` | Fully introspects 96 tables, columns, types, keys, and foreign keys via `INFORMATION_SCHEMA`. |
| **Database Explorer** | Tenant Record Inspection | `IMPLEMENTED` | `DataExplorerService.queryTableRecords()`, `local_medcore_server.dart:1271` | Read-only browsing with tenant isolation and PII masking. |
| **Database Explorer** | Single Table CSV/TXT | `IMPLEMENTED` | `DataExplorerService.exportTableDataCsv()`, `local_medcore_server.dart:1303` | Exports individual table data to CSV/TXT. |
| **Database Explorer** | Desktop UI Explorer View | `MISSING` | `medcore_desktop` | Frontend lacks a dedicated visual Database Explorer screen / modal to inspect table metadata and trigger table exports. |
| **Backup Engine** | Architecture & Provider Interface | `IMPLEMENTED` | `BackupProvider`, `LocalStorageProvider`, `S3CompatibleProvider` | Clean vendor-neutral provider contract. S3 contract is validated with wire execution deferred (zero fake HTTP 200). |
| **Backup Engine** | Logical Dump Coverage | `PARTIAL` | `BackupEngineService._extractTenantLogicalSnapshot()` | Dumps only 11 clinical/financial tables. Fails to cover all 96 tables or complete database DDL schema required for true restorable state. |
| **Backup Engine** | Compression & Encryption | `IMPLEMENTED` | `BackupEngineService.executeBackup()` | GZip compression + HMAC-SHA256 authenticated keystream sealing implemented in pure Dart. |
| **Backup Engine** | Independent Disk Read-Back | `IMPLEMENTED` | `LocalStorageProvider.storeAndVerifyArchive()` | Flushes bytes to disk, immediately re-reads, calculates SHA-256, and verifies byte-for-byte equality before marking `VERIFIED`. |
| **Backup Engine** | Multi-file Backup Package | `MISSING` | `BackupEngineService` | Currently generates a single `.json.gz.mcbak` file. Lacks standardized multi-artifact package: `database.sql`, `database.json`, `database.xlsx`, `csv/`, `manifest.json`, `schema.json`, `checksums.sha256`, `README.txt`. |
| **Export Engine** | SQL Dump Export | `MISSING` | N/A | No complete SQL schema + data dump generator exists in the service. |
| **Export Engine** | CSV Multi-Table Export | `PARTIAL` | `DataExplorerService` | Supports single-table export only. Batch export of all tables into `csv/` folder does not exist. |
| **Export Engine** | JSON Structured Export | `PARTIAL` | `BackupEngineService` | Partial JSON dump for 11 tables exists; full database multi-table JSON export does not exist. |
| **Export Engine** | XLSX Excel Export | `MISSING` | N/A | No OpenXML XLSX workbook generator exists. |
| **Export Engine** | ZIP Export Package | `MISSING` | N/A | No multi-format ZIP packaging pipeline exists. |
| **Runtime File Copy** | Raw MariaDB File Copy | `MISSING` | N/A | No coordinated, safe technician operation exists to quiesce and archive runtime files. |
| **Backup Verification** | Archive Inspection | `IMPLEMENTED` | `BackupEngineService.verifyBackupArchiveForRestore()`, `/api/v1/backups/verify-restore` | Inspects archive, verifies SHA-256, checks against `mc_backup_runs`. |
| **Backup Verification** | Package Manifest & Schema Verification | `MISSING` | N/A | Does not verify multi-artifact manifest, table counts, or schema migration compatibility. |
| **Restore Engine** | Restore Execution | `MISSING` | N/A | Only verification exists (`verifyBackupArchiveForRestore`). Actual execution of restoring tables and records into MariaDB is NOT implemented. |
| **Factory Reset** | Destructive Database Reset | `MISSING` | N/A | No endpoint, service method, or UI flow exists to enforce mandatory backup, require "RESET MEDCORE", drop/recreate database, re-run migrations `V001..V016`, and seed system data. |
| **Fresh Bootstrap / Rebuild** | Automatic Bootstrap | `IMPLEMENTED` | `MigrationRunner.runMigrations()`, `DbClient.ensureDatabaseExists()` | Automatically creates database if missing and runs `V001..V016`. Needs formal lifecycle integration. |
| **Maintenance Center UX** | Database & Backup Operations | `PARTIAL` | `MaintenanceCenterScreen` in `medcore_desktop` | Displays maintenance telemetry and triggers backup run, but lacks dedicated Database Status card, Location folder openers, Database Explorer button, Multi-format Export buttons, Restore button, and Factory Reset Danger Zone. |
| **Technician Mode** | Protected Technician Authorization | `IMPLEMENTED` | `TechnicianService`, `X-MedCore-Tech-Token` | Dual authentication (RSA-2048 token or constant-time verified installation secret), monotonic clock evaluation, and audit logging fully working. |
| **Financial Conservation** | Double-Entry Balancing Check | `IMPLEMENTED` | `MaintenanceCenterService.getOverview()` | Real SQL assertion: `SUM(DEBIT) == SUM(CREDIT)` verified on `mc_financial_postings`. |
| **Audit Logging** | Lifecycle Audit Records | `PARTIAL` | `mc_audit_logs` | Logs backup runs and technician sessions. Needs formal audit actions for `backup.verified`, `export.created`, `restore.started`, `restore.completed`, `factory_reset.started`, `factory_reset.completed`. |

---

## 3. FACT / INFERENCE / ASSUMPTION / UNKNOWN RECONCILIATION

### FACT
1. MariaDB 11.4.4 is running locally on port 3307 with user `root` and password `MedCoreLocalDb#2026`.
2. `medcore_local_service` connects to MariaDB via `mysql_client` and has 16 migrations (`V001`–`V016`).
3. `medcore_desktop` has zero direct database connections and relies 100% on HTTP REST.
4. `BackupProvider` and `LocalStorageProvider` are already architected cleanly with SHA-256 read-back verification.
5. All 124 automated tests are currently green and passing against the live database.
6. Neither `Restore` execution nor `Factory Reset` execution exists in the codebase today.

### INFERENCE
1. The existing `BackupEngineService` can be extended into a complete `DatabaseLifecycleService` without breaking any existing endpoints or tests.
2. An OpenXML XLSX generator and ZIP packaging can be implemented in pure Dart, ensuring zero external C-runtime or DLL dependencies.
3. MariaDB can be safely quiesced or exported via SQL/JSON/CSV without locking active read operations for extended periods.

### ASSUMPTION
1. The technician operating the system has access to the local machine and local filesystem for viewing exported folders.
2. The local disk has adequate free storage space for backup archives and database recreation.

### UNKNOWN
- **None.** All critical paths, dependencies, ports, database schemas, and service contracts are physically verified.

---

## 4. GATE 0 VERDICT: PASS

**GATE 0 STATUS: PASS**  
- Zero unknown critical paths remain.
- Full capability matrix reified against physical code and live runtime.
- Foundation components identified for reuse: `LocalStorageProvider`, `DataExplorerService`, `MigrationRunner`, `TechnicianService`.
- Missing scopes strictly mapped: Full Database Dump, Multi-format Export (SQL/CSV/JSON/XLSX/ZIP), Runtime File Copy, Full Verification, Restore Engine, Factory Reset, Maintenance UI completion, and Golden Round-Trip test.

Proceeding immediately to **GATE 1: ARCHITECTURE & THREAT MODEL**.
