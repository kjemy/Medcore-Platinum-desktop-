# WS3 — Financial Core Rules & Accounting Findings (`Project 3`)

> **Classification**: `FACT` — Extracted from `Backend/MedCorePlugin/includes/core/class-medcore-financial-transaction-service.php` (1,656 lines), `class-medcore-commission-engine.php` (413 lines), `class-medcore-shift-service.php` (551 lines), `class-medcore-accounting-service.php` (113 lines), `class-medcore-inventory-cost-engine.php` (23 lines), `class-medcore-inventory-consumption.php` (52 lines), and `includes/api/class-api-financial-settlement.php` (457 lines).

## 1. Authoritative Monetary Identity (`FIN-001` — `FACT`)
- **Source**: `MedCore_Financial_Transaction_Service::validate_and_normalize_visit_financials` (`class-medcore-financial-transaction-service.php:91-122`) and `MedCore_Visit_Service::create_visit` (`class-medcore-visit-service.php:314-347`).
- **Equations**:
  - `Gross = SUM(item.unit_price * item.quantity)` (`Gross >= 0`)
  - `Net = Gross - Discount` (`0 <= Discount <= Gross`)
  - `PatientResponsibility = Net - InsuranceCovered` (`0 <= InsuranceCovered <= Net`)
  - `Balance = PatientResponsibility - Paid` (`0 <= Paid <= PatientResponsibility`)
  - **Strict Identity Check**: `abs((Discount + Paid + InsuranceCovered + Balance) - Gross) <= 0.0001` (`WP_Error('financial_equation_mismatch')` thrown on violation).
- **Precision**: Stored as `DECIMAL(14,4)` in `wp_mc_financial_events` and `wp_mc_financial_postings`, and `DECIMAL(12,2)` in `wp_mc_visits` and `wp_mc_visit_items`.

## 2. Sub-Ledger Event & Posting Architecture (`FIN-002` — `FACT`)
- **Event Table (`wp_mc_financial_events`)**: Immutable event log (`event_uuid` UNIQUE, `idempotency_key` UNIQUE per hospital, `event_type`, `source_module`, `source_entity_type`, `source_entity_id`, `shift_id`, `gross_amount`, `discount_amount`, `net_amount`, `paid_amount`, `insurance_covered_amount`, `patient_responsibility_amount`, `balance_amount`, `commission_basis_type`, `commission_basis_amount`, `commission_rate`, `commission_amount`, `reversal_of_event_id`, `status`).
- **Posting Table (`wp_mc_financial_postings`)**: Multi-legged sub-ledger entries (`posting_uuid` UNIQUE, `event_id`, `posting_type`, `account_bucket`, `direction` [`DEBIT`|`CREDIT`], `amount`, `beneficiary_type`, `beneficiary_id`, `shift_id`, `status`).
- **Standard Visit Creation Postings (`post_visit_transaction`, `lines 264-478`)**:
  1. `REVENUE` (`account_bucket = 'REVENUE_OPERATING'`, `direction = 'CREDIT'`, `amount = $gross`)
  2. `DISCOUNT` (`account_bucket = 'CONTRA_REVENUE_DISCOUNT'`, `direction = 'DEBIT'`, `amount = $discount`, if `$discount > 0`)
  3. `CASH_IN` (`account_bucket = 'CASH_ON_HAND' | 'BANK_POS'`, `direction = 'DEBIT'`, `amount = $paid`, if `$paid > 0`)
  4. `PATIENT_AR` (`account_bucket = 'ACCOUNTS_RECEIVABLE_PATIENT'`, `direction = 'DEBIT'`, `amount = $balance`, if `$balance > 0`)
  5. `INSURANCE_AR` (`account_bucket = 'ACCOUNTS_RECEIVABLE_INSURANCE'`, `direction = 'DEBIT'`, `amount = $insurance_covered`, if `$insurance_covered > 0`)
  6. `COMMISSION_ACCRUAL` (`account_bucket = 'PAYABLE_COMMISSION_DOCTOR'`, `direction = 'CREDIT'`, `amount = $commission_amount`, `beneficiary_type = 'DOCTOR'`, `beneficiary_id = $doctor_id`, if `$commission_amount > 0`)

