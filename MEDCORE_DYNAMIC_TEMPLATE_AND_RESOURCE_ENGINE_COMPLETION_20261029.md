# MEDCORE PLATINUM DESKTOP
# DYNAMIC CLINICAL TEMPLATE ENGINE & MULTI-RESOURCE SLOT RULE ENGINE
## MASTER PRODUCT COMPLETION & ARCHITECTURAL VERIFICATION REPORT

- **Date**: October 29, 2026
- **Author**: MedCore Engineering (Main Agent Autonomous Execution)
- **Governance**: Khaled Universal Engineering Constitution v1.0.0
- **Workspace**: `C:\Users\hp\Desktop\project 4`
- **Repository**: `kjemy/Medcore-Platinum-desktop-`
- **Branch**: `main`
- **Base Release Candidate**: `v1.0.0-rc.3` (`713a8a4578cb7f82258b57497afa800346280534`) — STRICTLY IMMUTABLE

---

## 1. EXECUTIVE SUMMARY

This engineering deliverable marks the complete implementation, hardening, Red Team adversarial gating, and Blue Team verification of the two final configurable enterprise capabilities of MedCore Platinum Desktop:

1. **Dynamic Clinical Template Engine**:
   - Visual schema editor and field designer for medical administrators (`ClinicalTemplateEditorScreen`).
   - Dynamic typed rendering runtime supporting multiple input primitives: `text`, `multiline`, `integer`, `decimal`, `boolean`, `select`, and `date`.
   - Immutable version lifecycle: Draft editing, version bumping (`v1 -> v2`), single-active enforcement per template code with automatic retirement of previous active versions.
   - Encapsulated clinical encounter snapshot persistence in authoritative MariaDB storage (`mc_clinical_template_usages.snapshot_json`), guaranteeing that clinical documentation remains immutable even if template definitions evolve in the future.
   - Strict multi-tenant isolation, facility binding, and server-side RBAC validation.

2. **Dynamic Multi-Resource Slot Rule Engine**:
   - Unified resource registry (`mc_scheduling_resources`) classifying scheduling assets across 4 domain primitives: `DOCTOR`, `ROOM`, `EQUIPMENT`, and `DEVICE`.
   - Dynamic scheduling rule engine (`mc_scheduling_rules`) defining appointment prerequisites, durations, and clinical buffer windows (`buffer_before_minutes` and `buffer_after_minutes`).
   - Atomic transactional slot allocation engine (`allocateResourcesTransaction`) operating on MariaDB with ACID transaction guarantees, locking resources for update and preventing double-booking race conditions.
   - Buffer conflict detection: Guarantees that buffer windows (e.g., sterilization, room cleanup, prep) cannot be encroached by subsequent or preceding bookings.
   - Desktop management console (`ResourceSchedulingManagementScreen`) offering live conflict simulation, resource catalog management, and rule configuration.

---

## 2. DATABASE ARCHITECTURE & MIGRATION V017

### Migration File:
`medcore_local_service/sql/migrations/V017__dynamic_templates_and_scheduling_rules.sql`

### Schema Enhancements & DDL:

#### A. Clinical Templates Index Optimization
```sql
ALTER TABLE `mc_clinical_templates`
    ADD INDEX IF NOT EXISTS `idx_mc_clinical_templates_hosp_code` (`hospital_code`, `template_code`),
    ADD INDEX IF NOT EXISTS `idx_mc_clinical_templates_hosp_status` (`hospital_code`, `status`);

ALTER TABLE `mc_clinical_template_usages`
    ADD INDEX IF NOT EXISTS `idx_mc_template_usages_hosp_patient` (`hospital_code`, `patient_id`),
    ADD INDEX IF NOT EXISTS `idx_mc_template_usages_hosp_template` (`hospital_code`, `template_id`);
```

#### B. Scheduling Resources (`mc_scheduling_resources`)
```sql
CREATE TABLE IF NOT EXISTS `mc_scheduling_resources` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `resource_code` VARCHAR(64) NOT NULL,
    `name` VARCHAR(150) NOT NULL,
    `resource_type` ENUM('DOCTOR', 'ROOM', 'EQUIPMENT', 'DEVICE') NOT NULL,
    `department` VARCHAR(100) NULL,
    `is_active` TINYINT(1) NOT NULL DEFAULT 1,
    `metadata_json` JSON NULL,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    UNIQUE KEY `uq_mc_sched_res_hosp_code` (`hospital_code`, `resource_code`),
    INDEX `idx_mc_sched_res_hosp_type` (`hospital_code`, `resource_type`, `is_active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

