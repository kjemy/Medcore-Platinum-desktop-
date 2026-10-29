# MEDCORE PLATINUM DESKTOP
# FINAL WINDOWS RELEASE ARTIFACT VERIFICATION GATE
## Technician Bootstrap + First Admin — GitHub Actions Artifact Acceptance Report
**Document ID**: `MEDCORE-TECH-RELEASE-ACCEPTANCE-20261029`  
**Governing Standard**: `@Khaled All Rules` (Khaled Universal Engineering Constitution v1.0.0)  
**Execution Authority**: Main Execution Agent Only (Gemini 3.8 High)  
**Target Repository**: `kjemy/Medcore-Platinum-desktop-`  
**Target Branch**: `main`  
**Authoritative Target Commit**: `31d6e29aacad2ef5b5536755a783a9260721dc88`  
**RC-3 Immutable Base Commit**: `713a8a4578cb7f82258b57497afa800346280534`  
**Date**: 2026-10-29  

---

## 1. BASELINE FREEZE & GIT STATE RECONCILIATION

Direct physical Git inspection of the authoritative local repository at `C:\Users\hp\Desktop\project 4`:

| Metric | Inspected Value | Status |
| :--- | :--- | :--- |
| **Current HEAD SHA** | `31d6e29aacad2ef5b5536755a783a9260721dc88` | **VERIFIED** |
| **Commit Message** | `feat(commissioning): implement first-run technician bootstrap, CLI tools and admin handover acceptance gate` | **VERIFIED** |
| **Current Branch** | `main` | **VERIFIED** |
| **origin/main SHA** | `31d6e29aacad2ef5b5536755a783a9260721dc88` | **IN SYNC** |
| **Working Tree State** | Clean (`git status --short` returns 0 changes) | **VERIFIED** |
| **Immutable RC-3 Commit** | `713a8a4578cb7f82258b57497afa800346280534` (`v1.0.0-rc.3^{commit}`) | **IMMUTABLE** |
| **Annotated Tag Object** | `c44b4c273f5493aa3053b9c2f9d0ba989047b23f` (`refs/tags/v1.0.0-rc.3`) | **VERIFIED** |
| **Remote Origin URL** | `https://github.com/kjemy/Medcore-Platinum-desktop-.git` | **AUTHENTICATED** |

---

## 2. GITHUB ACTIONS RELEASE WORKFLOW EXECUTION

The official CI pipeline `.github/workflows/windows-release.yml` was dispatched on GitHub Actions using the official repository credentials for target `main` at commit `31d6e29aacad2ef5b5536755a783a9260721dc88`.

| Workflow Parameter | Value |
| :--- | :--- |
| **Workflow Name** | `MedCore Platinum Desktop — Official Windows Release` |
| **Workflow File** | `.github/workflows/windows-release.yml` |
| **Workflow Run ID** | `40841740280` |
| **Run Number** | `5` |
| **Event** | `workflow_dispatch` |
| **Target Reference** | `main` |
| **Triggered GITHUB_SHA** | `31d6e29aacad2ef5b5536755a783a9260721dc88` |
| **Checked-out Commit** | `31d6e29aacad2ef5b5536755a783a9260721dc88` |
| **Runner OS** | `windows-2022` (Visual Studio 17 2022) |
| **Toolchain** | Flutter 3.22.0 (channel stable) • Dart 3.4.0 (stable) |
| **Started At (UTC)** | `2026-10-29T08:23:12Z` |
| **Completed At (UTC)** | `2026-10-29T08:26:35Z` |
| **Duration** | 3m 23s |
| **Job Conclusion** | **SUCCESS** (`conclusion = success`) |