## 3. Two-Tier Commission Engine (`FIN-003` — `FACT`)
- **Source**: `MedCore_Commission_Engine::resolve_commission` (`class-medcore-commission-engine.php:24-321`).
- **Tier 1 (`wp_mc_definition_rules` where `rule_type = 'COMMISSION'`)**:
  - Evaluates active rules within `[effective_from, effective_to]`.
  - Computes specificity score based on matching `doctor_id` (+16), `service_code` (+8), `clinic_id` (+4), `department_id` (+2), `visit_type` (+1), plus explicit `precedence`.
  - Supports parent rule inheritance (`parent_rule_id`), `value_type` (`PERCENT` | `FIXED` | `NONE`), `basis_type` (`NET` | `GROSS` | `PAID` | `INSURANCE`), `cap`, and `floor`.
- **Tier 2 Fallback (`wp_mc_definitions` doctor `data_json`)**:
  - Checks `clinicPricing` array for matching `clinicId` -> `examCommPercent` / `consultCommPercent`.
  - Checks `serviceExceptions` / `diagnosticExceptions` for per-service overrides.
  - Falls back to `flatServiceCommPercent` -> `commissionPercent` -> `fixedCommission`, clamping by `commissionCap` and `commissionFloor`.

## 4. Critical Financial Defects & Missing Capabilities Discovered (`FACT`)
1. **CRITICAL GAP — No Service/Labor vs Consumable/Material Split (`FIN-GAP-01`)**:
   - In `post_visit_transaction` (`class-medcore-financial-transaction-service.php:424-438`), doctor commission is calculated on total visit `$net` (`basis_type = 'NET'`, `basis_amount = $net`).
   - If a visit or procedure includes consumables/materials (e.g., contrast media, anesthesia supplies, implants, medications), their cost/price is NOT deducted from the commissionable basis.
   - Furthermore, `MedCore_Inventory_Consumption::consume_for_service` (`class-medcore-inventory-consumption.php:5-51`, which implements FIFO batch deduction and `MedCore_Inventory_Cost_Engine::calculate_cost`) is **never called** by `MedCore_Visit_Service::create_visit`!
2. **CRITICAL BUG — Settlement Payout Double-Debit (`FIN-BUG-01`)**:
   - In `MCE_API_Financial_Settlement::receive` (`class-api-financial-settlement.php:104-106`) and `execute_direct_payout` (`lines 369 & 398`), BOTH the Beneficiary payable leg (`SETTLE-BEN-*`, `account_bucket = 'PAYABLE_COMMISSION'`) AND the Treasury cash disbursement leg (`SETTLE-TR-*`, `account_bucket = 'TREASURY_CASH'`, `posting_type = 'SETTLEMENT_PAYMENT'`) are inserted with `'direction' => 'DEBIT'`.
   - In proper double-entry accounting, reducing a Liability (`PAYABLE_COMMISSION`) is a `DEBIT`, and reducing an Asset (`TREASURY_CASH`) is a `CREDIT`. Because `SETTLE-TR-*` is recorded as `DEBIT`, `MedCore_Shift_Service::get_shift_totals` (`class-medcore-shift-service.php:279`) had to hardcode a query summing `posting_type IN ('REFUND_OUT', 'SETTLEMENT_PAYMENT', 'EXPENSE_OUT') AND direction = 'DEBIT'` as `cashOut`!
3. **SOURCE CONFLICT — Hardcoded Currency Drift (`FIN-BUG-02`)**:
   - `post_visit_transaction` (`class-medcore-financial-transaction-service.php:125`) and `create_visit` (`class-medcore-visit-service.php:271`) default currency to `'SAR'`.
   - `reverse_visit_transaction` (`line 1109`) and `adjust_visit_transaction` (`lines 1432, 1456, 1480, 1504`) hardcode `'EGP'`!
4. **Frontend Floating-Point Math (`FIN-BUG-03`)**:
   - Across `Frontend/src`, `parseFloat()` is used **28** times on monetary inputs without integer minor-unit (halala/piaster) or `Decimal` quantization.
