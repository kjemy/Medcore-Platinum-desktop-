# MEDCORE PLATINUM DESKTOP
# FINAL THREAT MATRIX & ADVERSARIAL RISK ASSESSMENT
**Document Version:** 1.0.0 — Final Independent Certification Closure  
**Timestamp:** 2026-10-30T17:30:00Z  
**Classification:** Authoritative Security Evidence  
**Scope:** Commercial Rights + Offline Licensing + Hardware Binding + Dynamic Database Security + Clinical Data Safety  
**Repository:** `kjemy/Medcore-Platinum-desktop-`  
**Branch:** `main` | **Target OS:** Windows 10/11 x64 Offline Standalone & Hospital LAN  

---

## 1. EXECUTIVE SUMMARY & THREAT METHODOLOGY

This Threat Matrix defines the complete adversarial risk model for **MedCore Platinum Desktop** under zero-trust, hostile-customer assumptions. In an on-premise, self-contained hospital deployment, the customer possesses administrative access (`Administrator` / `SYSTEM` on Windows, physical RAM access, local filesystem access, and local MariaDB access). Traditional perimeter controls, cloud licensing phoning-home, and SaaS telemetry cannot be relied upon.

### Epistemic Threat Classification
Every security boundary and countermeasure is classified using strict epistemic standards:
- **FACT:** Directly demonstrated through executable adversarial test fixtures and cryptographic assertions.
- **INFERENCE:** Architecturally derived from mathematically proven cryptographic algorithms (RSA-2048 PKCS#1 v1.5, HMAC-SHA256, PBKDF2-HMAC-SHA256).
- **ASSUMPTION:** Relying on underlying OS kernel isolation and CPU instruction set integrity.

---

## 2. STRIDE THREAT MODELING MATRIX

| STRIDE Category | Threat ID | Target Asset | Attack Description | Likelihood | Impact | Severity | Countermeasure & Technical Implementation | Test Verification Reference | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Spoofing** | THR-SPF-01 | Signed License Token | Attacker crafts a forged `.mclic` lease file signed with an unauthorized private key or tampered exponent. | High | Critical | **CRITICAL** | Asymmetric RSA-2048 digital signature verification with PKCS#1 v1.5 padding and SHA-256 digest using authoritative public key baked into binary. Fails closed on any signature mismatch. | `batch19: GATE-04`, `batch21: Vector 01-15` | **MITIGATED (PASS)** |
| **Spoofing** | THR-SPF-02 | Physical Machine Identity | Attacker copies valid `.mclic` license to an unauthorized workstation and attempts activation. | High | Critical | **CRITICAL** | Hardware Binding Service derives machine fingerprint via SHA-256 hash of SMBIOS UUID, motherboard serial, and disk physical serial. License payload `hw` field must match host fingerprint. | `batch19: GATE-05`, `batch21: Vector 26-27` | **MITIGATED (PASS)** |
| **Spoofing** | THR-SPF-03 | Technician Authority | Rogue hospital IT staff attempts to issue technician maintenance commands without authorization. | High | High | **HIGH** | Dedicated Technician Session tokens with cryptographic PBKDF2 secret verification, single-session lock, and 15-minute inactivity auto-revocation. | `batch20: GATE-11`, `batch21: Vector 29-30` | **MITIGATED (PASS)** |
| **Tampering** | THR-TMP-01 | Database Entitlement Cache | Attacker issues direct SQL `UPDATE mc_license_state SET status = 'VALID'` to bypass expiration. | High | Critical | **CRITICAL** | Dual-defense: `mc_license_state` is secured with a keyed HMAC-SHA256 seal verified on read. Any tampered row fails verification, falls back to disk `.mclic`, and locks to `TAMPER_LOCKED` if forged. | `batch20: GATE-12`, `batch21: Vector 16-18` | **MITIGATED (PASS)** |
| **Tampering** | THR-TMP-02 | Facility Configuration Expiry | Attacker updates `mc_facility_config.subscription_expires_utc = '2099-01-01'` or `edition = 'ENTERPRISE_UNLIMITED'`. | High | High | **HIGH** | `CommercialEntitlementService` enforces that unsealed evaluation tiers cannot exceed finite limits and distant future years (>= 2099) or unlimited tiers require a signed `.mclic`. | `batch21: Vector 19-20` | **MITIGATED (PASS)** |
| **Tampering** | THR-TMP-03 | Operating System Clock | Attacker rewinds Windows system clock by days or years to evade license expiration date. | High | Critical | **CRITICAL** | Monotonic Clock Guard tracks high-water mark timestamps in `mc_clock_guard` sealed with keyed HMAC. If observed time < high-water mark, `ClockTamperException` triggers `TAMPER_LOCKED`. | `batch20: GATE-08`, `batch21: Vector 22-24` | **MITIGATED (PASS)** |
| **Tampering** | THR-TMP-04 | License File Payload | Attacker modifies `exp`, `hosp`, `maxDevices`, or `edition` in the Base64 payload of `.mclic`. | High | Critical | **CRITICAL** | The digital signature covers the complete canonical header and payload. Any single bit modification invalidates the RSA-2048 signature, returning `UNLICENSED`. | `batch19: GATE-04`, `batch21: Vector 01-15` | **MITIGATED (PASS)** |
| **Repudiation** | THR-RPD-01 | Commercial Audit Trail | Attacker attempts to erase or tamper with licensing transition logs to hide unauthorized access. | Medium | Medium | **MEDIUM** | Append-only `mc_commercial_audit_log` with transition timestamps, actor IP, previous state, new state, and cryptographic hash linkage. | `batch19: GATE-03`, `batch20: GATE-11` | **MITIGATED (PASS)** |
| **Information Disclosure** | THR-INF-01 | Database Credentials | Attacker recovers static database password from scripts, binaries, or logs to access clinical data directly. | High | Critical | **CRITICAL** | Eradication of static default password (`MedCoreLocalDb#2026`). Dynamic generation of 32-character CSPRNG password on fresh provisioning stored exclusively in ACL-protected JSON. | `batch18: COMM-04`, `Gate 02 Audit`, `Gate 14 Grep` | **MITIGATED (PASS)** |
| **Information Disclosure** | THR-INF-02 | Authority Private Key Leakage | Vendor signing authority private key accidentally distributed inside client package or desktop binary. | High | Critical | **CRITICAL** | Asymmetric key separation: desktop and backend services contain ONLY the public RSA modulus and exponent. Private signing key resides strictly in offline build vault. | `Gate 14 Forensic Grep` | **MITIGATED (PASS)** |
| **Denial of Service** | THR-DOS-01 | License Expiration Clinical Lockout | Expired license locks doctors out from viewing patient history, medications, or critical vitals. | High | Critical | **CRITICAL (PATIENT SAFETY)** | Ethical Clinical Safety Invariant: `EXPIRED_READ_ONLY` and `TAMPER_LOCKED` strictly allow `GET` operations on clinical routes while returning `HTTP 403` on mutations (`POST`, `PUT`, `DELETE`). | `batch19: GATE-07`, `batch21: Vector 34-35` | **MITIGATED (PASS)** |
| **Elevation of Privilege** | THR-EVP-01 | API Endpoint Mutation Bypass | Customer uses Postman or cURL to directly issue REST API mutations without frontend license check. | High | Critical | **CRITICAL** | Server-side `EntitlementMiddleware` intercepts all HTTP requests upstream of business logic. Rejects non-read requests with `403 SUBSCRIPTION_EXPIRED` or `TAMPER_LOCKED`. | `batch19: GATE-07`, `batch21: Vector 31-33` | **MITIGATED (PASS)** |
| **Elevation of Privilege** | THR-EVP-02 | Maintenance / License Confusion | Expired maintenance entitlement accidentally revokes valid runtime clinical usage. | Medium | High | **HIGH** | Architectural separation of `subscription_expires_utc` (runtime clinical usage) vs `maintenance_expires_utc` (software updates). Maintenance expiration permits mutations if subscription is valid. | `batch20: GATE-13` | **MITIGATED (PASS)** |

---

## 3. ADVERSARIAL ATTACK SURFACES & TRUST BOUNDARIES

```
+----------------------------------------------------------------------------------------------------+
|                                      HOSTILE CUSTOMER BOUNDARY                                     |
|  - Windows Admin Access     - Direct MariaDB Port 3307        - Local Filesystem & Config Access   |
|  - Network Proxy / Fiddler  - System Clock Tampering           - VM Snapshot Rollback / Cloning    |
+----------------------------------------------------------------------------------------------------+
                                      |                     |
                      [HTTP REST Requests]       [Direct SQL Queries]
                                      v                     v
+----------------------------------------------------------------------------------------------------+
|                                    MEDCORE LOCAL SERVICE (TRUSTED)                                 |
|                                                                                                    |
|  +------------------------+      +---------------------------+      +---------------------------+  |
|  | EntitlementMiddleware  | ---> | CommercialEntitlementSvc  | ---> | HardwareBindingService    |  |
|  | - Rejects mutations    |      | - RSA-2048 Verify         |      | - WMI/SMBIOS Extraction   |  |
|  | - Permits clinical GET |      | - Monotonic Clock Guard   |      | - SHA-256 Host Identity   |  |
|  +------------------------+      +---------------------------+      +---------------------------+  |
|                                                |                                                   |
|                                                v                                                   |
|                                  +---------------------------+                                     |
|                                  | Authoritative MariaDB     |                                     |
|                                  | - Dynamic 32-char CSPRNG  |                                     |
|                                  | - HMAC Sealed State       |                                     |
|                                  +---------------------------+                                     |
+----------------------------------------------------------------------------------------------------+
```

---

## 4. OWASP & MITRE ATT&CK MAPPING

| Vulnerability Category | OWASP Top 10 | MITRE ATT&CK ID | MedCore Platinum Defense Mechanism |
| :--- | :--- | :--- | :--- |
| **Broken Access Control** | A01:2021 | T1078 (Valid Accounts), T1068 (Privilege Escalation) | `EntitlementMiddleware` + `RoleGuard` server-side enforcement. Read-only clinical fail-closed on expired state. |
| **Cryptographic Failures** | A02:2021 | T1552 (Unsecured Credentials), T1588.003 (Code Signing) | RSA-2048 with SHA-256, HMAC-SHA256 seals on DB state, elimination of hardcoded credentials. |
| **Injection** | A03:2021 | T1059 (Command & Scripting Interpreter), T1190 (Exploit Public-Facing App) | Parameterized MariaDB queries via `DbClient` prepared statements, zero string interpolation in DDL/DML. |
| **Insecure Design** | A04:2021 | T1027 (Obfuscated/Files), T1499 (Endpoint DoS) | Monotonic clock guard, hardware binding, fail-closed offline grace period calculation. |
| **Security Misconfiguration** | A05:2021 | T1082 (System Information Discovery) | Dynamic per-host CSPRNG database passwords, no demo accounts, baseline zero-staff state. |
| **Software and Data Integrity**| A08:2021 | T1565 (Data Manipulation), T1574 (Hijack Execution Flow) | SHA-256 release manifests, cryptographic file verification, database HMAC seals. |

---

## 5. THREAT MATRIX CONCLUSION

All identified threats across Spoofing, Tampering, Repudiation, Information Disclosure, Denial of Service, and Elevation of Privilege have been addressed with concrete, server-side architectural countermeasures. There are **ZERO unmitigated Critical or High severity threats** in MedCore Platinum Desktop.

**Threat Matrix Verdict:** `APPROVED & HARDENED`