### Step-by-Step Execution Verification:
1. `Set up job`: Success (2s)
2. `Checkout Release Source`: Success (6s) — Checked out `31d6e29aacad2ef5b5536755a783a9260721dc88`
3. `Audit & Enforce Release Source Traceability`: Success (0s) — `TRACEABILITY PASS: Verified target branch/commit source (main -> 31d6e29aacad2ef5b5536755a783a9260721dc88)`
4. `Setup Flutter Toolchain`: Success (1m 13s) — Flutter 3.22.0
5. `Configure Flutter Windows Support`: Success (27s)
6. `Install Desktop Client Dependencies`: Success (1s) — `flutter pub get`
7. `Run Static Code Analysis`: Success (10s) — `flutter analyze` (`No issues found! ran in 9.3s`)
8. `Run Desktop Automated Test Suite`: Success (14s) — `flutter test` (`🎉 12 tests passed.`)
9. `Build Windows Release Executable`: Success (1m 00s) — `flutter build windows --release`
10. `Verify Compiled Windows Output`: Success (0s) — Verified 146,432 bytes EXE
11. `Package Release Bundle & Generate Manifest`: Success (2s) — Generated `release_manifest.json` and zip
12. `Upload Windows Release Artifact`: Success (3s) — Artifact ID `12883660582`

---

## 3. RELEASE ARTIFACT IDENTITY & INTEGRITY

The downloadable Windows release bundle was acquired directly from GitHub Actions run `40841740280` via REST API download and verified:

```text
================================================================================
MEDCORE PLATINUM DESKTOP — ARTIFACT IDENTITY
================================================================================
GitHub Artifact ID          : 12883660582
GitHub Container Name       : medcore-platinum-windows-main-batch9-eval-31d6e29
GitHub Artifact Zip Size    : 15,394,763 bytes
GitHub Artifact Zip SHA-256 : D67618C808D239F72A45E394733F9A4107EB90C668687FDF36A1A4F01B5617CE

Packaged Bundle Zip Name    : medcore-platinum-windows-main-batch9-eval-31d6e29.zip
Packaged Bundle Zip Size    : 15,401,427 bytes
Packaged Bundle SHA-256     : 61B761A8685AE24413106F449E06E891ECF00BCB526F0C85A59639AF707B5408

Executable File Name        : medcore_desktop.exe
Executable File Size        : 146,432 bytes
Executable SHA-256          : B8CC8727BF114DEFC293FABACF9E777CEAF56852620CAD1FCCC4B4D93B30886F
================================================================================
```

### Manifest Verification (`release_manifest.json` inside artifact):
```json
{
  "project": "MedCore Platinum Desktop",
  "release": "main",
  "build_type": "EVALUATION",
  "screen_capture_mode": "WDA_NONE (Screen capture permitted for evaluation)",
  "branding_logo_integrated": true,
  "application_commit": "31d6e29aacad2ef5b5536755a783a9260721dc88",
  "rc3_base_commit": "713a8a4578cb7f82258b57497afa800346280534",
  "workflow_run_id": "40841740280",
  "workflow_run_number": "5",
  "workflow_name": "MedCore Platinum Desktop — Official Windows Release",
  "build_timestamp": "2026-10-29T08:26:27Z",
  "flutter_version": "Flutter 3.22.0 • channel stable • https://github.com/flutter/flutter.git",
  "dart_version": "Dart SDK version: 3.4.0 (stable) (Mon May 6 07:59:58 2024 -0700) on \"windows_x64\"",
  "artifact_name": "medcore-platinum-windows-main-batch9-eval-31d6e29.zip",
  "artifact_size_bytes": 15401427,
  "artifact_sha256": "61B761A8685AE24413106F449E06E891ECF00BCB526F0C85A59639AF707B5408"
}
```

---

## 4. ARTIFACT CONTENT INSPECTION

The release ZIP was extracted to an isolated directory:
- `medcore_desktop.exe` (146,432 bytes) — Native Windows binary
- `flutter_windows.dll` (18,124,288 bytes) — Flutter Windows runtime engine
- `data/` — Application asset bundle, flutter assets, icudtl.dat
- `native_assets.yaml` (51 bytes) — Flutter native assets mapping
- `release_manifest.json` (952 bytes) — Cryptographic build lineage manifest

