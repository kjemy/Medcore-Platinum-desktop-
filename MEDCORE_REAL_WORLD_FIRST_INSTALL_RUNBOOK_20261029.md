# MEDCORE PLATINUM DESKTOP
## REAL-WORLD FIRST INSTALLATION RUNBOOK
### FIELD DEPLOYMENT GUIDE • COMMISSIONING • ADMIN ONBOARDING • MULTI-WORKSTATION LAN

---

**Document Reference:** `MEDCORE_REAL_WORLD_FIRST_INSTALL_RUNBOOK_20261029.md`  
**Date:** 2026-10-29  
**Audience:** MedCore Field Deployment Engineers & Certified Technical Partners  
**Authority:** Gemini 3.8 High (Main Agent Authority)  
**Governance:** Khaled Universal Engineering Constitution (`Khaled All Rules`)  
**Workspace:** `C:\Users\hp\Desktop\project 4`  
**Repository:** `kjemy/Medcore-Platinum-desktop-`  
**Branch:** `main`

---

## 1. PRE-REQUISITES & SITE PREPARATION

### 1.1 Server Workstation Hardware
- **Operating System**: Windows 10 Pro / Enterprise (x64) or Windows 11 Pro (x64) / Windows Server 2022.
- **CPU**: 4+ Cores (Intel Core i5/i7 or AMD Ryzen 5/7 equivalent).
- **RAM**: Minimum 8 GB (16 GB recommended for multi-client facilities).
- **Storage**: 100 GB+ SSD (dedicated fast partition for MariaDB InnoDB data).
- **Network**: Local Gigabit Ethernet switch or isolated hospital Wi-Fi subnet.
- **Internet Access**: **NOT REQUIRED**. MedCore Platinum is 100% offline-capable.

### 1.2 Deployment Package Files
Ensure the official deployment package contains:
1. `runtime/mariadb/` — Embedded MariaDB 11.4 binaries and configuration (`my.ini`).
2. `medcore_local_service.exe` — Local MedCore Shelf HTTP server executable.
3. `medcore_desktop.exe` + `flutter_windows.dll` + `data/` — Flutter Desktop Release client.
4. `sql/migrations/` — 16 canonical schema migrations (V001..V016).

---

## 2. STEP-BY-STEP FIELD EXECUTION

```text
  STEP 1: Start Database (MariaDB 11.4 on 127.0.0.1:3307)
     │
     ▼
  STEP 2: Start Local MedCore Service (Port 8080)
     │
     ▼
  STEP 3: Launch MedCore Desktop (Evaluation / Release)
     │
     ▼
  STEP 4: Authenticate Technician Mode (Secret Key)
     │
     ▼
  STEP 5: Configure Facility, Edition & Subscription (Tab 1)
     │
     ▼
  STEP 6: Select Enabled Modules (Tab 2) & Patient Fields (Tab 3)
     │
     ▼
  STEP 7: Provision First Hospital Administrator (Tab 8)
     │
     ▼
  STEP 8: Print / Deliver Official Secure Handover Slip
     │
     ▼
  STEP 9: Hospital Administrator First Login & Mandatory Password Change
     │
     ▼
  STEP 10: Administrator Creates Operational Staff & Connects LAN Devices
```

---

### STEP 1: INITIALIZE & START MARIADB 11.4
1. Open PowerShell as Administrator on the server workstation.
2. Navigate to deployment root:
   ```powershell
   Set-Location "C:\MedCorePlatinum"
   ```
3. Initialize the database directory (if fresh install):
   ```powershell
   .\runtime\mariadb\bin\mysql_install_db.exe --datadir="C:\MedCorePlatinum\runtime\mariadb_data"
   ```
4. Start the MariaDB daemon bound strictly to loopback:
   ```powershell
   Start-Process -FilePath ".\runtime\mariadb\bin\mysqld.exe" -ArgumentList "--defaults-file=.\runtime\mariadb\my.ini", "--console" -WindowStyle Hidden
   ```
5. Verify MariaDB port 3307 is listening:
   ```powershell
   Test-NetConnection -ComputerName 127.0.0.1 -Port 3307
   ```

---

