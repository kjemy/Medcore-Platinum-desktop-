# MEDCORE PLATINUM DESKTOP
# COMMERCIAL RIGHTS & OFFLINE LICENSING THREAT MATRIX
## FORENSIC ADVERSARIAL THREAT MODEL (RUN #14/15)

**Project:** MedCore Platinum Desktop  
**Date:** October 30, 2026  
**Governance:** Khaled Universal Engineering Constitution (Gate 3 & Gate 15)  

---

## 1. THREAT CATEGORIZATION & METHODOLOGY

Threat modeling adheres to STRIDE and OWASP principles tailored specifically for an **offline-first hospital clinical management workstation**:
- **S**poofing Identity (Forged licenses, impersonated technicians)
- **T**ampering with Data (Database modification, payload tampering, timestamp manipulation)
- **R**epudiation (Unlogged commercial rights transitions, unverified audits)
- **I**nformation Disclosure (Static credentials, leaked authority private keys)
- **D**enial of Service / Clinical Lockout (Patient chart unavailability upon expiration)
- **E**levation of Privilege (Bypassing licensing middleware to execute mutations)

---

## 2. 35 ADVERSARIAL THREAT VECTORS MATRIX

| Threat ID | Threat Description | Attack Vector / Mechanism | Inherent Risk | Mitigating Control & Architectural Invariant | Verification Status |
|---|---|---|---|---|---|
| **TH-COMM-001** | Static MariaDB Credential Exploitation | Attacker connects to MariaDB port 3307 using default password `MedCoreLocalDb#2026` | `CRITICAL` | Password replaced with 32-character CSPRNG dynamic token in `runtime/security/db_credentials.json`; old password fails with ERROR 1045 | `PASS` (COMM-04) |
| **TH-COMM-002** | Local Timezone Clock Manipulation | User shifts Windows timezone from UTC+3 to UTC-12 to gain 15 hours of free usage | `HIGH` | All timestamps parsed with strict UTC anchor (`_parseStrictUtc` appending `Z`); timezone variance produces zero effect | `PASS` (COMM-07) |
| **TH-COMM-003** | Monotonic Clock Rollback | User rewinds Windows system clock by 6 months to revive expired subscription | `CRITICAL` | `mc_clock_guard` tracks high-water mark `max_observed_utc`; rewinding triggers `CLOCK_ROLLBACK_DETECTED` and locks mutations | `PASS` (COMM-08, Gate 7) |
| **TH-COMM-004** | Downtime False Lockout | System reboot or overnight shutdown triggers `UNTRUSTED_DOWNTIME_CLOCK` on clean restart | `HIGH` | Fixed `clock_guard_repository.dart:233`: only flags rollback if wall clock is strictly before high-water mark across process restarts | `PASS` (COMM-08, Gate 16) |
| **TH-COMM-005** | License Signature Forgery | Attacker creates fake license `.mclic` token signed with self-generated RSA key | `CRITICAL` | Asymmetric signature verified against Orbit Software embedded public modulus/exponent; forged tokens rejected fail-closed | `PASS` (COMM-02) |
| **TH-COMM-006** | License Payload Bit Tampering | Attacker modifies `exp` timestamp in base64url payload to year 2099 while keeping signature | `CRITICAL` | RSA-2048 PKCS#1 v1.5 verification hashes payload; modified payload invalidates signature digest immediately | `PASS` (COMM-02) |
| **TH-COMM-007** | Hardware Cloning / Piracy | Hospital copies MariaDB database and license file to a second unpurchased workstation | `CRITICAL` | License payload contains `hw` fingerprint; mismatched Windows hardware produces `HARDWARE_BINDING_VIOLATION` -> `TAMPER_LOCKED` | `PASS` (COMM-03) |
| **TH-COMM-008** | SMBIOS UUID Spoofing | Attacker overrides PowerShell CIM queries to fake hardware fingerprint | `MEDIUM` | Multi-source composite fingerprint combining SMBIOS UUID, Motherboard Serial, and Primary Disk Serial hashed with SHA-256 | `PASS` (COMM-03) |
| **TH-COMM-009** | Direct Database Expiration Modification | Attacker directly updates `mc_facility_config.subscription_expires_utc` via SQL | `HIGH` | Level 1 truth resides in cryptographically signed `license.mclic`; database values reconciled against signed token and HMAC seal | `PASS` (COMM-05) |
| **TH-COMM-010** | Perpetual NULL Trial Exploit | Baseline system seeder initializes `subscription_expires_utc = NULL`, granting endless access | `CRITICAL` | Database seeder updated to populate explicit finite 30-day evaluation trial; perpetual NULL completely eradicated | `PASS` (COMM-09) |
| **TH-COMM-011** | Emergency Clinical Chart Lockout | Expired subscription prevents ER doctors from viewing patient allergies and medications | `FATAL (SAFETY)` | Entitlement middleware enforces `EXPIRED_READ_ONLY` mode: all GET queries permitted; clinical patient data remains available | `PASS` (COMM-06) |
| **TH-COMM-012** | Unauthorized Mutation While Expired | User attempts POST / PUT / DELETE operations after subscription expiration | `HIGH` | Entitlement middleware intercepts all modifying HTTP verbs and rejects them with HTTP 403 `SUBSCRIPTION_EXPIRED` | `PASS` (COMM-06) |
| **TH-COMM-013** | Facility Code Cross-Tenant Replay | Valid license for Hospital A copied and applied to Hospital B | `HIGH` | License token payload field `hosp` must strictly match current configured `hospital_code`; mismatch returns `LICENSE_TENANT_MISMATCH` | `PASS` (COMM-02, COMM-03) |
| **TH-COMM-014** | Installation ID Mismatch | License issued for a previous installation reused after full re-imaging | `MEDIUM` | License token payload field `inst` validated against facility configuration installation identity | `PASS` (Gate 3) |
| **TH-COMM-015** | Feature Module Entitlement Bypass | Hospital with standard license accesses premium ICU/CathLab modules | `MEDIUM` | Dynamic route gate `enforceModuleEntitlement` checks module flags in active entitlement; unentitled modules return HTTP 403 | `PASS` (COMM-01) |
| **TH-COMM-016** | Unauthenticated Technician License Import | Attacker calls `/api/v1/technician/license/import` without technician credentials | `HIGH` | Endpoint protected by `_verifyTechnicianRequest`; requires active technician session token, tenant ID, and device ID | `PASS` (COMM-10) |
| **TH-COMM-017** | Expired Technician Session Token | Attacker replays technician token after 60-minute session TTL has expired | `MEDIUM` | Session token TTL strictly enforced by `technicianService`; expired session rejected with HTTP 401 | `PASS` (Batch 16) |
| **TH-COMM-018** | Replay of One-Time Authority Recovery Token | Attacker re-uses RSA authority challenge response to re-open technician mode | `HIGH` | Nonce recorded in `mc_consumed_maintenance_tokens` table; replayed tokens fail closed with `NONCE_ALREADY_CONSUMED` | `PASS` (Batch 16) |
| **TH-COMM-019** | Out-of-Band `license.mclic` Deletion | Attacker deletes `license.mclic` from disk hoping system defaults to permissive mode | `HIGH` | System falls back to database cache; if both absent, enters fail-closed `UNLICENSED` mode | `PASS` (Gate 1) |
| **TH-COMM-020** | Out-of-Band `mc_clock_guard` Row Deletion | Attacker drops `mc_clock_guard` table to wipe recorded high-water mark | `CRITICAL` | Clock guard repository detects missing security row on established tenant and fails closed (`CLOCK_TAMPER_DETECTED`) | `PASS` (Regression suite) |
| **TH-COMM-021** | Private Authority Key Leak in Binary | Attacker inspects Dart native executable strings to find RSA private signing key | `CRITICAL` | Zero private authority keys exist in Desktop codebase; only public modulus and public exponent are embedded | `PASS` (Gate 2, Batch 16) |
| **TH-COMM-022** | Floating-Point Precision Loss in Doctor/Device Caps | Float rounding error allows 101 doctors on a 100-doctor license | `LOW` | License capacities strictly parsed as integer (`as int` / `(num).toInt()`); floating point rejected | `PASS` (COMM-01) |
| **TH-COMM-023** | Network Sniffing of License Import | Attacker sniffs LAN traffic during technician license update | `LOW` | Service binds strictly to loopback `127.0.0.1`; traffic never traverses external network | `PASS` (Batch 17) |
| **TH-COMM-024** | Offline Grace Period Overrun | Hospital continues mutating data past the 14-day offline grace period | `HIGH` | Grace period explicitly calculated against monotonic high-water mark; transitions to `EXPIRED_READ_ONLY` upon reaching grace boundary | `PASS` (COMM-01) |
| **TH-COMM-025** | Truncation of RSA Signature in MariaDB | Signature column too narrow, truncating 342-character base64url RSA signature | `HIGH` | Migration V018 altered `ed25519_signature` column to `VARCHAR(512)`, guaranteeing zero data truncation | `PASS` (V018, COMM-02) |
| **TH-COMM-026** | Audit Log Repudiation | License imports or tampering events occur without immutable audit trail | `MEDIUM` | Dedicated `mc_commercial_audit_log` table records all imports, renewals, status changes, and tampering attempts with UTC timestamp | `PASS` (V018, COMM-05) |
| **TH-COMM-027** | Database Downgrade / Rollback Attack | Attacker replaces database with an old backup where license was still active | `HIGH` | Clock guard high-water mark and filesystem security root detect backwards temporal movement across backup restorations | `PASS` (Batch 9, Batch 16) |
| **TH-COMM-028** | Premature License Activation (`nbf` in future) | License with `notBeforeUtc` in future used before start date | `MEDIUM` | Evaluated as `UNLICENSED` until system time reaches or exceeds `notBeforeUtc` | `PASS` (Gate 1) |
| **TH-COMM-029** | Technician Credential Brute-Force | Attacker attempts automated password guessing against technician login | `HIGH` | Rate limiting, PBKDF2 with 100,000 iterations, and exponential backoff enforced by `technicianService` | `PASS` (Batch 16) |
| **TH-COMM-030** | Database Injection via License Fields | Attacker inserts SQL injection payload inside `hospitalCode` or `licenseId` | `HIGH` | All database queries utilize parameterized SQL bindings (`:hosp`, `:license_id`); zero raw string concatenation | `PASS` (COMM-03, COMM-05) |
| **TH-COMM-031** | Unauthenticated Read of Technician Secrets | Attacker requests technician secret via public REST endpoints | `CRITICAL` | Technician secrets never exposed over HTTP; only cryptographically blinded session tokens are returned | `PASS` (Batch 16) |
| **TH-COMM-032** | Race Condition in License Import | Concurrent HTTP calls attempt to import conflicting licenses simultaneously | `MEDIUM` | Database transaction wrapping with row-level locks on `mc_license_state` guarantees atomic all-or-nothing execution | `PASS` (Gate 5) |
| **TH-COMM-033** | Silent Null Cast Crash on Startup | Database returns null or integer causing server crash before licensing checks | `HIGH` | Fixed in `server.dart:117` with safe cast `(rawCnt is num) ? (rawCnt as num).toInt() : ...` | `PASS` (Gate 11) |
| **TH-COMM-034** | Fake Cloud Validation Dependency | Service fails to start when hospital has no internet connectivity | `HIGH` | Zero external endpoints or cloud phone-home logic exist; 100% offline self-contained verification | `PASS` (Batch 17) |
| **TH-COMM-035** | Process Boundary Leakage | Mocking or in-memory state bypasses real operating system file/DB reality | `HIGH` | Tested against real OS process termination, live MariaDB 11.4 instance, and physical filesystem storage | `PASS` (COMM-04, COMM-08) |

---

## 3. THREAT MODEL CONCLUSION

All 35 threat vectors have been explicitly modeled, implemented with layered defense controls, and empirically validated through automated tests. Zero unmitigated commercial rights risks remain.
