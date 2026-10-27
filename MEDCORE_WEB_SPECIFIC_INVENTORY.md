# MEDCORE — WEB-SPECIFIC INVENTORY (`CATEGORY F` — DO NOT PORT TO FLUTTER)
**Document ID**: `DOC-15A` | **Source**: `Frontend/src/**`

## 1. Summary of Web-Only Artifacts (`Category F`)
The following `Project 3` frontend mechanisms exist solely because of the browser/Next.js runtime and **MUST NOT** be ported to `MedCore Desktop`:

| # | Web-Specific Artifact | Location in `Project 3` | Why It Exists in Web | `MedCore Desktop` Replacement |
|---|---|---|---|---|
| 1 | Next.js App Router & SSR/CSR Hydration | `Frontend/src/app/**/layout.tsx`, `next.config.mjs` | Browser routing & React server component bundling | Flutter declarative router (`GoRouter` / `Navigator 2.0`) with offline role/license route guards. |
| 2 | Browser `localStorage` & `sessionStorage` Persistence (92 hits) | `Frontend/src/lib/tenantStorage.ts`, 48 Zustand stores | Persisting client state across browser tab refreshes | Direct LAN queries + WebSocket streams against `Local MedCore Service` (`Local MariaDB` is the single source of truth). |
| 3 | Next.js Server API Proxies (14 routes) | `Frontend/src/app/api/**/route.ts` | Avoiding browser CORS and hiding WordPress URLs | Eliminated: Flutter talks directly to `Local MedCore Service` over LAN HTTPS; AI calls route through `Local MedCore Service -> Cloud AI Gateway`. |
| 4 | User-Agent Desktop Spoofing Check | `Frontend/src/components/PermissionGuard.tsx:199` | Checking `navigator.userAgent.includes('MedcoreDesktop')` | Replaced by native OS executable + Ed25519 device key signature (`X-MedCore-Device-Sig`). |
| 5 | Browser `window.print()` CSS Media Queries | `Frontend/src/components/*Print*.tsx` | Printing invoices/lab reports via Chrome print dialog | Native ESC/POS thermal printing, ZPL barcode label printing, and native PDF generation in Flutter. |