### STEP 2: START LOCAL MEDCORE SERVICE
1. Launch the Local MedCore Shelf backend:
   ```powershell
   Start-Process -FilePath ".\medcore_local_service.exe" -ArgumentList "--port=8080" -WindowStyle Hidden
   ```
2. Verify service bootstrap health:
   ```powershell
   Invoke-RestMethod -Uri "http://127.0.0.1:8080/api/v1/health"
   ```
   *Expected response:* `{"ok": true, "data": {"status": "HEALTHY", "database": "CONNECTED", ...}}`

---

### STEP 3: LAUNCH MEDCORE DESKTOP
1. Launch `medcore_desktop.exe`.
2. The initial splash screen displays:
   - MedCore official logo
   - Facility identity banner
   - Uncommissioned status indicator
   - Button: **"Service / Technician Mode"**

---

### STEP 4: ENTER TECHNICIAN MODE
1. Click **"Service / Technician Mode"** at the bottom of the login card.
2. Enter the authorized hardware-bound **Technician Secret** for this facility.
3. The system generates an authenticated session token in `mc_technician_sessions`.
4. The **Protected Technician / Service Installation Console** opens with 8 tabs.

---

### STEP 5: CONFIGURE FACILITY, EDITION & SUBSCRIPTION (TAB 1)
1. Select **Tab 1: Facility, Edition & Subscription**.
2. Fill in:
   - **Facility Name**: e.g., `City Care General Hospital`
   - **Branch Code**: `MAIN`
   - **Installation Identity**: `INST-EGY-ALX-001`
   - **Facility Type**: Select from dropdown (`GENERAL_HOSPITAL`, `SPECIALIZED_CLINIC`, `DENTAL_CLINIC`, `DAY_SURGERY_CENTER`, `DIAGNOSTIC_CENTER`).
   - **Commercial Edition**: Select edition (`PLATINUM`, `GOLD`, `SILVER`, etc.).
   - **Subscription Dates**:
     - Subscription Start: `2026-10-29`
     - Subscription Expiry: `2027-10-29` (1-Year Term).
3. Click **"Commit Configuration to MariaDB"** at top right.
4. Verify success snackbar appears: `Configuration committed atomically to MariaDB.`

---

### STEP 6: CONFIGURE MODULES & PATIENT FIELDS (TABS 2 & 3)
1. In **Tab 2 (Enabled Modules)**:
   - Check/uncheck modules based on the hospital's contract.
   - For a Dental Clinic, uncheck `Inpatient`, `ICU`, `Surgery`, `Dialysis`.
   - For a General Hospital, leave all 17 modules checked.
2. In **Tab 3 (Facility Patient Fields)**:
   - Review the 14 configurable fields.
   - Set critical fields (e.g. `nationalId`, `bloodGroup`) to `REQUIRED`.
   - Set inapplicable fields to `HIDDEN`.
3. Click **"Commit Configuration to MariaDB"**.

---

### STEP 7: PROVISION THE FIRST HOSPITAL ADMINISTRATOR (TAB 8)
1. Navigate to **Tab 8: Initial Administrator Handover**.
2. Notice the status card indicates:
   `Status: Initial Administrator Required (0 accounts exist)`.
3. Fill in the provisioning form:
   - **Staff Code**: `ADM-001`
   - **Full Name**: Enter the Hospital Director's name (e.g. `Dr. Khaled Mansour`).
   - **Email Address**: `director@citycare.org`
4. Click **"Generate Strong Password"**.
   - The generator produces a 16-character high-entropy temporary password (e.g. `k8#M2$vP9!qL5@xR`).
5. Click **"Provision Initial Hospital Administrator"**.
6. The system executes `POST /api/v1/technician/initial-admin`, hashes the password with PBKDF2, sets `force_password_change = true`, commits the record to `mc_staff`, and creates an audit entry in `mc_audit_logs`.
7. The **Secure Handover Slip Card** renders with all details formatted for client delivery.
8. Click **"Print Handover Slip"** or **"Copy Handover Details"**.
9. Click **"Exit Service Mode"** at top right.

---

### STEP 8: CLIENT HANDOVER CEREMONY
1. Meet with the Hospital Director / designated Hospital Administrator.
2. Present the printed **Secure Handover Slip**.
3. Instruct the Administrator:
   - *"These temporary credentials grant one-time initial access."*
   - *"The system will immediately prompt you to create your own private permanent password."*
   - *"Once changed, no one—including the deployment technician—can access your account."*

