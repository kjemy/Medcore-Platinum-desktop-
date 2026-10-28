# MEDCORE PLATINUM DESKTOP
# DATABASE LIFECYCLE, BACKUP, EXPORT, RESTORE & FACTORY RESET
# GATE 1: ARCHITECTURE & THREAT MODEL SPECIFICATION
**Document ID:** `MEDCORE-DB-LIFECYCLE-GATE1-20261028`  
**Execution Timestamp:** `2026-10-28T22:36:00Z`  
**Governance Authority:** Master Engineering Constitution (`@Khaled All Rules` Gates 0–14)  
**Execution Agent:** `MAIN AGENT ONLY`  
**Working Directory:** `C:\Users\hp\Desktop\project 4`  

---

## 1. AUTHORITATIVE LIFECYCLE ARCHITECTURE

### 1.1 Architectural Boundary Principles
1. **Three-Tier Isolation:**
   ```
   [ Flutter Windows Desktop ]
              ↓  HTTP REST (Bearer Staff Token or X-MedCore-Tech-Token)
   [ Local MedCore Service ]
              ↓  TCP Loopback (127.0.0.1:3307, utf8mb4, Strict Trans Tables)
   [ MariaDB 11.4.x Engine ]
              ↓  Direct OS File IO
   [ Authoritative Storage: C:\Users\hp\Desktop\project 4\runtime\mariadb_data ]
   ```
2. **Absolute Invariant:** Flutter NEVER connects directly to MariaDB. `mysql_client` is forbidden in Flutter.
3. **Local MedCore Service** is the sole authoritative gatekeeper for database operations, migrations, backups, exports, restores, factory resets, and audit trails.

---

### 1.2 Authoritative Lifecycle Sequence Models

#### Flow 1: Full Restorable Backup & Multi-Format Export
```
Flutter Client / Technician Console
    │
    ▼ (POST /api/v1/backups/full-package or POST /api/v1/database/export)
Local MedCore Service
    │
    ├── 1. Authenticate Technician or High-Privilege Staff (settings_Backups + canEdit)
    ├── 2. Quiesce / Coordinate Writes (Exclusive Lifecycle Mutex in Service)
    ├── 3. Extract Full Logical Database Dump:
    │      - DDL Schema (CREATE TABLE definitions for all 96 tables)
    │      - Table Data (SELECT * from all tables in dependency-safe order)
    │      - Foreign Key Constraints & Indexes
    │      - Schema Migrations History (mc_schema_migrations)
    ├── 4. Generate Artifacts in Staging Directory:
    │      ├── database.sql        (Standard MySQL/MariaDB DDL + INSERT statements)
    │      ├── database.json       (Structured JSON with metadata, schema, and rows)
    │      ├── database.xlsx       (Multi-sheet OpenXML workbook for human inspection)
    │      ├── csv/                (Individual UTF-8 RFC 4180 CSV files per table)
    │      ├── manifest.json       (Table inventory, row counts, SHA-256 hashes, versions)
    │      ├── schema.json         (Structured DDL and column metadata)
    │      ├── checksums.sha256    (Cryptographic hashes of every artifact)
    │      └── README.txt          (Restoration instructions & environment metadata)
    ├── 5. Generate Encrypted Restorable Archive (.mcbak):
    │      - GZip compression of full logical dump
    │      - Authenticated keystream sealing (HMAC-SHA256) when encryption key provisioned
    │      - Compute SHA-256 digest
    ├── 6. Package ZIP Archive (when export requested):
    │      - Zip all artifacts into single downloadable package
    ├── 7. Independent Physical Read-Back:
    │      - Read all generated files from disk
    │      - Re-compute SHA-256 digests and compare with manifest
    ├── 8. Persist Record into mc_backup_runs (Status: VERIFIED)
    └── 9. Write Immutable Audit Log (action: backup.package.created, backup.verified)
```

