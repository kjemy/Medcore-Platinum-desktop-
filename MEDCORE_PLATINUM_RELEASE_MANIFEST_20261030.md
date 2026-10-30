# MEDCORE PLATINUM DESKTOP
# OFFICIAL RELEASE MANIFEST
## COMMERCIAL RIGHTS & OFFLINE LICENSING CLOSURE RELEASE (RUN #14/15)

**Project:** MedCore Platinum Desktop  
**Release Tag / Reference:** `v1.0.0-rc.3-commercial-closure`  
**Target Repository:** `kjemy/Medcore-Platinum-desktop-`  
**Branch:** `main`  
**Production Commit SHA:** `95a2ca8b163ee4c97577bc5f0ede92ef7511d642`  
**Base RC-3 Immutable Anchor:** `713a8a4578cb7f82258b57497afa800346280534`  
**Package Classification:** `B) Desktop + Local Service + Bundled MariaDB 11.4 Self-Contained Offline Hospital Distribution Package`  
**Build Date:** October 30, 2026  
**Governance:** Khaled Universal Engineering Constitution (Gate 13, Gate 19 & Gate 24)  

---

## 1. RELEASE ARTIFACT IDENTIFIERS & FORENSIC HASHES

| Attribute | Authoritative Value |
|---|---|
| **Archive File Name** | `medcore-platinum-windows-main-commercial-closure-95a2ca8.zip` |
| **Archive File Size** | 109,571,423 bytes (104.50 MB) |
| **Archive SHA-256 Digest** | `30DDF16F79CF13175EBE88C2EB3A935B93D3DECA4BE8D942EE41DCCC20A0036E` |
| **Staging Root Directory** | `package_staging/medcore-platinum-windows-main-commercial-closure-95a2ca8` |
| **Release Manifest File** | `package_staging/medcore-platinum-windows-main-commercial-closure-95a2ca8/release_manifest.json` |

---

## 2. BINARY SUB-COMPONENT CHECKSUMS

| Component | Path Inside Archive | File Size (Bytes) | SHA-256 Digest |
|---|---|---|---|
| **Desktop Client Executable** | `medcore_desktop.exe` | 51,802,624 | `BA44F0075D0F55DEB2F90B1CF4D86D82F7B0108A6BC0BE8B19672C9C8C236E0D` |
| **Local Service Daemon** | `service/medcore_local_service.exe` | 13,858,304 | `E3A587483DA98FE6055A7BEA1C184AD5517FCBAC9C90A6D4941AD13EEAF43BA8` |
| **Technician Commission CLI** | `service/medcore_commission.exe` | 13,678,080 | `C976B499B4A480A6DB2B48002204F61A40360B1A8DFF13C41D678F488F749587` |
| **MariaDB Server Daemon** | `service/mariadb/bin/mariadbd.exe` | 24,576 | `92DA590AC33516F0B95494325C143A5918C7BA3B3E081B467CF80B1A7370E693` |
| **MariaDB Client CLI** | `service/mariadb/bin/mariadb.exe` | 4,817,408 | `89782A57491D7B249A3648C19E536F0395529259D6AA448617AC68D2C5E53373` |
| **MariaDB Database Initializer**| `service/mariadb/bin/mariadb-install-db.exe` | 3,293,184 | `549A52BC7D585938D2C831F806ABA7FB51AE117C174E49F044F6EDDA9AC5EE46` |
| **Flutter Windows Engine DLL** | `flutter_windows.dll` | 21,399,552 | `4E913BE2F18A3267590212EB9BCBDC93A4F84BD8FA1CD235D9652BE8E2DC418E` |
| **System Launcher** | `start_medcore_system.bat` | 7,120 | `5CDCE446E65239EAC15F1C865487612EBF3F8CFEE5C1046A0B6FEFE3F571DDEB` |
| **Commissioning Shortcut** | `commission_technician.bat` | 3,420 | `E6BD839632C4A738914F8E5FE225B8E88EAF41BC2F97D3C52309C5DCDE3288EF` |
| **Database Migration V018** | `service/sql/migrations/V018__commercial_entitlement_and_hardware_binding.sql` | 1,580 | `4731E01B8DEFA75908C868EB1F790757E442436C9D187EDFBD7C9F92070FFFA5` |

---

## 3. DISTRIBUTION ARCHIVE STRUCTURE & CONTENTS

