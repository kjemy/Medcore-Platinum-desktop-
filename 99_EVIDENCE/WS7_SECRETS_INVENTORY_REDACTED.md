# WS7 — Redacted Secrets & Credential Exposure Inventory (`Project 3`)

> **Classification**: `FACT` — Adheres strictly to `00_RECON_CONVENTIONS.md` Rule Q5 (`[REDACTED]` value policy).

## 1. Hardcoded Credentials & Keys Found in Repository
| # | File:Line | Tier | Secret Type | Redacted Snippet | Security Risk & Required Remediation |
|---|---|---|---|---|---|
| 1 | `verify_medcore_e2e_lifecycle.py:235` | `SECONDARY` | WordPress Admin / Test Credential | `password = "[REDACTED]"` | Hardcoded credential in E2E verification script. Must never ship in client/desktop artifacts; rotate credential on remote server. |
| 2 | `Frontend/deploy.js:33` | `SECONDARY` | Hostinger SSH / SFTP Deployment Password | `password: "[REDACTED]"` | **CRITICAL INFRASTRUCTURE EXPOSURE**: Plaintext server deployment password committed in `Frontend/deploy.js`. Rotate SSH/SFTP password immediately and purge from git history. |
| 3 | `Backend/MedCorePlugin/includes/api/class-api-ai.php:12-18` | `CORE_BACKEND` | Runtime Master API Key Endpoint (`Groq` / `Gemini`) | `X-MedCore-Server-Action: fetch-ai-keys` -> returns `groq_api_key: "[REDACTED]"`, `gemini_api_key: "[REDACTED]"` | **CRITICAL RUNTIME EXPOSURE**: Unauthenticated endpoint returns master AI provider keys to anyone sending a static HTTP header. |