#### Flow 2: Safe Database Restore
```
Technician Console
    │
    ▼ (POST /api/v1/database/restore)
Local MedCore Service
    │
    ├── 1. Authenticate Technician Mode (X-MedCore-Tech-Token REQUIRED)
    ├── 2. Inspect & Pre-flight Validate Archive:
    │      - Verify archive file existence and file size > 0
    │      - Verify SHA-256 checksum matches recorded/provided hash
    │      - Decrypt envelope header and verify HMAC-SHA256 integrity
    │      - Decompress and parse manifest / schema metadata
    │      - Verify Tenant / Facility Code compatibility (HOSP_TEST / target hospital)
    │      - Verify Schema Migration Version compatibility (target >= backup schema)
    ├── 3. Acquire Exclusive Lifecycle Lock (Block all concurrent API requests with 503 SERVICE_MAINTENANCE)
    ├── 4. Terminate / Revoke Active Staff Sessions (mc_auth_sessions)
    ├── 5. Open Dedicated Single-Connection DB Session with FOREIGN_KEY_CHECKS = 0
    ├── 6. Execute Restore within ACID Transaction (or structured table-by-table restore):
    │      - Truncate or recreate tables in dependency order
    │      - Insert all restored rows
    │      - Re-enable FOREIGN_KEY_CHECKS = 1
    ├── 7. Execute Post-Restore Migrations (if backup was from earlier migration version)
    ├── 8. Post-Restore Integrity Verification:
    │      - Verify all 96 tables exist and are InnoDB
    │      - Verify row count parity against backup manifest
    │      - Verify Financial Trial Balance: SUM(DEBIT) == SUM(CREDIT) in mc_financial_postings
    │      - Verify Patient Graph integrity
    │      - Re-verify Monotonic Clock Guard anchor
    ├── 9. Persist Audit Record (action: database.restored, backupId, durationMs)
    └── 10. Release Exclusive Lifecycle Lock -> System Ready
```

#### Flow 3: True Factory Reset
```
Technician Console
    │
    ▼ (POST /api/v1/database/factory-reset)
Local MedCore Service
    │
    ├── 1. Authenticate Technician Mode (X-MedCore-Tech-Token REQUIRED)
    ├── 2. Verify Destructive Confirmation Token:
    │      - Must contain confirmationText: "RESET MEDCORE"
    │      - Must contain explicit requireMandatoryBackup flag (default: true)
    ├── 3. Execute Mandatory Pre-Reset Backup:
    │      - Run full restorable backup
    │      - Verify backup archive via physical read-back
    │      - IF BACKUP FAILS -> ABORT FACTORY RESET IMMEDIATELY (FAIL-CLOSED)
    ├── 4. Acquire Exclusive Lifecycle Lock (Quiesce all services)
    ├── 5. Invalidate All Active Staff and Non-Technician Sessions
    ├── 6. Close Existing Connection Pool to Database
    ├── 7. Open Root Connection (without selecting target database)
    ├── 8. Destroy Database:
    │      - DROP DATABASE IF EXISTS `medcore_truth` (or configured database)
    ├── 9. Recreate Clean Database:
    │      - CREATE DATABASE `medcore_truth` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
    ├── 10. Run Full Migration Chain from Zero:
    │      - Execute MigrationRunner for V001 through V016 in strict sequence
    │      - Verify mc_schema_migrations records 16 applied migrations
    ├── 11. Seed Mandatory Baseline System Data:
    │      - Seed Root Hospital Tenant (HOSP_TEST / Target Hospital)
    │      - Seed Default Facility Configuration (PLATINUM edition, General Hospital)
    │      - Initialize Monotonic Clock Guard root anchor
    │      - Seed Default Admin Staff Role & Account (with temporary secure password)
    ├── 12. Verify Schema & Database Readiness:
    │      - Assert exactly 96 InnoDB tables exist in information_schema
    │      - Assert Trial Balance is balanced: total debits == 0 == total credits
    │      - Assert Clock Guard is verified monotonic
    ├── 13. Persist Immutable Audit Log:
    │      - Log action: factory_reset.completed with preResetBackupUuid and actor context
    └── 14. Release Lifecycle Lock -> SYSTEM READY FOR FRESH ONBOARDING
```

---

## 2. COMPREHENSIVE THREAT MODEL & MITIGATION MATRIX

