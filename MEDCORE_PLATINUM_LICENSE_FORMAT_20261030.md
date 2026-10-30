# MEDCORE PLATINUM DESKTOP
# OFFLINE SIGNED LICENSE FORMAT SPECIFICATION (`.mclic`)
## FORMAT DEFINITION, CRYPTOGRAPHIC SIGNATURE & VALIDATION PROTOCOL (RUN #14/15)

**Project:** MedCore Platinum Desktop  
**Date:** October 30, 2026  
**Format Version:** `MEDCORE_LIC_V1`  

---

## 1. LICENSE TOKEN ENCODING STRUCTURE

A MedCore Platinum offline license token (`.mclic`) is a compact, URL-safe string composed of three dot-delimited segments:

```text
MEDCORE_LIC_V1.<base64url_payload>.<base64url_signature>
```

### Segment Breakdown:
1. **Segment 0 (Header Prefix)**: Constant ASCII string `MEDCORE_LIC_V1`. Specifies format version and indicates RSA-2048 PKCS#1 v1.5 with SHA-256 digital signature.
2. **Segment 1 (Payload)**: Base64URL-encoded UTF-8 JSON object containing all license lease claims, facility bindings, hardware fingerprint, and validity periods.
3. **Segment 2 (Signature)**: Base64URL-encoded 256-byte RSA-2048 signature computed over the ASCII byte sequence: `MEDCORE_LIC_V1.<base64url_payload>`.

---

## 2. CANONICAL PAYLOAD SCHEMA (JSON)

```json
{
  "v": 1,
  "lid": "LIC-ANNUAL-ENTERPRISE-2027",
  "hosp": "HOSP_MAIN",
  "inst": "INST-HOSP-MAIN-001",
  "hw": "E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855",
  "ed": "PLATINUM",
  "iat": "2026-10-30T10:00:00.000Z",
  "nbf": "2026-10-30T10:00:00.000Z",
  "exp": "2027-10-30T10:00:00.000Z",
  "grace": "2027-11-13T10:00:00.000Z",
  "maint_exp": "2027-10-30T10:00:00.000Z",
  "max_dev": 50,
  "max_doc": 100,
  "mods": {
    "Patients": true,
    "Clinical": true,
    "Emergency": true,
    "Surgery": true,
    "Inpatient": true,
    "Pharmacy": true,
    "Laboratory": true,
    "Radiology": true,
    "Finance": true,
    "Billing": true,
    "Reports": true,
    "Audit": true
  },
  "allow_read_only": true
}
```

### Field Definitions:

| Field | Type | Mandatory | Description |
|---|---|---|---|
| `v` | `int` | Yes | Token schema version; must be `1`. |
| `lid` | `String` | Yes | Unique authoritative license identifier issued by Orbit Software. |
| `hosp` | `String` | Yes | Authorized hospital / tenant facility code (`mc_tenants.hospital_code`). |
| `inst` | `String` | Yes | Facility installation identity string. |
| `hw` | `String` | Yes | Expected 64-character SHA-256 hardware fingerprint of the physical machine. |
| `ed` | `String` | Yes | Licensed product edition (`COMMUNITY`, `PROFESSIONAL`, `ENTERPRISE`, `PLATINUM`). |
| `iat` | `String (ISO 8601)` | Yes | Issued-at UTC timestamp. |
| `nbf` | `String (ISO 8601)` | Yes | Not-before UTC timestamp. Token is invalid prior to this moment. |
| `exp` | `String (ISO 8601)` | Yes | Subscription expiration UTC timestamp. |
| `grace` | `String (ISO 8601)` | No | Offline grace period expiration UTC timestamp. |
| `maint_exp` | `String (ISO 8601)` | Yes | Software maintenance & updates entitlement expiration UTC timestamp. |
| `max_dev` | `int` | No | Maximum permitted concurrent client device workstations (default: 25). |
| `max_doc` | `int` | No | Maximum registered physician / doctor accounts (default: 50). |
| `mods` | `Map<String, bool>` | Yes | Explicit map of enabled clinical and financial modules. |
| `allow_read_only` | `bool` | No | Safety invariant flag permitting read-only patient chart access post-expiration (default: `true`). |

