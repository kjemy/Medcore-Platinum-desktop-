# PATCH-001: Isolated Test Database Lifecycle for Batch 12

- **Patch ID:** PATCH-001
- **Gate:** GATE 02 — LOCAL DATABASE / MARIADB SECURITY
- **Severity:** LOW (Test harness isolation defect)
- **Root Cause:** `batch12_micro_pbkdf2_and_credential_isolation_test.dart` shared `dbName = 'medcore_commissioning_gate_test'` without dropping or cleaning up existing tenant records in `setUpAll` / `tearDownAll`. Subsequent runs encountered a duplicate key constraint violation (`1062 Duplicate entry`) on `uq_mc_staff_hosp_email`.
- **Affected Files:** `medcore_local_service/test/batch12_micro_pbkdf2_and_credential_isolation_test.dart`
- **Affected Components:** Test harness database lifecycle & setup/teardown.
- **Before State:** Reused `medcore_commissioning_gate_test` database without cleaning up rows before or after execution.
- **Change Made:** Gave `batch12` its own dedicated isolated test database `medcore_micro_credential_test`, and added DROP & CREATE in `setUpAll` and DROP in `tearDownAll`.
- **Why The Change Is Correct:** Guarantees strict database isolation per test suite, preventing cross-test pollution and duplicate key collision on unique indexes.
- **Security Impact:** None on production code; strengthens automated test suite reliability and repeatable execution.
- **Functional Impact:** Zero regressions; isolates test execution cleanly.
- **Regression Tests:** `batch12_micro_pbkdf2_and_credential_isolation_test.dart`
- **Red-Team Result:** PASS (All tests passed, clean database teardown verified).
- **Final Status:** VERIFIED (Exit Code 0).
