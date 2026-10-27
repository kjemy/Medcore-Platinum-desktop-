# MEDCORE PROJECT 4 — RECONNAISSANCE CONVENTIONS (BINDING FOR ALL WORKSTREAMS)

Source under analysis (read-only): `C:\Users\hp\Desktop\project 3`
Original reference (never touched except read-only hash parity): `C:\Users\hp\Desktop\project2`
Output workspace: `C:\Users\hp\Desktop\project 4`
Recon date: 2026-10-27

## 1. Safety decisions (agreed with the user, Q1–Q6)
| # | Decision |
|---|---|
| Q1 | **STRICTLY STATIC.** Read files only. Never connect to any remote server/DB/API. Never execute any Project 3 script (py/js/php). Live-DB facts are labelled `UNVERIFIED-RUNTIME`. |
| Q2 | Code / schema / migrations = **FACT**. `REPORTS/*.md`, `docs/`, `MEDCORE_ENGINEERING_HISTORY.md`, `.md` plans = **DOCUMENTED CLAIM** (cite them; promote to FACT only if code confirms; contradictions → `SOURCE CONFLICT`). |
| Q3 | English technical body. Arabic UI labels / business terms quoted verbatim from code. Final report gets a short Arabic executive summary. |
| Q4 | **Core tier**: `Frontend/src`, `Backend/MedCorePlugin` (incl. `medcore.php`, `includes/`, `admin/`), `Backend/medcore-database-explorer`, schema/migrations, `Frontend/docs`. **Secondary tier** (scan for risks/evidence only, NOT product logic): root scripts in `project 3\*.py|js|php`, `Frontend\*.js|py` patch scripts, `Frontend/tests`, `Frontend/scripts`, `Frontend/tools`, `stage_frontend`, `plugins_extracted`, `medcore-ai-manager`, `prisma`, `temp_prisma`. **Excluded**: `node_modules`, `.next`, `.git` internals, binaries (`.dll/.exe/.zip/.gz/.phar/.lib`). |
| Q5 | **Never copy secret values** (passwords, API keys, tokens, SSH creds, connection strings). Record `file:line`, secret type, risk; value = `[REDACTED]`. Real patient/staff names/phones/emails seen in code/fixtures → `[REDACTED-PII]`. |
| Q6 | Read-only hash parity Project 3 vs project2 (source only); report drift in 99_EVIDENCE. Project 3 remains the analysis source. |

Allowed git usage: `git -C <repo> --no-optional-locks <log|show|rev-parse|diff|ls-files|status --porcelain>` only. No fetch/pull/checkout/commit/stash/reset.
Never write, create, rename or delete anything inside `project 3` or `project2`. Do not run `npm`, `npx`, `composer`, `tsc`, `php` inside them (these can write caches).

## 2. Evidence labels (mandatory on every claim)
- `FACT` — proven by code/schema; cite `relative/path:line` (relative to `project 3\`).
- `INFERENCE` — derived from ≥2 pieces of evidence; cite them.
- `ASSUMPTION` — needs a decision; never presented as fact.
- `DOCUMENTED CLAIM` — stated in reports/docs, not confirmed in code.
- `UNKNOWN` — cannot be proven from the repo.
- `UNVERIFIED-RUNTIME` — depends on live DB/server state.
- `SOURCE CONFLICT` — two sources disagree (e.g., frontend vs backend); show both + proposed resolution.

Citation format: `` `Backend/MedCorePlugin/includes/core/class-medcore-visit-service.php:L120-L188` ``.

## 3. Classification categories (from mission §6)
A CORE BUSINESS LOGIC · B DOMAIN MODEL · C SECURITY/AUTHZ · D FINANCIAL · E CLINICAL · F WEB-SPECIFIC · G BACKEND-SPECIFIC · H OFFLINE GAP · I MISSING CAPABILITY · J UNKNOWN/NEEDS DECISION

## 4. ID namespaces (avoid collisions between workstreams)
| Item | Pattern | Owner |
|---|---|---|
| Business rules | `FIN-<AREA>-NNN` (AREA: INV, PAY, EVT, PST, SHF, TRS, COM, ERN, SET, REF, REV, IDM, WAL, RPT, INS) | WS3 Financial |
| Business rules | `CLN-<AREA>-NNN` (AREA: PAT, VIS, APT, QUE, ORD, LAB, RAD, PHR, ICU, DIA, SUR, ADM, NUR, ENC, TPL, INV) | WS4 Clinical |
| Business rules | `SEC-<AREA>-NNN` (AREA: AUTH, PERM, ROLE, SCOPE, AUD, TEN, LIC, DEV, SYNC) | WS5 Identity/Security |
| Business rules | `DAT-<AREA>-NNN` (schema-level invariants: UNQ, FK, IDM, AUD, TEN) | WS1 Database |
| Business rules | `UI-<AREA>-NNN` (validation/business rules found only in frontend) | WS6 Frontend |
| Risks | `RSK-<WS>-NNN` (WS ∈ DB, API, FIN, CLN, SEC, FE, SCAN) | each WS |
| Unknowns | `UNK-<WS>-NNN` | each WS |
| Source conflicts | `CONFLICT-<WS>-NNN` | each WS |
| Gap candidates | `GAPC-<WS>-NNN` (consolidated later into `GAP-NNN`) | each WS |

Each business rule entry must contain: Rule ID · Name · Category (A–J) · Current implementation · Source file(s) · Source layer (FE/BE/DB) · Inputs · Conditions · Outputs · Side effects · Persistence requirement · Security requirement · Offline requirement · Future implementation recommendation · Evidence (path:line) · Confidence (High/Med/Low) · Label (FACT/INFERENCE/…).

Do not invent rules. No evidence → `UNKNOWN`.

## 5. Offline readiness vocabulary
`ONLINE READY` · `OFFLINE READY` · `HYBRID` · `REQUIRES REDESIGN` · `UNKNOWN`

## 6. Target architecture reminder (user-mandated, not up for debate)
Flutter Client → Local MedCore Service → Local MariaDB (source of truth).
Local MedCore Service → WordPress Control Plane ONLY for license/renewal/entitlements/edition/modules/device limits/AI entitlement/(optional) updates.
No Flutter → Next.js → WordPress. No provider master AI keys in Flutter. No permanent master password/backdoor. Technician access = formal, temporary, authenticated, audited.
No premature technology lock-in (packages, drivers, frameworks, crypto libs, AI providers).
