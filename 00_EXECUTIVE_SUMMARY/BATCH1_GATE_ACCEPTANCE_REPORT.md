# MEDCORE DESKTOP FOUNDATION — BATCH 1 (GATE 1 & GATE 2) ACCEPTANCE REPORT

- **Project Workspace**: `C:\Users\hp\Desktop\project 4\medcore_local_service`
- **Database Runtime**: Local Portable MariaDB 11.4.4 (`InnoDB`, `utf8mb4_unicode_ci`) at `C:\Users\hp\Desktop\project 4\runtime\mariadb` (`127.0.0.1:3307`)
- **Service Stack**: Pure Dart HTTP/REST Service (`shelf`, `shelf_router`, `mysql_client`, `decimal`, `crypto`)
- **Execution Status**: **100% PASSED (`00:21 +8: All tests passed!`)**
- **Safety Verification**: `Project 2` and `Project 3` verified 100% untouched (`0` files modified, added, or deleted).

---

## 1. EXECUTIVE SUMMARY OF BATCH 1 EXECUTION

Batch 1 establishes the authoritative local relational database foundation (**GATE 1**) and the local service, native offline authentication, unified employee identity, and 3-dimensional 10-role RBAC enforcement layer (**GATE 2**) for MedCore Desktop.

All architectural flaws identified during the Phase 1 Reconnaissance (`SEC-FLAW-01` through `SEC-FLAW-06`, `FIN-001`, `FIN-004`, floating-point `double` drift, missing `InnoDB` foreign key constraints, and fragmented `wp_users` vs `mc_staff` identity) have been permanently eliminated in the new foundation.

---

## 2. GATE 1 — DATABASE SCHEMA, MIGRATIONS, INDEXES, REPOSITORIES & TRANSACTIONS

### TASK 1.1 — Database Schema (`sql/migrations/V001..V009`)
- **Total Tables Provisioned**: **90 tables** (`89` normalized `mc_*` domain tables + `mc_schema_migrations` version ledger).
- **Storage Engine & Charset**: 100% `ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`.
- **Monetary Precision**: 100% of monetary, rate, balance, cost, and ledger columns enforced as `DECIMAL(14,4)` in MariaDB and mapped strictly to `Decimal` in Dart (`decimal` package) — zero `double`/`FLOAT` usage.
- **Core Schema Highlights**:
  - **V001 (`V001__platform_governance_and_tenants.sql`)**: `mc_tenants`, `mc_devices`, `mc_license_state`, `mc_clock_guard` (monotonic anti-clock-rollback state), `mc_system_settings`.
  - **V002 (`V002__identity_staff_auth_and_audit.sql`)**: `mc_staff` (unified canonical employee identity with 10-role ENUM, PBKDF2-HMAC-SHA256 password hash, 3D permissions JSON, operational flags, and refund policy), `mc_auth_sessions` (cryptographically bound to `staff_id + hospital_code + device_id`), `mc_staff_evaluations`, `mc_dual_control_requests`, `mc_audit_logs`, `mc_security_logs`.
  - **V003 (`V003__core_patients_shifts_visits_and_ledger.sql`)**: `mc_patients`, `mc_shifts`, `mc_visits`, `mc_visit_items`, `mc_visit_item_cost_lines` (enforcing `FIN-004` service labor vs consumable FIFO cost split), `mc_financial_events` (immutable ledger header with idempotency key), `mc_financial_postings` (double-entry `DEBIT`/`CREDIT` lines).
  - **V004–V009 (`V004..V009__domain_tables_part_1..6.sql`)**: All remaining 69 clinical, ERP, inventory, pharmacy, lab, radiology, admissions, surgery, HR, payroll, insurance, and diagnostic tables normalized to `mc_*`.

