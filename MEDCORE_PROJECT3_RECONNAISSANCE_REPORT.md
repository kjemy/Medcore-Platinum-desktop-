# MEDCORE — PROJECT 3 FULL SYSTEM RECONNAISSANCE REPORT
**Document ID**: `DOC-01` | **Source**: `C:\Users\hp\Desktop\project 3` (Read-Only Reference Clone of `project2`)
**Target Workspace**: `C:\Users\hp\Desktop\project 4` | **Mode**: Static Reverse-Engineering Reconnaissance (`00_RECON_CONVENTIONS.md`)

---

## 1. Executive Summary (ملخص تنفيذي)
تم إجراء فحص معماري ساكن وشامل (100% Static Code & Schema Reconnaissance) لنسخة المرجع `Project 3` دون لمس أو تعديل أي ملف في `Project 2` أو `Project 3` (تم التحقق عبر بصمات `SHA-256` لجميع الملفات البالغ عددها **2,138** ملفًا).

### الحقائق الرقمية المستخرجة من الكود الفعلي (`FACT`):
| المقياس (Metric) | العدد الفعلي (`FACT`) | المصدر المرجعي في الكود |
|---|---|---|
| إجمالي الملفات المفحوصة في `Project 3` | **2,138** (`2,067` نصي/كود + `71` ثنائي) | `99_EVIDENCE/WS7_PARITY_P2_P3.md` |
| تطابق `SHA-256` بين `Project 2` و `Project 3` | **100%** (`0` اختلاف) | `99_EVIDENCE/WS7_PARITY_P2_P3.md` |
| ملفات الكود الأساسية (`Core Tier`) | **603** (`499` Frontend + `99` Backend + `5` DB Mirror) | `99_EVIDENCE/WS7_FILE_INVENTORY.md` |
| صفحات `Next.js App Router` (`page.tsx`) | **104** صفحة + **4** Layouts | `Frontend/src/app/**/page.tsx` |
| عناصر شجرة التنقل الجانبية (`Sidebar Navigation`) | **19** قسمًا رئيسيًا + **63** صفحة فرعية = **82** عقدة تنقل | `Frontend/src/lib/navigationConfig.ts:21-888` |
| مخازن الحالة (`Zustand Stores`) | **48** Store | `Frontend/src/store/*.ts` |
| المكونات والنوافذ والنماذج (`UI Components & Modals`) | **220** مكونًا (منها **70** Modal/Form و **42** Module) | `Frontend/src/components/**/*.tsx` |
| مفاتيح الصلاحيات في الواجهة (`UI Permission Keys`) | **261** مفتاحًا (`87` أساسي + `87` `_all` + `87` `_secure`) + **4** أعلام إجرائية | `Frontend/src/lib/permissions.ts:19-306` |
| الأدوار الوظيفية (`Roles`) | **6** في الواجهة مقابل **10** في الباك إند (`SOURCE CONFLICT`) | `permissions.ts:6` vs `class-medcore-security.php:16` |
| جداول قاعدة البيانات المعرفة (`CREATE TABLE`) | **79** جدولًا (`78` `wp_mc_*` + `1` `wp_medcore_staff_directory`) | `Backend/MedCorePlugin/medcore.php` + `includes/**` |
| جداول مذكورة في الاستعلامات بدون `CREATE TABLE` | **4** جداول يتيمة (`mc_expenses`, `mc_lab_orders`, `mc_radiology_orders`, `mc_staff_evaluations`) | `99_EVIDENCE/WS1_PHYSICAL_SCHEMA_INVENTORY.md` |
| نطاقات مرآة قاعدة البيانات (`DB Mirror Domains`) | **70** نطاقًا في `medcore-database-explorer` | `Backend/medcore-database-explorer/api/class-dbx-api-router.php:35-895` |
| مسارات `WordPress REST API` (`register_rest_route`) | **152** مسارًا عبر 5 نطاقات (`20` منها `__return_true`) | `99_EVIDENCE/WS2_FINDINGS.md` |
| مسارات `Next.js API Routes` (`app/api/**/route.ts`) | **14** مسارًا | `Frontend/src/app/api/**/route.ts` |

