# MEDCORE — LICENSE ENGINE, DEVICE BINDING, ANTI-CLOCK-ROLLBACK & SCREEN PROTECTION BLUEPRINT
**Document ID**: `DOC-09` | **Category**: `I (Missing Capability)` & `C (Security)`

---

## 1. Current Reality in `Project 3` (`FACT`)
1. **License Check (`Backend/MedCorePlugin/includes/api/class-api-saas.php:110-227`, `Frontend/src/store/useLicenseStore.ts:1-172`)**:
   - `GET /wp-json/mce/v1/license?hospital_code=...` is unauthenticated (`permission_callback => '__return_true'`).
   - Contains a hardcoded test-domain bypass (`lines 134-137`) that grants `max_doctors = 1000` and all modules.
   - Returns **unsigned plaintext JSON** with no cryptographic signature, no hardware binding, and no anti-clock-rollback check.
2. **Device Verification (`Backend/MedCorePlugin/includes/api/class-api-desktop.php:40-48`)**:
   - `POST /wp-json/medcore/v1/verify-device` is a **100% stub** that returns `['verified' => true, 'status' => 'active']` without checking `wp_mc_security_devices`!

---

## 2. Target Offline-First Cryptographic License Engine (`MedCore Desktop`)

### 2.1 Ed25519 Signed License Lease Artifact
The **WordPress Control Plane** holds an offline-protected **Ed25519 Private Signing Key**, while the **Local MedCore Service** embeds the corresponding **Pinned Ed25519 Public Key**.
Whenever the hospital server connects to the Control Plane (or imports an offline `.mclease` file during air-gapped activation), it receives a signed lease stored in `mc_license_state`:

```json
{
  "schema_version": "1.0",
  "license_id": "LIC-2026-HOSP01-9981",
  "hospital_code": "HOSP01",
  "edition": "ENTERPRISE_LAN",
  "server_hw_fingerprint_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  "entitled_modules": [
    "reception", "clinics", "command_center", "doctor_portal", "nursing",
    "inpatient", "icu_nicu", "surgery", "dialysis", "laboratory",
    "radiology", "pharmacy_inventory", "finance", "hr", "appointments"
  ],
  "limits": {
    "max_server_nodes": 1,
    "max_client_devices": 25,
    "max_active_doctors": 50
  },
  "ai_entitlement": {
    "enabled": true,
    "monthly_token_quota": 500000
  },
  "issued_at_utc": "2026-10-27T00:00:00Z",
  "expires_at_utc": "2027-10-27T00:00:00Z",
  "offline_grace_days": 30,
  "signature_ed25519": "<128-hex-char-signature>"
}
```

### 2.2 License State Machine & Graceful Degradation (Patient Safety First)
- **`VALID`**: Current verified UTC time `< expires_at_utc`. Full read/write access to all `entitled_modules`.
- **`GRACE_PERIOD`**: `expires_at_utc <= Current UTC < expires_at_utc + offline_grace_days`. Full clinical & financial operation continues with a persistent non-blocking renewal banner for `HospitalAdmin`.
- **`EXPIRED_READ_ONLY`**: `Current UTC >= expires_at_utc + offline_grace_days`.
  - **Patient Safety Rule**: Viewing existing patient records, lab results, radiology reports, active inpatient charts, and printing discharge summaries remains **100% accessible**.
  - **Blocked Actions**: Creating new outpatient visits (`POST /visits`) or opening new shifts is blocked until lease renewal or a signed **Emergency 72-Hour Extension Token** is entered.
- **`TAMPER_LOCKED`**: Triggered by signature mismatch, hardware fingerprint mismatch, or clock rollback > threshold. Requires online re-verification or a Technician Service Tool **Signed Maintenance Unlock Token**.

---

## 3. Hardware Device Binding & Enrollment (`mc_devices`)

### 3.1 Multi-Platform Hardware Fingerprint Derivation (`hw_fingerprint_sha256`)
- **Windows Host / Desktop Client**:
  - `SHA-256(SMBIOS_UUID + "|" + Motherboard_Serial + "|" + SystemDrive_VolumeSerial + "|" + Windows_MachineGuid)`
- **Android Tablet / Client**:
  - `SHA-256(Android_Keystore_Attestation_PublicKey_ID + "|" + Settings.Secure.ANDROID_ID + "|" + Build.BOARD)`