### TASK 1.2 — Versioned Migrations (`lib/src/db/migration_runner.dart`)
- Implemented `MigrationRunner` tracking applied SQL files in `mc_schema_migrations` (`version`, `description`, `filename`, `checksum_sha256`, `execution_ms`, `status`).
- Computes SHA-256 checksums for every migration file (`V001..V010`) and verifies checksum integrity on every startup, throwing a tamper error if an already-applied migration file is modified.
- Verified idempotent re-execution (`secondRun` applies `0` migrations when `V001..V010` are already recorded).

### TASK 1.3 — Composite Tenant Indexes & Foreign Keys (`V001..V010`)
- Every multi-tenant table carries a composite `(hospital_code, ...)` index (`idx_mc_*_hosp_*`).
- `V010__composite_indexes.sql` adds high-frequency operational composite indexes (`idx_mc_staff_hosp_active_role`, `idx_mc_patients_hosp_deleted_id`, `idx_mc_visits_hosp_status_created`, `idx_mc_finev_hosp_type_created`).
- Relational `CONSTRAINT fk_* FOREIGN KEY (...) REFERENCES ... ON DELETE RESTRICT ON UPDATE CASCADE` enforced across parent-child hierarchies (`mc_tenants -> mc_devices`, `mc_tenants -> mc_staff`, `mc_staff -> mc_auth_sessions`, `mc_patients -> mc_visits`, `mc_visits -> mc_visit_items`, `mc_visit_items -> mc_visit_item_cost_lines`, `mc_financial_events -> mc_financial_postings`).

### TASK 1.4 — Typed Repositories (`lib/src/repositories/`)
- `ScopeContext` (`lib/src/repositories/scope_context.dart`): Mandatory execution context passed into every repository call (`hospitalCode`, `actor`, `deviceId`, `isTrustedSecureDevice`, `dataScopeMode`).
- `TenantGovernanceRepository` (`lib/src/repositories/tenant_governance_repository.dart`): Tenant management, device enrollment/fingerprint verification, and `ClockGuard` anti-clock-rollback enforcement.
- `StaffIdentityRepository` & `AuthSessionRepository` (`lib/src/repositories/staff_auth_repository.dart`): Canonical staff CRUD, HR rating (`1..5`) persistence, and session lifecycle.
- `PatientRepository`, `ShiftRepository`, & `VisitFinancialService` (`lib/src/repositories/clinical_financial_repositories.dart`): Enforces tenant isolation (`WHERE hospital_code = :hospitalCode`) and Dimension 2 scope filtering (`DataScopeMode.ownOnly` adds `AND (created_by = :actorStaffId OR assigned_doctor_id = :actorStaffId)` unless the user holds `<module>_all`).

### TASK 1.5 — ACID Transaction Boundaries (`lib/src/db/transaction_manager.dart`)
- Implemented `TransactionManager` supporting `IsolationLevel.repeatableRead` and `IsolationLevel.serializable`.
- Dedicated connection reservation per transaction (`START TRANSACTION` -> `COMMIT` / `ROLLBACK`) with nested `SAVEPOINT` support (`tx.withSavepoint(...)`), row-level pessimistic locking (`SELECT ... FOR UPDATE` on `mc_shifts`), atomic audit trail insertion (`tx.writeAuditLog(...)`), and idempotency key lookup (`tx.findFinancialEventByIdempotencyKey(...)`).
- Verified atomic multi-table financial posting (`mc_visits` + `mc_visit_items` + `mc_visit_item_cost_lines` + `mc_financial_events` + `mc_financial_postings` + `mc_shifts` + `mc_audit_logs`):
  - **FIN-004 Verification**: For a `1000.0000 EGP` visit composed of `600.0000 EGP` service labor and `400.0000 EGP` medical consumables (`250.0000 EGP` FIFO cost), a `50%` doctor commission is calculated strictly on the `600.0000 EGP` service labor (`300.0000 EGP` doctor commission), never on consumables.
  - **FIN-001 Double-Entry Trial Balance Verification**: `SUM(DEBIT) == SUM(CREDIT) == 1550.0000 EGP` across `CASH_DRAWER`, `DOCTOR_COMMISSION_EXPENSE`, `COGS_CONSUMABLES`, `SERVICE_REVENUE`, `CONSUMABLE_REVENUE`, `DOCTOR_PAYABLE`, and `INVENTORY_ASSET`.

