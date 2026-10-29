# MEDCORE PLATINUM DESKTOP
## CANONICAL ROLE, PERMISSION & NAVIGATION MATRIX
### 10-ROLE TAXONOMY • 261-PERMISSION MATRIX • MODULE ENTITLEMENT GOVERNANCE

---

**Document Reference:** `MEDCORE_ADMIN_ROLE_PERMISSION_NAVIGATION_MATRIX_20261029.md`  
**Date:** 2026-10-29  
**Authority:** Gemini 3.8 High (Main Agent Authority)  
**Governance:** Khaled Universal Engineering Constitution (`Khaled All Rules`)  
**Workspace:** `C:\Users\hp\Desktop\project 4`  
**Repository:** `kjemy/Medcore-Platinum-desktop-`  
**Branch:** `main`

---

## 1. THE 10 CANONICAL ROLES TAXONOMY

MedCore Platinum enforces a strict 10-role RBAC taxonomy reified in MariaDB table `mc_staff` (column `role`):

1. **`SuperAdmin`**: Platform-wide master administrative authority (full 261 permissions).
2. **`HospitalAdmin`**: Chief Hospital Administrator & Director. Governs operational staff, reports, dual-control financial approvals, and hospital workflows.
3. **`Doctor`**: Outpatient clinics, clinical encounters, electronic prescriptions (e-Rx), orders, inpatient ward rounds.
4. **`Nurse`**: Nursing stations, triage scoring, vitals monitoring flowsheets, medication administration, shift handover.
5. **`Receptionist`**: Patient registration, queue management, quick check-in, appointment booking, emergency intake.
6. **`Cashier`**: Shift box opening/closing, invoice payment collections, deposit refunds, treasury expenses.
7. **`Pharmacist`**: Medication dispensing, inventory batch tracking (FIFO), purchase receipts, stocktake.
8. **`Lab`** (`LabTechnician`): LIS specimen reception, sample barcode tracking, laboratory results entry, panic alert verification, blood bank.
9. **`Radiology`** (`Radiologist`): RIS worklist, modality exam execution, DICOM report transcription, contrast consumables.
10. **`Employee`** (`Maintenance` / Support): Baseline operational staff, personal dashboard, attendance tracking.

---

## 2. THE 3-DIMENSIONAL PERMISSION ARCHITECTURE

MedCore permissions operate across **3 orthogonal dimensions**, yielding **261 UI Permission Keys** plus **43 Backend Dot-Notation Keys**:

```text
Dimension 1: Base Feature Access (<key>)
  → 87 Canonical Base Keys (19 Sidebar Sections + 63 Subpages + 5 System Scopes)

Dimension 2: Tenant-Wide Data Scope (<key>_all)
  → 87 Keys. When granted, user sees all hospital records in that domain.
  → When omitted, user is strictly restricted to "Own-Only" scope at the SQL query level (WHERE doctor_id = :me OR cashier_id = :me).

Dimension 3: Device / Page Security (<key>_secure)
  → 87 Keys. Requires dedicated secure runtime device or elevated security posture.

Total UI Permission Keys = 87 + 87 + 87 = 261 Keys.
```

### Operational Action Flags (in `mc_staff`):
In addition to permission keys, every staff account enforces **4 Operational Flags**:
- `canEdit` (bool): Grants write and mutation capabilities.
- `canDelete` (bool): Grants soft-deletion capabilities (hard deletion is forbidden in clinical/financial paths).
- `canCollectMoney` (bool): Grants authorization to receive cash payments into an active shift box.
- `canMakeRefunds` (bool): Grants authorization to issue patient refunds.
- `refundPolicy`:
  - `none`: Refunds completely forbidden.
  - `direct`: Immediate refund permitted up to shift limit.
  - `approval`: Requires supervisor/admin dual-control approval before disbursement.

---

## 3. CANONICAL ROLE × PERMISSION MATRIX

