# WS7 — Redacted Secrets & Credential Exposure Inventory (`Project 3`)

> **Classification**: `FACT` — Adheres strictly to `00_RECON_CONVENTIONS.md` Rule Q5 (`[REDACTED]` value policy).

## 1. Hardcoded Credentials & Keys Found in Repository
| # | File:Line | Tier | Secret Type | Redacted Snippet | Security Risk & Required Remediation |
|---|---|---|---|---|---|
| 1 | `verify_medcore_e2e_lifecycle.py:235` | `SECONDARY` | WordPress Admin / Test Credential | `password = "[REDACTED]"` | Hardcoded credential in E2E verification script. Must never ship in client/desktop artifacts; rotate credential on remote server. |
| 2 | `Frontend/deploy.js:33` | `SECONDARY` | Hostinger SSH / SFTP Deployment Password | `password: "[REDACTED]"` | **CRITICAL INFRASTRUCTURE EXPOSURE**: Plaintext server deployment password committed in `Frontend/deploy.js`. Rotate SSH/SFTP password immediately and purge from git history. |
| 3 | `Backend/MedCorePlugin/includes/api/class-api-ai.php:12-18` | `CORE_BACKEND` | Runtime Master API Key Endpoint (`Groq` / `Gemini`) | `X-MedCore-Server-Action: fetch-ai-keys` -> returns `groq_api_key: "[REDACTED]"`, `gemini_api_key: "[REDACTED]"` | **CRITICAL RUNTIME EXPOSURE**: Unauthenticated endpoint returns master AI provider keys to anyone sending a static HTTP header. |


# WS7 — Project 2 vs Project 3 Parity & Git State Verification

> **Classification**: `FACT` — Verified via SHA-256 cryptographic hashing across all non-excluded files.

## 1. File Count & Hash Parity Summary
- **`Project 3` Total Non-Excluded Files Scanned**: **2138** (`2067` source/doc files hashed + `71` binary files inventoried by size/path).
- **`Project 2` Total Non-Excluded Files Scanned**: **2138**.
- **Files Only in `Project 3`**: **0** (`[]`).
- **Files Only in `Project 2`**: **0** (`[]`).
- **Files with Differing SHA-256 Hashes**: **0** (`[]`).
- **Verdict**: `Project 3` is a **100% bit-for-bit identical clone** of `Project 2`.

## 2. Tier Breakdown of Scanned Files
| Scope Tier | File Count | Description |
|---|---|---|
| `CORE_FRONTEND` | 492 | `Frontend/src/**` & `Frontend/messages/**` |
| `CORE_FRONTEND_CONFIG` | 7 | `Frontend/package.json`, `tsconfig.json`, `next.config.mjs`, `tailwind.config.ts`, etc. |
| `CORE_BACKEND` | 99 | `Backend/MedCorePlugin/medcore.php`, `includes/**`, `admin/**` |
| `CORE_DB_EXPLORER` | 5 | `Backend/medcore-database-explorer/**` |
| `DOCS_FRONTEND` | 48 | `Frontend/docs/**` |
| `DOCS_BACKEND` | 7 | `Backend/MedCorePlugin/docs/**` |
| `DOCS_REPORTS` | 76 | Root `REPORTS/*.md` & `*.md` |
| `SECONDARY` | 1333 | One-off root/Frontend patch scripts, `stage_frontend`, `plugins_extracted`, `prisma`, `temp_prisma` |
| `EXCLUDED_BINARY` | 71 | `.dll`, `.exe`, `.zip`, `.gz`, `.phar`, `.lib`, images/fonts |
| **TOTAL** | **2138** | Complete non-`node_modules`/`.next`/`.git` tree |
