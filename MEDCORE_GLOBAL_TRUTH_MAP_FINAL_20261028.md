# MEDCORE PLATINUM — GLOBAL SYSTEM TRUTH MAP (FINAL RELEASE CANDIDATE)
**Execution Date:** 2026-10-28
**Authority:** Master Engineering Constitution (@Khaled All Rules)
**Scope:** Complete 18-Layer Traceability from Flutter Desktop UI to Physical MariaDB Storage

---

## 1. AUTHORITATIVE PERSISTENCE TRUTH (MARIADB 11.4.4)
The authoritative data layer consists of 16 versioned migrations executing on MariaDB InnoDB engine:
- Total Tables: 98 Tables (InnoDB)
- Total Migrations: 16 (`V001` through `V016`)
- Key Subsystems:
  1. Platform Governance & Tenancy (`mc_tenants`, `mc_devices`, `mc_license_state`)
  2. Identity, Auth & RBAC (`mc_staff`, `mc_auth_sessions`, `mc_roles`, `mc_audit_trail`)
  3. Clinical Core (`mc_patients`, `mc_encounters`, `mc_diagnoses`, `mc_beds`, `mc_prescriptions`)
  4. Diagnostic Core (`mc_diagnostic_orders`, `mc_diagnostic_results`, `mc_samples`)
  5. Financial Core (`mc_visits`, `mc_shifts`, `mc_invoices`, `mc_financial_postings`, `mc_accounts`)
  6. Product Layer (`mc_facility_config`, `mc_technician_sessions`, `mc_maintenance_reports`)
  7. External Liabilities & PKI (`mc_external_payables`, `mc_lan_certificates`)

---

## 2. SERVICE BOUNDARY (LOCAL MEDCORE SERVICE)
- Framework: Dart AOT/JIT HTTP Daemon on `127.0.0.1:8443`
- Database Connector: `mysql_client` used strictly within `medcore_local_service/lib/src/repositories/`
- Authorization: Bearer session token + `x-tenant-id` + `x-medcore-device-id`
- Isolation: Multi-tenant filtering enforced at repository SQL level (`hospital_code = :hosp`).

---

## 3. CLIENT PRESENTATION LAYER (FLUTTER DESKTOP)
- Architecture: Zero direct database connectivity. All mutations dispatched via `MedCoreApiClient` over HTTP REST.
- Dynamic Configuration: Patient intake fields adaptively rendered based on facility type and configuration (`REQUIRED`, `OPTIONAL`, `HIDDEN`).
- Role-Aware Shell: Navigation items dynamically filtered based on staff permissions and enabled facility modules.
