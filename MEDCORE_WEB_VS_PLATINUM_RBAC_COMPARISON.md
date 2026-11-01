# MEDCORE PLATINUM — READ-ONLY RBAC & PERMISSION FORENSIC COMPARISON
# WEB REFERENCE vs PLATINUM TAXONOMY & ENFORCEMENT AUDIT

- **AUDIT TYPE**: STRICTLY READ-ONLY FORENSIC AUDIT
- **GOVERNANCE AUTHORITY**: Khaled Universal Engineering Constitution (`Khaled All Rules`)
- **DATE OF EXECUTION**: 2026-11-01
- **CODE CHANGES**: 0
- **DATABASE MUTATIONS**: 0
- **GIT CHANGES**: 0
- **DEPLOYMENT**: 0

---

## 1. EXECUTIVE SUMMARY OF RBAC PARITY

MedCore Web and MedCore Platinum Desktop both implement advanced Role-Based Access Control (RBAC) with operational action flags, but they differ fundamentally in **Role Taxonomy**, **Permission Architecture**, and **User Interface Capabilities**:

1. **Role Taxonomy**:
   - **MedCore Web** uses **6 Canonical Roles**: `SuperAdmin`, `HospitalAdmin`, `Doctor`, `Nurse`, `Receptionist`, `Employee`. Dedicated departmental roles (Cashier, Pharmacist, Lab Technician, Radiologist) are handled as specialized `Employee` or `Doctor` accounts with custom permissions.
   - **MedCore Platinum** defines a **10-Role Taxonomy**: `SuperAdmin`, `HospitalAdmin`, `Doctor`, `Nurse`, `Receptionist`, `Cashier`, `Pharmacist`, `Lab`, `Radiology`, `Employee`.

2. **Permission Model & Dimensions**:
   - **MedCore Web** uses 120+ granular string keys with `_all` variants (tenant-wide scope vs own records) and hierarchical child-to-parent inheritance (`PARENT_TO_CHILD_PERMISSIONS`).
   - **MedCore Platinum** implements a **3-Dimensional Architecture**: 87 Base Keys + 87 Scope Keys (`_all`) + 87 Secure Device Keys (`_secure`) = **261 UI Permission Keys**, mapped to **43 Backend Dot-Notation Keys**.

3. **User Interface Management (CRITICAL GAP)**:
   - **MedCore Web** provides a **Complete Visual RBAC Studio** at `/dashboard/settings/roles`:
     - Interactive matrix toggling permissions per role.
     - `CustomPermissionsBuilder.tsx`: Enables assigning specific, fine-grained permissions to individual doctors, nurses, or employees independently of their role.
     - Mode selection: `default` (inherits role presets) vs `custom` (explicit whitelist).
     - Operational flags toggles: `canEdit`, `canDelete`, `canCollectMoney`, `canMakeRefunds`, `refundPolicy`, `refundApprovers`.
   - **MedCore Platinum Desktop**:
     - **Backend / Engine**: Fully implements custom permissions mode, operational flags, 261 keys, and dual-control request flows in `medcore_local_service` and `mc_staff`.
     - **Frontend / UI**: **ZERO UI CAPABILITY**. The Flutter `AdminEmployeeManagementScreen` only provides a single dropdown menu allowing the administrator to choose a role (`Admin`, `Doctor`, `Nurse`, `Receptionist`, `Cashier`). It has **no** permission tree, **no** permission checkboxes, and **no** operational flag toggles.

---

## 2. ROLE TAXONOMY COMPARISON

| Role Name | MedCore Web Presence | MedCore Platinum Presence | Functional Scope & Differences |
|---|:---:|:---:|---|
| **`SuperAdmin`** | **YES** | **YES** | Platform-wide master administrative authority. Bypasses all license and permission checks. Full parity. |
| **`HospitalAdmin`** | **YES** | **YES** | Hospital Director / General Manager. Bypasses module permission checks within the licensed hospital scope. Governs staff, financial dual-control, and reports. Full parity. |
| **`Doctor`** | **YES** | **YES** | Outpatient clinic queues, clinical examinations, electronic prescriptions (e-Rx), orders, inpatient notes. In Web, doctors can have custom clinic pricing; in Platinum, tariffs are not yet defined. |
| **`Nurse`** | **YES** | **YES** | Ward flowsheet vitals, medication administration, nursing tasks, shift handover. In Web, assigned to specific clinics/wards. In Platinum, general nursing station tasks. |
| **`Receptionist`** | **YES** | **YES** | Patient registration, queue intake, appointment booking. In Web, manages clinic cards, countdown timers, and quick check-in. In Platinum, manages shift visits and appointment registration. |
| **`Cashier`** | **NO** (Modeled via `Employee` + `canCollectMoney`) | **YES** (First-Class Canonical Role) | In Web, Cashier is an Employee with `canCollectMoney=true` and `fin_treasury` permission. In Platinum, `Cashier` is a dedicated canonical role in `mc_staff`. |
| **`Pharmacist`** | **NO** (Modeled via `Employee` + `pharmacy_view`) | **YES** (First-Class Canonical Role) | In Web, handled via employee role with pharmacy module permissions. In Platinum, dedicated role with automatic `pharmacy_inventory` and `pharmacy_Dispensing` entitlements. |
| **`Lab` / `LabTechnician`** | **NO** (Modeled via `Employee` + `clin_lab`) | **YES** (First-Class Canonical Role) | In Web, handled via employee role with `clin_lab` permission. In Platinum, dedicated role for specimen reception, result entry, and panic alert verification. |
| **`Radiology` / `Radiologist`** | **NO** (Modeled via `Employee` + `clin_rad`) | **YES** (First-Class Canonical Role) | In Web, handled via employee role with `clin_rad` permission. In Platinum, dedicated role for RIS worklist and modality reporting. |
| **`Employee`** | **YES** | **YES** | Baseline operational employee, self-portal, attendance tracking, and maintenance. Full parity. |

