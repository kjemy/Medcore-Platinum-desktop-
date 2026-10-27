# MEDCORE — IDENTITY, PERMISSIONS & SECURITY MODEL (`CATEGORY C`)
**Document ID**: `DOC-08` | **Source**: `Frontend/src/lib/permissions.ts` (740 lines), `Frontend/src/components/PermissionGuard.tsx` (273 lines), `Backend/MedCorePlugin/includes/security/class-medcore-security.php` (730 lines)

---

## 1. Unified 10-Role Taxonomy for `MedCore Desktop`
In `Project 3`, `Backend/MedCorePlugin/includes/security/class-medcore-security.php:16-92` defines **10 roles**, whereas `Frontend/src/lib/permissions.ts:592-618` (`normalizeRole`) collapses 4 clinical/financial roles (`Pharmacist`, `Lab`, `Radiology`, `Cashier`) into `"Employee"`.
**`MedCore Desktop` unifies all 10 canonical roles across both Local MedCore Service and Flutter Client**:

| # | Canonical Role Key | Arabic Title | Default Landing Route | Scope Summary |
|---|---|---|---|---|
| 1 | `SuperAdmin` | مدير النظام الأعلى | `/dashboard` | Platform/Multi-Hospital governance, DB Mirror, Security, Licensing |
| 2 | `HospitalAdmin` | مدير المستشفى | `/dashboard` | Full hospital operational & administrative access within `hospital_code` |
| 3 | `Doctor` | طبيب | `/doctor/workspace` | Doctor Portal, Outpatient Queue (own or `_all`), Inpatient Rounds, ICU/Surgery/Dialysis clinical notes, Order placement |
| 4 | `Nurse` | تمريض | `/nurse/station` | Nursing Station, Triage, Vitals, e-MAR, Inpatient/ICU/NICU/Dialysis/OR nursing care |
| 5 | `Receptionist` | موظف استقبال | `/reception/check-in` | Patient registration, Appointments, Quick Check-In, Queue management, Shift cash collection (if `canCollectMoney`) |
| 6 | `Cashier` | أمين خزينة / محاسب وردية | `/shifts` | Shifts open/close, Invoice collection, Refunds (per `refundPolicy`), Treasury vouchers |
| 7 | `Pharmacist` | صيدلي | `/pharmacy-inventory/dispensing` | Prescription dispensing, Stock batches, Requisitions, Controlled drugs log |
| 8 | `Lab` | أخصائي مختبر | `/lab/dashboard` | Specimen collection/tracking, Lab result entry, Verification, Blood Bank, Reagents |
| 9 | `Radiology` | أخصائي أشعة | `/rad/worklist` | Radiology modality worklist, Study execution, Radiology reporting, Contrast consumables |
| 10 | `Employee` | موظف إداري / عام | `/dashboard` | Restricted baseline profile; requires explicit role/custom permissions for clinical or financial modules |

---

## 2. The Three-Dimensional Permission Architecture (261 UI Keys + 4 Action Flags)
Every navigation node and API endpoint is governed by a **3-layer permission tuple** extracted from `Frontend/src/lib/permissions.ts:19-306`:

1. **Layer 1 — Base Page/Module Access (`<module>_<page>`, 87 Keys)**:
   - Controls whether the user can view and enter the screen/endpoint (e.g., `reception_QuickCheckIn`, `clinic_DoctorQueue`, `lab_ResultsEntry`, `finance_Settlements`).
2. **Layer 2 — Data Visibility Scope (`<module>_<page>_all`, 87 Keys)**:
   - When `FALSE`: Local MedCore Service restricts queries to records assigned to or created by the authenticated `staff_id` / `doctor_id` / `department_id`.
   - When `TRUE`: User can view and operate across all departments/doctors within `hospital_code`.
3. **Layer 3 — Protected Runtime Enforcement (`<module>_<page>_secure`, 87 Keys)**:
   - Marks sensitive screens (e.g., Financial Revenue, Doctor Settlements, Patient MPI Export, HR Payroll) as **Protected Screens**.
   - In `MedCore Desktop`, entering a `_secure` screen:
     1. Verifies the request originates from an enrolled, hardware-bound Desktop/Tablet device (`mc_devices.status == 'ACTIVE'`).
     2. Activates OS-level screen-capture / recording block (`WDA_EXCLUDEFROMCAPTURE` on Windows, `FLAG_SECURE` on Android, `isCaptured` blur shield on iPadOS).
     3. Applies dynamic watermark overlay (`Staff Name + Device ID + Timestamp`) over the viewport.

### 2.1 Operational Action Flags (`UserPermissionsConfig`)
Stored in `mc_staff.permissions_config_json` and enforced on every mutation endpoint:
- `canEdit: boolean` — Required for `PUT`/`PATCH` updates on existing clinical/administrative records.
- `canDelete: boolean` — Required for soft-delete/archive actions.
- `canCollectMoney: boolean` — Required to post `CASH_IN` or open a cashier shift.
- `canMakeRefunds: boolean` + `refundPolicy: 'none' | 'direct' | 'approval'`:
  - `'none'`: Cannot initiate refunds.
  - `'approval'`: Can submit a refund request to `mc_dual_control_requests`; requires a `HospitalAdmin` or authorized supervisor to approve before ledger reversal executes.
  - `'direct'`: Can execute immediate visit refund/reversal within an open shift.

---

## 3. Remediation of `Project 3` Security Flaws in `MedCore Desktop`
| Flaw ID | Vulnerability in `Project 3` (`file:line`) | Mandatory Remediation in `MedCore Desktop` |
|---|---|---|
| `SEC-FLAW-01` | `PermissionGuard.tsx:154-158` & `useAuthStore.ts:127,144` grant wildcard access (`["*", ...ALL_PERMISSIONS]`) whenever `permissionsMode !== "custom"`. | **Eliminated**: `effectivePermissions` is computed on the server (`Local MedCore Service`) as `mode == 'custom' ? user.customPermissions : DEFAULT_ROLE_PERMISSIONS[user.role]`. The client never synthesizes `"*"`. |
| `SEC-FLAW-02` | `PermissionGuard.tsx:199` checks `navigator.userAgent.includes('MedcoreDesktop')` for `_secure` pages. | **Eliminated**: Flutter Desktop/Tablet authenticates each LAN request with a device-bound Ed25519 signature (`X-MedCore-Device-Signature`). Browser User-Agent strings are ignored. |
| `SEC-FLAW-03` | `class-auth-service.php:59-60` stores only `$target_email` in `mc_token_<md5>`. | **Eliminated**: Local MedCore Service issues short-lived PASETO/JWT access tokens + `mc_auth_sessions` rows bound to `(session_id, staff_id, hospital_code, device_id, ip_address, expires_at)`. |
| `SEC-FLAW-04` | `class-api-ai.php:6-18` leaks master Groq/Gemini API keys via `X-MedCore-Server-Action: fetch-ai-keys`. | **Eliminated**: Master AI keys never leave the Cloud AI Gateway; neither Flutter nor Local MedCore Service ever fetches raw provider keys. |
| `SEC-FLAW-05` | `class-api-desktop.php:40-48` `/verify-device` unconditionally returns `verified: true`. | **Eliminated**: Replaced by cryptographic challenge-response against `mc_devices.device_public_key_ed25519` and `hw_fingerprint_sha256`. |
