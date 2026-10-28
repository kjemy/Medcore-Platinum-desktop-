# MEDCORE — BACKEND-SPECIFIC & API CONTRACT INVENTORY (`CATEGORY G` vs `CATEGORY A`)
**Document ID**: `DOC-15B` | **Source**: `Backend/MedCorePlugin/**` & `99_EVIDENCE/WS2_FINDINGS.md`

## 1. WordPress Runtime Artifacts to Discard (`Category G`)
| # | WordPress-Specific Mechanism | Location in `Project 3` | Replacement in `Local MedCore Service` |
|---|---|---|---|
| 1 | WordPress Plugin Bootstrap & Hooks (`add_action('rest_api_init')`) | `Backend/MedCorePlugin/medcore.php` | Standalone Local MedCore Service binary/daemon running as a Windows Service on the Hospital Host. |
| 2 | `dbDelta()` Schema Creation (No Foreign Keys) | `Backend/MedCorePlugin/medcore.php:150-880` | Deterministic versioned SQL migrations (`V001__init.sql` .. `V010__desktop_tables.sql`) with strict `InnoDB` `FOREIGN KEY` constraints. |
| 3 | WordPress Transients for Auth Tokens (`set_transient('mc_token_...')`) | `includes/domain/staff/class-auth-service.php:60` | Dedicated `mc_auth_sessions` table in Local MariaDB bound to `(staff_id, hospital_code, device_id)`. |
| 4 | `wp_options` & `wp_usermeta` Calls | `class-api-saas-extended.php`, `class-api-ai-extra.php` | Dedicated `mc_local_meta` and `mc_license_state` tables in Local MariaDB. |
| 5 | Hostinger Deployment & One-Off Patch Scripts | `Frontend/deploy.js`, root `*.php`/`*.py` scripts | Signed MSIX / Windows Installer package + Technician Service Tool migration runner. |

