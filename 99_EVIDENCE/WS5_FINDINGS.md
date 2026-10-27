# WS5 — Identity, Permissions, Security & Licensing Findings (`Project 3`)

> **Classification**: `FACT` — Extracted from `Backend/MedCorePlugin/includes/security/class-medcore-security.php` (730 lines), `includes/domain/staff/class-auth-service.php` (391 lines), `includes/api/class-api-desktop.php` (112 lines), `includes/api/class-api-saas.php` (229 lines), `includes/api/class-api-ai.php` (163 lines), `Frontend/src/lib/permissions.ts` (740 lines), `Frontend/src/components/PermissionGuard.tsx` (273 lines), and `Frontend/src/store/useAuthStore.ts` (157 lines).

## 1. Role Taxonomy Conflict: 6 Frontend Roles vs 10 Backend Roles (`SEC-CONFLICT-01` — `FACT`)
- **Frontend (`Frontend/src/lib/permissions.ts:6-12 & 592-618`)**:
  - Defines `UserRole = "SuperAdmin" | "HospitalAdmin" | "Doctor" | "Nurse" | "Receptionist" | "Employee"`.
  - `normalizeRole()` explicitly collapses `"Pharmacist"`, `"Lab"`, `"Radiology"`, and `"Cashier"` into `"Employee"`!
- **Backend (`Backend/MedCorePlugin/includes/security/class-medcore-security.php:16-92`)**:
  - Defines 10 distinct role keys in `$default_role_permissions`: `super_admin`, `HospitalAdmin`, `Doctor`, `Nurse`, `Pharmacist`, `Lab`, `Radiology`, `Cashier`, `Receptionist`, `Employee`.
- **Impact**: A user assigned `Pharmacist` or `Cashier` in backend `wp_mc_staff` has specialized backend permissions (`pharmacy.read/write`, `finance.read/write`), but when hydrated in the React UI (`normalizeRole`), their role becomes `Employee`, stripping role-specific UI defaults unless custom permissions are manually toggled.

## 2. Permission Key Matrix: 261 UI Keys vs 43 Backend Keys (`SEC-002` — `FACT`)
- **Frontend (`Frontend/src/lib/permissions.ts:19-306`)**:
  - **87 base page/module keys** (e.g., `reception_QuickCheckIn`, `clinic_DoctorQueue`, `lab_SampleTracking`, `finance_Revenue`, `hr_Payroll`).
  - **87 `_all` data-scope keys** (e.g., `reception_QuickCheckIn_all`) — controls whether the user sees all hospital records or only their own assigned department/doctor records.
  - **87 `_secure` page-security keys** (e.g., `reception_QuickCheckIn_secure`) — marks a page as requiring the protected Desktop runtime.
  - **4 Operational Action Flags (`UserPermissionsConfig`)**: `canDelete: boolean`, `canEdit: boolean`, `canCollectMoney: boolean`, `canMakeRefunds: boolean`, plus `refundPolicy: 'none' | 'direct' | 'approval'`.
- **Backend (`class-medcore-security.php:16-92 & 331-369`)**:
  - Uses 43 dot-notation resource permissions (`patients.read`, `patients.write`, `visits.read`, `visits.write`, `finance.read`, `finance.write`, `finance.settle`, `shifts.open`, `shifts.close`, `lab.read`, `lab.write`, `rad.read`, `rad.write`, `pharmacy.read`, `pharmacy.write`, `inventory.read`, `inventory.write`, `hr.read`, `hr.write`, `settings.manage`, etc.) with bidirectional translation in `check_permission_matches()`.

## 3. Critical Security Flaws in `Project 3` (`FACT`)
1. **`PermissionGuard.tsx` Default-Mode RBAC Bypass (`SEC-FLAW-01` — P0 CRITICAL)**:
   - **Location**: `Frontend/src/components/PermissionGuard.tsx:154-158`:
     ```ts
     const isDefaultMode = effectiveMode !== "custom";
     if (isHospitalAdmin) {
         access = true;
     } else if (user && ((!isAdministrativePerm && isDefaultMode) || hasPermission(effectivePermissions, permission))) {
         access = true;
     }
     ```
   - **Also in `Frontend/src/store/useAuthStore.ts:127 & 144`**: When `permissionsMode !== "custom"`, `finalPermissions` is overwritten with `["*", ...ALL_PERMISSIONS]`.
   - **Effect**: Any staff member whose `permissionsMode` is `"default"` (the default for newly created staff!) bypasses `hasPermission()` in `PermissionGuard` for **every clinical, reception, lab, radiology, pharmacy, and financial page** that is not in `ADMINISTRATIVE_PERMISSIONS`!
2. **Spoofable `_secure` Desktop Check (`SEC-FLAW-02` — P0 CRITICAL)**:
   - **Location**: `Frontend/src/components/PermissionGuard.tsx:199`:
     `const isDesktop = typeof window !== 'undefined' && (window.navigator.userAgent.includes('MedcoreDesktop') || (window as any).__MEDCORE_DESKTOP__ === true);`
   - **Effect**: Any browser user can spoof `User-Agent: MedcoreDesktop` or set `window.__MEDCORE_DESKTOP__ = true` in DevTools console to bypass `_secure` page locks, and the backend does not enforce `_secure` at all.
3. **Tenant-Unbound Auth Token (`SEC-FLAW-03` — P0 CRITICAL)**:
   - **Location**: `Backend/MedCorePlugin/includes/domain/staff/class-auth-service.php:59-60` and `class-medcore-security.php:712`:
     `set_transient('mc_token_' . md5($token), $target_email, DAY_IN_SECONDS);`
   - **Effect**: The bearer token stores only `$target_email`, not `hospital_code`, `staff_id`, or `device_id`.
4. **Unauthenticated Master AI Key Leak (`SEC-FLAW-04` — P0 CRITICAL)**:
   - **Location**: `Backend/MedCorePlugin/includes/api/class-api-ai.php:6-18`:
     `GET /wp-json/medcore-ai/v1/keys` has `permission_callback => '__return_true'` and returns raw Groq and Gemini master API keys whenever `X-MedCore-Server-Action: fetch-ai-keys` is sent.
5. **Unauthenticated Device Verification Stub (`SEC-FLAW-05` — P0 CRITICAL)**:
   - **Location**: `Backend/MedCorePlugin/includes/api/class-api-desktop.php:40-48`:
     `POST /wp-json/medcore/v1/verify-device` has `permission_callback => '__return_true'` and returns `['verified' => true, 'status' => 'active']` unconditionally without querying `wp_mc_security_devices`!
