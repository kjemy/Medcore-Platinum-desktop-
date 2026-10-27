# WS1 — Database & Persistence Findings (`Project 3`)

> **Classification**: `FACT` (Code-Verified)

## 1. Zero Foreign Key Constraints in MySQL/MariaDB (`FACT`)
- Across all **79** `CREATE TABLE` definitions in `Backend/MedCorePlugin/medcore.php` and domain classes, there are **0 `FOREIGN KEY ... REFERENCES` constraints** (`dbDelta()` limitation in WordPress).
- All referential integrity is enforced (or left unenforced) in PHP application code (`MedCore_Visit_Service`, `MedCore_Financial_Transaction_Service`, etc.).
- **Impact on MedCore Desktop (`Category H / B`)**: Local MariaDB in `MedCore Desktop` is not constrained by WordPress `dbDelta()`. All core parent-child relationships (`mc_visits -> mc_patients`, `mc_visit_items -> mc_visits`, `mc_financial_postings -> mc_financial_events`, `mc_lab_results -> mc_orders`, `mc_inventory_StockBatch -> mc_inventory_items`) MUST have explicit `InnoDB` foreign keys and `ON DELETE RESTRICT` rules on financial/clinical ledgers.

## 2. Mixed Case & Naming Conventions (`FACT`)
- 74 tables use lowercase snake_case (`wp_mc_patients`, `wp_mc_visits`, `wp_mc_financial_events`), while 4 tables use mixed PascalCase suffixes:
  - `wp_mc_inventory_StockBatch` (`Backend/MedCorePlugin/medcore.php:764`)
  - `wp_mc_inventory_StockMovement` (`Backend/MedCorePlugin/medcore.php:782`)
  - `wp_mc_inventory_PurchaseReceipt` (`Backend/MedCorePlugin/medcore.php:800`)
  - `wp_mc_inventory_SupplierReturn` (`Backend/MedCorePlugin/medcore.php:816`)
- **Cross-Platform Risk (`Windows vs Linux MariaDB`)**: On Windows (`lower_case_table_names=1`), MySQL/MariaDB folds table names to lowercase on disk, whereas Linux (`lower_case_table_names=0`) treats `mc_inventory_StockBatch` and `mc_inventory_stockbatch` as distinct tables. `MedCore Desktop` on Windows MUST standardize all table identifiers to lowercase `snake_case`.

## 3. Dual-Table / Shadow-State Architecture (`wp_mc_definitions` vs Specialized Tables) (`FACT`)
- `wp_mc_definitions` (`Backend/MedCorePlugin/medcore.php:401`) stores polymorphic JSON configurations (`type`, `code`, `name`, `data_json`) for `doctor`, `clinic`, `department`, `service`, `lab_test`, `rad_test`, `surgery_package`, `ward`, `room`, `bed`, `insurance_company`, `supplier`, `warehouse`, `shift_policy`, `hospital_settings`.
- Simultaneously, specialized relational tables exist for several of these entities (`wp_mc_beds`, `wp_mc_inventory_items`, `wp_mc_staff`, `wp_mc_definition_rules`).
- In `MedCore_Commission_Engine::resolve_commission` (`Backend/MedCorePlugin/includes/core/class-medcore-commission-engine.php:24-321`), Tier 1 queries `wp_mc_definition_rules`, while Tier 2 parses `data_json` inside `wp_mc_definitions`.

## 4. WordPress Storage Coupling (`wp_options`, `wp_usermeta`, Transients) (`FACT`)
- **Auth Tokens**: Stored in WordPress transients `mc_token_<md5>` (`Backend/MedCorePlugin/includes/domain/staff/class-auth-service.php:60`) backed by `wp_options`.
- **SaaS Plans & Gateway Settings**: Stored in `wp_options` (`medcore_saas_plans`, `medcore_payment_settings`, `medcore_ai_settings`) (`Backend/MedCorePlugin/includes/api/class-api-saas-extended.php:120-210`, `class-api-ai-extra.php:35`).
- **Schema Migration Flag**: Stored in `wp_options` (`medcore_db_version`) (`Backend/MedCorePlugin/medcore.php:152`).
- **Desktop Replacement**: Replace all `wp_options` and transient usage with local MariaDB tables: `mc_local_meta`, `mc_auth_sessions`, `mc_license_state`, `mc_devices`, `mc_clock_guard`.
