# MEDCORE PLATINUM DESKTOP
# FINAL RELEASE MANIFEST & CRYPTOGRAPHIC SIGN-OFF
**Document Version:** 1.0.0 — Final Independent Certification Closure  
**Timestamp:** 2026-10-30T17:34:00Z  
**Classification:** Authoritative Distribution Manifest  
**Package Name:** `medcore-platinum-windows-main-commercial-closure-95a2ca8.zip`  
**Package Classification:** Category B — Desktop Client + Local Service + Bundled MariaDB 11.4 Self-Contained Offline Hospital Distribution Package  
**Repository:** `kjemy/Medcore-Platinum-desktop-`  
**Release Tag / Anchor:** `v1.0.0-rc.3` (Commit `713a8a4578cb7f82258b57497afa800346280534` Confirmed Untouched)  
**Commercial Baseline Commit:** `95a2ca8b163ee4c97577bc5f0ede92ef7511d642`  

---

## 1. PRODUCTION EXECUTABLE INVENTORY & HASH REGISTRY

All five core production executables have been built from clean source trees and cryptographically hashed:

| Executable File Path | File Size (Bytes) | SHA-256 Checksum | Build Source / Compiler | Role & Purpose |
| :--- | :--- | :--- | :--- | :--- |
| `medcore_desktop.exe` | 54,635,520 | `5FCCA1E797DEDA272702D49360D413726B4EBA057CB169DC9C20BD80736D47D7` | Flutter 3.29.0-1.0.pre.18 (MSVC x64 Release) | Frontend UI Desktop Workstation Shell |
| `service/medcore_local_service.exe` | 13,294,080 | `B1E1D0486F1D2EF70C1CD1673DEAC6ADCEE969DF6E885CA33D73B81A3D560E07` | Dart 3.7.0 AOT Compiler (`dart compile exe`) | Local Hospital Backend Service + API Engine |
| `service/medcore_commission.exe` | 10,779,648 | `98858272C2D76506752B70EE7D51B242E6426388EABE3E43DCFD4C40C1CEC312` | Dart 3.7.0 AOT Compiler (`dart compile exe`) | Technician Bootstrap & Commissioning Tool |
| `service/mariadb/bin/mariadbd.exe` | 27,247,104 | `92DA590AC33516F0B95494325C143A5918C7BA3B3E081B467CF80B1A7370E693` | MariaDB Community 11.4.4 (GPLv2 x64) | Bundled Authoritative MariaDB Database Daemon |
| `service/mariadb/bin/mariadb.exe` | 7,654,400 | `89782A57491D7B249A3648C19E536F0395529259D6AA448617AC68D2C5E53373` | MariaDB Community 11.4.4 (GPLv2 x64) | MariaDB Command Line Administrative Client |

---

## 2. DISTRIBUTION DIRECTORY STRUCTURE

The self-contained offline hospital release package exhibits the following internal layout:

```text
medcore-platinum-windows-main-commercial-closure-95a2ca8/
├── medcore_desktop.exe                   # Flutter Desktop Workstation executable
├── flutter_windows.dll                   # Flutter runtime engine DLL
├── data/                                 # UI flutter assets, icudtl.dat, fonts
│   ├── icudtl.dat
│   └── flutter_assets/
├── service/                              # Local Backend & Database runtime
│   ├── medcore_local_service.exe         # Local Shelf REST API daemon
│   ├── medcore_commission.exe            # Technician provisioning utility
│   ├── sql/
│   │   └── migrations/                   # 18 Versioned SQL migrations (V001 to V018)
│   ├── scripts/
│   │   └── provision_mariadb.ps1         # Dynamic 32-char CSPRNG credential generator
│   └── mariadb/                          # Bundled MariaDB 11.4.4 distribution
│       ├── bin/                          # mariadbd.exe, mariadb.exe, etc.
│       ├── lib/                          # plugins, auth_gssapi, storage engines
│       ├── share/                        # charsets, english error messages
│       └── COPYING                       # GPLv2 License
├── runtime/
│   ├── mariadb_data/                     # Physical DB tablespaces (created on provisioning)
│   └── security/                         # Dynamic credentials (db_credentials.json)
├── packaging/
│   ├── start_medcore_system.bat          # 1-Click launcher: MariaDB + Service + Desktop
│   ├── commission_technician.bat         # Field technician initialization CLI
│   └── README_INSTALL.txt                # Operational commissioning runbook
├── start_medcore_system.bat              # Root launcher convenience link
├── commission_technician.bat             # Root technician convenience link
├── README_INSTALL.txt                    # Root quickstart instructions
└── release_manifest.json                 # Machine-readable cryptographic manifest
```

---

## 3. SYSTEM REQUIREMENTS & RUNTIME CONSTRAINTS

- **Operating System:** Windows 10 (Build 19041+) or Windows 11 x64.
- **Hardware Architecture:** x86_64 / AMD64 (ARM64 requires emulation).
- **RAM:** 4 GB minimum (8 GB recommended for concurrent hospital LAN clients).
- **Disk Storage:** 10 GB free space on local SSD (NTFS formatted).
- **Network Ports:**
  - `TCP 127.0.0.1:3307` (Local MariaDB daemon — strictly loopback bound).
  - `TCP 127.0.0.1:8443` (Local MedCore REST Service — LAN exposed if enabled).
- **Internet Dependency:** **ZERO (0%)**. 100% self-contained and offline operational.

---

## 4. FIELD COMMISSIONING RUNBOOK

1. **Step 1 — Extract Archive:** Extract `medcore-platinum-windows-main-commercial-closure-95a2ca8.zip` to `C:\MedCore\`.
2. **Step 2 — Technician Initialization:** Run `commission_technician.bat`. This automatically:
   - Initializes MariaDB database cluster at `runtime/mariadb_data/`.
   - Generates a unique 32-character CSPRNG password in `runtime/security/db_credentials.json`.
   - Applies 18 database migrations (V001 to V018) establishing 100 tables.
   - Enrolls server workstation device identity with hardware binding SHA-256.
   - Prompts technician to enter hospital facility details and import signed `.mclic` license.
3. **Step 3 — Hospital Launch:** Double click `start_medcore_system.bat`.
   - Starts bundled MariaDB on port 3307.
   - Starts local backend service on port 8443.
   - Launches Flutter desktop workstation shell connected to local service.

---

## 5. FINAL RELEASE ATTESTATION

The release package represents the authoritative, certified commercial build of MedCore Platinum Desktop. All static credentials have been purged, RSA-2048 offline licensing is enforced, machine hardware binding is validated, and clinical data safety is guaranteed.

**Release Manifest Status:** `VERIFIED & SIGNED OFF`
