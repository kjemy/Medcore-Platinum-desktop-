# MEDCORE — PROJECT 3 → PROJECT 4 FINAL ARCHITECTURAL & EXTRACTION REPORT
**Document ID**: `DOC-20 (MASTER CAPSTONE)` | **Date**: `2026-10-27`
**Source Repository**: `C:\\Users\\hp\\Desktop\\project 3` (Verified 100% SHA-256 Clone of `project2`)
**Deliverable Workspace**: `C:\\Users\\hp\\Desktop\\project 4`

---

## الملخص التنفيذي بالعربية (Arabic Executive Summary)

تم إنجاز مهمة الاستطلاع المعماري الشامل (Full System Reconnaissance)، واستخراج النواة المنطقية والمالية والسريرية (Core Extraction)، وتحليل الفجوات (Gap Analysis)، وتصميم الأساس المعماري الكامل لمنتج **MedCore Desktop** الجديد داخل المجلد المستهدف `C:\Users\hp\Desktop\project 4`، مع الالتزام الصارم بنسبة **100%** بقواعد الأمان:
1. **عدم المساس مطلقًا بـ `Project 2` أو `Project 3`**: تم أخذ بصمة `SHA-256` لجميع ملفات `Project 3` قبل الفحص (`P3_INTEGRITY_SNAPSHOT_BEFORE.tsv`) وبعد انتهاء الفحص (`P3_INTEGRITY_SNAPSHOT_AFTER.tsv`) — النتيجة: **0 ملفات معدلة، 0 ملفات مضافة، 0 ملفات محذوفة**، وتطابق **100%** بين `Project 2` و `Project 3` عبر **2,138** ملفًا.
2. **عدم كتابة أي كود تطبيقي سابق لأوانه لـ Flutter**: التزمنا بمبدأ **UNDERSTAND FIRST — BUILD SECOND**، وتم استخراج وتوثيق كل قاعدة عمل، وكل جدول، وكل معادلة مالية، وكل صلاحية، وكل ثغرة بدقة مرجعية (`file:line`).
3. **الفصل المعماري الصارم لـ MedCore Desktop**:
   - المعمارية المستهدفة هي: **`Flutter Client (Windows / Android / iPad) → Local MedCore Service (Hospital LAN) → Local MariaDB`** حيث تكون قاعدة بيانات `MariaDB` المحلية هي **مصدر الحقيقة الوحيد (Authoritative Source of Truth)** لجميع البيانات الطبية والمالية والمخزنية.
   - ينحصر دور **WordPress Control Plane** اختياريًا عبر الإنترنت في **التراخيص والاستحقاقات والتجديدات (Signed Ed25519 License Leases)** فقط.
   - تعمل **خلية الذكاء الاصطناعي (AI Cell)** كخدمة اختيارية عبر بوابة سحابية آمنة (Cloud AI Gateway) دون وجود أي مفاتيح مزودين (`Groq` / `Gemini`) داخل تطبيق Flutter أو السيرفر المحلي.

---

## Section 1 — Complete Quantitative Inventory (§25 Completeness Counts — `FACT`)