---

### STEP 9: FIRST ADMIN SIGN-IN & MANDATORY PASSWORD CHANGE
1. In `medcore_desktop.exe`, on the Login Screen:
   - Email: `director@citycare.org`
   - Password: Enter the temporary password from the handover slip.
2. Click **"Sign In"**.
3. The desktop shell opens, but **sidebar navigation is locked**.
4. The screen renders **`_ForcePasswordChangeScreen`**:
   - Title: *"Initial Login — Mandatory Password Change"*.
   - Input 1: Enter Temporary Password (for identity verification).
   - Input 2: Enter New Permanent Password (minimum 8 characters).
   - Input 3: Confirm New Password.
5. Click **"Update Password & Unlock Workspace"**.
6. The system executes `POST /api/v1/staff/change-password`, updates `mc_staff.force_password_change = 0`, and revokes the temporary password.
7. The full **MedCore Platinum Desktop Workspace** immediately unlocks!

---

### STEP 10: CREATE OPERATIONAL STAFF ACCOUNTS
1. The Administrator navigates to **"Staff & Employee Accounts"** (`staff_admin` in sidebar).
2. Click **"Add New Employee"**.
3. Create accounts for hospital departments:
   - Doctor: Staff Code `DOC-001`, Role `Doctor`, Email `doctor@citycare.org`
   - Nurse: Staff Code `NUR-001`, Role `Nurse`, Email `nurse@citycare.org`
   - Cashier: Staff Code `CSH-001`, Role `Cashier`, Email `cashier@citycare.org`
   - Receptionist: Staff Code `REC-001`, Role `Receptionist`, Email `reception@citycare.org`
   - Pharmacist: Staff Code `PHR-001`, Role `Pharmacist`, Email `pharmacy@citycare.org`
   - Lab Tech: Staff Code `LAB-001`, Role `LabTechnician`, Email `lab@citycare.org`
   - Radiologist: Staff Code `RAD-001`, Role `Radiologist`, Email `rad@citycare.org`
4. Temporary passwords are generated for each staff member; each staff member will be prompted to set their permanent password upon their first sign-in.

---

### STEP 11: CONNECT CLIENT WORKSTATIONS OVER LAN
1. On each client workstation (e.g. Doctor's PC in Clinic 1):
   - Install `medcore_desktop.exe`.
   - Point the server base URL to the server's LAN IP: `http://192.168.1.100:8080`.
2. Launch the desktop app:
   - The app displays a 6-digit Device Pairing Request code (e.g. `482-910`).
3. On the Server Workstation, Administrator navigates to **"LAN / Wi-Fi Devices"** (`network_devices`).
4. Click **"Approve Device"** matching the pairing code.
5. The client workstation is now authenticated and permitted to sign in hospital staff!
6. **MariaDB port 3307 remains strictly closed and protected behind the server firewall.**

---

## 3. VERIFICATION & RECOVERY SQL QUERIES

Technicians can verify physical database truth using the embedded mysql client:

```sql
-- 1. Verify Facility Configuration Record:
SELECT hospital_code, facility_name, facility_type, edition, subscription_expires_utc 
FROM mc_facility_config;

-- 2. Verify Staff Table (Zero backdoor accounts, only authorized staff):
SELECT staff_code, full_name, email, role, force_password_change, is_active 
FROM mc_staff;

-- 3. Verify Initial Admin Commissioning Audit Entry:
SELECT event_type, details, created_at 
FROM mc_audit_logs 
WHERE event_type = 'technician.initial_admin.provisioned';

-- 4. Verify Active Network Devices:
SELECT device_id, device_name, connection_type, status 
FROM mc_devices;
```

---

## 4. FIELD SUCCESS DECLARATION

The commissioning engineer may declare the deployment successful and conclude the visit when:
- [x] Initial administrator created without default credentials.
- [x] Handover slip delivered to hospital director.
- [x] First-login password change completed and verified.
- [x] At least one operational staff user created and logged in.
- [x] Sidebar navigation accurately reflects licensed modules.
- [x] Backup package test verified (`POST /api/v1/database/backup`).
