# MEDCORE — FLUTTER MULTI-PLATFORM CLIENT ARCHITECTURE BLUEPRINT
**Document ID**: `DOC-11` | **Target Platforms**: Windows Desktop (Primary), Android Tablet/Phone, iPadOS

---

## 1. Guiding Principles (Zero Premature Lock-In, Strict Separation of Concerns)
1. **Flutter Client is a Pure Presentation & Interaction Layer**:
   - All authoritative financial equations (`FIN-001`..`FIN-008`), commission calculations, shift reconciliations, FIFO stock deductions, and RBAC/Data-Scope filters execute in the **Local MedCore Service**.
   - The Flutter client performs immediate UI validation and preview calculations for responsiveness, but **never commits financial or clinical truth directly to local client storage**.
2. **Unified Codebase with Adaptive Responsive Shells**:
   - **Desktop Shell (`Windows >= 1280px`)**: Persistent collapsible RTL/LTR Sidebar (`82` canonical routes), multi-pane workspace (e.g., Queue on right + Clinical Chart on left), full keyboard shortcut navigation (`F1` Quick Check-In, `F2` Patient Lookup, `Ctrl+P` Thermal Receipt Print), USB Barcode Scanner (`HID` keyboard wedge / serial) support.
   - **Tablet Shell (`Android & iPadOS 768px–1199px`)**: Navigation Rail + touch-optimized clinical cards for Bedside Nursing (`e-MAR`, Vitals), ICU/NICU Flowsheets, Dialysis Chairside charting, and OR Safety Checklists.

---

## 2. Layered Package / Module Structure (Conceptual Blueprint)
```text
medcore_client/
├── core/
│   ├── network/          # HTTPS LAN client, mTLS/Device-Sig interceptor, Idempotency-Key injector, WebSocket stream
│   ├── security/         # Native platform channels: ScreenProtection (Win32/Android/iOS), HardwareFingerprint, SecureStorage
│   ├── money/            # Fixed-point Decimal(14,4) value object (NO double/float arithmetic!)
│   ├── permissions/      # 10-Role + 261-Permission + 4-Action-Flag evaluator & SecureScreenWrapper
│   ├── localization/     # Arabic (RTL Primary) & English (LTR) strings extracted from Frontend/messages/*.json
│   └── printing/         # Thermal POS Receipt (80mm ESC/POS), Barcode Label (ZPL/TSPL for Lab Tubes), A4 PDF Reports
├── domain/               # Pure Dart immutable entities & API contracts (mapped 1:1 to Local MedCore Service DTOs)
└── features/             # 19 Feature Modules matching CANONICAL_NAVIGATION_CONFIG:
    ├── 01_dashboard/
    ├── 02_patients/
    ├── 03_appointments/
    ├── 04_hospital_summary/
    ├── 05_shifts_cashier/
    ├── 06_reception_er/
    ├── 07_outpatient_clinics/
    ├── 08_command_center/
    ├── 09_doctor_portal/
    ├── 10_nursing_station/
    ├── 11_inpatient_wards/
    ├── 12_icu_nicu/
    ├── 13_surgery_or/
    ├── 14_dialysis/
    ├── 15_laboratory/
    ├── 16_radiology/
    ├── 17_pharmacy_inventory/
    ├── 18_finance_accounting/
    └── 19_hr_settings_security/
```

---

## 3. Release Hardening & Anti-Reverse-Engineering Requirements
1. **AOT Compilation & Symbol Obfuscation**:
   - Build all production releases with `--obfuscate --split-debug-info=<secure_symbol_vault>`.
2. **Code Signing**:
   - Windows: EV/OV Authenticode signing (`signtool.exe`) on `medcore_desktop.exe`, native `.dll` plugins, and the Windows Service installer (`Local MedCore Service`).
   - Android: APK/AAB v2/v3 signing + Play Integrity / Keystore hardware attestation.
   - iPadOS: Apple Enterprise / Ad-Hoc / App Store code signing with provisioning profile validation.
3. **Runtime Binary & Certificate Integrity**:
   - Pin the Hospital Local Root CA / Server public key and verify the native screen-protection plugin `.dll` SHA-256 hash at startup.


---

## 4. Implemented Windows Desktop Foundation (`medcore_desktop` — `2026-10-28`)

The Windows Desktop client foundation has been implemented at `medcore_desktop/` strictly adhering to the architecture:

```text
Flutter Desktop (medcore_desktop)
       ↓  HTTP JSON (Bearer Staff Token OR X-MedCore-Tech-Token)
Local MedCore Service (medcore_local_service)
       ↓  Loopback TCP (127.0.0.1)
MariaDB 11.4.4 (Authoritative Truth)
```

