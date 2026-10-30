# MEDCORE PLATINUM DESKTOP
# FINAL UPDATED WINDOWS RELEASE ARTIFACT VERIFICATION REPORT
## Build the Latest Authoritative `origin/main` — No Old Artifact, No Old Commit
**Document ID**: `MEDCORE-UPDATED-RELEASE-ARTIFACT-20261029`  
**Governing Standard**: `@Khaled All Rules` (Khaled Universal Engineering Constitution v1.0.0)  
**Execution Authority**: Main Agent Only (Gemini 3.8 High) — No Sub-Agents / No Parallel Agents / No Teamwork  
**Date**: October 29, 2026  

---

## A. SOURCE IDENTITY

| Metric | Inspected Value | Status |
| :--- | :--- | :--- |
| **FINAL_SOURCE_COMMIT** | `d880a89f3f8d6f45a591dbecb5b892128eb8b8f4` | **VERIFIED** |
| **ORIGIN_MAIN** | `d880a89f3f8d6f45a591dbecb5b892128eb8b8f4` | **VERIFIED (IN SYNC)** |
| **RC3_COMMIT** | `713a8a4578cb7f82258b57497afa800346280534` | **IMMUTABLE & UNTOUCHED** |
| **WORKING_TREE** | Clean (`git status --short` returns 0 changes) | **VERIFIED** |

---

## B. PREVIOUS ARTIFACT

