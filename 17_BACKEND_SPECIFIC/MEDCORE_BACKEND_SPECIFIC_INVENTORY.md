# MEDCORE — BACKEND-SPECIFIC & API CONTRACT INVENTORY (`CATEGORY G` vs `CATEGORY A`)
**Document ID**: `DOC-15B` | **Source**: `Backend/MedCorePlugin/**` & `99_EVIDENCE/WS2_FINDINGS.md`

## 1. WordPress Runtime Artifacts to Discard (`Category G`)
| # | WordPress-Specific Mechanism | Location in `Project 3` | Replacement in `Local MedCore Service` |
|---|---|---|---|
| 1 | WordPress Plugin Bootstrap & Hooks (`add_action('rest_api_init')`) | `Backend/MedCorePlugin/medcore.php` | Standalone Local MedCore Service binary/daemon running as a Windows Service on the Hospital Host. |
| 2 | `dbDelta()` Schema Creation (No Foreign Keys) | `Backend/MedCorePlugin/medcore.php:150-880` | Deterministic versioned SQL migrations (`V001__init.sql` .. `V010__desktop_tables.sql`) with strict `InnoDB` `FOREIGN KEY` constraints. |
| 3 | WordPress Transients for Auth Tokens (`set_transient('mc_token_...')`) | `includes/domain/staff/class-auth-service.php:60` | Dedicated `mc_auth_sessions` table in Local MariaDB bound to `(staff_id, hospital_code, device_id)`. |
| 4 | `wp_options` & `wp_usermeta` Calls | `class-api-saas-extended.php`, `class-api-ai-extra.php` | Dedicated `mc_local_meta` and `mc_license_state` tables in Local MariaDB. |
| 5 | Hostinger Deployment & One-Off Patch Scripts | `Frontend/deploy.js`, root `*.php`/`*.py` scripts | Signed MSIX / Windows Installer package + Technician Service Tool migration runner. |

## 2. Canonical API Contract Inventory (152 Backend Routes + 14 Next.js Routes)
The complete 152-route specification (with exact namespace, path, HTTP method, controller `file:line`, and permission callback) is cataloged in [`WS2_FINDINGS.md`](file:///C:/Users/hp/Desktop/project%204/99_EVIDENCE/WS2_FINDINGS.md).
- **124 Core Hospital Operational Routes (`medcore/v1/*`, `mce/v1/financial/*`)**: Ported to **Local MedCore Service** over LAN (`/api/v1/*`).
- **18 SaaS & Licensing Routes (`mce/v1/license`, `medcore-SaaS/v1/*`)**: Retained on **WordPress Control Plane** (hardened with Ed25519 lease signing).
- **6 AI Routes (`medcore-ai/v1/*`, `mce/v1/ai/*`)**: Redesigned into **Cloud AI Gateway** (`GET /medcore-ai/v1/keys` permanently deleted).
- **4 DB Explorer Routes (`medcore-dbx/v1/*`)**: Ported into **Technician Service Tool** local diagnostic inspector.