| Threat ID | Threat Vector & Scenario | Impact Severity | Concrete Mitigation & Defense Invariant |
|---|---|---|---|
| **THR-01** | **Accidental Factory Reset**<br>Operator clicks reset accidentally. | **CRITICAL** | **Two-Man / Double Confirmation Defense:** Requires explicit confirmation phrase `"RESET MEDCORE"` in payload + technician token. UI shows visual red Danger Zone with countdown modal. |
| **THR-02** | **Reset Without Backup**<br>Database wiped without any recovery path. | **CRITICAL** | **Mandatory Pre-Reset Backup Rule:** Reset engine automatically triggers, verifies, and reads back a full backup before dropping database. If backup fails, reset is BLOCKED fail-closed. |
| **THR-03** | **Malicious Technician / Rogue Caller**<br>Attacker calls reset/restore API directly. | **CRITICAL** | **Technician Session Enforcement:** Protected with `X-MedCore-Tech-Token` (`mct_...`). Regular staff Bearer tokens (`SuperAdmin`, etc.) are rejected with `403 FORBIDDEN`. |
| **THR-04** | **Corrupted / Truncated Backup Archive**<br>Disk error or partial download corrupts archive. | **HIGH** | **Pre-Restore Checksum & Manifest Verification:** Archive SHA-256 and HMAC-SHA256 authenticated envelope verified before any write operation touches MariaDB. |
| **THR-05** | **Tampered Backup Archive**<br>Attacker modifies financial postings or user accounts inside backup. | **CRITICAL** | **Cryptographic MAC Validation:** Sealed backups use HMAC-SHA256 authenticated keystream sealing. Any single-byte modification invalidates MAC, aborting restore. |
| **THR-06** | **Interrupted Reset / Power Loss**<br>Power cuts during DROP/CREATE DATABASE. | **CRITICAL** | **Rebuild on Startup (Gate 12):** Service startup routine verifies database existence and migration completeness. If database is missing or partial, service automatically bootstraps from zero or prompts for recovery. |
| **THR-07** | **Disk Full During Backup/Export**<br>Disk runs out of space during dump. | **HIGH** | **Atomic Staging & Cleanup:** Backup writes to temporary staging directory, checks file completeness and free space, and removes partial artifacts on error. |
| **THR-08** | **Active Concurrent Writes During Backup/Restore**<br>Cashier posts visit while restore is writing. | **HIGH** | **Exclusive Lifecycle Mutex:** Service maintains an in-memory lifecycle lock. Any concurrent write request receives `503 SERVICE_MAINTENANCE` with retry header. |
| **THR-09** | **Cross-Tenant / Wrong Facility Restore**<br>Backup from Hospital B restored onto Hospital A. | **CRITICAL** | **Tenant Binding Check:** Archive manifest embeds `hospitalCode`. Restore verifies that archive hospital code matches current facility, or requires explicit override flag with security audit. |
| **THR-10** | **Path Traversal / Malicious ZIP Entries**<br>Archive contains `../../Windows/System32` entries. | **CRITICAL** | **Strict Filename Sanitization:** All extracted archive filenames are normalized; any path containing `..`, absolute drives, or separators outside sandbox is rejected fail-closed. |
| **THR-11** | **Oversized Archive / Zip Bomb**<br>Archive unpacks into terabytes of zeroes. | **HIGH** | **Decompression Limits:** Maximum decompressed size threshold enforced (e.g. 500 MB for local DB). Decompressor aborts if output exceeds quota. |
| **THR-12** | **SQL Injection via Imported Dump**<br>Corrupted or crafted SQL commands executed during restore. | **HIGH** | **Structured Parameterized / Table-by-Table Restore:** Data is imported through validated type parsers or table-level statements with disabled multi-statement arbitrary injection channels. |
| **THR-13** | **Stale Financial State / Ledger Imbalance**<br>Restored backup has unbalanced debit/credit. | **CRITICAL** | **Post-Restore Conservation Assertion:** Database engine runs real SQL `SUM(DEBIT) == SUM(CREDIT)` check immediately after restore. If imbalanced, flag `DEGRADED_ACTION_REQUIRED`. |
| **THR-14** | **Clock Rollback via Backup Restore**<br>Old backup restored with timestamps in past. | **HIGH** | **Clock Guard Integration:** Restore updates Clock Guard monotonically; monotonic clock root prevents system from accepting old timestamps as current time. |
| **THR-15** | **Plaintext Secrets in Export / Dump**<br>Exported CSV/JSON contains password hashes or keys. | **HIGH** | **PII & Secrets Redaction:** Password hashes (`password_hash`), token secrets, and private keys are either stripped or replaced with sanitized tokens in human-readable exports. |

---

## 3. GATE 1 VERDICT: PASS

**GATE 1 STATUS: PASS**  
- Complete authoritative sequence models defined for Backup, Export, Restore, Factory Reset, and Rebuild.
- 15 specific threat vectors modeled with concrete fail-closed mitigations.
- Ready to proceed to **GATE 2: DATABASE LIFECYCLE CONTRACT**.