### 4.1 Physical Package Layout (`FACT`)
```text
medcore_desktop/
├── pubspec.yaml                                  # http, decimal, crypto — ZERO mysql_client dependency
├── lib/
│   ├── main.dart                                 # MedCorePlatinumDesktopApp centralized MaterialApp & MediaQuery fontScale
│   ├── core/
│   │   ├── api/medcore_api_client.dart           # Typed HTTP client, structured MedCoreApiException, zero DB access
│   │   ├── models/product_models.dart            # BrandingConfig, FacilityConfigModel, AuthenticatedStaffUser, TechnicianSessionInfo
│   │   ├── navigation/desktop_navigation_catalog.dart # RBAC permission + 17-module entitlement route catalog
│   │   ├── shell/medcore_desktop_shell.dart      # Adaptive sidebar, facility/edition header, active-route entitlement guard
│   │   └── state/medcore_app_controller.dart     # Separated staff vs technician session state & configuration loader
│   └── features/
│       ├── auth/connection_and_login_screen.dart # Service health, LAN/Wi-Fi pairing request, staff login, isolated Technician Gate
│       ├── clinical/clinical_modules_hub_screen.dart # Appointments, Doctor Queue, Lab, Radiology, Pharmacy/FIFO, Inpatient, Specialty status
│       ├── dashboard/executive_dashboard_screen.dart # Facility, edition, entitled modules & operational summary
│       ├── finance/patient_financial_ledger_screen.dart # Authoritative MariaDB read-back: Account, Invoice, Receipt, Statement, AR, History, Allocations
│       ├── maintenance/maintenance_center_screen.dart # 14 diagnostic dimensions, PII-redacted report generator, verified local backup trigger
│       ├── network/network_device_center_screen.dart # LAN/Wi-Fi topology, MariaDB loopback check, 6-char pairing approval & device revocation
│       ├── patients/patients_workspace_screen.dart # Configuration-driven REQUIRED / OPTIONAL / HIDDEN patient form & directory
│       ├── reception/shifts_and_visits_screen.dart # Cashier shifts & atomic Decimal visit check-in
│       └── technician/technician_console_screen.dart # Protected service console (isolated from hospital roles)
└── test/
    └── product_layer_desktop_test.dart           # 6 widget & architectural governance tests
```

### 4.2 Architectural Invariants Enforced (`FACT`)
1. **Zero Direct MariaDB Access**: `medcore_desktop/pubspec.yaml` contains no SQL/MariaDB driver; all reads and mutations traverse `MedCoreApiClient` over HTTP.
2. **Zero Second Financial Truth**: `PatientFinancialLedgerScreen` renders exact `DECIMAL(14,4)` string totals computed in `PatientFinancialLedgerService` from `mc_visits`, `mc_financial_events`, `mc_financial_postings`, `mc_visit_item_cost_lines`, `mc_commissions`, and `mc_commission_settlements`, and surfaces explicit `BACKEND_GAP` banners where accounting operations are not yet supported in the backend.
3. **Dual-Layer Module Entitlement Enforcement**: Disabled modules are filtered out by `DesktopNavigationCatalog.visibleRoutes(...)` / blocked by `MedCoreDesktopShell` AND rejected fail-closed in `LocalMedCoreServer._authorize(...)` with `403 MODULE_NOT_ENTITLED`.
4. **Centralized Appearance Source**: `BrandingConfig.buildTheme()` + `MedCorePlatinumDesktopApp` `TextScaler.linear(branding.fontScale)` control application title, facility display name, logo badge, edition label, primary seed color, light/dark/system mode, font scale (`0.85..1.30`), and UI density (`COMPACT` / `STANDARD` / `COMFORTABLE`) from a single source.
5. **Native Win32 Screen Capture Protection (`IMPLEMENTED`)**: Implemented in `medcore_desktop/windows/runner/flutter_window.cpp` using `SetWindowDisplayAffinity(GetHandle(), WDA_EXCLUDEFROMCAPTURE)` with fallback to `WDA_MONITOR`.
6. **Hardware & Real-Time Client Hardening (`DEFERRED`)**: Physical LAN mTLS certificate pinning (`TLS_CERT_INFRASTRUCTURE_PENDING`), physical thermal POS / ZPL USB printer hardware verification (`HARDWARE_VERIFICATION_PENDING`), Android tablet & iPadOS shells (`Phase 5`), and EV Authenticode signing (`Phase 12`).
