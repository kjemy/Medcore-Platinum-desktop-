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