| # | Completeness Metric (§25) | Verified Count (`FACT`) | Primary Evidence Artifact |
|---|---|---:|---|
| 1 | Total Non-Excluded Files Scanned in `Project 3` | **2,138** (`2,067` text/code + `71` binary) | `99_EVIDENCE/WS7_PARITY_P2_P3.md` |
| 2 | Core Tier Source Files (`CORE_FRONTEND` + `CORE_BACKEND` + `CORE_DB_EXPLORER`) | **603** (`499` FE + `99` BE + `5` DBX) | `99_EVIDENCE/WS7_FILE_INVENTORY.md` |
| 3 | Documentation & Report Markdown Files Audited (`REPORTS/`, `docs/`) | **131** (`76` Reports + `48` FE Docs + `7` BE Docs) | `99_EVIDENCE/WS7_DOCUMENTED_CLAIMS_REGISTER.md` |
| 4 | Secondary Tier Scripts & Archives Audited (`*.py`, `*.js`, `*.php`, `stage_frontend`, `prisma`) | **1,333** | `99_EVIDENCE/WS7_SCRIPTS_AUDIT.md` |
| 5 | Canonical Sidebar Top-Level Navigation Sections | **19** (`6` standalone + `13` expandable) | `Frontend/src/lib/navigationConfig.ts:21-888` |
| 6 | Canonical Sidebar Child Subpages / Total Navigation Nodes | **63** child subpages / **82** total nodes | `99_EVIDENCE/WS6_NAVIGATION_AND_ROUTES.md` |
| 7 | Next.js App Router Pages (`page.tsx`) & Layouts (`layout.tsx`) | **104** pages + **4** layouts | `99_EVIDENCE/WS6_NAVIGATION_AND_ROUTES.md` |
| 8 | Zustand Client State Stores (`Frontend/src/store/*.ts`) | **48** stores | `99_EVIDENCE/WS6_NAVIGATION_AND_ROUTES.md` |
| 9 | Frontend UI Components / Modules / Modals & Forms | **220** components (**42** modules, **70** modals/forms) | `99_EVIDENCE/WS6_FINDINGS.md` |
| 10 | Frontend Permission Keys (`Permission` union type) | **261** keys (`87` base + `87` `_all` + `87` `_secure`) + **4** action flags | `Frontend/src/lib/permissions.ts:19-306` |
| 11 | Roles Defined (`Frontend` vs `Backend`) | **6** UI roles vs **10** Backend roles (`SOURCE CONFLICT` resolved to **10**) | `07_IDENTITY_AND_PERMISSIONS/MEDCORE_PERMISSION_AND_SECURITY_MODEL.md` |
| 12 | Physical SQL Tables with `CREATE TABLE` DDL | **79** tables (`78` `wp_mc_*` + `1` `wp_medcore_staff_directory`) | `99_EVIDENCE/WS1_PHYSICAL_SCHEMA_INVENTORY.md` |
| 13 | Distinct `mc_*` Table Names Referenced in SQL Queries / Orphan Table Refs | **83** referenced / **4** orphans without `CREATE TABLE` | `99_EVIDENCE/WS1_PHYSICAL_SCHEMA_INVENTORY.md` |
| 14 | `ALTER TABLE` Schema Migration Blocks | **12** blocks | `99_EVIDENCE/WS1_PHYSICAL_SCHEMA_INVENTORY.md` |
| 15 | Database Mirror Logical Domains (`medcore-database-explorer`) | **70** domains | `Backend/medcore-database-explorer/api/class-dbx-api-router.php:35-895` |
| 16 | WordPress REST API Route Registrations (`register_rest_route`) | **152** routes (`20` with `__return_true`) | `99_EVIDENCE/WS2_FINDINGS.md` |
| 17 | Next.js Server API Routes (`Frontend/src/app/api/**/route.ts`) | **14** routes | `99_EVIDENCE/WS2_FINDINGS.md` |
| 18 | Authoritative New Tables Designed for `MedCore Desktop` | **6** new tables + `mc_staff_evaluations` DDL = **86** total normalized tables | `04_DATABASE_MODEL/MEDCORE_DATABASE_LOGICAL_MODEL.md` |

---

## Section 2 — Direct Answers to All 22 Acceptance Questions (§32)