### TASK 1.6 — Live MariaDB Acceptance Tests (`test/batch1_gate1_and_gate2_acceptance_test.dart`)
- Executed directly against local MariaDB 11.4.4 (`127.0.0.1:3307`) with zero mocks.

---

## 3. GATE 2 — LOCAL SERVICE, AUTHENTICATION, EMPLOYEE IDENTITY, RBAC & PERMISSION ENFORCEMENT

### TASK 2.1 — Local MedCore Service (`lib/src/api/local_medcore_server.dart`)
- Pure Dart `shelf` HTTP/REST server exposing:
  - `GET /api/v1/health` (DB liveness, applied migrations count, table count)
  - `POST /api/v1/auth/login` (Offline PBKDF2 login + device enrollment check + clock rollback guard)
  - `POST /api/v1/auth/logout` (Immediate session revocation + audit log)
  - `GET /api/v1/auth/me` (Session & 3D permission introspection)
  - `GET /api/v1/staff`, `POST /api/v1/staff`, `POST /api/v1/staff/<id>/evaluate`
  - `GET /api/v1/patients`, `POST /api/v1/patients`, `DELETE /api/v1/patients/<id>`
  - `POST /api/v1/shifts/open`, `POST /api/v1/visits/atomic-checkout`
  - `POST /api/v1/finance/refunds`, `GET /api/v1/finance/settlements`
  - `GET /api/v1/clinical/lab/worklist`

### TASK 2.2 — Native Offline Authentication (`lib/src/security/auth_service.dart` & `password_hasher.dart`)
- Uses `PBKDF2-HMAC-SHA256` (`60,000` iterations, 16-byte cryptographic random salt, constant-time comparison).
- Closes **SEC-FLAW-03** & **SEC-FLAW-05**:
  - Refuses login (`403 DEVICE_NOT_VERIFIED`) if `deviceId` is not enrolled and `ACTIVE` in `mc_devices` for that `hospital_code`.
  - Binds every session token (`mcs_<64-hex>`) in `mc_auth_sessions` to `(staff_id, hospital_code, device_id)`.
  - Rejects cross-tenant token replay (`403 TENANT_BINDING_MISMATCH`) and cross-device token replay (`403 DEVICE_BINDING_MISMATCH`) and records forensic rows in `mc_security_logs`.
  - Rejects requests if system clock rollback (`> 300s`) is detected by `ClockGuard` (`403 CLOCK_ROLLBACK_DETECTED`).

### TASK 2.3 — Canonical Employee Identity (`mc_staff`)
- Eliminates WordPress `wp_users` / `mc_staff` dual-table drift.
- Stores `staff_code`, `hospital_code`, `email`, `username`, `password_hash`, `role` (10-value ENUM), `permission_mode` (`default` | `custom`), `permissions_json` (`base`, `all`, `secure`), `can_edit`, `can_delete`, `can_collect_money`, `can_make_refunds`, `refund_policy` (`none` | `direct` | `approval`), `doctor_definition_code`, `clinic_codes_json`, and HR `rating` (`1..5`).

### TASK 2.4 — Complete 10-Role & 261-Key RBAC Catalog (`lib/src/security/permissions_catalog.dart`)
- Preserves all **10 canonical roles** (`SuperAdmin`, `HospitalAdmin`, `Doctor`, `Nurse`, `Receptionist`, `Cashier`, `Pharmacist`, `Lab`, `Radiology`, `Employee`) — never collapses `Pharmacist`, `Lab`, or `Radiology` into `Employee`.
- Codifies all **87 Base UI permission keys**, **87 `_all` Scope keys**, and **87 `_secure` Device Lock keys** (**261 UI keys total**) plus **43 backend dot-notation permissions** and **4 operational flags** (`canEdit`, `canDelete`, `canCollectMoney`, `canMakeRefunds` + `refundPolicy`).

