# MEDCORE — FINANCIAL & ACCOUNTING CORE SPECIFICATION (`CATEGORY D`)
**Document ID**: `DOC-06` | **Source**: `class-medcore-financial-transaction-service.php`, `class-medcore-commission-engine.php`, `class-medcore-shift-service.php`, `class-api-financial-settlement.php`

---

## 1. Authoritative Monetary Architecture
All financial calculations in `MedCore Desktop` MUST execute inside the **Local MedCore Service** within an `InnoDB` `SERIALIZABLE` or `REPEATABLE READ` transaction with explicit row-level locks (`SELECT ... FOR UPDATE`).

### 1.1 The Fundamental Visit Monetary Identity (`FIN-001`)
For every visit and invoice:
$$\text{Gross} = \sum_{i=1}^{n} (\text{UnitPrice}_i \times \text{Quantity}_i)$$
$$\text{Net} = \text{Gross} - \text{Discount} \quad (0 \le \text{Discount} \le \text{Gross})$$
$$\text{PatientResponsibility} = \text{Net} - \text{InsuranceCovered} \quad (0 \le \text{InsuranceCovered} \le \text{Net})$$
$$\text{Balance (Patient AR)} = \text{PatientResponsibility} - \text{Paid} \quad (0 \le \text{Paid} \le \text{PatientResponsibility})$$
$$\text{Discount} + \text{Paid} + \text{InsuranceCovered} + \text{Balance} = \text{Gross}$$

---

## 2. Mandatory Upgrade: Service/Labor Fee vs Consumable/Material Cost Split (`FIN-004`)

### 2.1 The Gap in `Project 3` (`FIN-GAP-01` — `FACT`)
In `Project 3`:
- `MedCore_Financial_Transaction_Service::post_visit_transaction` (`class-medcore-financial-transaction-service.php:424-438`) passes the entire visit `$net` to `MedCore_Commission_Engine::resolve_commission()`.
- `MedCore_Inventory_Consumption::consume_for_service()` (`class-medcore-inventory-consumption.php:5-51`) exists in the codebase to deduct FIFO batches from `wp_mc_inventory_StockBatch`, **but is never called during visit creation or clinical execution**.
- Consequently, if a procedure costs `1,000` (composed of `600` medical service fee + `400` surgical/radiology consumables), a doctor with a `50%` commission rate erroneously receives `500` (`50%` of `1,000`) instead of `300` (`50%` of `600`), and hospital inventory is not automatically decremented.

### 2.2 The Authoritative `MedCore Desktop` Cost-Split & Commission Formula
Every billable item (`mc_visit_items`) is decomposed into `mc_visit_item_cost_lines`:
1. **Explicit Line Split (Bill of Materials / Procedure Package)**:
   - `ItemGross = ServiceLaborGross + ConsumableBilledGross + EquipmentFeeGross`
   - Discount is pro-rated across components (or applied to `ServiceLaborGross` per rule configuration):
     $$\text{ServiceLaborNet} = \text{ServiceLaborGross} - \text{ServiceDiscount}$$
2. **FIFO Inventory Cost Deduction (`FIFO_COGS`)**:
   - When consumables are attached to a service (via standard BOM `mc_service_consumables_bom` or dynamic clinical consumption in OR/Dialysis/ER/Lab/Rad), the engine locks matching non-expired batches in `mc_inventory_stock_batches` (`ORDER BY expiry_date ASC, id ASC FOR UPDATE`) and computes:
     $$\text{FIFO\_COGS} = \sum_{b} (\text{QtyConsumed}_b \times \text{BatchUnitCost}_b)$$
3. **Commissionable Basis Modes (`commission_basis_mode`)**:
   - `SERVICE_NET_ONLY` (Default Recommended): Doctor commission applies strictly to `ServiceLaborNet` (`ConsumableBilledNet` and `EquipmentFeeNet` are `is_commissionable = 0`).
   - `NET_AFTER_FIFO_COGS` (Bundled Procedure Mode): When a procedure has a single bundled price without separate patient billing for consumables, `CommissionableBasis = max(0, ItemNet - FIFO_COGS)`.
   - `GROSS_SERVICE_ONLY`: Commission applies to `ServiceLaborGross` before hospital-funded promotional discounts.