---

## 3. CRYPTOGRAPHIC SIGNATURE & VERIFICATION ALGORITHM

### 3.1 Signing Algorithm (Orbit Authority):
1. Construct payload JSON and serialize to UTF-8 without whitespace.
2. Base64URL-encode payload without padding (`=`).
3. Construct message string: `M = "MEDCORE_LIC_V1." + payloadB64`.
4. Hash message using SHA-256: `H = SHA256(UTF8(M))`.
5. Encode digest into PKCS#1 v1.5 padding block for 2048-bit modulus:
   ```text
   EM = 0x00 || 0x01 || PS (0xFF bytes) || 0x00 || DigestInfo(SHA256, H)
   ```
6. Sign block using Orbit Software private key: `S = EM^d mod n`.
7. Base64URL-encode 256-byte signature without padding.
8. Output token: `MEDCORE_LIC_V1.<payloadB64>.<sigB64>`.

### 3.2 Verification Algorithm (MedCore Local Service):
1. Split token by `.`. Assert exactly 3 segments and segment 0 equals `MEDCORE_LIC_V1`.
2. Extract message bytes: `messageBytes = UTF8(token.substring(0, token.lastIndexOf('.')))`.
3. Decode signature bytes from Base64URL segment 2. Assert length is exactly 256 bytes.
4. Perform modular exponentiation with public key: `EM = S^e mod n`.
5. Verify PKCS#1 v1.5 padding structure: starts with `0x00 0x01`, followed by `0xFF` bytes, delimiter `0x00`, and SHA-256 DigestInfo prefix.
6. Compute `SHA256(messageBytes)` and compare using constant-time comparison against extracted hash.
7. If any check fails, reject token immediately.

---

## 4. SAMPLE PRODUCTION TOKEN

```text
MEDCORE_LIC_V1.eyJ2IjoxLCJsaWQiOiJMSUMtQU5OVUFMLUVOVEVSUFJJU0UtMjAyNyIsImhvc3AiOiJIT1NQX01BSU4iLCJpbnN0IjoiSU5TVC1IT1NQLU1BSU4tMDAxIiwiaHciOiJFM0IwQzQ0Mjk4RkMxQzE0OUFGQkY0Qzg5OTZGQjkyNDI3QUU0MUU0NjQ5QjkzNENBNDk1OTkxQjc4NTJCODDUiLCJlZCI6IlBMQVRJTlVNIiwiaWF0IjoiMjAyNi0xMC0zMFQxMDowMDowMC4wMDBaIiwibmJmIjoiMjAyNi0xMC0zMFQxMDowMDowMC4wMDBaIiwiZXhwIjoiMjAyNy0xMC0zMFQxMDowMDowMC4wMDBaIiwibWFpbnRfZXhwIjoiMjAyNy0xMC0zMFQxMDowMDowMC4wMDBaIiwibW9kcyI6eyJQYXRpZW50cyI6dHJ1ZSwiU3VyZ2VyeSI6dHJ1ZSwiRmluYW5jZSI6dHJ1ZX19.bXlkdW1teXNpZ25hdHVyZXRva2VuZXhhbXBsZTIwNDhiaXRzcGtjczFzaGExMjU2ZGF0YXRvYmVsYXJnZXJlbm91Z2h0b2ZpdHZhcmlvdXNjYXNlc2FuZGV4YW1wbGVzb2ZzaWduZWRwYXlsb2Fkc3ZlcmlmaWVkYnlvcmJpdHNvZnR3YXJlYXV0aG9yaXR5...
```

---

## 5. STORAGE & RECONCILIATION ON DISK

The active token is persisted on the hospital host at:
`runtime/security/license.mclic`

During startup or periodic validation:
1. `license.mclic` is read from disk and cryptographically validated.
2. Verified claims are synchronized to MariaDB `mc_license_state`.
3. HMAC seal is updated in MariaDB to bind the cached row to local secrets.
4. If `license.mclic` is missing or corrupted, the system falls back to the sealed database cache before failing closed to `UNLICENSED`.