**Windows Process Execution Proof**:
The compiled `medcore_desktop.exe` was executed directly as a real Windows OS process (`Start-Process`):
- Process ID: `PID 2848`
- Working Set Memory: `91,009,024 bytes` (~91 MB)
- Process Status: Executed cleanly without missing DLL errors, crashes, or unhandled exceptions.

---

## 5. REAL RELEASE-BUNDLE FIRST-RUN TEST & LIFECYCLE VERIFICATION

The full commissioning lifecycle was executed against physical MariaDB 11.4 on `127.0.0.1:3307`:

```
+---------------------------------------------------------------------------------------------------------------+
|                                      FULL COMMISSIONING LIFECYCLE VERIFIED                                    |
|                                                                                                               |
| 1. Fresh Database Setup       --> Clean MariaDB medcore_acceptance_run_gate created; V001..V017 applied       |
| 2. Zero-Staff Invariant       --> SELECT COUNT(*) FROM mc_staff = 0 (Verified zero initial staff)             |
| 3. Service Auto-Bootstrap     --> ensureCommissioningSecretProvisioned() creates high-entropy TECH-COMM-*     |
| 4. Ephemeral Slip File        --> FIRST_RUN_COMMISSIONING_SECRET.txt generated (Length: 32 chars)             |
| 5. Hash Persistence           --> runtime/security/technician_secret.json stores pbkdf2_sha256$20000$ (No pw) |
| 6. Technician Gate Open       --> POST /api/v1/technician/session/open succeeds with HTTP 201 Created         |
| 7. One-Time Slip Deletion     --> FIRST_RUN_COMMISSIONING_SECRET.txt is PHYSICALLY DELETED upon consumption   |
| 8. Session Persistence        --> mc_technician_sessions records sessionUuid, deviceId, is_active=1           |
| 9. Facility Configuration     --> PUT /api/v1/technician/config updates mc_facility_config                    |
| 10. Initial Admin Provision   --> POST /api/v1/technician/initial-admin creates ADM-REL-001 (HospitalAdmin)   |
| 11. Force Password Invariant  --> mc_staff.force_password_change = 1; Audit log written to mc_audit_logs     |
| 12. Session Closure           --> POST /api/v1/technician/session/close deactivates session (is_active=0)     |
| 13. Admin First Login         --> POST /api/v1/auth/login returns forcePasswordChange = true                  |
| 14. Password Change           --> POST /api/v1/auth/change-password updates password; force_password_change=0|
| 15. Invalidation Proof        --> Old temp password rejected with HTTP 401; New permanent password succeeds   |
| 16. Operational Access        --> GET /api/v1/patients accessible with new permanent session (HTTP 200 OK)    |
| 17. Service Restart Replay    --> Service restarted; slip file NOT recreated; consumed state preserved        |
+---------------------------------------------------------------------------------------------------------------+
```

---

## 6. SECURITY & RED TEAM SUITE RESULTS (RT-01 TO RT-12)

The 12-vector adversarial attack suite was executed against the running service:

| Test ID | Description | Target Endpoint | Expected Status | Actual Status | Verdict |
| :---: | :--- | :--- | :---: | :---: | :---: |
| **RT-01** | Technician API called without technician secret/token | `POST /api/v1/technician/session/open` | HTTP 401/403 | **HTTP 401** | **PASS** |
| **RT-02** | Wrong technician secret supplied | `POST /api/v1/technician/session/open` | HTTP 403 | **HTTP 403** | **PASS** |
| **RT-03** | Wrong device binding presented | `GET /api/v1/technician/config` | HTTP 403 | **HTTP 403** | **PASS** |
| **RT-04** | Wrong / rogue hospital tenant ID | `POST /api/v1/technician/session/open` | HTTP 403 | **HTTP 403** | **PASS** |
| **RT-05** | Expired / revoked technician token | `GET /api/v1/technician/config` | HTTP 403 | **HTTP 403** | **PASS** |
| **RT-06** | Closed technician session reused | `GET /api/v1/technician/config` | HTTP 403 | **HTTP 403** | **PASS** |
| **RT-07** | Staff token attempting technician initial-admin endpoint | `POST /api/v1/technician/initial-admin` | HTTP 403 | **HTTP 403** | **PASS** |
| **RT-08** | Duplicate initial admin staffCode provisioning | `POST /api/v1/technician/initial-admin` | HTTP 409 | **HTTP 409** | **PASS** |
| **RT-09** | Consumed commissioning secret slip reuse | File system check | Deleted (false) | **Deleted (false)** | **PASS** |
| **RT-10** | Temporary admin password after password change | `POST /api/v1/auth/login` | HTTP 401 | **HTTP 401** | **PASS** |
| **RT-11** | Weak permanent password (<8 characters) | `POST /api/v1/auth/change-password` | HTTP 400 | **HTTP 400** | **PASS** |
| **RT-12** | Unauthenticated access to Technician Console | `GET /api/v1/technician/config` | HTTP 403 | **HTTP 403** | **PASS** |

---

## 7. PBKDF2 CRYPTOGRAPHIC TRUTH RECONCILIATION

Direct static code inspection and runtime assertions resolve the historical documentation inconsistency between 20,000 and 100,000 iterations:

| Mechanism | Code Authority | Algorithm | Iterations | Salt Size | Digest Size | Storage Format | Constant-Time Verification |
| :--- | :--- | :--- | :---: | :---: | :---: | :--- | :---: |
| **Normal Staff Users** | `PasswordHasher.hashPassword()` | PBKDF2-HMAC-SHA256 | **20,000** | 16 bytes (Base64Url) | 32 bytes (256-bit) | `pbkdf2_sha256$<iter>$<salt>$<digest>` | Yes (`_constantTimeEquals`) |
| **Initial Administrator** | `PasswordHasher.hashPassword()` | PBKDF2-HMAC-SHA256 | **20,000** | 16 bytes (Base64Url) | 32 bytes (256-bit) | `pbkdf2_sha256$<iter>$<salt>$<digest>` | Yes (`_constantTimeEquals`) |
| **Technician Secret** | `TechnicianService.ensureCommissioningSecretProvisioned()` | PBKDF2-HMAC-SHA256 | **20,000** | 16 bytes (Base64Url) | 32 bytes (256-bit) | `pbkdf2_sha256$<iter>$<salt>$<digest>` | Yes (`_constantTimeEquals`) |

### Iteration Agility & Threshold Invariant:
In `PasswordHasher.verifyPassword(String plainPassword, String storedHash)`:
1. The verifier dynamically parses the iteration count from the hash string (`parts[1]`).
2. An explicit security floor enforces `iterations >= 1000`; any hash with `< 1000` is rejected immediately.
3. The reference to "100,000 iterations for technician secrets" in legacy markdown was an un-reified documentation note; authoritative source code strictly reifies 20,000 rounds across all components.

---

## 8. TEST-CREDENTIAL ISOLATION AUDIT

A repository-wide AST and regex scan audited every occurrence of test credentials across all code, tests, migrations, and documentation:

| Scanned String | Production Code (`lib/`) | Migrations / Seeds | Runtime Defaults | Tests (`test/`) | Markdown Docs | Classification |
| :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| `TempAdminSecret#2026` | **0** | **0** | **0** | 2 | 4 | **TEST-ONLY / DOCS** |
| `PermanentAdminPass#2026` | **0** | **0** | **0** | 3 | 4 | **TEST-ONLY / DOCS** |
| `InitialAdminTempPass#2026` | **0** | **0** | **0** | 1 | 2 | **TEST-ONLY / DOCS** |
| `PermanentAdminSecret#2026` | **0** | **0** | **0** | 1 | 1 | **TEST-ONLY / DOCS** |
| `AdminPassword#2026` | **0** | **0** | **0** | 1 | 14 | **TEST-ONLY / DOCS** |
| `admin@medcore.local` | **0** | **0** | **0** | 4 | 14 | **TEST-ONLY / DOCS** |

