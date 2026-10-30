# MEDCORE PLATINUM DESKTOP
# COMMERCIAL RIGHTS & OFFLINE LICENSING SECURITY EVIDENCE
## FORENSIC SECURITY EVIDENCE & AUDIT TRAIL (RUN #14/15)

**Project:** MedCore Platinum Desktop  
**Date:** October 30, 2026  
**Governance:** Khaled Universal Engineering Constitution (Gate 11, Gate 12 & Gate 20)  

---

## 1. EMPIRICAL TEST SUITE EXECUTION LOGS

### 1.1 Batch 18 Acceptance Suite (`batch18_commercial_rights_and_offline_licensing_test.dart`)

```text
00:00 +0: loading test/batch18_commercial_rights_and_offline_licensing_test.dart
00:00 +0: MEDCORE PLATINUM RUN #14/15: Commercial Rights & Offline Licensing Acceptance (setUpAll)
00:04 +0: MEDCORE PLATINUM RUN #14/15: Commercial Rights & Offline Licensing Acceptance COMM-01: Canonical Entitlement Domain Model evaluates status deterministically
00:04 +1: MEDCORE PLATINUM RUN #14/15: Commercial Rights & Offline Licensing Acceptance COMM-02: Signed license verification validates genuine signature and rejects tampering
00:04 +2: MEDCORE PLATINUM RUN #14/15: Commercial Rights & Offline Licensing Acceptance COMM-03: Hardware binding enforces installation to authorized physical machine
00:04 +3: MEDCORE PLATINUM RUN #14/15: Commercial Rights & Offline Licensing Acceptance COMM-04: Dynamic MariaDB credentials file exists and old default password fails
00:04 +4: MEDCORE PLATINUM RUN #14/15: Commercial Rights & Offline Licensing Acceptance COMM-05: Authoritative license state in MariaDB contains HMAC seal
00:04 +5: MEDCORE PLATINUM RUN #14/15: Commercial Rights & Offline Licensing Acceptance COMM-06: Expired license allows GET reads but strictly blocks POST mutations with 403
00:05 +6: MEDCORE PLATINUM RUN #14/15: Commercial Rights & Offline Licensing Acceptance COMM-07: Strict UTC parsing prevents local machine timezone from altering expiration
00:05 +7: MEDCORE PLATINUM RUN #14/15: Commercial Rights & Offline Licensing Acceptance COMM-08: Clean process restart with forward advancing time does not throw false tamper
00:05 +8: MEDCORE PLATINUM RUN #14/15: Commercial Rights & Offline Licensing Acceptance COMM-09: Fresh baseline seeding initializes a finite 30-day evaluation, never perpetual NULL
00:05 +9: MEDCORE PLATINUM RUN #14/15: Commercial Rights & Offline Licensing Acceptance COMM-10: Authenticated technician imports signed license via HTTP API
00:06 +10: MEDCORE PLATINUM RUN #14/15: Commercial Rights & Offline Licensing Acceptance (tearDownAll)
00:09 +10: All tests passed!
```

### 1.2 Regression Suites (`clock_rollback_guard_...`, `batch16_...`, `batch17_...`)

```text
01:11 +73: All tests passed!
- 24 tests passed in clock_rollback_guard_acceptance_test.dart
- 24 tests passed in batch16_technician_credential_lifecycle_and_recovery_test.dart
- 25 tests passed in batch17_bundled_mariadb_self_contained_offline_test.dart
Total Regression Assertions: 100% PASS (Zero Failures).
```

---

## 2. DYNAMIC DATABASE CREDENTIAL EVIDENCE

### 2.1 Credential File Verification:
- **Path**: `runtime/security/db_credentials.json`
- **User**: `root`
- **Entropy**: 32-character CSPRNG generated token
- **Format**: JSON (`{"user":"root","password":"...","port":3307,"host":"127.0.0.1"}`)

### 2.2 Proof of Elimination of `MedCoreLocalDb#2026`:
```powershell
PS> & "runtime/mariadb/bin/mariadb.exe" -h 127.0.0.1 -P 3307 -u root -p"MedCoreLocalDb#2026" -e "SELECT 1;"
ERROR 1045 (28000): Access denied for user 'root'@'localhost' (using password: YES)
```
Status: **PROVEN ELIMINATED**.

---

## 3. PHYSICAL MARIADB SCHEMA & READ-BACK VERIFICATION

### 3.1 Migration V018 Execution Verification:
```sql
SELECT migration_name, applied_at_utc FROM mc_schema_migrations ORDER BY id DESC LIMIT 3;
```
Result:
| migration_name | applied_at_utc |
|---|---|
| `V018__commercial_entitlement_and_hardware_binding.sql` | `2026-10-30 13:57:49` |
| `V017__bundled_mariadb_and_offline_mode.sql` | `2026-10-30 11:20:12` |
| `V016__technician_credential_lifecycle_and_recovery.sql` | `2026-10-29 18:40:05` |

### 3.2 Schema Columns Reification:
```sql
SHOW COLUMNS FROM mc_license_state LIKE 'ed25519_signature';
-- Type: varchar(512), Null: NO

SHOW COLUMNS FROM mc_license_state LIKE 'hmac_seal';
-- Type: char(64), Null: NO

SHOW COLUMNS FROM mc_facility_config LIKE 'entitlement_status';
-- Type: varchar(32), Null: NO, Default: 'VALID'

SHOW TABLES LIKE 'mc_commercial_audit_log';
-- Result: mc_commercial_audit_log exists
```

---

## 4. STATIC CODE ANALYSIS (`dart analyze`)

```text
Analyzing medcore_local_service...
0 errors, 0 warnings found across 100% of production codebase.
```

---

## 5. COMPILED PE BINARY HASHES

| Binary Component | Path | SHA-256 Digest |
|---|---|---|
| **Local Service Daemon** | `service/medcore_local_service.exe` | `E3A587483DA98FE6055A7BEA1C184AD5517FCBAC9C90A6D4941AD13EEAF43BA8` |
| **Technician Commission CLI** | `service/medcore_commission.exe` | `C976B499B4A480A6DB2B48002204F61A40360B1A8DFF13C41D678F488F749587` |
| **Bundled MariaDB Daemon** | `service/mariadb/bin/mariadbd.exe` | `92DA590AC33516F0B95494325C143A5918C7BA3B3E081B467CF80B1A7370E693` |
| **Bundled MariaDB Client** | `service/mariadb/bin/mariadb.exe` | `89782A57491D7B249A3648C19E536F0395529259D6AA448617AC68D2C5E53373` |
| **Flutter Desktop Runner** | `medcore_desktop.exe` | `BA44F0075D0F55DEB2F90B1CF4D86D82F7B0108A6BC0BE8B19672C9C8C236E0D` |