#### C. Scheduling Rules (`mc_scheduling_rules`)
```sql
CREATE TABLE IF NOT EXISTS `mc_scheduling_rules` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `rule_code` VARCHAR(64) NOT NULL,
    `name` VARCHAR(150) NOT NULL,
    `appointment_type` VARCHAR(64) NOT NULL,
    `primary_resource_type` ENUM('DOCTOR', 'ROOM', 'EQUIPMENT', 'DEVICE') NOT NULL,
    `required_co_resource_types` JSON NOT NULL,
    `default_duration_minutes` INT UNSIGNED NOT NULL DEFAULT 30,
    `buffer_before_minutes` INT UNSIGNED NOT NULL DEFAULT 0,
    `buffer_after_minutes` INT UNSIGNED NOT NULL DEFAULT 0,
    `is_active` TINYINT(1) NOT NULL DEFAULT 1,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    UNIQUE KEY `uq_mc_sched_rules_hosp_code` (`hospital_code`, `rule_code`),
    INDEX `idx_mc_sched_rules_hosp_appttype` (`hospital_code`, `appointment_type`, `is_active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

#### D. Appointment Resource Allocations (`mc_appointment_resource_allocations`)
```sql
CREATE TABLE IF NOT EXISTS `mc_appointment_resource_allocations` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `hospital_code` VARCHAR(64) NOT NULL DEFAULT 'DEFAULT',
    `appointment_id` BIGINT UNSIGNED NOT NULL,
    `resource_id` BIGINT UNSIGNED NOT NULL,
    `resource_type` ENUM('DOCTOR', 'ROOM', 'EQUIPMENT', 'DEVICE') NOT NULL,
    `start_time` DATETIME NOT NULL,
    `end_time` DATETIME NOT NULL,
    `status` ENUM('RESERVED', 'CONFIRMED', 'CANCELLED', 'COMPLETED') NOT NULL DEFAULT 'RESERVED',
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    INDEX `idx_mc_apptres_lookup` (`hospital_code`, `resource_id`, `status`, `start_time`, `end_time`),
    INDEX `idx_mc_apptres_appt` (`hospital_code`, `appointment_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

---

## 3. BACKEND REPOSITORIES & SERVICES

### 1. `ClinicalTemplateRepository`
Located at `medcore_local_service/lib/src/repositories/clinical_template_repository.dart`.
- `createTemplate`: Provisions initial version (Draft v1) with serialized JSON schema.
- `updateTemplateDraft`: Allows in-place mutation strictly if template status is `DRAFT`.
- `createNextVersion`: Clones an existing template into a new Draft incrementing `version` (e.g. `v1 -> v2`).
- `activateTemplate`: Atomically transitions target version to `ACTIVE` and retires any previously active versions of the same `template_code` to `RETIRED`.
- `deactivateTemplate`: Transitions active template to `INACTIVE`.
- `recordTemplateUsage`: Persists complete immutable clinical documentation snapshot in `mc_clinical_template_usages`.

### 2. `SchedulingResourceRepository`
Located at `medcore_local_service/lib/src/repositories/scheduling_resource_repository.dart`.
- `upsertResource`: Manages catalog of doctors, rooms, equipment, and devices.
- `upsertRule`: Manages scheduling rules with duration and prep/cleanup buffer specifications.
- `checkConflicts`: Evaluates prospective interval `[start - bufferBefore, start + duration + bufferAfter]` against existing allocations with status in (`RESERVED`, `CONFIRMED`).
- `allocateResourcesTransaction`: Runs inside an ACID transaction (`START TRANSACTION ... COMMIT`), re-checking conflicting allocations under row locking and inserting allocations for all required resources simultaneously.
- `releaseAllocationsForAppointment`: Marks allocations as `CANCELLED` upon appointment cancellation or rescheduling.

---

## 4. REST API ENDPOINTS

All endpoints are hosted on `medcore_local_service` (`127.0.0.1:8080`) behind `AuthMiddleware`:

| Method | Endpoint | Description | Permissions |
|---|---|---|---|
| `GET` | `/api/v1/clinical/templates` | List clinical templates with optional status filter | Staff / Admin |
| `POST` | `/api/v1/clinical/templates` | Create draft clinical template | Admin / Doctor |
| `GET` | `/api/v1/clinical/templates/active/<number>`| Fetch active template by template number/code | Staff / Doctor |
| `GET` | `/api/v1/clinical/templates/<id>` | Fetch single template by ID | Staff / Admin |
| `PUT` | `/api/v1/clinical/templates/<id>` | Update draft template fields | Admin / Doctor |
| `POST` | `/api/v1/clinical/templates/<id>/version` | Fork template to next version draft | Admin / Doctor |
| `POST` | `/api/v1/clinical/templates/<id>/activate` | Publish version to active | Admin |
| `POST` | `/api/v1/clinical/templates/<id>/deactivate` | Deactivate active template | Admin |
| `POST` | `/api/v1/clinical/templates/usages` | Record clinical encounter usage snapshot | Doctor / Nurse |
| `GET` | `/api/v1/clinical/templates/usages` | List usage records by patient | Doctor / Nurse / Admin |
| `GET` | `/api/v1/scheduling/resources` | List scheduling resources | Staff / Admin |
| `POST` | `/api/v1/scheduling/resources` | Register / update scheduling resource | Admin / Technician |
| `GET` | `/api/v1/scheduling/rules` | List scheduling rules | Staff / Admin |
| `POST` | `/api/v1/scheduling/rules` | Upsert scheduling rule | Admin / Technician |
| `POST` | `/api/v1/scheduling/conflicts/check` | Check multi-resource conflict and buffers | Staff / Admin |
| `POST` | `/api/v1/scheduling/appointments/multi-resource` | Atomic multi-resource slot allocation | Staff / Reception |
| `POST` | `/api/v1/scheduling/appointments/<id>/release` | Release allocations for appointment | Staff / Reception |
| `GET` | `/api/v1/scheduling/appointments/<id>/allocations` | List resource allocations for appointment | Staff / Admin |

---

## 5. DESKTOP USER INTERFACE INTEGRATION

1. **`ClinicalTemplateEditorScreen`** (`medcore_desktop/lib/features/templates/clinical_template_editor_screen.dart`):
   - Sidebar template catalog with live search and status chip filters (`DRAFT`, `ACTIVE`, `RETIRED`).
   - Dynamic schema editor enabling administrators to construct sections, add fields, specify labels, keys, and validation parameters (e.g. required flags, min/max bounds, options).
   - Real-time Interactive Doctor Preview panel: Renders the active form dynamically and tests validation logic before publishing.
   - Version controls: Create Draft, Save Draft, Bump Version (`v2`), and Publish/Activate.

2. **`ResourceSchedulingManagementScreen`** (`medcore_desktop/lib/features/scheduling/resource_scheduling_management_screen.dart`):
   - Multi-tab operational console:
     - **Tab 1: Resources Catalog**: View and register Doctors, Rooms, Equipment, and Devices.
     - **Tab 2: Slot Rules**: Configure appointment rules, durations, and prep/clean buffer minutes.
     - **Tab 3: Conflict & Allocation Simulator**: Live interactive diagnostic tool allowing receptionists and admins to simulate overlapping bookings and verify buffer conflict prevention in real time.

3. **Navigation Catalog & Shell Integration**:
   - Registered under navigation items `clinical_templates` ("Clinical Templates") and `resource_scheduling` ("Multi-Resource Scheduling") in `DesktopNavigationCatalog`.
   - Wired in `MedCoreDesktopShell` with role-aware access controls.

---

## 6. VERIFICATION EVIDENCE & RED TEAM AUDIT

### Backend Integration & Red Team Suite:
- Test File: `medcore_local_service/test/batch13_dynamic_template_and_resource_engine_test.dart`
- Database: Authoritative MariaDB 11.4 on `127.0.0.1:3307`
- Total Tests: **18/18 PASSED (100%)**
- Red Team Gates:
  - `RT-1 (Cross-tenant IDOR attack on templates)`: Attacker from Tenant B attempting to read or activate Tenant A's template was blocked with 404/409.
  - `RT-2 (Cross-tenant resource booking and conflict leakage)`: Attacker booking Tenant A's resources received 404 (Resource not found for tenant), preventing cross-tenant availability reconnaissance.
  - Double-booking race condition test: Concurrent/overlapping booking was rejected with 409 `RESOURCE_CONFLICT`.
  - Buffer window encroachment test: Booking attempted during post-appointment buffer period (10:50 for a 10:00-10:45 + 15 min buffer appointment) was rejected with 409 `RESOURCE_CONFLICT`.

### Desktop Unit & Widget Suite:
- Test File: `medcore_desktop/test/dynamic_template_and_resource_engine_desktop_test.dart`
- Total Tests: **3/3 PASSED (100%)**
- Full Desktop Test Suite: **12/12 PASSED (100%)**

### Static Code Analysis:
- `dart analyze` in `medcore_local_service`: **0 errors, 0 warnings**
- `flutter analyze` in `medcore_desktop`: **0 issues found**

---

## 7. RELEASE INTEGRITY & PRODUCTION CANDIDACY

- **Git Commit**: Clean working tree committed to `origin/main`.
- **v1.0.0-rc.3 Tag**: Immutable and untouched (`713a8a4578cb7f82258b57497afa800346280534`).
- **Release Executable**: Built cleanly via `flutter build windows --release`.
- **Authoritative Persistence**: MariaDB 11.4 verified with direct read-back of serialized template schemas, immutable encounter snapshots, and transactional resource allocations.