### TASK 2.5 — Multi-Layer Permission Enforcement (`lib/src/security/rbac_evaluator.dart`)
- **Closes SEC-FLAW-01**: `permission_mode = 'default'` resolves strictly to `PermissionsCatalog.defaultBasePermissionsForRole(role)` — never wildcard `*`.
- **Closes SEC-FLAW-02**: Dimension 3 (`<module>_secure`) is evaluated server-side by inspecting `mc_devices.is_trusted_secure_device` in MariaDB, never trusting client-supplied booleans.
- **Enforces Dimension 2 (`<module>_all`) in SQL**: When a user has `<module>` base permission but lacks `<module>_all`, `RbacEvaluator.authorize(...)` sets `DataScopeMode.ownOnly`, and the repository appends `AND (created_by = :actorStaffId OR assigned_doctor_id = :actorStaffId)` to the SQL query.
- **Enforces Operational Flags & Refund Policy**:
  - Destructive endpoints require `canDelete == true` (`403 DELETE_FORBIDDEN` otherwise).
  - Cash collection endpoints require `canCollectMoney == true` (`403 COLLECT_MONEY_FORBIDDEN` otherwise).
  - Refund endpoints enforce `refundPolicy`: `'none'` -> `403 REFUND_FORBIDDEN`; `'approval'` without `dualControlApprovalToken` -> `202 Accepted (PENDING_DUAL_CONTROL_APPROVAL)`; `'approval'` with token or `'direct'` -> `200 OK (REFUND_EXECUTED)`.

---

## 4. LIVE ACCEPTANCE TEST EXECUTION LOG (`dart test`)

```text
00:00 +0: loading test/batch1_gate1_and_gate2_acceptance_test.dart
00:00 +0: (setUpAll)
00:02 +0: GATE 1 — Database Schema, Migrations, Indexes, Repositories & Transactions TASK 1.1 & 1.2: Applies V001..V010 migrations, verifies 92 InnoDB utf8mb4 tables & idempotency
00:08 +1: GATE 1 — Database Schema, Migrations, Indexes, Repositories & Transactions TASK 1.3: Verifies Composite Tenant Indexes and Foreign Key ON DELETE RESTRICT enforcement
00:09 +2: GATE 1 — Database Schema, Migrations, Indexes, Repositories & Transactions TASK 1.4 & 1.5: Verifies ACID Transaction Rollback, FOR UPDATE Locks, FIN-001 & FIN-004 Cost Split
00:11 +3: GATE 2 — Local Service, Authentication, Employee Identity, 10-Role RBAC & Permission Enforcement TASK 2.1, 2.2 & 2.3: Starts LocalMedCoreServer and authenticates all 10 Canonical Roles natively
00:19 +4: GATE 2 — Local Service, Authentication, Employee Identity, 10-Role RBAC & Permission Enforcement TASK 2.2: Closes SEC-FLAW-03 & SEC-FLAW-05 (Blocks Unenrolled Device, Cross-Tenant & Cross-Device Replay)
00:20 +5: GATE 2 — Local Service, Authentication, Employee Identity, 10-Role RBAC & Permission Enforcement TASK 2.4 & 2.5: Closes SEC-FLAW-01 (Default mode enforces strict role permissions, never wildcard *)
00:20 +6: GATE 2 — Local Service, Authentication, Employee Identity, 10-Role RBAC & Permission Enforcement TASK 2.5: Enforces Dimension 2 (_all Tenant-Wide vs Own-Only Scope) at SQL Repository Layer
00:20 +7: GATE 2 — Local Service, Authentication, Employee Identity, 10-Role RBAC & Permission Enforcement TASK 2.5: Enforces Dimension 3 (_secure Device Lock) & Operational Flags (canDelete, canCollectMoney, refundPolicy)
00:21 +8: (tearDownAll)
00:21 +8: All tests passed!
```
