# WS2 — Backend REST API & Next.js Route Inventory (`Project 3`)

> **Classification**: `FACT` — Extracted from all `register_rest_route()` calls across `Backend/MedCorePlugin` and `Backend/medcore-database-explorer`, plus `Frontend/src/app/api/**/route.ts`.

## 1. Summary Metrics
- **Total WordPress REST Route Registrations**: **152** across 5 namespaces (`medcore/v1`, `mce/v1`, `medcore-ai/v1`, `medcore-dbx/v1`, `medcore-SaaS/v1`).
- **Total Next.js App Router API Routes**: **14**.
- **Routes with `permission_callback => '__return_true'` (Unauthenticated at WP Router Layer)**: **20** registrations.

## 2. Complete WordPress REST API Route Inventory (152 Registrations)

| # | Namespace | Route Pattern | HTTP Methods | Controller File:Line | Permission Callback | Category |
|---|---|---|---|---|---|---|
| 1 | `'mce/v1'` | `'/accounting/coa'` | `'POST', 'GET'` | `Backend/MedCorePlugin/includes/api/class-api-accounting.php:6` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 2 | `'mce/v1'` | `'/accounting/journals'` | `'POST', 'GET'` | `Backend/MedCorePlugin/includes/api/class-api-accounting.php:19` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 3 | `'mce/v1'` | `'/admissions'` | `'POST', 'GET'` | `Backend/MedCorePlugin/includes/api/class-api-admissions.php:6` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 4 | `'mce/v1'` | `'/admissions/(?P<id>[a-zA-Z0-9-]+)/discharge'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-admissions.php:18` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 5 | `'medcore/v1'` | `'/ai-balance'` | `'GET'` | `Backend/MedCorePlugin/includes/api/class-api-ai-extra.php:6` | `` | H/I (Control Plane / AI Gateway) |
| 6 | `'medcore/v1'` | `'/ai-deduct'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-ai-extra.php:11` | `` | H/I (Control Plane / AI Gateway) |
| 7 | `'medcore-ai/v1'` | `'/keys'` | `WP_REST_Server::READABLE` | `Backend/MedCorePlugin/includes/api/class-api-ai.php:6` | `` | H/I (Control Plane / AI Gateway) |
| 8 | `'mce/v1'` | `'/ai/usage/consume'` | `WP_REST_Server::CREATABLE` | `Backend/MedCorePlugin/includes/api/class-api-ai.php:20` | `` | H/I (Control Plane / AI Gateway) |
| 9 | `MEDCORE_LEGACY_NAMESPACE` | `'/consume-tokens'` | `WP_REST_Server::CREATABLE` | `Backend/MedCorePlugin/includes/api/class-api-ai.php:28` | `` | H/I (Control Plane / AI Gateway) |
| 10 | `MEDCORE_API_NAMESPACE` | `'/audit-log'` | `WP_REST_Server::READABLE, WP_REST_Server::CREATABLE` | `Backend/MedCorePlugin/includes/api/class-api-audit-log.php:6` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 11 | `MEDCORE_API_NAMESPACE` | `'/audit'` | `WP_REST_Server::READABLE` | `Backend/MedCorePlugin/includes/api/class-api-audit-log.php:23` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 12 | `'mce/v1'` | `'/auth/login'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-auth.php:6` | `'__return_true'` | G (Backend-Specific Transport) / A (Core Contract) |
| 13 | `'mce/v1'` | `'/auth/verify-admin'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-auth.php:11` | `'__return_true'` | G (Backend-Specific Transport) / A (Core Contract) |
| 14 | `'mce/v1'` | `'/auth/request-otp'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-auth.php:16` | `'__return_true'` | G (Backend-Specific Transport) / A (Core Contract) |
| 15 | `'mce/v1'` | `'/auth/verify-otp'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-auth.php:21` | `'__return_true'` | G (Backend-Specific Transport) / A (Core Contract) |
| 16 | `'mce/v1'` | `'/auth/forgot-password'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-auth.php:26` | `'__return_true'` | G (Backend-Specific Transport) / A (Core Contract) |
| 17 | `'mce/v1'` | `'/auth/reset-password'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-auth.php:31` | `'__return_true'` | G (Backend-Specific Transport) / A (Core Contract) |
| 18 | `'mce/v1'` | `'/auth/validate-activation'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-auth.php:36` | `'__return_true'` | G (Backend-Specific Transport) / A (Core Contract) |
| 19 | `'mce/v1'` | `'/auth/complete-activation'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-auth.php:41` | `'__return_true'` | G (Backend-Specific Transport) / A (Core Contract) |
| 20 | `'mce/v1'` | `$x[0]` | `$x[1` | `Backend/MedCorePlugin/includes/api/class-api-clinical-orders.php:20` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 21 | `'mce/v1'` | `'/clinical/templates'` | `'GET', 'POST'` | `Backend/MedCorePlugin/includes/api/class-api-clinical-templates.php:6` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 22 | `'mce/v1'` | `'/clinical/templates/(?P<id>[A-Za-z0-9-]+)'` | `'PUT', 'DELETE'` | `Backend/MedCorePlugin/includes/api/class-api-clinical-templates.php:10` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 23 | `'mce/v1'` | `'/clinical/templates/(?P<id>[A-Za-z0-9-]+)/use'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-clinical-templates.php:14` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 24 | `'mce/v1'` | `'/labs/orders'` | `'GET', 'POST'` | `Backend/MedCorePlugin/includes/api/class-api-clinical.php:5` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 25 | `'mce/v1'` | `'/radiology/orders'` | `'GET', 'POST'` | `Backend/MedCorePlugin/includes/api/class-api-clinical.php:9` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 26 | `'mce/v1'` | `'/pharmacy/prescriptions'` | `'GET', 'POST'` | `Backend/MedCorePlugin/includes/api/class-api-clinical.php:13` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 27 | `'mce/v1'` | `'/pharmacy/prescriptions/(?P<id>[A-Za-z0-9-]+)/transition'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-clinical.php:17` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 28 | `'mce/v1'` | `'/labs/orders/(?P<id>[A-Za-z0-9-]+)'` | `'PATCH'` | `Backend/MedCorePlugin/includes/api/class-api-clinical.php:20` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 29 | `'mce/v1'` | `'/radiology/orders/(?P<id>[A-Za-z0-9-]+)'` | `'PATCH'` | `Backend/MedCorePlugin/includes/api/class-api-clinical.php:23` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 30 | `'mce/v1'` | `'/debug/logs'` | `'GET'` | `Backend/MedCorePlugin/includes/api/class-api-debug.php:7` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 31 | `'mce/v1'` | `'/debug/stats'` | `'GET'` | `Backend/MedCorePlugin/includes/api/class-api-debug.php:17` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 32 | `'mce/v1'` | `'/debug/purge'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-debug.php:27` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 33 | `'mce/v1'` | `'/definitions/rules/(?P<public_id>[A-Za-z0-9-]+)'` | `'PUT'` | `Backend/MedCorePlugin/includes/api/class-api-definition-rules.php:8` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 34 | `'mce/v1'` | `'/definitions/rules'` | `'GET', 'POST'` | `Backend/MedCorePlugin/includes/api/class-api-definition-rules.php:11` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 35 | `'mce/v1'` | `'/definitions'` | `'GET', 'POST'` | `Backend/MedCorePlugin/includes/api/class-api-definitions.php:15` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 36 | `'mce/v1'` | `'/definitions/upsert'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-definitions.php:19` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 37 | `'mce/v1'` | `'/definitions/(?P<public_id>[a-f0-9-]{36})'` | `'GET', 'PUT', 'DELETE'` | `Backend/MedCorePlugin/includes/api/class-api-definitions.php:22` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 38 | `'medcore/v1'` | `'/desktop-version'` | `'GET'` | `Backend/MedCorePlugin/includes/api/class-api-desktop.php:6` | `'__return_true'` | G (Backend-Specific Transport) / A (Core Contract) |
| 39 | `'medcore/v1'` | `'/verify-device'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-desktop.php:11` | `'__return_true'` | G (Backend-Specific Transport) / A (Core Contract) |
| 40 | `'medcore/v1'` | `'/verify-tenant'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-desktop.php:16` | `'__return_true'` | G (Backend-Specific Transport) / A (Core Contract) |
| 41 | `'medcore/v1'` | `'/tutorials'` | `'GET'` | `Backend/MedCorePlugin/includes/api/class-api-desktop.php:21` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 42 | `'mce/v1'` | `$path` | `'POST', 'GET'` | `Backend/MedCorePlugin/includes/api/class-api-dialysis.php:8` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 43 | `'mce/v1'` | `$path . '/(?P<id>[A-Za-z0-9-]+)'` | `'PATCH', 'PUT'` | `Backend/MedCorePlugin/includes/api/class-api-dialysis.php:20` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 44 | `'mce/v1'` | `'/files'` | `'GET', 'POST'` | `Backend/MedCorePlugin/includes/api/class-api-files.php:4` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 45 | `'mce/v1'` | `'/files/(?P<public_id>[A-Za-z0-9-]+)/ai-link'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-files.php:8` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 46 | `'mce/v1'` | `'/files/(?P<public_id>[A-Za-z0-9-]+)/upload-url'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-files.php:11` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 47 | `'mce/v1'` | `'/files/(?P<public_id>[A-Za-z0-9-]+)/complete'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-files.php:14` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 48 | `'mce/v1'` | `'/files/(?P<public_id>[A-Za-z0-9-]+)/download-url'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-files.php:17` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 49 | `'mce/v1'` | `'/financial/settlements'` | `'GET', 'POST'` | `Backend/MedCorePlugin/includes/api/class-api-financial-settlement.php:5` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 50 | `'mce/v1'` | `'/financial/settlements/direct-payout'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-financial-settlement.php:9` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 51 | `'mce/v1'` | `"/financial/settlements/(?P<id>[A-Za-z0-9-]+)/{$action}"` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-financial-settlement.php:13` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 52 | `'mce/v1'` | `'/financial/transactions'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-financial-transaction.php:5` | `[$this,'verify_permission']` | G (Backend-Specific Transport) / A (Core Contract) |
| 53 | `'mce/v1'` | `'/financial/charge/quote'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-financial.php:6` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 54 | `'mce/v1'` | `'/financial/commission/resolve'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-financial.php:9` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 55 | `'mce/v1'` | `'/financial/events'` | `'POST', 'GET'` | `Backend/MedCorePlugin/includes/api/class-api-financial.php:12` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 56 | `'mce/v1'` | `'/financial/events/(?P<public_id>[a-f0-9-]{36})/earnings'` | `'POST', 'GET'` | `Backend/MedCorePlugin/includes/api/class-api-financial.php:16` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 57 | `'mce/v1'` | `'/financial/earnings'` | `'GET'` | `Backend/MedCorePlugin/includes/api/class-api-financial.php:20` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 58 | `'mce/v1'` | `'/financial/earnings/(?P<public_id>[a-f0-9-]{36})/settle'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-financial.php:23` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 59 | `'mce/v1'` | `'/financial/earnings/adjustment'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-financial.php:26` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 60 | `'mce/v1'` | `'/icu/flowsheets'` | `'POST', 'GET'` | `Backend/MedCorePlugin/includes/api/class-api-icu-nicu-clinical.php:6` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 61 | `'mce/v1'` | `'/nicu/apgar'` | `'POST', 'GET'` | `Backend/MedCorePlugin/includes/api/class-api-icu-nicu-clinical.php:19` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 62 | `'mce/v1'` | `'/nicu/telemetry'` | `'POST', 'GET'` | `Backend/MedCorePlugin/includes/api/class-api-icu-nicu-clinical.php:32` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 63 | `'mce/v1'` | `'/nicu/growth-logs'` | `'POST', 'GET'` | `Backend/MedCorePlugin/includes/api/class-api-icu-nicu-clinical.php:45` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 64 | `'mce/v1'` | `'/inventory/locations'` | `'GET', 'POST'` | `Backend/MedCorePlugin/includes/api/class-api-inventory-catalog.php:6` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 65 | `'mce/v1'` | `'/inventory/items'` | `'GET', 'POST'` | `Backend/MedCorePlugin/includes/api/class-api-inventory-catalog.php:10` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 66 | `'mce/v1'` | `'/inventory/batches'` | `'GET', 'POST'` | `Backend/MedCorePlugin/includes/api/class-api-inventory-catalog.php:14` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 67 | `'mce/v1'` | `'/inventory/cost/resolve'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-inventory-cost.php:5` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 68 | `'mce/v1'` | `'/inventory/requests'` | `'GET', 'POST'` | `Backend/MedCorePlugin/includes/api/class-api-inventory-requests.php:6` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 69 | `'mce/v1'` | `'/inventory/requests/(?P<public_id>[a-f0-9-]{36})/approve'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-inventory-requests.php:10` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 70 | `'mce/v1'` | `'/inventory/requests/(?P<public_id>[a-f0-9-]{36})/reject'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-inventory-requests.php:13` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 71 | `'mce/v1'` | `'/inventory/requests/(?P<public_id>[a-f0-9-]{36})/issue'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-inventory-requests.php:16` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 72 | `'mce/v1'` | `'/inventory/reservations'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-inventory-reservations.php:5` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 73 | `'mce/v1'` | `'/inventory/reservations'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-inventory.php:6` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 74 | `'mce/v1'` | `'/inventory/reservations/(?P<public_id>[A-Za-z0-9-]+)/release'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-inventory.php:9` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 75 | `'mce/v1'` | `'/inventory/reservations/expire'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-inventory.php:12` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 76 | `'mce/v1'` | `'/inventory/movements'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-inventory.php:15` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 77 | `'mce/v1'` | `'/inventory/balances'` | `'GET'` | `Backend/MedCorePlugin/includes/api/class-api-inventory.php:18` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 78 | `'mce/v1'` | `'/clinical/lab/referrals'` | `'GET', 'POST'` | `Backend/MedCorePlugin/includes/api/class-api-lab-referrals.php:6` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 79 | `'mce/v1'` | `'/clinical/lab/referrals/(?P<id>[A-Za-z0-9-]+)/transition'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-lab-referrals.php:10` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 80 | `'mce/v1'` | `'/nursing/tasks'` | `'GET', 'POST'` | `Backend/MedCorePlugin/includes/api/class-api-nursing.php:5` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 81 | `'mce/v1'` | `'/nursing/tasks/(?P<id>[A-Za-z0-9-]+)/status'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-nursing.php:9` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 82 | `'mce/v1'` | `'/patients/(?P<public_id>[A-Za-z0-9-]+)/profile'` | `'GET', 'PUT'` | `Backend/MedCorePlugin/includes/api/class-api-patient-domain.php:6` | `` | H/I (Control Plane / AI Gateway) |
| 83 | `'mce/v1'` | `'/appointments'` | `'GET', 'POST'` | `Backend/MedCorePlugin/includes/api/class-api-patient-domain.php:10` | `` | H/I (Control Plane / AI Gateway) |
| 84 | `'mce/v1'` | `'/appointments/(?P<id>[A-Za-z0-9-]+)'` | `'PUT'` | `Backend/MedCorePlugin/includes/api/class-api-patient-domain.php:14` | `` | H/I (Control Plane / AI Gateway) |
| 85 | `'mce/v1'` | `'/encounters'` | `'GET', 'POST'` | `Backend/MedCorePlugin/includes/api/class-api-patient-domain.php:17` | `` | H/I (Control Plane / AI Gateway) |
| 86 | `'mce/v1'` | `'/encounters/(?P<id>[A-Za-z0-9-]+)'` | `'PUT'` | `Backend/MedCorePlugin/includes/api/class-api-patient-domain.php:21` | `` | H/I (Control Plane / AI Gateway) |
| 87 | `MEDCORE_API_NAMESPACE` | `'/patients'` | `WP_REST_Server::READABLE, WP_REST_Server::CREATABLE` | `Backend/MedCorePlugin/includes/api/class-api-patients.php:6` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 88 | `MEDCORE_API_NAMESPACE` | `'/patients/(?P<public_id>[A-Za-z0-9-]+)'` | `WP_REST_Server::EDITABLE` | `Backend/MedCorePlugin/includes/api/class-api-patients.php:19` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 89 | `MEDCORE_API_NAMESPACE` | `'/patients/search'` | `WP_REST_Server::READABLE` | `Backend/MedCorePlugin/includes/api/class-api-patients.php:23` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 90 | `'mce/v1'` | `'/pharmacy/dispenses'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-pharmacy.php:4` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 91 | `'mce/v1'` | `'/saas/users'` | `'GET', 'POST'` | `Backend/MedCorePlugin/includes/api/class-api-saas-extended.php:7` | `` | H/I (Control Plane / AI Gateway) |
| 92 | `'mce/v1'` | `'/saas/audit'` | `'GET'` | `Backend/MedCorePlugin/includes/api/class-api-saas-extended.php:21` | `` | H/I (Control Plane / AI Gateway) |
| 93 | `'mce/v1'` | `'/saas/transactions'` | `'GET'` | `Backend/MedCorePlugin/includes/api/class-api-saas-extended.php:28` | `` | H/I (Control Plane / AI Gateway) |
| 94 | `'mce/v1'` | `'/saas/storage/(?P<key>[a-zA-Z0-9_-]+)'` | `'GET', 'POST'` | `Backend/MedCorePlugin/includes/api/class-api-saas-extended.php:35` | `` | H/I (Control Plane / AI Gateway) |
| 95 | `'mce/v1'` | `'/saas/plans'` | `'GET', 'POST'` | `Backend/MedCorePlugin/includes/api/class-api-saas-extended.php:49` | `` | H/I (Control Plane / AI Gateway) |
| 96 | `'mce/v1'` | `'/saas/ai-stats/(?P<tenant_id>[a-zA-Z0-9_-]+)'` | `'GET'` | `Backend/MedCorePlugin/includes/api/class-api-saas-extended.php:63` | `` | H/I (Control Plane / AI Gateway) |
| 97 | `'mce/v1'` | `'/saas/check-permission'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-saas-extended.php:70` | `` | H/I (Control Plane / AI Gateway) |
| 98 | `'medcore-saas/v1'` | `'/categories'` | `'GET'` | `Backend/MedCorePlugin/includes/api/class-api-saas.php:6` | `` | H/I (Control Plane / AI Gateway) |
| 99 | `'medcore-saas/v1'` | `'/plans'` | `'GET'` | `Backend/MedCorePlugin/includes/api/class-api-saas.php:11` | `` | H/I (Control Plane / AI Gateway) |
| 100 | `'medcore/v1'` | `'/plans'` | `'GET'` | `Backend/MedCorePlugin/includes/api/class-api-saas.php:16` | `` | H/I (Control Plane / AI Gateway) |
| 101 | `'medcore-saas/v1'` | `'/prices'` | `'GET'` | `Backend/MedCorePlugin/includes/api/class-api-saas.php:21` | `` | H/I (Control Plane / AI Gateway) |
| 102 | `'medcore-saas/v1'` | `'/create-order'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-saas.php:26` | `` | H/I (Control Plane / AI Gateway) |
| 103 | `'medcore-saas/v1'` | `'/process-headless-checkout'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-saas.php:31` | `` | H/I (Control Plane / AI Gateway) |
| 104 | `'medcore-saas/v1'` | `'/generate-topup-link'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-saas.php:36` | `` | H/I (Control Plane / AI Gateway) |
| 105 | `'medcore-saas/v1'` | `'/license'` | `'GET'` | `Backend/MedCorePlugin/includes/api/class-api-saas.php:41` | `` | H/I (Control Plane / AI Gateway) |
| 106 | `'mce/v1'` | `'/license'` | `'GET'` | `Backend/MedCorePlugin/includes/api/class-api-saas.php:47` | `` | H/I (Control Plane / AI Gateway) |
| 107 | `'mce/v1'` | `'/shifts/current'` | `'GET'` | `Backend/MedCorePlugin/includes/api/class-api-shifts.php:18` | `[ $this, 'verify_read_permission' ]` | G (Backend-Specific Transport) / A (Core Contract) |
| 108 | `'mce/v1'` | `'/shifts/open'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-shifts.php:26` | `[ $this, 'verify_write_permission' ]` | G (Backend-Specific Transport) / A (Core Contract) |
| 109 | `'mce/v1'` | `'/shifts'` | `'GET'` | `Backend/MedCorePlugin/includes/api/class-api-shifts.php:34` | `[ $this, 'verify_read_permission' ]` | G (Backend-Specific Transport) / A (Core Contract) |
| 110 | `'mce/v1'` | `'/shifts/(?P<id>[0-9]+)'` | `'GET'` | `Backend/MedCorePlugin/includes/api/class-api-shifts.php:42` | `[ $this, 'verify_read_permission' ]` | G (Backend-Specific Transport) / A (Core Contract) |
| 111 | `'mce/v1'` | `'/shifts/(?P<id>[0-9]+)/close'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-shifts.php:50` | `[ $this, 'verify_close_permission' ]` | G (Backend-Specific Transport) / A (Core Contract) |
| 112 | `'mce/v1'` | `'/shifts/(?P<id>[0-9]+)/audit'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-shifts.php:58` | `[ $this, 'verify_audit_permission' ]` | G (Backend-Specific Transport) / A (Core Contract) |
| 113 | `'medcore/v1'` | `'/login'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-staff.php:6` | `'__return_true'` | G (Backend-Specific Transport) / A (Core Contract) |
| 114 | `'medcore/v1'` | `'/verify-staff'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-staff.php:12` | `'__return_true'` | G (Backend-Specific Transport) / A (Core Contract) |
| 115 | `'medcore/v1'` | `'/verify-admin'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-staff.php:17` | `'__return_true'` | G (Backend-Specific Transport) / A (Core Contract) |
| 116 | `'medcore/v1'` | `'/sync-staff'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-staff.php:22` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 117 | `'medcore/v1'` | `'/delete-staff'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-staff.php:27` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 118 | `'medcore/v1'` | `'/set-password'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-staff.php:32` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 119 | `'medcore/v1'` | `'/forgot-password'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-staff.php:37` | `'__return_true'` | G (Backend-Specific Transport) / A (Core Contract) |
| 120 | `'medcore/v1'` | `'/verify-otp'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-staff.php:42` | `'__return_true'` | G (Backend-Specific Transport) / A (Core Contract) |
| 121 | `'medcore/v1'` | `'/reset-password'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-staff.php:47` | `'__return_true'` | G (Backend-Specific Transport) / A (Core Contract) |
| 122 | `'medcore/v1'` | `'/activation/validate'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-staff.php:52` | `'__return_true'` | G (Backend-Specific Transport) / A (Core Contract) |
| 123 | `'medcore/v1'` | `'/activation/complete'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-staff.php:57` | `'__return_true'` | G (Backend-Specific Transport) / A (Core Contract) |
| 124 | `MEDCORE_API_NAMESPACE` | `'/storage/(?P<tenant>[a-zA-Z0-9_-]+)/(?P<key>[a-zA-Z0-9_-]+)'` | `WP_REST_Server::READABLE, WP_REST_Server::CREATABLE` | `Backend/MedCorePlugin/includes/api/class-api-storage.php:6` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 125 | `'mce/v1'` | `'/surgeries'` | `'POST', 'GET'` | `Backend/MedCorePlugin/includes/api/class-api-surgery.php:6` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 126 | `'mce/v1'` | `'/surgeries/(?P<id>[A-Za-z0-9-]+)'` | `'PATCH', 'DELETE'` | `Backend/MedCorePlugin/includes/api/class-api-surgery.php:18` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 127 | `MEDCORE_API_NAMESPACE` | `'/sync/commands'` | `WP_REST_Server::CREATABLE` | `Backend/MedCorePlugin/includes/api/class-api-sync.php:6` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 128 | `'mce/v1'` | `'/system/migrate'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-system.php:6` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 129 | `'mce/v1'` | `'/system/legal/terms'` | `'GET'` | `Backend/MedCorePlugin/includes/api/class-api-system.php:12` | `'__return_true'` | G (Backend-Specific Transport) / A (Core Contract) |
| 130 | `'mce/v1'` | `'/system/backfill/legacy-storage'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-system.php:18` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 131 | `'mce/v1'` | `'/hospitals'` | `'GET', 'POST'` | `Backend/MedCorePlugin/includes/api/class-api-tenants.php:6` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 132 | `'mce/v1'` | `'/hospitals/(?P<tenant_id>[a-zA-Z0-9_-]+)'` | `'GET', 'PUT'` | `Backend/MedCorePlugin/includes/api/class-api-tenants.php:18` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 133 | `'mce/v1'` | `'/hospitals/(?P<tenant_id>[a-zA-Z0-9_-]+)/status'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-tenants.php:30` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 134 | `'mce/v1'` | `'/hospitals/(?P<tenant_id>[a-zA-Z0-9_-]+)/tokens'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-tenants.php:37` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 135 | `'mce/v1'` | `'/hospitals/(?P<tenant_id>[a-zA-Z0-9_-]+)/resend-onboarding'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-tenants.php:44` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 136 | `MEDCORE_API_NAMESPACE` | `'/upload'` | `WP_REST_Server::CREATABLE` | `Backend/MedCorePlugin/includes/api/class-api-uploads.php:6` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 137 | `'mce/v1'` | `'/visits'` | `'GET', 'POST'` | `Backend/MedCorePlugin/includes/api/class-api-visits.php:17` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 138 | `'mce/v1'` | `'/visits/(?P<id>[A-Za-z0-9_-]+)'` | `'GET', 'PUT', 'PATCH', 'DELETE'` | `Backend/MedCorePlugin/includes/api/class-api-visits.php:34` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 139 | `'mce/v1'` | `'/visits/(?P<id>[A-Za-z0-9_-]+)/transition'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-visits.php:65` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 140 | `'mce/v1'` | `'/visits/(?P<id>[A-Za-z0-9_-]+)/refund'` | `'POST'` | `Backend/MedCorePlugin/includes/api/class-api-visits.php:75` | `` | G (Backend-Specific Transport) / A (Core Contract) |
| 141 | `$this->namespace` | `'/registry'` | `'GET'` | `Backend/medcore-database-explorer/api/class-dbx-api-router.php:939` | `[ $this, 'verify_super_admin' ]` | G (Admin DB Mirror) |
| 142 | `$this->namespace` | `'/coverage'` | `'GET'` | `Backend/medcore-database-explorer/api/class-dbx-api-router.php:946` | `[ $this, 'verify_super_admin' ]` | G (Admin DB Mirror) |
| 143 | `$this->namespace` | `'/list/(?P<domain>[a-zA-Z0-9_-]+)'` | `'GET'` | `Backend/medcore-database-explorer/api/class-dbx-api-router.php:953` | `[ $this, 'verify_super_admin' ]` | G (Admin DB Mirror) |
| 144 | `$this->namespace` | `'/record/(?P<domain>[a-zA-Z0-9_-]+)/(?P<id>[a-zA-Z0-9_-]+)'` | `'GET'` | `Backend/medcore-database-explorer/api/class-dbx-api-router.php:960` | `[ $this, 'verify_super_admin' ]` | G (Admin DB Mirror) |
| 145 | `$this->namespace` | `'/record/(?P<domain>[a-zA-Z0-9_-]+)/(?P<id>[a-zA-Z0-9_-]+)/relations/(?P<relation>[a-zA-Z0-9_-]+)'` | `'GET'` | `Backend/medcore-database-explorer/api/class-dbx-api-router.php:967` | `[ $this, 'verify_super_admin' ]` | G (Admin DB Mirror) |
| 146 | `$this->namespace` | `'/search'` | `'GET'` | `Backend/medcore-database-explorer/api/class-dbx-api-router.php:974` | `[ $this, 'verify_super_admin' ]` | G (Admin DB Mirror) |
| 147 | `$this->namespace` | `'/compare'` | `'POST'` | `Backend/medcore-database-explorer/api/class-dbx-api-router.php:981` | `[ $this, 'verify_super_admin' ]` | G (Admin DB Mirror) |
| 148 | `$this->namespace` | `'/watcher/verify'` | `'POST'` | `Backend/medcore-database-explorer/api/class-dbx-api-router.php:988` | `[ $this, 'verify_super_admin' ]` | G (Admin DB Mirror) |
| 149 | `$this->namespace` | `'/tenants'` | `'GET'` | `Backend/medcore-database-explorer/api/class-dbx-api-router.php:995` | `[ $this, 'verify_super_admin' ]` | G (Admin DB Mirror) |
| 150 | `$this->namespace` | `'/diagnostics/(?P<section>[a-zA-Z0-9_-]+)'` | `'GET'` | `Backend/medcore-database-explorer/api/class-dbx-api-router.php:1002` | `[ $this, 'verify_super_admin' ]` | G (Admin DB Mirror) |
| 151 | `$this->namespace` | `'/patient-truth/(?P<id>[a-zA-Z0-9_-]+)'` | `'GET'` | `Backend/medcore-database-explorer/api/class-dbx-api-router.php:1009` | `[ $this, 'verify_super_admin' ]` | G (Admin DB Mirror) |
| 152 | `$this->namespace` | `'/field-trace'` | `'GET'` | `Backend/medcore-database-explorer/api/class-dbx-api-router.php:1016` | `[ $this, 'verify_super_admin' ]` | G (Admin DB Mirror) |

## 3. Audit of All `__return_true` Endpoints (Security Exposure Analysis)

| # | Endpoint | File:Line | Internal Auth Check? | Security Verdict |
|---|---|---|---|---|
| 1 | `'mce/v1' :: '/auth/login'` | `Backend/MedCorePlugin/includes/api/class-api-auth.php:6` | None (Public by design or stub) | Public / Auth Entrypoint |
| 2 | `'mce/v1' :: '/auth/verify-admin'` | `Backend/MedCorePlugin/includes/api/class-api-auth.php:11` | None (Public by design or stub) | Public / Auth Entrypoint |
| 3 | `'mce/v1' :: '/auth/request-otp'` | `Backend/MedCorePlugin/includes/api/class-api-auth.php:16` | None (Public by design or stub) | Public / Auth Entrypoint |
| 4 | `'mce/v1' :: '/auth/verify-otp'` | `Backend/MedCorePlugin/includes/api/class-api-auth.php:21` | None (Public by design or stub) | Public / Auth Entrypoint |
| 5 | `'mce/v1' :: '/auth/forgot-password'` | `Backend/MedCorePlugin/includes/api/class-api-auth.php:26` | None (Public by design or stub) | Public / Auth Entrypoint |
| 6 | `'mce/v1' :: '/auth/reset-password'` | `Backend/MedCorePlugin/includes/api/class-api-auth.php:31` | None (Public by design or stub) | Public / Auth Entrypoint |
| 7 | `'mce/v1' :: '/auth/validate-activation'` | `Backend/MedCorePlugin/includes/api/class-api-auth.php:36` | None (Public by design or stub) | Public / Auth Entrypoint |
| 8 | `'mce/v1' :: '/auth/complete-activation'` | `Backend/MedCorePlugin/includes/api/class-api-auth.php:41` | None (Public by design or stub) | Public / Auth Entrypoint |
| 9 | `'medcore/v1' :: '/desktop-version'` | `Backend/MedCorePlugin/includes/api/class-api-desktop.php:6` | None (Public by design or stub) | STUB (`'Migrated functionally with security constraint'`) |
| 10 | `'medcore/v1' :: '/verify-device'` | `Backend/MedCorePlugin/includes/api/class-api-desktop.php:11` | None (Public by design or stub) | CRITICAL STUB: Returns `verified => true` unconditionally (`class-api-desktop.php:47`) |
| 11 | `'medcore/v1' :: '/verify-tenant'` | `Backend/MedCorePlugin/includes/api/class-api-desktop.php:16` | None (Public by design or stub) | Public / Auth Entrypoint |
| 12 | `'medcore/v1' :: '/login'` | `Backend/MedCorePlugin/includes/api/class-api-staff.php:6` | None (Public by design or stub) | Public / Auth Entrypoint |
| 13 | `'medcore/v1' :: '/verify-staff'` | `Backend/MedCorePlugin/includes/api/class-api-staff.php:12` | None (Public by design or stub) | Public / Auth Entrypoint |
| 14 | `'medcore/v1' :: '/verify-admin'` | `Backend/MedCorePlugin/includes/api/class-api-staff.php:17` | None (Public by design or stub) | Public / Auth Entrypoint |
| 15 | `'medcore/v1' :: '/forgot-password'` | `Backend/MedCorePlugin/includes/api/class-api-staff.php:37` | None (Public by design or stub) | Public / Auth Entrypoint |
| 16 | `'medcore/v1' :: '/verify-otp'` | `Backend/MedCorePlugin/includes/api/class-api-staff.php:42` | None (Public by design or stub) | Public / Auth Entrypoint |
| 17 | `'medcore/v1' :: '/reset-password'` | `Backend/MedCorePlugin/includes/api/class-api-staff.php:47` | None (Public by design or stub) | Public / Auth Entrypoint |
| 18 | `'medcore/v1' :: '/activation/validate'` | `Backend/MedCorePlugin/includes/api/class-api-staff.php:52` | None (Public by design or stub) | Public / Auth Entrypoint |
| 19 | `'medcore/v1' :: '/activation/complete'` | `Backend/MedCorePlugin/includes/api/class-api-staff.php:57` | None (Public by design or stub) | Public / Auth Entrypoint |
| 20 | `'mce/v1' :: '/system/legal/terms'` | `Backend/MedCorePlugin/includes/api/class-api-system.php:12` | None (Public by design or stub) | Public / Auth Entrypoint |

## 4. Next.js API Route Inventory (`Frontend/src/app/api/**/route.ts`)

| # | Route Path | File | Exported HTTP Handlers | Classification | Purpose & Security Notes |
|---|---|---|---|---|---|
| 1 | `Frontend/src/app/api/admin-ai/route.ts` | `Frontend/src/app/api/admin-ai/route.ts` | `POST` | `F (Web-Specific)` | Admin AI assistant proxy to Groq/Gemini; NO user auth check in route handler (`admin-ai/route.ts:1-97`). |
| 2 | `Frontend/src/app/api/ai-doctor/route.ts` | `Frontend/src/app/api/ai-doctor/route.ts` | `POST` | `F (Web-Specific)` | Clinical AI proxy to Groq/Gemini; fetches raw keys via `X-MedCore-Server-Action: fetch-ai-keys`; NO user auth check in route handler (`ai-doctor/route.ts:1-341`). |
| 3 | `Frontend/src/app/api/ai-wallet/route.ts` | `Frontend/src/app/api/ai-wallet/route.ts` | `GET, POST` | `F (Web-Specific)` | Next.js server proxy / helper |
| 4 | `Frontend/src/app/api/checkout/route.ts` | `Frontend/src/app/api/checkout/route.ts` | `POST` | `F (Web-Specific)` | Next.js server proxy / helper |
| 5 | `Frontend/src/app/api/debug/route.ts` | `Frontend/src/app/api/debug/route.ts` | `GET` | `F (Web-Specific)` | Next.js server proxy / helper |
| 6 | `Frontend/src/app/api/desktop-version/route.ts` | `Frontend/src/app/api/desktop-version/route.ts` | `GET` | `F (Web-Specific)` | Next.js server proxy / helper |
| 7 | `Frontend/src/app/api/interactions/route.ts` | `Frontend/src/app/api/interactions/route.ts` | `GET` | `F (Web-Specific)` | Next.js server proxy / helper |
| 8 | `Frontend/src/app/api/license/route.ts` | `Frontend/src/app/api/license/route.ts` | `GET` | `F (Web-Specific)` | Proxies license check to WP `/wp-json/mce/v1/license` (`license/route.ts:1-39`). |
| 9 | `Frontend/src/app/api/pricing-plans/route.ts` | `Frontend/src/app/api/pricing-plans/route.ts` | `GET` | `F (Web-Specific)` | Next.js server proxy / helper |
| 10 | `Frontend/src/app/api/send-debug-error/route.ts` | `Frontend/src/app/api/send-debug-error/route.ts` | `POST` | `F (Web-Specific)` | Next.js server proxy / helper |
| 11 | `Frontend/src/app/api/send-report/route.ts` | `Frontend/src/app/api/send-report/route.ts` | `POST` | `F (Web-Specific)` | Next.js server proxy / helper |
| 12 | `Frontend/src/app/api/upload/route.ts` | `Frontend/src/app/api/upload/route.ts` | `POST` | `F (Web-Specific)` | Next.js server proxy / helper |
| 13 | `Frontend/src/app/api/storage/presign/route.ts` | `Frontend/src/app/api/storage/presign/route.ts` | `POST` | `F (Web-Specific)` | Next.js server proxy / helper |
| 14 | `Frontend/src/app/api/storage/[tenant]/[key]/route.ts` | `Frontend/src/app/api/storage/[tenant]/[key]/route.ts` | `GET, POST` | `F (Web-Specific)` | Next.js server proxy / helper |