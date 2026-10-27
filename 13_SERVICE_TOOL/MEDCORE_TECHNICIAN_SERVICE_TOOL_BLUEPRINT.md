# MEDCORE — TECHNICIAN SERVICE TOOL BLUEPRINT (`CATEGORY I`)
**Document ID**: `DOC-12` | **Requirement Reference**: Prompt §18 (Technician Service Tool, Dual-Output Diagnostic Bundle & PII Privacy Filter)

---

## 1. Purpose & Security Boundary
When an offline hospital server experiences a database anomaly, shift variance dispute, clock-rollback lock, or backup restoration need, support engineers cannot SSH into an air-gapped hospital LAN.
The **MedCore Technician Service Tool (`medcore-service-tool`)** is a standalone, cryptographically gated local maintenance utility (CLI + lightweight local admin UI) deployed on the Hospital Server alongside `Local MedCore Service`.

---

## 2. Cryptographic Maintenance Authorization (Challenge-Response)
High-privilege maintenance operations (unlocking `mc_clock_guard`, resetting a revoked device, restoring an encrypted backup, running ledger repair) CANNOT be triggered by a static password:
1. The tool displays a **Maintenance Challenge Code** containing `hospital_code`, `server_hw_fingerprint`, `current_clock_guard_state`, and a `nonce`.
2. MedCore Central Support signs an **Ed25519 Maintenance Unlock Token** valid for a single `nonce` and a strict window (e.g., 2 hours) specifying the allowed action (`CLOCK_UNLOCK`, `DEVICE_RESET`, `DB_RESTORE`, `DIAGNOSTIC_EXPORT`).
3. Every action performed by the Technician Service Tool is permanently recorded in `mc_audit_logs` and `mc_security_logs` with the technician token ID.

---

## 3. Dual-Output Diagnostic Export Architecture

Whenever the technician runs a system health check or exports a support package, the tool produces **two strictly separated outputs**:

### 3.1 Output A — Executive Report (`Executive_Health_Report_<date>.pdf` / `.html`)
Designed for the **Hospital Director / Non-Technical Management** (Arabic & English):
- **System & License Status**: Edition, remaining lease days, active vs entitled devices (`mc_devices`), last online heartbeat.
- **Database & Backup Integrity**: Total patients, visits, active admissions, last successful backup timestamp & SHA-256 verification status (`mc_backup_runs`).
- **Financial & Shift Health Summary**:
  - Open cashier shifts count and duration alerts (`shifts open > 24h`).
  - Trial balance verification status (`SUM(DEBIT) == SUM(CREDIT)` check across `mc_financial_postings`).
  - Unsettled doctor commissions summary.
- **Zero Technical Jargon & Zero Raw Stack Traces**.

### 3.2 Output B — Engineering Bundle (`MedCore_Diag_Bundle_<uuid>.mcdiag` — Encrypted ZIP)
Designed for **MedCore Core L3 Engineers**:
- Service & MariaDB configuration metrics (`innodb_buffer_pool_size`, slow query digest, table row counts, index cardinality, schema migration history).
- Application structured error logs, deadlocks (`SHOW ENGINE INNODB STATUS`), failed idempotency keys, and anomalous financial events (`mc_financial_events` where `SUM(DEBIT) != SUM(CREDIT)`).
- Clock guard state (`mc_clock_guard`) and device handshake error logs.

---

## 4. Mandatory PII Privacy Filter (Zero Patient Leak Guarantee)
Before any SQL row, JSON payload, or log line is written into the **Engineering Bundle (`Output B`)**, it passes through the deterministic **PII Privacy Filter** (modeled and expanded from `Backend/medcore-database-explorer/api/class-dbx-api-router.php` sensitive field rules):

| Entity / Log Source | Columns / Fields Stripped or Pseudonymized | Transformation Rule |
|---|---|---|
| `mc_patients` | `full_name`, `first_name`, `last_name`, `phone`, `mobile`, `national_id`, `passport_no`, `email`, `address`, `emergency_contact` | Replaced with deterministic HMAC token: `PAT-REDACTED-<HMAC_SHA256(id)[:8]>` |
| `mc_staff` | `password_hash`, `pin_code`, `national_id`, `phone`, `email`, `bank_account_iban` | Passwords/PINs → `[REDACTED-SECRET]`; PII → `STAFF-REDACTED-<id>` |
| `mc_clinical_notes`, `mc_lab_results`, `mc_radiology_reports`, `mc_discharge_summaries` | Free-text clinical narratives (`chief_complaint`, `findings`, `impression`, `notes`) | Omitted by default in standard diagnostic bundle; only structural metadata (`order_id`, `status`, `timestamps`, `abnormal_flag`) is exported |
| `mc_auth_sessions`, `mc_local_meta`, HTTP Logs | `Authorization` headers, `Cookie`, `session_token`, `ed25519_private_key`, API keys | Replaced with `[REDACTED-CREDENTIAL]` |
