# MEDCORE — OFFLINE GAP ANALYSIS & HOSPITAL LAN ARCHITECTURE BLUEPRINT (`CATEGORY H`)
**Document ID**: `DOC-10` | **Source**: `Frontend/src/lib/offlineSync.ts`, `Backend/MedCorePlugin/includes/api/class-api-sync.php`

---

## 1. Current Offline Reality in `Project 3` (`FACT`)
- **Frontend (`Frontend/src/lib/offlineSync.ts:24`)**:
  ```ts
  const OFFLINE_ALLOWED_COMMANDS = new Set(['patient:create']);
  ```
- **Backend (`Backend/MedCorePlugin/includes/api/class-api-sync.php:91`)**:
  ```php
  if ($entity_type === 'patient' && $operation === 'create') { ... }
  ```
- **Verdict (`OFF-GAP-01`)**: Despite numerous markdown reports in `REPORTS/` claiming offline capabilities, **99% of MedCore in `Project 3` cannot function offline**. Visits, cashier shifts, invoice payments, refunds, commission accruals, lab orders/results, radiology reports, pharmacy dispensing, inventory movements, inpatient admissions, ICU/NICU flows, surgeries, and dialysis sessions all fail immediately without internet connectivity to the remote WordPress server.

---

## 2. Target Offline-First Hospital LAN Architecture (`MedCore Desktop`)

### 2.1 Architectural Shift: Eliminate Browser-to-Cloud Sync Queues for Daily Operations
In `MedCore Desktop`, "Offline" means **the hospital has zero internet connectivity to the outside world**, while **the internal Hospital LAN (Ethernet / Wi-Fi) connects all workstation and tablet Flutter clients to the on-premise Hospital Server running Local MedCore Service + Local MariaDB**.

```mermaid
sequenceDiagram
    participant C1 as Flutter Reception Desktop (LAN)
    participant C2 as Flutter Doctor Tablet (Wi-Fi LAN)
    participant LMS as Local MedCore Service (Hospital Server)
    participant MDB as Local MariaDB (ACID Storage)
    participant WP as WordPress Control Plane (Internet - Optional)

    Note over C1,MDB: 100% Offline Hospital LAN Operation (Zero Internet Required)
    C1->>LMS: POST /api/v1/visits (Idempotency-Key, Device-Sig)
    LMS->>MDB: START TRANSACTION; Lock Patient, Shift, StockBatch; Insert Visit + Financial Postings; COMMIT
    MDB-->>LMS: Committed (visit_id, invoice_no, receipt_payload)
    LMS-->>C1: 201 Created (Authoritative Receipt)
    LMS-->>C2: WebSocket Event: queue.updated (Doctor Queue Instant Refresh)

    Note over LMS,WP: Optional Background Control-Plane Heartbeat (When Internet Available)
    LMS--)WP: POST /wp-json/mce/v1/license/heartbeat (hospital_code, server_fingerprint)
    WP--)LMS: 200 OK (Signed Ed25519 License Lease Renewal)
```

### 2.2 LAN Topology & Discovery Specification
1. **On-Premise Host Node (`Hospital Server` / `Standalone Single-PC Mode`)**:
   - Runs **Local MariaDB** (`127.0.0.1:3306`, bound strictly to loopback so no client device can connect directly to the SQL port).
   - Runs **Local MedCore Service** listening on `0.0.0.0:8443` (HTTPS with Hospital Local Root CA + mTLS/Device Signature verification) and `127.0.0.1:8443` (for Single-PC standalone mode where Flutter Desktop and Local MedCore Service run on the same Windows machine).
2. **Client Discovery & Pairing**:
   - Primary: Explicit static LAN IP / Hostname (`https://medcore-server.local:8443` or `https://192.168.1.10:8443`) + QR Code pairing from the Hospital Admin screen for Android/iPad tablets.
   - Secondary: mDNS / DNS-SD broadcast (`_medcore._tcp.local.`) on the hospital subnet.
3. **Real-Time LAN Event Bus**:
   - Local MedCore Service exposes a multiplexed **WebSocket (`wss://<server>:8443/ws/events`)** broadcasting domain events (`queue.visit_created`, `lab.critical_result`, `bed.status_changed`, `shift.closed`) so all connected Flutter screens update in `< 100ms` without polling.
4. **Client Network-Blip Resilience (Short Wi-Fi Drop on Tablets)**:
   - Flutter clients maintain a lightweight encrypted local SQLite/Drift cache for **read-only reference catalogs** (`definitions`, ICD-10 codes, drug catalog) and an **idempotent request retry buffer** (using UUIDv7 `idempotency_key`) so a 5-second Wi-Fi roam between hospital floors never loses a form submission or double-charges a patient.
