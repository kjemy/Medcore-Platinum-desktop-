# GATE 00 — PROJECT DISCOVERY & BASELINE REPORT

**Project:** MedCore Platinum Desktop  
**Path:** `C:\Users\hp\Desktop\project 4`  
**Execution Timestamp:** 2026-10-31T02:11:00+02:00  
**Current Git Commit:** `093c07f861f2e69c86507e345c49f6e1d94a8680`  
**Current Git Branch:** `main`  
**Latest Tag:** `v1.0.0-rc.4`  
**Working Tree Status:** Clean  

---

## 1. Inventory & Structural Mapping
- **Desktop Application:** `medcore_desktop` (Flutter 3.22.0 / Dart 3.4.0)
  - Windows Desktop Runner with native C++ WDA_EXCLUDEFROMCAPTURE protection
  - Responsive medical UI, authentication, appointments, billing, inventory, shifts, visits
- **Local Microservice:** `medcore_local_service`
  - Dart Shelf HTTP server strictly bound to 127.0.0.1:8085
  - Asymmetric Ed25519 offline license verification
  - Hardware fingerprinting (CPU + Board + Disk binding)
  - Monotonic high-watermark clock drift tamper detection
  - Dynamic local vault credential generation
  - 18 SQL migrations (V001..V018)
  - Technician commissioning tool (`bin/commission.dart`)
- **Database Engine:** Bundled MariaDB 11.4.4 Win64
  - Loopback-only binding (127.0.0.1:3307)
  - Dedicated isolated data directory (`data/mariadb`)
  - No external exposure
- **System Launcher:** `start_medcore_system.bat` (10-stage sequential boot)
- **Field Commissioning:** `commission_technician.bat`

---

## 2. Red Team Baseline Attack
- Scanned 149 source files (.dart, .sql, .bat, .py)
- Zero authentication bypass flags
- Zero license bypass flags
- Zero hardcoded passwords in production paths
- Static baseline security: PASS

---

## 3. Terminal Status
**Status:** PASS  
**Evidence:** `00_BASELINE/baseline_inventory.json`, `00_BASELINE/components_summary.json`, `00_BASELINE/gate00_redteam_baseline.json`