- **iPadOS Client**:
  - `SHA-256(SecureEnclave_DeviceKey_PublicKey_Hash + "|" + Keychain_Persistent_Device_UUID + "|" + identifierForVendor)`

### 3.2 Cryptographic Device Handshake Over Hospital LAN
1. On first launch, the Flutter Client generates an **Ed25519 keypair** stored in OS Secure Storage (Windows DPAPI / Credential Manager, Android Keystore, iOS Keychain).
2. Client sends `POST /api/v1/devices/enroll` with `(device_name, platform, hw_fingerprint_sha256, device_public_key_ed25519)`.
3. If `COUNT(ACTIVE devices) < license.max_client_devices` and approved by `HospitalAdmin`, `mc_devices.status` becomes `'ACTIVE'`.
4. Every subsequent API request from Flutter includes `X-MedCore-Device-ID`, `X-MedCore-Timestamp`, and `X-MedCore-Device-Sig` (signing `Method + Path + Timestamp + BodyHash`).

---

## 4. Four-Source Monotonic Anti-Clock-Rollback Engine (`mc_clock_guard`)

To prevent an operator from setting the Windows system clock backward to bypass license expiration:
1. **Source 1 — Monotonic High-Water Mark Table (`mc_clock_guard.max_observed_utc`)**:
   - Updated every 60 seconds and on every transaction commit with `GREATEST(max_observed_utc, UTC_TIMESTAMP(3))`, sealed with an HMAC-SHA256 key derived from the host hardware fingerprint.
2. **Source 2 — Ledger Event & Audit Timestamp Ceiling**:
   - On startup and every API request, Local MedCore Service queries:
     `MAX(created_at)` across `mc_financial_events`, `mc_visits`, `mc_audit_logs`, and `mc_shifts`.
3. **Source 3 — OS Hardware Monotonic Tick Counter**:
   - Tracks `GetTickCount64()` (Windows) / `clock_gettime(CLOCK_MONOTONIC)` across service heartbeats to detect wall-clock jumps while the machine is running.
4. **Source 4 — Signed Network Time Anchor**:
   - Whenever the Local MedCore Service communicates with the WordPress Control Plane or LAN NTP/HTTPS peers, it updates `max_observed_utc` from the signed server timestamp.

### Rollback Detection Formula:
If `Current_Wall_Clock_UTC + 300 seconds (5-min drift tolerance) < MAX(Source1, Source2, Source3, Source4)`:
- Set `mc_clock_guard.rollback_detected = 1`.
- Transition system to **`TAMPER_LOCKED`** (blocks all new financial/visit mutations and displays the exact clock discrepancy: `"System clock (T_now) is behind last recorded hospital transaction timestamp (T_max). Correct system clock or apply Technician Unlock Token."`).

---

## 5. Native OS Screen Capture & Recording Protection (`_secure` Pages)

Whenever a user navigates to a route whose permission has `<perm>_secure` enabled (`SEC-004`) or globally when `hospital_settings.enforce_screen_protection == true`:

| Target OS | Native Enforcement Mechanism | OS Capability & Honest Limitation |
|---|---|---|
| **Windows Desktop** | Win32 API `SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE)` (`0x00000011` on Windows 10 2004+ / Windows 11). | **Blocks 100%** of OS screenshots (`PrtScn`, Snipping Tool), OBS, Teams/Zoom screen sharing, and BitBlt/DXGI capture (window renders completely black in capture). *Cannot prevent an external physical camera (phone photo); mitigated via dynamic forensic watermark overlay.* |
| **Android** | `window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)` via Flutter platform channel. | **Blocks 100%** of screenshots, screen recording, Google Assistant screen capture, and Recent Apps thumbnail previews. |
| **iPadOS / iOS** | 1. Wrap protected viewport in a secure `UITextField.isSecureTextEntry` layer (renders blank in iOS screenshots).<br>2. Observe `UIScreen.capturedDidChangeNotification` (`UIScreen.main.isCaptured`) and `UIApplication.userDidTakeScreenshotNotification`. | When `isCaptured == true` (Screen Recording / AirPlay Mirroring active), immediately replaces the Flutter viewport with a full-screen opaque security shield (`"Screen Recording Detected — Clinical View Hidden"`) and logs a `security.screen_capture_attempt` event in `mc_security_logs`. |