---

## 3. PERMISSION COMPARISON BY FUNCTIONAL CAPABILITY

| Functional Capability | Web Allowed Roles / Conditions | Platinum Allowed Roles / Conditions | Parity Status & Forensic Notes |
|---|---|---|---|
| **Executive Overview / Dashboard** | All authenticated staff (`view_dashboard`) | All authenticated staff (`dashboard`) | **FULL_PARITY** |
| **Patient Registration (Create/Edit)** | `SuperAdmin`, `HospitalAdmin`, `Receptionist` (`edit_patients`) | `SuperAdmin`, `HospitalAdmin`, `Receptionist` (`patients`, `canEdit`) | **FULL_PARITY** |
| **Patient Deletion (Soft Delete)** | `SuperAdmin`, `HospitalAdmin` (`canDelete=true`) | `SuperAdmin`, `HospitalAdmin` (`patients`, `canDelete`) | **FULL_PARITY** |
| **Patient Financial Ledger & Invoices** | `SuperAdmin`, `HospitalAdmin`, `Receptionist`, `Cashier` | `SuperAdmin`, `HospitalAdmin`, `Cashier` (`finance_Invoices`) | **FULL_PARITY** |
| **Shift Box Open / Close** | `HospitalAdmin`, `Cashier`, `Receptionist` (`canCollectMoney=true`) | `HospitalAdmin`, `Cashier` (`shifts`, `canCollectMoney`) | **FULL_PARITY** |
| **Visit Checkout & Payment Collection** | Users with `canCollectMoney=true` | Users with `canCollectMoney=true` | **FULL_PARITY** |
| **Refund Issuance (Direct)** | Users with `canMakeRefunds=true` & `refundPolicy='direct'` | Users with `canMakeRefunds=true` & `refundPolicy='direct'` | **FULL_PARITY** |
| **Refund Dual-Control Request** | Users with `refundPolicy='approval'` | Users with `refundPolicy='approval'` (`mc_dual_control_request`) | **FULL_PARITY** |
| **Refund Dual-Control Decision** | `HospitalAdmin`, `SuperAdmin`, named approver IDs | `HospitalAdmin`, `SuperAdmin` (`/api/v1/dual-control/requests/<id>/decide`) | **FULL_PARITY** |
| **Outpatient Consultation Queue** | `Doctor`, `HospitalAdmin` (`clinic_exam`) | `Doctor`, `HospitalAdmin` (`doctor`, `clinic_DoctorQueue`) | **FULL_PARITY** |
| **Electronic Prescriptions (e-Rx)** | `Doctor`, `HospitalAdmin` (`clinic_record`) | `Doctor`, `HospitalAdmin` (`clinic_Prescriptions`) | **FULL_PARITY** |
| **Clinical Diagnostic Orders (Lab/Rad)**| `Doctor`, `HospitalAdmin` (`clin_lab`, `clin_rad`) | `Doctor`, `HospitalAdmin` (`orders.write`) | **FULL_PARITY** |
| **Lab Results Entry & Panic Alerts** | Staff with `clin_lab` or `Lab` role | `Lab`, `HospitalAdmin` (`lab_ResultsEntry`, `lab_Verification`) | **FULL_PARITY** |
| **Radiology Reporting** | Staff with `clin_rad` or `Radiology` role | `Radiology`, `HospitalAdmin` (`rad_Reporting`) | **FULL_PARITY** |
| **Pharmacy Medication Dispensing** | Staff with `pharmacy_pos` / `pharmacy_view` | `Pharmacist`, `HospitalAdmin` (`pharmacy_Dispensing`) | **FULL_PARITY** |
| **Inpatient Bed Allocation & Admissions**| Staff with `clin_ward` | `HospitalAdmin`, `Receptionist`, `Nurse` (`inpatient_Admissions`) | **FULL_PARITY** |
| **Nursing Station Tasks** | `Nurse`, `HospitalAdmin` (`nursing_tasks`) | `Nurse`, `HospitalAdmin` (`nurse`, `nurse_Station`) | **FULL_PARITY** |
| **ICU Flowsheets & Scores** | `Doctor`, `Nurse`, `HospitalAdmin` (`clin_icu`) | Backend: `icu_nicu` (`/api/v1/clinical/icu/*`) / UI: Summary card only | **BACKEND_ONLY** |
| **Operating Theater Scheduling** | `Doctor`, `HospitalAdmin` (`clin_surg`) | Backend: `surgery` (`/api/v1/clinical/surgeries`) / UI: Summary card only | **BACKEND_ONLY** |
| **Dialysis Treatment Sessions** | `Doctor`, `Nurse`, `HospitalAdmin` (`clin_dialysis`) | Backend: `dialysis` (`/api/v1/clinical/dialysis/sessions`) / UI: Summary card only | **BACKEND_ONLY** |
| **Clinical Template Designer** | `Doctor`, `HospitalAdmin` (`clinic_templates`) | `Doctor`, `HospitalAdmin` (`doctor_ClinicalWorkspace`, `admin`) | **FULL_PARITY** |
| **Multi-Resource Scheduling** | N/A (Standard single appointment booking) | `HospitalAdmin`, `Receptionist` (`resource_scheduling`) | **PLATINUM_ONLY** |
| **LAN Hardware Device Pairing** | N/A (Browser-based cloud/LAN access) | `HospitalAdmin`, `SuperAdmin` (`settings_Devices`) | **PLATINUM_ONLY** |
| **Technician Mode / Disaster Recovery** | N/A (Handled via WordPress WP-Admin / CLI) | `Technician` hardware token / challenge session | **PLATINUM_ONLY** |
| **Fine-Grained Permission Assignment UI**| `HospitalAdmin`, `SuperAdmin` (`set_roles`) | **NOT IMPLEMENTED IN UI** (Backend API `PUT /api/v1/staff/<id>/permissions` exists) | **BACKEND_ONLY** |
| **Operational Flags Configuration UI** | `HospitalAdmin`, `SuperAdmin` (`set_roles`, `set_definitions`) | **NOT IMPLEMENTED IN UI** (Backend API exists, Flutter UI dialog has no inputs) | **BACKEND_ONLY** |
| **Custom Permissions Mode Toggle** | `HospitalAdmin`, `SuperAdmin` (`permissionsMode: 'custom'`) | **NOT IMPLEMENTED IN UI** (Backend API exists, Flutter UI dialog has no inputs) | **BACKEND_ONLY** |