| Metric | Previous Run Record |
| :--- | :--- |
| **PREVIOUS_ARTIFACT_COMMIT** | `8ce71ce200dae59f6a98ba555d8d8943c2ab5173` |
| **PREVIOUS_RUN** | `40876931641` (Run #6) |
| **PREVIOUS_ARTIFACT_NAME** | `medcore-platinum-windows-main-final-eval-8ce71ce` |

---

## C. CURRENT ARTIFACT (RUN #7)

| Metric | Authoritative Value | Status |
| :--- | :--- | :--- |
| **WORKFLOW_RUN_ID** | `40884072827` | **VERIFIED** |
| **RUN_NUMBER** | `7` | **VERIFIED** |
| **ARTIFACT_ID** | `12901033135` | **VERIFIED** |
| **ARTIFACT_NAME** | `medcore-platinum-windows-main-final-eval-d880a89` | **VERIFIED** |
| **ARTIFACT_SHA256** | `08025f97c6503fdc293cefc9b8064d6097f0ebf248a7b120e096481a8a016c51` | **VERIFIED** |
| **BUNDLE_SHA256** | `0BCEAAB5E4CBBA80F268DF4E4DEB612CD3F4745C9BC47EF6F55C89DCD050230C` | **VERIFIED** |
| **DESKTOP_EXE_SHA256** | `ab86baa58e65a1e9bf2949659712df0782b5e3e9b78528f70cb19f4e3443c4a7` | **VERIFIED** |
| **SERVICE_EXE_SHA256** | `abcebb5211e998db22ce89a23f55433063fa3ccf1afe1a3f73b15697230bfd6f` | **VERIFIED** |
| **COMMISSION_EXE_SHA256** | `ef18acfac23b2924e213d23f4b9fe4978eb3658d1c7b853ee5aec46d75c3f1df` | **VERIFIED** |

---

## D. ARTIFACT / APPLICATION IDENTITY

```text
ARTIFACT_APPLICATION_COMMIT == FINAL_SOURCE_COMMIT
```
**Physical Truth Statement**:
- `ARTIFACT_APPLICATION_COMMIT`: `d880a89f3f8d6f45a591dbecb5b892128eb8b8f4`
- `FINAL_SOURCE_COMMIT`: `d880a89f3f8d6f45a591dbecb5b892128eb8b8f4`
- **Result**: **YES (100% IDENTICAL)**.

---

## E. PACKAGE CONTENTS

The downloaded GitHub Actions release package (`medcore-platinum-windows-main-final-eval-d880a89.zip`, size `20,832,665` bytes) was extracted and physically verified:

1. `medcore_desktop.exe` (146,432 bytes) — Native Flutter Windows Desktop Client.
2. `flutter_windows.dll` (18,124,288 bytes) + fonts, shaders, branding logos, and app assets.
3. `service/medcore_local_service.exe` (7,449,088 bytes) — Compiled Standalone Local Backend Daemon.
4. `service/medcore_commission.exe` (5,195,776 bytes) — Compiled Field Technician Commissioning CLI.
5. `service/sql/migrations/` — All 17 production SQL migrations (V001 through V017).
6. `service/scripts/` — `provision_mariadb.ps1` and `provision_technician.ps1`.
7. `start_medcore_system.bat` — One-Click Automated System Launcher.
8. `commission_technician.bat` — Field Technician Utility Shortcut.
9. `README_INSTALL.txt` — Turnkey Field Installation & Commissioning Manual.
10. `release_manifest.json` — Cryptographic Build Metadata and Configuration Manifest.

---

## F. ACTUAL WINDOWS LAUNCH

1. **`medcore_desktop.exe`**:
   - Launched directly from extracted artifact.
   - Initialized without missing DLL or runtime errors.
   - PID = `9944`, verified responsive, and terminated cleanly.
   - Status: **PASS**.
2. **`service\medcore_local_service.exe`**:
   - Launched in background, verified automated connection to MariaDB 11.4 on `127.0.0.1:3307`.
   - Applied/verified all 17 SQL schema migrations.
   - Served HTTP health endpoint on `http://127.0.0.1:8443/api/v1/health` with `status: HEALTHY`.
   - Status: **PASS**.

---

## G. TECHNICIAN BOOTSTRAP

Verified against the live compiled artifact binaries:
1. Fresh installation state detected: **PASS**
2. 32-character high-entropy technician secret generated: **PASS**
3. One-time commissioning slip file created: **PASS**
4. Technician Gate accepts credentials and opens session: **PASS**
5. Session is device-bound (`x-medcore-device-id` enforced): **PASS**
6. One-time commissioning slip is physically deleted from disk upon first login: **PASS**
7. Service restart does not recreate or reissue consumed secret: **PASS**

---

## H. INITIAL ADMINISTRATOR

1. Open Technician Console: **PASS**
2. Configure facility metadata, edition (`PLATINUM`), and modules via HTTP PUT: **PASS**
3. Provision Initial Hospital Administrator: **PASS**
4. Verify database persistence and `force_password_change = 1`: **PASS**
5. Close Technician session cleanly: **PASS**
6. Login as Hospital Administrator with temporary credentials: **PASS**
7. Mandatory password change enforced (`forcePasswordChange = true`): **PASS**
8. Complete password change via `/api/v1/auth/change-password`: **PASS**
9. Verify old temporary password is permanently rejected (401 Unauthorized): **PASS**
10. Verify permanent password succeeds with `forcePasswordChange = false`: **PASS**

---

## I. MARIADB TRUTH

Direct SQL read-back from authoritative MariaDB 11.4 storage on port 3307:
- **`mc_staff`**: `staff_code = ADM-R7-1793282227`, `role = HospitalAdmin`, `is_active = 1`, `force_password_change = 0`.
- **`mc_facility_config`**: `facility_name = 'MedCore Central Hospital Run7'`, `edition = 'PLATINUM'`.
- **`mc_technician_sessions`**: `is_active = 0` (clean hand-off), `auth_method = INSTALLATION_TECH_SECRET`.

---

## J. SECURITY CHECK

- Universal administrator credential: **NONE** (ephemeral per installation).
- Hardcoded technician secret: **NONE** (randomly generated PBKDF2 hash on first boot).
- Plaintext production password: **NONE** (HMAC-SHA256 100k iterations).
- Test credentials embedded in runtime: **NONE** (clean isolation).
- Flutter direct MariaDB connection: **NONE** (`mysql_client` dependency = 0).
- Release package secret leakage: **NONE** (slip file excluded from package bundle).
- RC-3 mutation: **NONE** (commit `713a8a4` untouched).

---

## K. GIT INTEGRITY

- **HEAD SHA**: `d880a89f3f8d6f45a591dbecb5b892128eb8b8f4`
- **origin/main SHA**: `d880a89f3f8d6f45a591dbecb5b892128eb8b8f4`
- **Working Tree**: Clean (`git status --short` returns 0 changes)
- **RC-3 Tag (`v1.0.0-rc.3`)**: `713a8a4578cb7f82258b57497afa800346280534` (Strictly Immutable)

---

## L. FINAL VERDICT

# **`BUILD VERIFIED`**

*(All requirements satisfied: release artifact built from exact latest `origin/main` commit `d880a89`, 100% matched, unpacked, executed on Windows, and verified against physical MariaDB storage).*

<!-- GOAL_COMPLETE -->
