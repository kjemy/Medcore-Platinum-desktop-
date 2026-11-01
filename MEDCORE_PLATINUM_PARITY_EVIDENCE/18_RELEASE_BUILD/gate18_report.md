# GATE 18: RELEASE CANDIDATE BUILD & VERIFICATION REPORT
**Project:** MedCore Platinum Desktop  
**Status:** PASS  
**Timestamp:** 2026-11-01T23:28:45Z  
**Branch:** feature/platinum-functional-parity-arabic  
**Framework:** Khaled Universal Software Engineering Constitution (Gate 18)

---

## 1. Executive Summary
Gate 18 certifies the self-contained Release Candidate packaging, portable directory layout, process orchestration scripts, and offline deployment prerequisites. MedCore Platinum package structure guarantees that all required runtimes (bundled MariaDB 11.4, MedCore Local Service, Flutter Desktop executable, C++ runtime DLLs, and additive migrations) operate in complete isolation without external internet access or external Windows service dependencies.

---

## 2. Release Candidate Architecture & Layout

```text
medcore-platinum-windows-v1.0.0-parity-rc5/
├── medcore_desktop.exe                # Native Windows Flutter Desktop Executable
├── start_medcore_system.bat           # 10-Stage Verified Self-Contained System Launcher
├── stop_medcore_system.bat            # Graceful Process Teardown Script
├── commission_technician.bat          # Hardware Token & Technician Provisioning Tool
├── README_INSTALL.txt                 # Air-Gapped Deployment Instructions
├── release_manifest.json              # Cryptographic SHA-256 Release Manifest
├── data/                              # Flutter Assets, Localized Fonts & Engine Binaries
├── runtime/                           # Local Data & Security Directory
│   ├── mariadb_data/                  # Authoritative MariaDB Database Storage
│   ├── security/                      # Cryptographic Secrets & Token Storage
│   └── logs/                          # Operational & Audit Trail Logs
└── service/                           # Self-Contained Backend Services
    ├── medcore_local_service.exe      # Dart Shelf Local Microservices Executable
    ├── mariadb/                       # Bundled MariaDB 11.4 Portable Server
    │   ├── bin/mariadbd.exe           # MariaDB Database Engine Daemon
    │   └── share/                     # Charsets, Error Messages, Language Files
    └── sql/migrations/                # Certified Flyway-Style Migrations (V001 - V019)
```

---

## 3. Operational Integrity & Launcher Verification
1. **Dynamic Credential Resolution**:
   `start_medcore_system.bat` dynamically extracts the PBKDF2/AES-protected database credentials from `runtime\security\db_credentials.json`, strictly avoiding hardcoded passwords.
2. **Loopback Isolation (`127.0.0.1`)**:
   MariaDB is launched strictly binding to `127.0.0.1:3307`. External interface binding is strictly blocked, ensuring zero network exposure to adjacent local networks.
3. **Additive Schema Synchronization**:
   On first boot, the Local Service automatically reifies additive migration `V019__master_definitions_and_clinic_extensions.sql` idempotently, preserving existing clinical data without data destruction or schema truncation.

---

## 4. Packaging Manifest Verification
- All executable binaries, DLLs, and migration scripts are inventoried with SHA-256 hashes.
- Clean shutdown script kills child processes gracefully (`mariadbd.exe`, `medcore_local_service.exe`) with zero zombie process retention.

**GATE 18 VERDICT: PASS**