---

## 4. PERMISSION GRANULARITY COMPARISON & TECHNICAL FINDINGS

### 4.1 Granularity Level Assessment
Does MedCore Platinum support the same level of permission granularity as MedCore Web?
- **At the Data Model & Schema Level**: **YES**. Table `mc_staff` contains:
  - `role`: Canonical role enum.
  - `permissions_mode`: `default` vs `custom`.
  - `custom_permissions`: JSON set of granted permission strings.
  - `secure_page_locks`: JSON set of elevated device-bound locks.
  - `can_edit`, `can_delete`, `can_collect_money`, `can_make_refunds`, `refund_policy`.
- **At the Backend Service & Routing Level**: **YES**.
  - `medcore_local_service` includes `permissions_catalog.dart` with 261 UI keys and 43 backend keys.
  - Every route is wrapped with `_authorize(req, requiredPermission: '...', requireCanEdit: bool)`.
  - Endpoint `PUT /api/v1/staff/<id>/permissions` accepts and persists custom permissions and operational flags.
- **At the Flutter Desktop UI Level**: **NO (CRITICAL GAP)**.
  - MedCore Web has an interactive visual tree builder (`CustomPermissionsBuilder.tsx` and `PermissionTree.tsx`) allowing an administrator to check/uncheck any of the 120+ permissions for any specific staff member.
  - MedCore Platinum has **no UI** for custom permissions. The administrator in Platinum cannot grant or revoke individual permissions from the desktop app; they can only switch the employee's role among 5 choices.

### 4.2 Independent Permission Assignment (Independent of Role)
- **Can Platinum assign permissions independently of roles?**
  - **Programmatically via API**: **YES**. Sending a payload to `PUT /api/v1/staff/<id>/permissions` with `permissionsMode: 'custom'` and `customPermissions: ['patients', 'clinic_Prescriptions']` works and is enforced.
  - **Operationally via Desktop Application**: **NO**. The desktop user interface provides no mechanism to perform this action.