---

## 3. Corrected Double-Entry Sub-Ledger Posting Matrix (`mc_financial_postings`)

In `Project 3`, `MCE_API_Financial_Settlement` (`class-api-financial-settlement.php:104-106, 369, 398`) erroneously posted both legs of a settlement payout as `DEBIT`. Below is the **corrected, strictly balanced Double-Entry Posting Matrix** for `MedCore Desktop`:

| Event Type | Leg # | `posting_type` | `account_bucket` | Account Class | `direction` | Amount Formula |
|---|---|---|---|---|---|---|
| `VISIT_CREATE` | 1 | `REVENUE` | `REVENUE_SERVICE_LABOR` | Revenue | `CREDIT` | `ServiceLaborGross` |
| `VISIT_CREATE` | 2 | `REVENUE_CONSUMABLES` | `REVENUE_CONSUMABLES_BILLED` | Revenue | `CREDIT` | `ConsumableBilledGross` (if > 0) |
| `VISIT_CREATE` | 3 | `DISCOUNT` | `CONTRA_REVENUE_DISCOUNT` | Contra-Revenue | `DEBIT` | `TotalDiscount` (if > 0) |
| `VISIT_CREATE` | 4 | `CASH_IN` | `CASH_ON_HAND` / `BANK_POS` | Asset | `DEBIT` | `PaidAmount` (if > 0) |
| `VISIT_CREATE` | 5 | `PATIENT_AR` | `ACCOUNTS_RECEIVABLE_PATIENT` | Asset | `DEBIT` | `BalanceAmount` (if > 0) |
| `VISIT_CREATE` | 6 | `INSURANCE_AR` | `ACCOUNTS_RECEIVABLE_INSURANCE` | Asset | `DEBIT` | `InsuranceCovered` (if > 0) |
| `VISIT_CREATE` | 7 | `COGS_CONSUMABLES` | `EXPENSE_COGS_CONSUMABLES` | Expense | `DEBIT` | `FIFO_COGS` (if > 0) |
| `VISIT_CREATE` | 8 | `INVENTORY_RELIEF` | `ASSET_INVENTORY_STOCK` | Asset | `CREDIT` | `FIFO_COGS` (if > 0) |
| `VISIT_CREATE` | 9 | `COMMISSION_EXPENSE` | `EXPENSE_DOCTOR_COMMISSION` | Expense | `DEBIT` | `CommissionAmount` (if > 0) |
| `VISIT_CREATE` | 10 | `COMMISSION_ACCRUAL` | `PAYABLE_COMMISSION_DOCTOR` | Liability | `CREDIT` | `CommissionAmount` (if > 0) |
| `COMMISSION_SETTLEMENT` | 1 | `SETTLEMENT_LIABILITY` | `PAYABLE_COMMISSION_DOCTOR` | Liability | `DEBIT` | `SettledAmount` |
| `COMMISSION_SETTLEMENT` | 2 | `SETTLEMENT_PAYMENT` | `CASH_ON_HAND` / `TREASURY_CASH` | Asset | **`CREDIT`** *(Fixes P3 Bug)* | `SettledAmount` |
| `EXPENSE_VOUCHER_OUT` | 1 | `EXPENSE_RECOGNITION` | `EXPENSE_OPERATING` | Expense | `DEBIT` | `VoucherAmount` |
| `EXPENSE_VOUCHER_OUT` | 2 | `EXPENSE_OUT` | `CASH_ON_HAND` / `TREASURY_CASH` | Asset | **`CREDIT`** | `VoucherAmount` |

> **Trial Balance Invariant**: For every `event_id` in `mc_financial_events`, `SUM(DEBIT) == SUM(CREDIT)` across `mc_financial_postings` to `0.0000` tolerance!
