# GATE 07 — HARDWARE / MACHINE BINDING REPORT

**Project:** MedCore Platinum Desktop  
**Path:** `C:\Users\hp\Desktop\project 4`  
**Timestamp:** 2026-10-31T02:38:00+02:00  
**Overall Status:** PASS  

---

## 1. Hardware Fingerprinting Architecture
- Machine Identifiers: Composite SHA-256 hash derived from CPU processor ID, Motherboard serial number, and primary Drive volume serial.
- Normalization & Stability: Resilient against non-critical peripheral changes while strictly identifying host workstation.
- License Lease Binding: The offline license contains `hw` claim matching the machine fingerprint hash.

---

## 2. Adversarial Test Evidence
- Tested in `batch18_commercial_rights_and_offline_licensing_test.dart` and `batch19_independent_certification_gates_03_to_07_test.dart`.
- Cloned database attack: Importing valid license on different machine fingerprint fails closed with `HARDWARE_MISMATCH_ERROR`.
- Spoofed fingerprint: Verification confirms exact 64-char hex match; partial spoofing is rejected.
- Legitimate host stability: Unaltered host maintains consistent fingerprint across restarts.

**Evidence Artifact:** `07_HARDWARE/gate07_results.json`
