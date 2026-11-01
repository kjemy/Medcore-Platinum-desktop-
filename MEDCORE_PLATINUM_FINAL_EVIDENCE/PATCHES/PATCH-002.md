# PATCH-002: Add tearDownAll Resource Cleanup to Batch 8

- **Patch ID:** PATCH-002
- **Gate:** GATE 13 — END-TO-END CLINICAL / BUSINESS FUNCTIONALITY
- **Severity:** LOW (Test harness resource leak defect)
- **Root Cause:** `batch8_external_payables_and_lan_pki_test.dart` started a local Shelf HTTP server and opened a dedicated database connection pool in `setUpAll`, but lacked a `tearDownAll` block. Lingering sockets and database connections prevented clean process exit, resulting in exit code 255 despite all test assertions passing.
- **Affected Files:** `medcore_local_service/test/batch8_external_payables_and_lan_pki_test.dart`
- **Affected Components:** Test harness lifecycle & clean teardown.
- **Before State:** No `tearDownAll` defined; server and DB pool remained open.
- **Change Made:** Added `tearDownAll` to stop the server, drop the temporary test database `medcore_test_extpay`, close the DB pool, and clean up temporary security root files.
- **Why The Change Is Correct:** Ensures all asynchronous socket handles and event loop listeners are closed cleanly upon test suite completion.
- **Security Impact:** None on production code; ensures automated test suites exit with code 0 cleanly.
- **Functional Impact:** Zero regressions; clean execution and database isolation.
- **Regression Tests:** `batch8_external_payables_and_lan_pki_test.dart` (Exit Code 0).
- **Red-Team Result:** PASS (Clean exit, 100% assertions passed).
- **Final Status:** VERIFIED (Exit Code 0).