```text
medcore-platinum-windows-main-commercial-closure-95a2ca8/
├── data/                                 # Flutter assets, fonts, icons
├── packaging/                            # Batch launcher utilities
│   ├── start_medcore_system.bat          # 10-Stage Fail-Closed System Launcher
│   ├── commission_technician.bat         # Technician first-run CLI wrapper
│   └── README_INSTALL.txt                # Hospital IT deployment documentation
├── runtime/                              # Local runtime persistence
│   ├── mariadb_data/                     # Hospital MariaDB tablespace
│   └── security/                         # Master technician secrets & license store
├── service/                              # Local backend service subsystem
│   ├── mariadb/                          # Bundled MariaDB 11.4.4 Win64 distribution
│   │   ├── bin/                          # mariadbd.exe, mariadb.exe, etc.
│   │   ├── lib/                          # Plugins & storage engines
│   │   ├── share/                        # Error strings & character sets
│   │   └── licenses/                     # GPLv2, CREDITS, README notices
│   ├── scripts/                          # Automation scripts
│   │   ├── provision_mariadb.ps1         # Dynamic DB initialization & password generator
│   │   └── provision_technician.ps1      # First-run commissioning script
│   ├── sql/migrations/                   # Authoritative database migrations (V001..V018)
│   ├── medcore_local_service.exe         # Compiled native Dart daemon (Port 8443)
│   └── medcore_commission.exe            # Compiled commissioning CLI
├── commission_technician.bat             # Root commissioning shortcut
├── flutter_windows.dll                   # Flutter runtime engine
├── medcore_desktop.exe                   # Flutter desktop client application
├── README_INSTALL.txt                    # IT deployment guide
├── release_manifest.json                 # Machine-readable cryptographic truth manifest
└── start_medcore_system.bat              # One-click hospital system launcher
```

---

## 4. RELEASE TRUTH MANIFEST (`release_manifest.json`)

```json
{
  "project": "MedCore Platinum Desktop",
  "release": "v1.0.0-rc.3-commercial-closure",
  "build_type": "EVALUATION",
  "package_classification": "B) Desktop + Local Service + Bundled MariaDB 11.4 Self-Contained Offline Hospital Distribution Package",
  "commercial_rights_closure": true,
  "offline_licensing": "RSA-2048 Signed .mclic with PKCS#1 v1.5",
  "hardware_binding": "SHA-256 Windows Host Machine Fingerprint",
  "anti_rollback_clock_guard": "Monotonic Security Anchor + Keyed HMAC Seal",
  "dynamic_db_credentials": "32-character CSPRNG Generated root password",
  "static_passwords_eliminated": [
    "MedCoreLocalDb#2026"
  ],
  "bundled_mariadb": true,
  "mariadb_version": "11.4.4-MariaDB",
  "desktop_binary_sha256": "BA44F0075D0F55DEB2F90B1CF4D86D82F7B0108A6BC0BE8B19672C9C8C236E0D",
  "service_binary_sha256": "E3A587483DA98FE6055A7BEA1C184AD5517FCBAC9C90A6D4941AD13EEAF43BA8",
  "mariadb_daemon_sha256": "92DA590AC33516F0B95494325C143A5918C7BA3B3E081B467CF80B1A7370E693",
  "mariadb_client_sha256": "89782A57491D7B249A3648C19E536F0395529259D6AA448617AC68D2C5E53373",
  "offline_capable": true,
  "application_commit": "95a2ca8b163ee4c97577bc5f0ede92ef7511d642",
  "build_timestamp": "2026-10-30T14:00:20Z"
}
```

---

## 5. REPRODUCTION & VERIFICATION COMMANDS

To independently verify the release archive on any Windows machine:
```powershell
# 1. Verify archive hash
(Get-FileHash -Path "medcore-platinum-windows-main-commercial-closure-95a2ca8.zip" -Algorithm SHA256).Hash
# Expected: 30DDF16F79CF13175EBE88C2EB3A935B93D3DECA4BE8D942EE41DCCC20A0036E

# 2. Extract archive
Expand-Archive -Path "medcore-platinum-windows-main-commercial-closure-95a2ca8.zip" -DestinationPath "medcore_deploy"

# 3. Launch self-contained system
cd "medcore_deploy"
.\start_medcore_system.bat
```