---

## 2. Current System Architecture (`Project 3` Reality)
1. **Frontend Runtime (`Category F`)**:
   - Built on **Next.js 14 App Router** (`React 18`, `TypeScript`, `TailwindCSS`, `Zustand`, `next-intl` with Arabic RTL primary + English).
   - Relies heavily on browser `localStorage` (`tenantStorage` wrapper in `Frontend/src/lib/tenantStorage.ts`) across **48 Zustand stores** and **92 `localStorage`/`sessionStorage` call sites**, creating dual-source-of-truth hazards against the MySQL backend.
2. **Backend Runtime (`Category G` + `Category A/D/E` Domain Services)**:
   - Implemented as a monolithic WordPress plugin (`Backend/MedCorePlugin/medcore.php`, version `3.1.0-test-20261017`) plus an admin database viewer plugin (`Backend/medcore-database-explorer`).
   - While the transport layer (`WP_REST_Server`, `wp_options`, WordPress transients) is web/WordPress-specific (`Category G`), **the authoritative financial, commission, shift, visit, admissions, surgery, dialysis, and ICU/NICU business rules (`Categories A, D, E`) live inside PHP domain services** under `Backend/MedCorePlugin/includes/core/` and `includes/domain/`.
3. **Database Layer (`Category B`)**:
   - MySQL/MariaDB tables created via WordPress `dbDelta()` in `medcore.php`.
   - **Zero `FOREIGN KEY` constraints** exist at the SQL DDL level due to `dbDelta()` limitations; all relational integrity is manual in PHP.
   - Multi-tenancy is logical (`hospital_code` column on 74 of 79 tables).

---

## 3. Top 10 Critical Findings & Architectural Risks (`FACT`)
1. **CRITICAL RBAC BYPASS (`SEC-FLAW-01`)**: `Frontend/src/components/PermissionGuard.tsx:154-158` and `useAuthStore.ts:127,144` grant full access (`["*", ...ALL_PERMISSIONS]`) to any authenticated user whose `permissionsMode !== "custom"` for all non-administrative pages!
2. **CRITICAL AI MASTER KEY EXPOSURE (`SEC-FLAW-04`)**: `Backend/MedCorePlugin/includes/api/class-api-ai.php:6-18` (`GET /wp-json/medcore-ai/v1/keys`) has `permission_callback => '__return_true'` and returns raw Groq and Gemini master API keys whenever the static header `X-MedCore-Server-Action: fetch-ai-keys` is sent.
3. **CRITICAL DEVICE VERIFICATION STUB (`SEC-FLAW-05`)**: `Backend/MedCorePlugin/includes/api/class-api-desktop.php:40-48` (`POST /wp-json/medcore/v1/verify-device`) is unauthenticated and unconditionally returns `verified: true` without checking `wp_mc_security_devices`.
4. **CRITICAL TENANT-UNBOUND AUTH TOKEN (`SEC-FLAW-03`)**: `MedCore_Auth_Service::login` (`class-auth-service.php:59-60`) stores only `$target_email` in `mc_token_<md5>` transient, not binding the session token to `hospital_code`, `staff_id`, or `device_id`.
5. **CRITICAL SPOOFABLE `_secure` DESKTOP GUARD (`SEC-FLAW-02`)**: `PermissionGuard.tsx:199` checks `navigator.userAgent.includes('MedcoreDesktop')`, which is trivially spoofable in any browser and has zero backend enforcement.
6. **CRITICAL FINANCIAL GAP — NO SERVICE VS CONSUMABLE SPLIT (`FIN-GAP-01`)**: `MedCore_Financial_Transaction_Service::post_visit_transaction` (`class-medcore-financial-transaction-service.php:424-438`) calculates doctor commissions on total visit `$net` without deducting consumable/material costs, and `MedCore_Inventory_Consumption::consume_for_service` (`class-medcore-inventory-consumption.php:5-51`) is never invoked during visit creation.
7. **CRITICAL ACCOUNTING BUG — SETTLEMENT DOUBLE-DEBIT (`FIN-BUG-01`)**: `MCE_API_Financial_Settlement::receive` (`class-api-financial-settlement.php:104-106`) and `execute_direct_payout` (`lines 369, 398`) post BOTH the Beneficiary payable reduction (`SETTLE-BEN-*`) AND the Treasury cash outflow (`SETTLE-TR-*`) as `'direction' => 'DEBIT'`, breaking double-entry trial balance invariant (`SUM(DEBIT) == SUM(CREDIT)`).
8. **CURRENCY HARDCODING CONFLICT (`FIN-BUG-02`)**: `post_visit_transaction` (`line 125`) defaults currency to `'SAR'`, whereas `reverse_visit_transaction` (`line 1109`) and `adjust_visit_transaction` (`lines 1432-1504`) hardcode `'EGP'`.
9. **OFFLINE SYNC IS 99% MISSING (`OFF-GAP-01`)**: `Frontend/src/lib/offlineSync.ts:24` (`OFFLINE_ALLOWED_COMMANDS = new Set(['patient:create'])`) and `class-api-sync.php:91` support ONLY `patient:create`. All clinical, financial, shift, lab, radiology, pharmacy, and inpatient mutations fail offline.
10. **HARDCODED SERVER CREDENTIALS IN REPO (`SEC-FLAW-06`)**: Plaintext deployment/test credentials exist in `Frontend/deploy.js:33` (`[REDACTED]`) and `verify_medcore_e2e_lifecycle.py:235` (`[REDACTED]`).

