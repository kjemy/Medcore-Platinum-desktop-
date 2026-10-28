# MEDCORE PLATINUM — EXTERNAL PAYABLES & THIRD-PARTY LIABILITIES REPORT
**Execution Date:** 2026-10-28
**Authority:** Master Engineering Constitution (@Khaled All Rules)
**Status:** PASS (Fully Verified Against Live MariaDB 11.4.4)

---

## 1. EXECUTIVE SUMMARY
Third-party liabilities (outsourced laboratory investigations, external radiology reads, specialist consults, external medical supplies) are managed with strict double-entry ledger atomicity. Every payable allocation and disbursement maintains complete trial balance equality: `SUM(DEBIT) == SUM(CREDIT)`.

---

## 2. DATABASE REIFICATION & PHYSICAL DDL
Authoritative schema migration `V016__employee_accounts_and_external_payables.sql`:
```sql
CREATE TABLE IF NOT EXISTS mc_external_payables (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    hospital_code VARCHAR(64) NOT NULL,
    payable_uuid VARCHAR(128) NOT NULL,
    source_visit_id BIGINT UNSIGNED NOT NULL,
    source_event_id BIGINT UNSIGNED NOT NULL,
    party_type ENUM('LAB', 'RADIOLOGY', 'REFERRAL_DOCTOR', 'VENDOR') NOT NULL,
    party_code VARCHAR(64) NOT NULL,
    party_name VARCHAR(191) NOT NULL,
    gross_amount DECIMAL(14,4) NOT NULL,
    allocated_amount DECIMAL(14,4) NOT NULL,
    paid_amount DECIMAL(14,4) NOT NULL DEFAULT 0.0000,
    balance_amount DECIMAL(14,4) NOT NULL,
    status ENUM('PENDING', 'PARTIAL', 'SETTLED', 'CANCELLED') NOT NULL DEFAULT 'PENDING',
    shift_id BIGINT UNSIGNED NULL,
    notes TEXT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mc_ext_pay_uuid (payable_uuid),
    KEY idx_mc_ext_pay_hosp_status (hospital_code, status),
    KEY idx_mc_ext_pay_visit (hospital_code, source_visit_id),
    CONSTRAINT fk_mc_ext_pay_tenant FOREIGN KEY (hospital_code) REFERENCES mc_tenants (hospital_code) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

---

## 3. FINANCIAL ACCOUNTING & LEDGER INTEGRITY
1. **Allocation Entry**:
   - Debit: `EXPENSE_OUTSOURCED_SERVICES` (150.0000)
   - Credit: `ACCOUNTS_PAYABLE_EXTERNAL` (150.0000)
   - Equality: `Total Debits == Total Credits`.
2. **Disbursement / Settlement Entry**:
   - Debit: `ACCOUNTS_PAYABLE_EXTERNAL` (Amount settled)
   - Credit: `CASH_ON_HAND` or `BANK` (Amount disbursed)
   - Status Transition: `PENDING` -> `PARTIAL` -> `SETTLED`.
   - Over-settlement is strictly prevented fail-closed with 400 Bad Request.

---

## 4. VERIFICATION EVIDENCE
- Test Suite: `medcore_local_service/test/batch8_external_payables_and_lan_pki_test.dart`
- Results:
  - Test 1: External payable allocation verified against physical `mc_external_payables` and `mc_financial_postings`. Trial balance strictly balanced.
  - Test 2: Multi-step settlement (`PARTIAL` then `SETTLED`), ledger clearing, over-settlement fail-closed rejection.