**Summary**:
- `PRODUCTION CODE = 0`
- `MIGRATION/SEED = 0`
- `RUNTIME DEFAULT = 0`
- Zero hardcoded backdoors exist in production paths.

---

## 9. STATIC ANALYSIS & REGRESSION TEST RESULTS

### Static Analysis:
- **`medcore_desktop`**: `flutter analyze` reports **No issues found!** (code 0).
- **`medcore_local_service`**: `dart analyze` reports **0 errors, 0 warnings** (code 0).

### Automated Test Suites:
- **GitHub Actions Desktop Test Suite**: **12/12 passed** (Run `40841740280`, Job `123339504752`).
- **Local Backend Batch 14 (Technician Bootstrap & Admin Handover)**: **21/21 passed** (code 0).
- **Local Release Acceptance Verification**: **12/12 Red Team vectors + 8 lifecycle phases PASSED (100%)**.

---

## 10. FACT / INFERENCE / UNKNOWN RECONCILIATION

### FACT (Directly Verified):
1. GitHub `main` commit `31d6e29aacad2ef5b5536755a783a9260721dc88` was built by GitHub Actions workflow `windows-release.yml` in run `40841740280`.
2. The checked-out commit on the GitHub Actions runner was explicitly audited and logged as `31d6e29aacad2ef5b5536755a783a9260721dc88`.
3. GitHub Actions produced downloadable Windows release artifact `12883660582` (`medcore-platinum-windows-main-batch9-eval-31d6e29.zip`, SHA256 `61B761A8685AE24413106F449E06E891ECF00BCB526F0C85A59639AF707B5408`).
4. The packaged binary `medcore_desktop.exe` (146,432 bytes, SHA256 `B8CC8727BF114DEFC293FABACF9E777CEAF56852620CAD1FCCC4B4D93B30886F`) executes as a real OS process (PID 2848).
5. Fresh start creates a one-time secret slip `FIRST_RUN_COMMISSIONING_SECRET.txt` which is physically deleted upon first successful session opening.
6. Initial administrator creation sets `force_password_change = 1` and rejects staff access until permanent password change is completed, setting `force_password_change = 0`.
7. Direct MariaDB SQL read-backs confirm state reification across `mc_technician_sessions`, `mc_facility_config`, `mc_staff`, and `mc_audit_logs`.
8. All test credentials are isolated from production code, seeds, and migrations (`PRODUCTION CODE = 0`).

### INFERENCE:
1. Since the GitHub Actions runner environment uses the identical Flutter 3.22.0 Windows compilation toolchain and source code as the local environment, the artifact's UI presentation is functionally identical to the local evaluation build.
2. Hospital IT deploying the Windows artifact on a physical workstation can follow the real-world runbook (`FIRST_RUN_COMMISSIONING_SECRET.txt` or `bin/commission.dart`) to achieve authenticated first-admin handover without any backdoors.

### UNKNOWN:
1. Performance under high concurrency (>100 concurrent hospital tablet clients) was not evaluated during this single-workstation release verification gate.
2. Third-party HL7/FHIR remote cloud synchronization adapters remain deferred to future milestones outside the scope of this desktop release gate.

---

## 11. FINAL VERDICT

```text
================================================================================
                                FINAL VERDICT:
                     CLOSED WITH NON-BLOCKING LIMITATIONS
================================================================================
```

### Justification:
The complete first-installation lifecycle (clean installation, random secret generation, physical slip creation, technician authentication, automatic slip deletion, facility configuration, initial administrator creation with forced password change, password update, and normal system operation) is 100% verified on the physical runtime and backed by the official GitHub Actions Windows release artifact. Non-blocking limitations relate strictly to deferred future enterprise extensions (FHIR remote sync, cloud backup providers).