---

## 4. Complete A–J Taxonomy Classification Summary
Every component in `Project 3` has been classified into Categories **A through J** in `01_CORE_EXTRACTION/MEDCORE_CORE_EXTRACTION_SPEC.md`:
- **Category A (Core Business Logic)**: Monetary identity equations, 12-step atomic visit pipeline, 2-tier commission resolution, shift open/close reconciliation, FIFO batch cost engine, lab/rad/dialysis/admission state machines.
- **Category B (Domain Model)**: 79 physical tables consolidated into 12 bounded domain contexts (`Logical Data Model`) + 6 new offline/desktop tables (`mc_local_meta`, `mc_devices`, `mc_license_state`, `mc_clock_guard`, `mc_backup_runs`, `mc_visit_item_cost_lines`).
- **Category C (Security / Authorization)**: Unified 10-role RBAC + 87 resource scopes (`base`, `_all`, `_secure`) + 4 operational flags (`canDelete`, `canEdit`, `canCollectMoney`, `canMakeRefunds` + `refundPolicy`).
- **Category D (Financial Logic)**: Event/Posting double-entry ledger, commission engine (upgraded with mandatory Service/Labor vs Consumable/Material split), shift & treasury handover, insurance AR claims, settlement payouts.
- **Category E (Clinical Logic)**: Patient MPI, Appointments, Outpatient Visits, EMR/EHR, Lab, Radiology, Pharmacy/Inventory, Admissions/Beds, ICU/NICU, Surgery, Dialysis.
- **Category F (Web-Specific — DO NOT PORT)**: Next.js App Router, React DOM components, `localStorage` Zustand persistence, `/api/*` CORS proxy routes, User-Agent spoofing checks.
- **Category G (Backend-Specific — DO NOT PORT AS RUNTIME)**: WordPress plugin hooks, `dbDelta()`, `wp_options`, transients, Hostinger deployment scripts. (WordPress remains ONLY as an optional online Control Plane for licensing/entitlements).
- **Category H (Offline Gap)**: Local MedCore Service + Local MariaDB as primary source of truth over Hospital LAN.
- **Category I (Missing Capability)**: Ed25519 Signed License Engine, Hardware Fingerprint Binding, 4-Source Anti-Clock-Rollback Guard, Native OS Screen Capture Protection (`WDA_EXCLUDEFROMCAPTURE` / `FLAG_SECURE` / `isCaptured`), Service vs Consumable Cost Split, Technician Service Tool (`Executive Report` + `Engineering Bundle` + `PII Privacy Filter`).
- **Category J (Unknown / Needs Decision)**: Documented in `19_RISKS_AND_UNKNOWN/MEDCORE_RISKS_UNKNOWN_ASSUMPTIONS.md` without turning any unknown into a silent assumption.
