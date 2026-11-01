# GATE 02 — LOCAL DATABASE / MARIADB SECURITY REPORT

**Project:** MedCore Platinum Desktop  
**Path:** `C:\Users\hp\Desktop\project 4`  
**Timestamp:** 2026-10-31T02:26:30+02:00  
**Overall Status:** PASS  

---

## 1. Database Configuration & Engine Verification
- Engine: MariaDB 11.4.4-MariaDB (Win64)
- Host Binding: `127.0.0.1` (Strict Loopback Only; @@bind_address = 127.0.0.1)
- Port: `3307`
- Dynamic Credentials Vault: Stored in isolated `runtime/security/db_credentials.json`
- Root Isolation: Random 32-character dynamic password, zero universal/default passwords.
- Data Directory: `runtime/mariadb_data` (isolated per installation).

---

## 2. Test Suite Verification
- `batch17_bundled_mariadb_self_contained_offline_test.dart`: 11 tests passed (100%).
  - MARIADB-01: Bundled MariaDB binary exists in runtime or service paths
  - MARIADB-02: Bundled MariaDB version matches 11.4 LTS
  - MARIADB-03: Dynamic binary resolution locates bundled instance without system PATH
  - MARIADB-04: my.ini enforces local bind-address 127.0.0.1 and port 3307
  - MARIADB-05: Authenticated connection succeeds and queries database metadata
  - MARIADB-06: MariaDB rejects unauthenticated connections on port 3307
  - MARIADB-07: All 17 migrations apply and verify with 100% integrity
  - MARIADB-08: LocalMedCoreServer starts against bundled database and reports HEALTHY
  - MARIADB-09: Committed data persists across connection terminations
  - MARIADB-10: Factory Reset executes complete schema reset and credential re-seeding
  - MARIADB-11: Complete authentication, cryptographic checks and DB execution run offline
- `batch12_micro_pbkdf2_and_credential_isolation_test.dart`: 4 tests passed (100% after PATCH-001).
- `batch9_database_lifecycle_and_recovery_test.dart`: 9 tests passed (100%).

---

## 3. Red Team Attacks
- `DB-RT-01`: Passwordless root login attempt -> Access Denied (Fail closed).
- `DB-RT-02`: Default password ('root' / 'admin') attempt -> Access Denied (Fail closed).
- `DB-RT-03`: Network exposure probe -> Binding strictly to 127.0.0.1.

**Evidence Artifacts:** `02_DATABASE/gate02_results.json`, `PATCHES/PATCH-001.md`