### Q1. What is the exact authoritative source of truth for Sidebar Navigation in `Project 3`, and how many sections/subpages exist?
- **Answer (`FACT`)**: `CANONICAL_NAVIGATION_CONFIG` in [`navigationConfig.ts`](file:///C:/Users/hp/Desktop/project%203/Frontend/src/lib/navigationConfig.ts#L21-L888) consumed by [`Sidebar.tsx`](file:///C:/Users/hp/Desktop/project%203/Frontend/src/components/Sidebar.tsx#L240-L452). It defines **19 top-level sections** (6 standalone links + 13 expandable groups) containing **63 child subpages**, totaling **82 canonical navigation nodes** (plus **104** physical `page.tsx` routes in Next.js App Router).

### Q2. How do Roles and Permissions actually work in `Project 3`, and where do Frontend and Backend disagree?
- **Answer (`FACT` + `SOURCE CONFLICT`)**:
  - Frontend [`permissions.ts`](file:///C:/Users/hp/Desktop/project%203/Frontend/src/lib/permissions.ts#L6-L12) defines **6 roles** (`SuperAdmin`, `HospitalAdmin`, `Doctor`, `Nurse`, `Receptionist`, `Employee`), and `normalizeRole()` (`lines 592-618`) collapses `Pharmacist`, `Lab`, `Radiology`, and `Cashier` into `"Employee"`.
  - Backend [`class-medcore-security.php`](file:///C:/Users/hp/Desktop/project%203/Backend/MedCorePlugin/includes/security/class-medcore-security.php#L16-L92) defines **10 distinct roles** and **43 dot-notation permissions**, while Frontend defines **261 permission keys** (`87` base, `87` `_all` data scope, `87` `_secure` desktop lock) + **4 operational action flags** (`canEdit`, `canDelete`, `canCollectMoney`, `canMakeRefunds` + `refundPolicy`).
  - **Critical Flaw (`SEC-FLAW-01`)**: [`PermissionGuard.tsx`](file:///C:/Users/hp/Desktop/project%203/Frontend/src/components/PermissionGuard.tsx#L154-L158) and [`useAuthStore.ts`](file:///C:/Users/hp/Desktop/project%203/Frontend/src/store/useAuthStore.ts#L127-L144) grant wildcard access (`["*", ...ALL_PERMISSIONS]`) to any authenticated user whose `permissionsMode !== "custom"` for all non-administrative pages!

### Q3. How does Page Security (`_secure`) work today, and why is it insecure?
- **Answer (`FACT`)**: Each of the 87 base permissions has a `<perm>_secure` counterpart (`permissions.ts:261-306`). However, [`PermissionGuard.tsx`](file:///C:/Users/hp/Desktop/project%203/Frontend/src/components/PermissionGuard.tsx#L199) checks `window.navigator.userAgent.includes('MedcoreDesktop') || window.__MEDCORE_DESKTOP__ === true`. This is trivially bypassed in any browser via DevTools and has zero backend enforcement.

### Q4. How does Authentication work in `Project 3`, and is the session token bound to a tenant or device?
- **Answer (`FACT`)**: [`MedCore_Auth_Service::login`](file:///C:/Users/hp/Desktop/project%203/Backend/MedCorePlugin/includes/domain/staff/class-auth-service.php#L59-L60) generates a 64-character token stored in a WordPress transient (`mc_token_<md5>`) whose value is **only `$target_email`**. It is **not bound to `hospital_code` or `device_id`** (`SEC-FLAW-03`).

### Q5. What is the exact Monetary Equation enforced on Visits and Invoices?
- **Answer (`FACT`)**: Enforced in [`class-medcore-financial-transaction-service.php`](file:///C:/Users/hp/Desktop/project%203/Backend/MedCorePlugin/includes/core/class-medcore-financial-transaction-service.php#L91-L122):
  `Net = Gross - Discount`; `PatientResponsibility = Net - InsuranceCovered`; `Balance = PatientResponsibility - Paid`; with strict identity `abs((Discount + Paid + InsuranceCovered + Balance) - Gross) <= 0.0001`.

### Q6. How are Financial Events and Postings structured in the database?
- **Answer (`FACT`)**: Two-table sub-ledger: `wp_mc_financial_events` (immutable header with `event_uuid`, `idempotency_key`, monetary summary, commission snapshot, `reversal_of_event_id`) and `wp_mc_financial_postings` (multi-leg `DEBIT`/`CREDIT` entries across `REVENUE_OPERATING`, `CONTRA_REVENUE_DISCOUNT`, `CASH_ON_HAND`, `ACCOUNTS_RECEIVABLE_PATIENT`, `ACCOUNTS_RECEIVABLE_INSURANCE`, `PAYABLE_COMMISSION_DOCTOR`).

### Q7. How does the Doctor Commission Engine work in `Project 3`?
- **Answer (`FACT`)**: [`MedCore_Commission_Engine::resolve_commission`](file:///C:/Users/hp/Desktop/project%203/Backend/MedCorePlugin/includes/core/class-medcore-commission-engine.php#L24-L321) implements a 2-tier resolver: Tier 1 queries `wp_mc_definition_rules` (`rule_type='COMMISSION'`, specificity scoring + precedence + parent rule inheritance + `cap`/`floor`); Tier 2 falls back to the doctor's `data_json` in `wp_mc_definitions`.

### Q8. Does `Project 3` separate Service/Labor Fees from Consumable/Material Costs before calculating Doctor Commissions?
- **Answer (`FACT` — CRITICAL GAP `FIN-GAP-01`)**: **NO.** `post_visit_transaction` (`line 424`) calculates commission on the entire visit `$net`. Even though [`MedCore_Inventory_Consumption::consume_for_service`](file:///C:/Users/hp/Desktop/project%203/Backend/MedCorePlugin/includes/core/class-medcore-inventory-consumption.php#L5-L51) exists to deduct FIFO stock batches, it is **never called** during visit creation. `DOC-05` and `DOC-06` design the complete `mc_visit_item_cost_lines` + FIFO cost-split solution for `MedCore Desktop`.

### Q9. Are there any accounting bugs in Commission Settlement Payouts or Currency handling?
- **Answer (`FACT`)**: **YES, two critical bugs**:
  1. **Double-Debit Bug (`FIN-BUG-01`)**: [`class-api-financial-settlement.php`](file:///C:/Users/hp/Desktop/project%203/Backend/MedCorePlugin/includes/api/class-api-financial-settlement.php#L104-L106) (and `lines 369, 398`) inserts both `SETTLE-BEN-*` (Payable reduction) and `SETTLE-TR-*` (Treasury cash outflow) with `'direction' => 'DEBIT'`.
  2. **Currency Conflict (`FIN-BUG-02`)**: `post_visit_transaction` (`line 125`) defaults currency to `'SAR'`, whereas `reverse_visit_transaction` (`line 1109`) and `adjust_visit_transaction` (`lines 1432-1504`) hardcode `'EGP'`.

### Q10. How do Cashier Shifts work, and can money be collected without an open shift?
- **Answer (`FACT`)**: [`MedCore_Shift_Service`](file:///C:/Users/hp/Desktop/project%203/Backend/MedCorePlugin/includes/core/class-medcore-shift-service.php#L110-L165) enforces at most one `OPEN` shift per cashier and blocks any visit payment (`$paid > 0`) or refund unless an active `OPEN` shift exists (`require_open_shift` called at `class-medcore-visit-service.php:225`).

### Q11. What happens atomically when a Visit is created (`MedCore_Visit_Service::create_visit`)?
- **Answer (`FACT`)**: A 12-step MySQL transaction (`START TRANSACTION .. COMMIT` in `class-medcore-visit-service.php:130-690`): verifies idempotency, requires open shift, locks patient & appointment (`FOR UPDATE`), validates monetary equation, inserts `wp_mc_visits` and `wp_mc_visit_items`, spawns `wp_mc_orders` (`LAB`/`RAD`), posts `wp_mc_financial_events` + `wp_mc_financial_postings` + commission accrual, syncs `wp_mc_invoices`/`wp_mc_payments`, and writes `wp_mc_audit_logs`.

### Q12. What prevents a Visit from being cancelled after clinical services are performed?
- **Answer (`FACT`)**: `MedCore_Visit_Service::cancel_visit` (`lines 750-830`) inspects downstream `wp_mc_orders`, `wp_mc_lab_results`, `wp_mc_radiology_reports`, and `wp_mc_pharmacy_dispenses`. If clinical execution has occurred, full cancellation is blocked.

### Q13. How does Inventory & Pharmacy Stock tracking work?
- **Answer (`FACT`)**: Master items live in `wp_mc_inventory_items`, while actual batch quantities, expiry dates, and unit costs live in `wp_mc_inventory_StockBatch`, with all mutations logged in `wp_mc_inventory_StockMovement` and supplier receipts in `wp_mc_inventory_PurchaseReceipt` / `wp_mc_inventory_SupplierReturn`.

### Q14. What is the real state of Offline Mode in `Project 3`?
- **Answer (`FACT`)**: [`offlineSync.ts`](file:///C:/Users/hp/Desktop/project%203/Frontend/src/lib/offlineSync.ts#L24) (`OFFLINE_ALLOWED_COMMANDS = new Set(['patient:create'])`) and [`class-api-sync.php`](file:///C:/Users/hp/Desktop/project%203/Backend/MedCorePlugin/includes/api/class-api-sync.php#L91) support **ONLY `patient:create`**. All other 99% of hospital workflows are online-only in `Project 3`.

### Q15. What is the real state of Desktop & Device Verification endpoints in `Project 3`?
- **Answer (`FACT`)**: [`class-api-desktop.php`](file:///C:/Users/hp/Desktop/project%203/Backend/MedCorePlugin/includes/api/class-api-desktop.php#L28-L48) is a stub: `/desktop-version` and `/tutorials` return placeholder strings, and `/verify-device` is unauthenticated (`__return_true`) and unconditionally returns `'verified' => true`.

### Q16. What is the real state of Licensing & SaaS endpoints in `Project 3`?
- **Answer (`FACT`)**: In [`class-api-saas.php`](file:///C:/Users/hp/Desktop/project%203/Backend/MedCorePlugin/includes/api/class-api-saas.php#L54-L227), 6 checkout/catalog routes are stubs, and `/wp-json/mce/v1/license` is unauthenticated, includes a hardcoded host bypass (`lines 134-137`), and returns unsigned JSON.

### Q17. How does the AI Cell work in `Project 3`, and where are the API keys stored/exposed?
- **Answer (`FACT` — CRITICAL FLAW `SEC-FLAW-04`)**: [`class-api-ai.php`](file:///C:/Users/hp/Desktop/project%203/Backend/MedCorePlugin/includes/api/class-api-ai.php#L6-L18) exposes `GET /wp-json/medcore-ai/v1/keys` with `permission_callback => '__return_true'`, returning raw Groq and Gemini master API keys to any caller sending `X-MedCore-Server-Action: fetch-ai-keys`! And Next.js routes `ai-doctor/route.ts` and `admin-ai/route.ts` have no user authentication or pre-call quota enforcement.

### Q18. What database constraints or table anomalies exist in `Project 3`?
- **Answer (`FACT`)**:
  - **0 Foreign Keys** across all 79 `CREATE TABLE` definitions.
  - **4 Orphan Table References** queried in PHP without `CREATE TABLE` DDL (`mc_expenses`, `mc_lab_orders`, `mc_radiology_orders`, `mc_staff_evaluations` in `class-api-hr.php:209`).
  - **5 Mixed-Case Table Names** (`mc_inventory_StockBatch`, `mc_inventory_StockMovement`, `mc_inventory_PurchaseReceipt`, `mc_inventory_SupplierReturn`, `mc_DualControlRequest`) that cause Windows vs Linux MariaDB case-sensitivity hazards.

### Q19. How will `MedCore Desktop` operate Offline over a Hospital LAN without routing clinical/financial data through WordPress?
- **Answer (`Blueprint DOC-10`)**: `Flutter Client (Windows / Android / iPad) <--> Local MedCore Service (Hospital Server on LAN HTTPS/WebSocket) <--> Local MariaDB (Authoritative ACID Source of Truth)`. WordPress is contacted optionally over the internet **solely** as a Control Plane for Ed25519-signed license leases and entitlements.

### Q20. How will `MedCore Desktop` prevent Clock Rollback, Unauthorized Devices, and Screen Capture?
- **Answer (`Blueprint DOC-09`)**:
  - **Clock Guard (`mc_clock_guard`)**: 4-source monotonic high-water mark (`max_observed_utc`, max ledger timestamp across `mc_financial_events`/`mc_visits`/`mc_audit_logs`, OS monotonic tick counter, and signed network timestamps). Rollback > 5 minutes locks mutations (`TAMPER_LOCKED`).
  - **Device Binding (`mc_devices`)**: Hardware fingerprint (`SMBIOS UUID` / `Android Keystore` / `iOS Secure Enclave`) + per-device Ed25519 request signing.
  - **Screen Protection (`_secure`)**: Native Win32 `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)`, Android `FLAG_SECURE`, and iPadOS secure layer + `UIScreen.isCaptured` shield + forensic watermark.

### Q21. How will the Technician Service Tool diagnose offline hospitals without leaking Patient PII?
- **Answer (`Blueprint DOC-12`)**: Standalone `medcore-service-tool` authorized via Ed25519 challenge-response maintenance tokens, generating Dual Outputs: **Output A (`Executive Report` PDF/HTML)** for hospital management and **Output B (`Engineering Bundle` `.mcdiag`)** scrubbed by a deterministic **PII Privacy Filter** that hashes/strips all patient names, phones, national IDs, clinical narratives, and secrets.

### Q22. Were any files in `Project 2` or `Project 3` modified during this reconnaissance?
- **Answer (`FACT`)**: **ZERO.** Verified by comparing `P3_INTEGRITY_SNAPSHOT_BEFORE.tsv` and `P3_INTEGRITY_SNAPSHOT_AFTER.tsv` across all **2,138** files.

---

## Section 3 — Complete Deliverable Map in `C:\\Users\\hp\\Desktop\\project 4`

| Folder / Root Deliverable | Document Path in `Project 4` | Status |
|---|---|---|
| `00_EXECUTIVE_SUMMARY` | [`MEDCORE_PROJECT3_RECONNAISSANCE_REPORT.md`](file:///C:/Users/hp/Desktop/project%204/00_EXECUTIVE_SUMMARY/MEDCORE_PROJECT3_RECONNAISSANCE_REPORT.md) | COMPLETE |
| `00_EXECUTIVE_SUMMARY` | [`MEDCORE_PROJECT3_TO_PROJECT4_FINAL_REPORT.md`](file:///C:/Users/hp/Desktop/project%204/00_EXECUTIVE_SUMMARY/MEDCORE_PROJECT3_TO_PROJECT4_FINAL_REPORT.md) | COMPLETE |
| `01_CORE_EXTRACTION` | [`MEDCORE_CORE_EXTRACTION_SPEC.md`](file:///C:/Users/hp/Desktop/project%204/01_CORE_EXTRACTION/MEDCORE_CORE_EXTRACTION_SPEC.md) | COMPLETE |
| `02_DOMAIN_MODEL` | [`MEDCORE_DOMAIN_MODEL.md`](file:///C:/Users/hp/Desktop/project%204/02_DOMAIN_MODEL/MEDCORE_DOMAIN_MODEL.md) | COMPLETE |
| `03_BUSINESS_RULES` | [`MEDCORE_BUSINESS_RULES_CATALOG.md`](file:///C:/Users/hp/Desktop/project%204/03_BUSINESS_RULES/MEDCORE_BUSINESS_RULES_CATALOG.md) | COMPLETE |
| `04_DATABASE_MODEL` | [`MEDCORE_DATABASE_LOGICAL_MODEL.md`](file:///C:/Users/hp/Desktop/project%204/04_DATABASE_MODEL/MEDCORE_DATABASE_LOGICAL_MODEL.md) | COMPLETE |
| `05_FINANCIAL_CORE` | [`MEDCORE_FINANCIAL_CORE.md`](file:///C:/Users/hp/Desktop/project%204/05_FINANCIAL_CORE/MEDCORE_FINANCIAL_CORE.md) | COMPLETE |
| `06_CLINICAL_CORE` | [`MEDCORE_CLINICAL_CORE.md`](file:///C:/Users/hp/Desktop/project%204/06_CLINICAL_CORE/MEDCORE_CLINICAL_CORE.md) | COMPLETE |
| `07_IDENTITY_AND_PERMISSIONS` | [`MEDCORE_PERMISSION_AND_SECURITY_MODEL.md`](file:///C:/Users/hp/Desktop/project%204/07_IDENTITY_AND_PERMISSIONS/MEDCORE_PERMISSION_AND_SECURITY_MODEL.md) | COMPLETE |
| `08_SECURITY` | [`MEDCORE_SECURITY_MODEL.md`](file:///C:/Users/hp/Desktop/project%204/08_SECURITY/MEDCORE_SECURITY_MODEL.md) | COMPLETE |
| `09_LICENSE_AND_ENTITLEMENTS` | [`MEDCORE_LICENSE_DEVICE_SECURITY_BLUEPRINT.md`](file:///C:/Users/hp/Desktop/project%204/09_LICENSE_AND_ENTITLEMENTS/MEDCORE_LICENSE_DEVICE_SECURITY_BLUEPRINT.md) | COMPLETE |
| `10_OFFLINE_ARCHITECTURE` | [`MEDCORE_OFFLINE_GAP_ANALYSIS.md`](file:///C:/Users/hp/Desktop/project%204/10_OFFLINE_ARCHITECTURE/MEDCORE_OFFLINE_GAP_ANALYSIS.md) | COMPLETE |
| `11_FLUTTER_ARCHITECTURE` | [`MEDCORE_FLUTTER_ARCHITECTURE_BLUEPRINT.md`](file:///C:/Users/hp/Desktop/project%204/11_FLUTTER_ARCHITECTURE/MEDCORE_FLUTTER_ARCHITECTURE_BLUEPRINT.md) | COMPLETE |
| `12_LAN_ARCHITECTURE` | [`MEDCORE_LAN_ARCHITECTURE_BLUEPRINT.md`](file:///C:/Users/hp/Desktop/project%204/12_LAN_ARCHITECTURE/MEDCORE_LAN_ARCHITECTURE_BLUEPRINT.md) | COMPLETE |
| `13_SERVICE_TOOL` | [`MEDCORE_TECHNICIAN_SERVICE_TOOL_BLUEPRINT.md`](file:///C:/Users/hp/Desktop/project%204/13_SERVICE_TOOL/MEDCORE_TECHNICIAN_SERVICE_TOOL_BLUEPRINT.md) | COMPLETE |
| `14_AI_CELL` | [`MEDCORE_AI_CELL_BLUEPRINT.md`](file:///C:/Users/hp/Desktop/project%204/14_AI_CELL/MEDCORE_AI_CELL_BLUEPRINT.md) | COMPLETE |
| `15_UI_UX_EXTRACTION` | [`MEDCORE_UI_UX_EXTRACTION.md`](file:///C:/Users/hp/Desktop/project%204/15_UI_UX_EXTRACTION/MEDCORE_UI_UX_EXTRACTION.md) | COMPLETE |
| `16_WEB_SPECIFIC` | [`MEDCORE_WEB_SPECIFIC_INVENTORY.md`](file:///C:/Users/hp/Desktop/project%204/16_WEB_SPECIFIC/MEDCORE_WEB_SPECIFIC_INVENTORY.md) | COMPLETE |
| `17_BACKEND_SPECIFIC` | [`MEDCORE_BACKEND_SPECIFIC_INVENTORY.md`](file:///C:/Users/hp/Desktop/project%204/17_BACKEND_SPECIFIC/MEDCORE_BACKEND_SPECIFIC_INVENTORY.md) | COMPLETE |
| `18_GAPS_AND_MISSING` | [`MEDCORE_MISSING_CAPABILITIES.md`](file:///C:/Users/hp/Desktop/project%204/18_GAPS_AND_MISSING/MEDCORE_MISSING_CAPABILITIES.md) | COMPLETE |
| `19_RISKS_AND_UNKNOWN` | [`MEDCORE_RISKS_UNKNOWN_ASSUMPTIONS.md`](file:///C:/Users/hp/Desktop/project%204/19_RISKS_AND_UNKNOWN/MEDCORE_RISKS_UNKNOWN_ASSUMPTIONS.md) | COMPLETE |
| `20_MIGRATION` | [`MEDCORE_CORE_TRACEABILITY_MATRIX.md`](file:///C:/Users/hp/Desktop/project%204/20_MIGRATION/MEDCORE_CORE_TRACEABILITY_MATRIX.md) | COMPLETE |
| `21_IMPLEMENTATION_ROADMAP` | [`MEDCORE_PROJECT4_IMPLEMENTATION_ROADMAP.md`](file:///C:/Users/hp/Desktop/project%204/21_IMPLEMENTATION_ROADMAP/MEDCORE_PROJECT4_IMPLEMENTATION_ROADMAP.md) | COMPLETE |
| `99_EVIDENCE` | [`00_RECON_CONVENTIONS.md`](file:///C:/Users/hp/Desktop/project%204/99_EVIDENCE/00_RECON_CONVENTIONS.md) & `WS1`–`WS7` Evidence Files | COMPLETE |