| Domain / Base Permission | HospitalAdmin | Doctor | Nurse | Receptionist | Cashier | Pharmacist | Lab | Radiology | Employee |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **`dashboard`** (Overview) | **FULL** | READ | READ | READ | READ | READ | READ | READ | READ |
| **`patients`** (Patient Registry) | **FULL** | READ | READ | **FULL** | READ | READ | READ | READ | NONE |
| **`reception_PatientRegistration`** | **FULL** | NONE | NONE | **FULL** | NONE | NONE | NONE | NONE | NONE |
| **`reception_QuickCheckIn`** | **FULL** | NONE | NONE | **FULL** | **FULL** | NONE | NONE | NONE | NONE |
| **`appointments`** (Booking) | **FULL** | READ | NONE | **FULL** | NONE | NONE | NONE | NONE | NONE |
| **`shifts`** (Shift Box) | **FULL** | NONE | NONE | NONE | **FULL** | NONE | NONE | NONE | NONE |
| **`clinic`** / **`doctor`** (Clinical) | **FULL** | **FULL** | NONE | NONE | NONE | NONE | NONE | NONE | NONE |
| **`clinic_Prescriptions`** (e-Rx) | **FULL** | **FULL** | NONE | NONE | NONE | NONE | NONE | NONE | NONE |
| **`nurse`** (Nursing Station) | **FULL** | NONE | **FULL** | NONE | NONE | NONE | NONE | NONE | NONE |
| **`inpatient`** (Wards & Beds) | **FULL** | READ | READ | READ | NONE | NONE | NONE | NONE | NONE |
| **`icu_nicu`** (Critical Care) | **FULL** | READ | READ | NONE | NONE | NONE | NONE | NONE | NONE |
| **`surgery`** (Operating Theaters) | **FULL** | **FULL** | READ | NONE | NONE | NONE | NONE | NONE | NONE |
| **`dialysis`** (Hemodialysis) | **FULL** | **FULL** | READ | NONE | NONE | NONE | NONE | NONE | NONE |
| **`lab`** (Laboratory LIS) | **FULL** | NONE | NONE | NONE | NONE | NONE | **FULL** | NONE | NONE |
| **`lab_Verification`** (Panic Alert) | **FULL** | NONE | NONE | NONE | NONE | NONE | **APPROVE**| NONE | NONE |
| **`rad`** (Radiology RIS) | **FULL** | NONE | NONE | NONE | NONE | NONE | NONE | **FULL** | NONE |
| **`pharmacy_inventory`** | **FULL** | NONE | NONE | NONE | NONE | **FULL** | NONE | NONE | NONE |
| **`inventory_Stocktake`** | **FULL** | NONE | NONE | NONE | NONE | **FULL** | NONE | NONE | NONE |
| **`finance`** (General Ledger) | **FULL** | NONE | NONE | NONE | READ | NONE | NONE | NONE | NONE |
| **`finance_Invoices`** | **FULL** | NONE | NONE | NONE | **FULL** | NONE | NONE | NONE | NONE |
| **`finance_Settlements`** (Dual Control) | **APPROVE**| NONE | NONE | NONE | REQUEST | NONE | NONE | NONE | NONE |
| **`hr_Employees`** (Staff Admin) | **FULL** | NONE | NONE | NONE | NONE | NONE | NONE | NONE | NONE |
| **`hr_Evaluations`** | **FULL** | NONE | NONE | NONE | NONE | NONE | NONE | NONE | NONE |
| **`settings_Devices`** (LAN Pairing) | **APPROVE**| NONE | NONE | NONE | NONE | NONE | NONE | NONE | NONE |
| **`security_Center`** (Audit Trail) | **READ** | NONE | NONE | NONE | NONE | NONE | NONE | NONE | NONE |
| **`technician.*`** (Tech Console) | **DENIED** | **DENIED**| **DENIED**| **DENIED**| **DENIED**| **DENIED**| **DENIED**| **DENIED**| **DENIED**|

---

## 4. NAVIGATION CATALOG & VISIBILITY RULES

MedCore Desktop shell dynamically builds the left sidebar navigation using the canonical rule:

$$\mathbf{Visible}(\text{Route}) = \big(\text{requiredModule} == \text{null} \lor \text{config.isModuleEnabled}(\text{requiredModule})\big) \;\land\; \mathbf{user.hasAnyPermission}(\text{anyOfPermissions})$$

### The 14 Desktop Routes Detailed:

| # | Route ID | Menu Label | Required Module | Required Any-Of Permissions | Visible to Admin | Visible to Doctor | Visible to Cashier | Visible to Reception |
|:---:|:---|:---|:---|:---|:---:|:---:|:---:|:---:|
| **1** | `dashboard` | Executive Overview | *None* | `['dashboard']` | **YES** | **YES** | **YES** | **YES** |
| **2** | `patients` | Patients & Registration | `Patients` | `['patients', 'reception_PatientRegistration']` | **YES** | **YES** | **YES** | **YES** |
| **3** | `reception_visits` | Shifts & Visit Billing | `Reception` | `['reception_QuickCheckIn', 'shifts']` | **YES** | *NO* | **YES** | **YES** |
| **4** | `finance_ledger` | Financial Ledger & Reports | `Finance` | `['finance', 'finance_Invoices', 'finance_Revenue']` | **YES** | *NO* | **YES** | *NO* |
| **5** | `appointments` | Appointments | `Appointments` | `['appointments', 'reception_Appointments', 'clinic_Appointments']` | **YES** | **YES** | *NO* | **YES** |
| **6** | `doctors` | Doctors & Outpatient | `Doctors` | `['doctor', 'clinic', 'clinic_DoctorQueue', 'doctor_ClinicalWorkspace']` | **YES** | **YES** | *NO* | *NO* |
| **7** | `laboratory` | Laboratory (LIS) | `Laboratory` | `['lab', 'lab_Dashboard', 'lab_ResultsEntry']` | **YES** | *NO* | *NO* | *NO* |
| **8** | `radiology` | Radiology (RIS) | `Radiology` | `['rad', 'rad_Worklist', 'rad_Reporting']` | **YES** | *NO* | *NO* | *NO* |
| **9** | `pharmacy` | Pharmacy & Inventory | `Pharmacy` | `['pharmacy_inventory', 'pharmacy_Dispensing', 'inventory_ItemsCatalog']` | **YES** | *NO* | *NO* | *NO* |
| **10** | `inpatient` | Inpatient & Beds | `Inpatient` | `['inpatient', 'inpatient_BedMap', 'inpatient_Admissions']` | **YES** | **YES** | *NO* | **YES** |
| **11** | `specialty_units` | Nursing / ICU / OR / Dialysis | *None* (Multi) | `['nurse', 'icu_nicu', 'surgery', 'dialysis', 'CommandCenter']` | **YES** | **YES** | *NO* | *NO* |
| **12** | `staff_admin` | Staff & Employee Accounts | *None* | `['admin', 'hr_Employees', 'security_Center']` | **YES** | *NO* | *NO* | *NO* |
| **13** | `network_devices` | LAN / Wi-Fi Devices | *None* | `['settings_Devices']` | **YES** | *NO* | *NO* | *NO* |
| **14** | `maintenance_center` | Maintenance & Backups | *None* | `['security_Center', 'settings_Backups']` | **YES** | *NO* | *NO* | *NO* |

---

## 5. WHAT HAPPENS WHEN A MODULE IS DISABLED?

When the Field Technician disables a module in Tab 2 of the Technician Console (e.g. `Laboratory = false` in a Specialized Dental Clinic):
1. **Sidebar Navigation**: Route `laboratory` fails `config.isModuleEnabled('Laboratory')` and is immediately omitted from the navigation bar.
2. **Deep-Link / Manual Navigation Protection**: If a user attempts to activate the route programmatically, `_buildGuardedRouteBody` displays a fail-closed lock screen:
   `"Module Not Entitled (Laboratory): This module is disabled in the active Facility configuration."`
3. **Server-Side API Enforcement**: Any HTTP request to `/api/v1/orders?type=LAB` is intercepted by `enforceModuleEntitlement` and rejected with `403 MODULE_NOT_ENTITLED`.
4. **Conclusion**: Frontend hiding is accompanied by 100% fail-closed backend enforcement.

---

## 6. HOSPITAL ADMINISTRATOR BOUNDARY ENFORCEMENT

The Hospital Administrator role (`HospitalAdmin`) is the operational authority of the facility, but is strictly quarantined from system-level infrastructure:

### Forbidden to Hospital Administrator:
1. **Technician Mode (`/api/v1/technician/*`)**: Calling any technician route with an Admin Bearer token returns `401 Unauthorized: Technician token required`.
2. **Database Factory Reset (`/api/v1/database/factory-reset`)**: Strictly requires active technician session; Hospital Admin cannot erase the database.
3. **Module Entitlement Override (`PUT /api/v1/technician/config`)**: Hospital Admin cannot unilaterally re-enable unlicensed modules or extend subscription dates.
4. **Direct MariaDB Port Access**: Admin workstation connects only via Shelf REST APIs; MariaDB port 3307 remains bound to loopback.
