================================================================================
MEDCORE PLATINUM DESKTOP — FIELD COMMISSIONING & INSTALLATION GUIDE
================================================================================

PREREQUISITES:
1. Windows 10/11 x64 or Windows Server 2019/2022.
2. MariaDB 10.6+ or 11.4+ listening on 127.0.0.1:3307 with root access.
   (Run service\scripts\provision_mariadb.ps1 if MariaDB is not yet installed).

FIRST-RUN COMMISSIONING STEPS:
1. Double-click "start_medcore_system.bat" to start the Local Service and Desktop Client.
2. Upon first boot, the Local Service automatically provisions a secure, one-time
   technician commissioning secret and writes:
   service\runtime\security\FIRST_RUN_COMMISSIONING_SECRET.txt
3. On the MedCore Desktop connection screen, switch to:
   "Technician / Service Installation Gate"
4. Enter your Facility Code (e.g. HOSP_MAIN), Device ID, and the Commissioning Secret
   from FIRST_RUN_COMMISSIONING_SECRET.txt.
5. In the Technician Console:
   - Configure Hospital Metadata, Edition, and Entitled Modules (Tabs 1-7).
   - Go to Tab 8 ("Initial Admin Provisioning") to create the first Hospital Administrator.
   - Hand the Secure Handover Slip with the temporary password to the Hospital Administrator.
   - Click "Close Technician Session".
6. The Hospital Administrator logs in, completes the mandatory password change,
   and normal hospital operations begin.

COMMISSIONING CLI UTILITY:
To inspect or rotate technician credentials from the command line:
   commission_technician.bat status
   commission_technician.bat generate
   commission_technician.bat set <NewSecret#2026>

SECURITY ARCHITECTURE INVARIANT:
- Flutter Desktop connects strictly via HTTP to Local MedCore Service (127.0.0.1:8443).
- MariaDB connects strictly via loopback (127.0.0.1:3307).
- Flutter NEVER connects directly to MariaDB.
================================================================================