## 2. Canonical API Contract Inventory (152 Backend Routes + 14 Next.js Routes)
The complete 152-route specification (with exact namespace, path, HTTP method, controller `file:line`, and permission callback) is cataloged in [`WS2_FINDINGS.md`](file:///C:/Users/hp/Desktop/project%204/99_EVIDENCE/WS2_FINDINGS.md).
- **124 Core Hospital Operational Routes (`medcore/v1/*`, `mce/v1/financial/*`)**: Ported to **Local MedCore Service** over LAN (`/api/v1/*`).
- **18 SaaS & Licensing Routes (`mce/v1/license`, `medcore-SaaS/v1/*`)**: Retained on **WordPress Control Plane** (hardened with Ed25519 lease signing).
- **6 AI Routes (`medcore-ai/v1/*`, `mce/v1/ai/*`)**: Redesigned into **Cloud AI Gateway** (`GET /medcore-ai/v1/keys` permanently deleted).
- **4 DB Explorer Routes (`medcore-dbx/v1/*`)**: Ported into **Technician Service Tool** local diagnostic inspector.


---

## 3. Implemented Product Layer API Routes in `LocalMedCoreServer` (`Sections 13–18` — `2026-10-28`)

In addition to the Batch 1–4 foundation endpoints (`Sections 1–12` in `medcore_local_service/lib/src/api/local_medcore_server.dart`), Batch 5 implements:

- **Global Module Entitlement Enforcement Hook**: `LocalMedCoreServer._authorize(...)` invokes `FacilityConfigService.enforceModuleEntitlement(...)` on every permission-protected route; disabled modules fail closed with HTTP `403 MODULE_NOT_ENTITLED` and append an audit entry to `mc_security_logs`.

| Section | Method & Route | Auth Boundary | Purpose |
|---|---|---|---|
| **13. Product Config & Shifts** | `GET /api/v1/product/bootstrap` | Public-safe pre-login (`?hospitalCode=...`) | Returns non-sensitive branding, facility display name, edition label, and pairing/clock readiness for the login shell. |
| **13. Product Config & Shifts** | `GET /api/v1/product/config` | Staff Bearer Token | Returns authoritative `FacilityConfigRecord` (entitled modules, `REQUIRED`/`OPTIONAL`/`HIDDEN` patient fields, branding/appearance, network/hybrid summary). |
| **13. Product Config & Shifts** | `GET /api/v1/shifts` | Staff Bearer (`shifts_Manage`) | Lists authoritative cashier shifts (`mc_shifts`) for the authenticated tenant. |
| **14. Technician / Service Mode** | `GET /api/v1/technician/time-challenge` | Public challenge (`?hospitalCode=...`) | Issues monotonic time-window challenge from `ClockGuardRepository` for offline RSA-2048 maintenance token minting. |
| **14. Technician / Service Mode** | `POST /api/v1/technician/session/open` | RSA-2048 `MC_MAINT_V1` (`TECHNICIAN_SERVICE_MODE`) OR `MEDCORE_TECHNICIAN_SECRET` | Opens isolated `mc_technician_sessions` token; rejects ordinary hospital staff credentials. |
| **14. Technician / Service Mode** | `POST /api/v1/technician/session/close` | `X-MedCore-Tech-Token` | Revokes active technician session in `mc_technician_sessions`. |
| **14. Technician / Service Mode** | `GET /api/v1/technician/config` | `X-MedCore-Tech-Token` (rejects Staff Bearer `403 TECHNICIAN_SESSION_REQUIRED`) | Reads full technician configuration including backup & remote/hybrid contracts. |
| **14. Technician / Service Mode** | `PUT /api/v1/technician/config` | `X-MedCore-Tech-Token` | Atomically updates `mc_facility_config`, `mc_tenants`, and `mc_license_state` (`config_version` incremented + `mc_security_logs`). |
| **14. Technician / Service Mode** | `POST /api/v1/technician/clock-recovery` | `X-MedCore-Tech-Token` + signed `UNLOCK_CLOCK_ROLLBACK` token | Executes audited clock-rollback recovery via `ClockGuardRepository.recoverFromRollbackWithSignedToken`. |
| **15. Maintenance Center** | `GET /api/v1/maintenance/overview` | `X-MedCore-Tech-Token` OR Staff (`sec_AuditLogs` / `cmd_Dashboard`) | Aggregates 14 authoritative diagnostic dimensions (app/service, MariaDB, `15` migrations, table row/storage metrics, clock guard, license, network, devices, backups, double-entry trial balance, security/audit/error logs, maintenance history). |
| **15. Maintenance Center** | `POST /api/v1/maintenance/reports` | `X-MedCore-Tech-Token` OR Staff (`sec_AuditLogs`) | Generates PII-redacted diagnostic snapshot and persists to `mc_maintenance_reports`. |
| **16. Network & Device Pairing** | `GET /api/v1/network/discovery` | Public discovery metadata (`?hospitalCode=...`) | Advertises non-sensitive node discovery metadata (`Discovery != Authorization`, `TLS_CERT_INFRASTRUCTURE_PENDING`, MariaDB `127.0.0.1` loopback-only). |
| **16. Network & Device Pairing** | `POST /api/v1/network/pairing/request` | Pre-auth enrollment request | Registers/updates device in `mc_devices` with `status = 'PENDING'` and SHA-256 hashed 6-char pairing code (`AuthService.login` continues to reject until approved). |
| **16. Network & Device Pairing** | `GET /api/v1/network/topology` | `X-MedCore-Tech-Token` OR Staff (`sec_Devices` / `cmd_Dashboard`) | Lists LAN/Wi-Fi/Loopback device inventory (`name`, `IP`, `connectionType`, `status`, `medcoreVersion`, `role`, `lastSeenAt`). |
| **16. Network & Device Pairing** | `POST /api/v1/network/devices/<deviceId>/approve` | `X-MedCore-Tech-Token` OR Staff (`sec_Devices`) | Verifies 6-char pairing code constant-time against `pairing_code_sha256` and transitions device to `ACTIVE`. |
| **16. Network & Device Pairing** | `POST /api/v1/network/devices/<deviceId>/revoke` | `X-MedCore-Tech-Token` OR Staff (`sec_Devices`) | Transitions device to `REVOKED` and immediately terminates active `mc_auth_sessions` and `mc_technician_sessions` bound to that device. |
| **17. Patient Financial Ledger & Reports** | `GET /api/v1/finance/patients/<patientId>/ledger` | Staff (`fin_Reports` / `fin_Invoices` / `fin_Dashboard` + `Finance` module) | Authoritative MariaDB read-back of patient charges, payments, discounts, refund status, current balance, outstanding debt, postings, cost splits, commissions, and explicit `backendGaps`. |
| **17. Patient Financial Ledger & Reports** | `GET /api/v1/finance/documents/invoice/<visitId>` | Staff (`fin_Invoices` / `fin_Reports`) | Authoritative visit invoice document payload (`mc_visits` + `mc_visit_items` + `mc_visit_item_cost_lines` + `mc_financial_postings`). |
| **17. Patient Financial Ledger & Reports** | `GET /api/v1/finance/documents/receipt/<visitId>` | Staff (`fin_Invoices` / `fin_Reports` / `rec_Billing`) | Authoritative payment receipt payload (`paid_amount`, `payment_method`, `TREASURY_CASH` / `PATIENT_AR` postings). |
| **17. Patient Financial Ledger & Reports** | `GET /api/v1/finance/documents/patient-statement/<patientId>` | Staff (`fin_Reports` / `fin_Invoices`) | Chronological running-balance patient statement derived strictly from MariaDB visits & ledger events. |
| **17. Patient Financial Ledger & Reports** | `GET /api/v1/finance/reports/outstanding-balances` | Staff (`fin_Reports` / `fin_Dashboard`) | Tenant-wide `PATIENT_AR` / unpaid visit debt aging & debtor summary. |
| **17. Patient Financial Ledger & Reports** | `GET /api/v1/finance/reports/financial-history` | Staff (`fin_Reports` / `fin_Dashboard`) | Chronological financial events + account-level `SUM(DEBIT) == SUM(CREDIT)` trial balance summary. |
| **17. Patient Financial Ledger & Reports** | `GET /api/v1/finance/reports/allocations` | Staff (`fin_Reports` / `fin_Commissions`) | Hospital net revenue, consumable COGS (`mc_visit_item_cost_lines`), and doctor commission/settlement (`mc_commissions`) allocation report + `FIN-GAP-LAB-CLINIC-PAYABLE-RULES` disclosure. |
| **18. Backup Engine Foundation** | `GET /api/v1/backups/status` | `X-MedCore-Tech-Token` OR Staff (`sec_AuditLogs` / `cmd_Dashboard`) | Returns backup configuration, vendor-neutral provider catalog (`LOCAL_STORAGE`, `S3_COMPATIBLE`, `CLOUD_ADAPTER`), hybrid contract, and `mc_backup_runs` history. |
| **18. Backup Engine Foundation** | `POST /api/v1/backups/run` | `X-MedCore-Tech-Token` | Executes `BackupEngineService` pipeline (`MariaDB logical snapshot -> GZip -> Authenticated Cipher/HMAC envelope -> SHA-256 -> Provider write -> Independent disk read-back SHA-256 verification -> mc_backup_runs VERIFIED`). |
| **19. Batch 6 Master Product Extensions** | `POST /api/v1/finance/ar-collections` | Staff Bearer (`finance_Invoices` / `finance_Revenue`) | Standalone `PATIENT_AR` debt collection; posts balanced double entries (`DEBIT CASH_ON_HAND / CREDIT ACCOUNTS_RECEIVABLE_PATIENT`) into active shift. |
| **19. Batch 6 Master Product Extensions** | `POST /api/v1/backups/restore/verify` | `X-MedCore-Tech-Token` OR Staff (`sec_AuditLogs`) | Verifies physical backup archive SHA-256 against recorded `mc_backup_runs` before restore. |
| **19. Batch 6 Master Product Extensions** | `POST /api/v1/printing/format` | Staff Bearer (`finance_Invoices`) | Generates formatted ESC/POS thermal receipts and ZPL barcode label buffers with `HARDWARE_VERIFICATION_PENDING` marker. |
| **19. Batch 6 Master Product Extensions** | `POST /api/v1/maintenance/engineering-bundle` | `X-MedCore-Tech-Token` OR Staff (`sec_AuditLogs`) | Generates PII-redacted technician diagnostic bundle (`mc_maintenance_reports`). |
| **20. Specialty Clinical & Real-Time Stream** | `GET /api/v1/clinical/events/stream` | Staff Bearer (`doctor_ClinicalWorkspace` / `nursing_MAR` / `triage_Dashboard`) | SSE stream for real-time doctor queue, triage updates, and critical panic alerts. |
| **20. Specialty Clinical & Real-Time Stream** | `GET /api/v1/clinical/nursing/tasks` | Staff Bearer (`nursing_MAR` + `Nursing` module) | Lists nursing tasks (`mc_nursing_tasks`) filtered by patient/status. |
| **20. Specialty Clinical & Real-Time Stream** | `POST /api/v1/clinical/nursing/tasks` | Staff Bearer (`nursing_MAR` + `Nursing` module) | Creates nursing medication / care task in `mc_nursing_tasks`. |
| **20. Specialty Clinical & Real-Time Stream** | `PUT /api/v1/clinical/nursing/tasks/<id>` | Staff Bearer (`nursing_MAR` + `Nursing` module) | Updates task status to `COMPLETED` / `ADMINISTERED` with audit record. |
| **20. Specialty Clinical & Real-Time Stream** | `GET /api/v1/clinical/icu/flowsheets` | Staff Bearer (`icu_Monitoring` + `ICU` module) | Queries ICU flowsheets (`mc_icu_flowsheets`) by admission. |
| **20. Specialty Clinical & Real-Time Stream** | `POST /api/v1/clinical/icu/flowsheets` | Staff Bearer (`icu_Monitoring` + `ICU` module) | Logs ICU hemodynamic vitals, vent parameters, and GCS score. |
| **20. Specialty Clinical & Real-Time Stream** | `POST /api/v1/clinical/icu/sofa-scores` | Staff Bearer (`icu_Monitoring` + `ICU` module) | Computes and persists calculated SOFA score in `mc_icu_sofa_scores`. |
| **20. Specialty Clinical & Real-Time Stream** | `GET /api/v1/clinical/surgery/schedules` | Staff Bearer (`surgery_OT` + `Surgery` module) | Lists scheduled surgeries (`mc_surgeries`) by date / OR room. |
| **20. Specialty Clinical & Real-Time Stream** | `POST /api/v1/clinical/surgery/schedules` | Staff Bearer (`surgery_OT` + `Surgery` module) | Schedules surgical procedure with checklist validation. |
| **20. Specialty Clinical & Real-Time Stream** | `PUT /api/v1/clinical/surgery/schedules/<id>/status` | Staff Bearer (`surgery_OT` + `Surgery` module) | Transitions surgical status (`IN_THEATRE`, `POST_OP`, `COMPLETED`). |
| **20. Specialty Clinical & Real-Time Stream** | `GET /api/v1/clinical/dialysis/sessions` | Staff Bearer (`dialysis_RRT` + `Dialysis` module) | Lists dialysis sessions (`mc_dialysis_sessions`) with station/machine filters. |
| **20. Specialty Clinical & Real-Time Stream** | `POST /api/v1/clinical/dialysis/sessions` | Staff Bearer (`dialysis_RRT` + `Dialysis` module) | Initiates hemodialysis session (`IN_PROGRESS`). |
| **20. Specialty Clinical & Real-Time Stream** | `PUT /api/v1/clinical/dialysis/sessions/<id>/complete` | Staff Bearer (`dialysis_RRT` + `Dialysis` module) | Finalizes dialysis session with post-weight and ultrafiltration metrics. |
