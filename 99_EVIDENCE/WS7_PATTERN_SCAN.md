# WS7 — Static Code Pattern & Risk Scan (`Project 3`)

> **Classification**: `FACT` — Automated regex scan across all 603 Core Frontend and Core Backend files.

## 1. Pattern Hit Counts Across Core Tiers

| Pattern Category | Core Frontend Hits | Core Backend Hits | Total Core Hits | Architectural Meaning |
|---|---|---|---|---|
| `Math_random_Date_now` | 204 | 0 | 204 | Verified in static scan |
| `TODO_FIXME_HACK` | 0 | 0 | 0 | Verified in static scan |
| `dangerouslySetInnerHTML_eval` | 4 | 0 | 4 | Verified in static scan |
| `fallback` | 70 | 22 | 92 | Verified in static scan |
| `hardcoded_domains` | 18 | 9 | 27 | Verified in static scan |
| `localStorage_sessionStorage` | 92 | 0 | 92 | Verified in static scan |
| `mock_dummy_fake` | 7 | 2 | 9 | Verified in static scan |
| `parseFloat` | 28 | 0 | 28 | Verified in static scan |
| `return_true_perm` | 0 | 20 | 20 | Verified in static scan |
| `ts_ignore_eslint_disable` | 4 | 0 | 4 | Verified in static scan |

## 2. Detailed Sample Hits per Pattern (Core Frontend & Core Backend)

### Pattern: `Math_random_Date_now`
| # | Sample Hit (`File:Line: Snippet`) |
|---|---|
| 1 | `Frontend/src/lib/api.ts:L65: : 'req-' + Date.now() + '-' + Math.random().toString(36).slice(2);` |
| 2 | `Frontend/src/lib/api.ts:L69: (config as any).__medcoreStartedAt = typeof performance !== 'undefined' && performance.now ? performance.now() : Date.now();` |
| 3 | `Frontend/src/lib/api.ts:L98: durationMs: started ? ((typeof performance !== 'undefined' && performance.now ? performance.now() : Date.now()) - started) : undefined,` |
| 4 | `Frontend/src/lib/clinicalTemplatesApi.ts:L6: export async function createClinicalTemplate(input:Omit<ClinicalTemplate,'id'\|'version'\|'status'\|'templateNumber'>):Promise<ClinicalTemplate` |
| 5 | `Frontend/src/lib/clinicalTemplatesApi.ts:L8: export async function useClinicalTemplate(id:string,input:{encounterId?:string;patientId?:string;providerId?:string;usedBy?:string;snapshot?` |
| 6 | `Frontend/src/lib/definitionsApi.ts:L23: return safe \|\| `${type}_${Date.now()}`;` |
| 7 | `Frontend/src/lib/mockApi.ts:L39: visitId: `v_${Date.now()}`,` |
| 8 | `Frontend/src/lib/mockApi.ts:L69: data: { id: `pat_${Date.now()}`, ...patientData, registeredAt: new Date().toISOString() },` |
| 9 | `Frontend/src/lib/mockApi.ts:L98: data: { orderId: `lab_${Date.now()}`, patientId, testCodes, status: 'pending_specimen' },` |
| 10 | `Frontend/src/lib/mockApi.ts:L120: data: { poId: `po_${Date.now()}`, vendorId, items, totalAmount, status: 'submitted' },` |
| 11 | `Frontend/src/lib/mockApi.ts:L145: data: { id: `pat_${Date.now()}`, ...patientData },` |
| 12 | `Frontend/src/lib/mockApi.ts:L185: data: { id: `apt_${Date.now()}`, ...bookingData, createdAt: new Date().toISOString(), status: 'scheduled' },` |
| 13 | `Frontend/src/lib/mockApi.ts:L218: data: { encounterId: encounter.encounterId \|\| `enc_${Date.now()}` },` |
| 14 | `Frontend/src/lib/offlineSync.ts:L77: : 'device-' + Date.now() + '-' + Math.random().toString(36).slice(2);` |
| 15 | `Frontend/src/lib/offlineSync.ts:L108: : 'cmd-' + Date.now() + '-' + Math.random().toString(36).slice(2)),` |
| 16 | `Frontend/src/lib/offlineSync.ts:L162: const cutoff = Date.now() - maxAgeMs;` |
| 17 | `Frontend/src/lib/offlineSync.ts:L190: const now = Date.now();` |
| 18 | `Frontend/src/lib/offlineSync.ts:L223: const now = Date.now();` |
| 19 | `Frontend/src/lib/offlineSync.ts:L289: await updateCommand({ ...command, status: 'PENDING', last_error: error?.message \|\| 'sync_failed', next_retry_at: Date.now() + delayMs });` |
| 20 | `Frontend/src/lib/shiftApi.ts:L30: const cmd = commandId \|\| `cmd-shift-open-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;` |
| 21 | `Frontend/src/lib/tenantStorage.ts:L102: const cacheBuster = Date.now();` |
| 22 | `Frontend/src/lib/tenantStorage.ts:L227: fetch(`${getStorageApiBase()}/storage/${code}/${name}?cb=${Date.now()}`, {` |
| 23 | `Frontend/src/lib/tenantStorage.ts:L239: fetch(`${getStorageApiBase()}/storage/${code}/${name}?cb=${Date.now()}`, {` |
| 24 | `Frontend/src/lib/tenantStorage.ts:L286: fetch(`${getStorageApiBase()}/storage/${code}/${name}?cb=${Date.now()}`, {` |
| 25 | `Frontend/src/lib/tenantStorage.ts:L329: recentlyWritten.set(name, Date.now());` |

### Pattern: `TODO_FIXME_HACK`
| # | Sample Hit (`File:Line: Snippet`) |
|---|---|

### Pattern: `dangerouslySetInnerHTML_eval`
| # | Sample Hit (`File:Line: Snippet`) |
|---|---|
| 1 | `Frontend/src/components/modules/EmployeeAttendanceScanner.tsx:L254: <style dangerouslySetInnerHTML={{__html: `` |
| 2 | `Frontend/src/components/modules/lab/LabReceiptPrint.tsx:L149: <style dangerouslySetInnerHTML={{__html: `` |
| 3 | `Frontend/src/components/modules/radiology/RadiologyReceiptPrint.tsx:L149: <style dangerouslySetInnerHTML={{__html: `` |
| 4 | `Frontend/src/app/[locale]/dashboard/clinics/doctor/page.tsx:L530: <style dangerouslySetInnerHTML={{__html: `` |

### Pattern: `fallback`
| # | Sample Hit (`File:Line: Snippet`) |
|---|---|
| 1 | `Frontend/src/hooks/useEmployeeRole.ts:L74: // 5. Fallback: If candidate is email, derive friendly name if possible` |
| 2 | `Frontend/src/store/useAiUsageStore.ts:L34: setAutoFallback: (fallback: boolean) => void;` |
| 3 | `Frontend/src/store/useAiUsageStore.ts:L58: // Auto-Fallback Logic` |
| 4 | `Frontend/src/store/useAiUsageStore.ts:L61: isHospital = false; // Fallback to personal` |
| 5 | `Frontend/src/store/useAiUsageStore.ts:L64: isHospital = true; // Fallback to hospital` |
| 6 | `Frontend/src/store/useAiUsageStore.ts:L127: setAutoFallback: (fallback) => set({ autoFallback: fallback }),` |
| 7 | `Frontend/src/store/useAuditStore.ts:L101: // Fallback to legacy storage if endpoint returns non-ok` |
| 8 | `Frontend/src/store/useEncounterStore.ts:L26: const jsonValue=(value:any, fallback:any={})=>{` |
| 9 | `Frontend/src/store/useEncounterStore.ts:L27: if(value===null\|\|value===undefined\|\|value==='') return fallback;` |
| 10 | `Frontend/src/store/useEncounterStore.ts:L29: try{return JSON.parse(value);}catch{return fallback;}` |
| 11 | `Frontend/src/store/usePatientStore.ts:L53: const jsonValue=(value:any,fallback:any={})=>{if(value===null\|\|value===undefined\|\|value==='')return fallback;if(typeof value==='object')retu` |
| 12 | `Frontend/src/store/usePayrollRulesStore.ts:L189: // Fallback to base rules` |
| 13 | `Frontend/src/store/useReceptionStore.ts:L1127: // Try to find exact clinic pricing, or fallback to first one, or use defaults` |
| 14 | `Frontend/src/store/useReceptionStore.ts:L1152: share = (v.paidAmount \|\| v.invoiceTotal \|\| 0) * 0.2; // default 20% fallback` |
| 15 | `Frontend/src/store/useReceptionStore.ts:L1467: console.warn('[ReceptionStore] hydrateFromServer fallback failed:', hydErr);` |
| 16 | `Frontend/src/app/api/admin-ai/route.ts:L29: // Fallback to env` |
| 17 | `Frontend/src/app/api/ai-doctor/route.ts:L120: // Fallback to env` |
| 18 | `Frontend/src/app/api/ai-doctor/route.ts:L271: // 3. Cross-Provider Fallback to Gemini for text queries if Groq failed or has no keys` |
| 19 | `Frontend/src/app/api/ai-doctor/route.ts:L303: console.error(`Gemini Text ${gModel} fallback failed:`, lastGeminiErr);` |
| 20 | `Frontend/src/app/api/ai-doctor/route.ts:L324: lastError = `Gemini fallback failed: ${lastGeminiErr}`;` |
| 21 | `Frontend/src/app/api/ai-doctor/route.ts:L326: lastError = `Gemini fallback exception: ${geminiErr.message}`;` |
| 22 | `Frontend/src/app/api/desktop-version/route.ts:L23: // Fallback if WP plugin is not yet installed or unreachable` |
| 23 | `Frontend/src/app/api/interactions/route.ts:L122: // We can implement Gemini fallback here later if needed` |
| 24 | `Frontend/src/app/api/interactions/route.ts:L127: // Fallback below if all AI attempts fail` |
| 25 | `Frontend/src/app/api/interactions/route.ts:L131: // Fallback to internal database if AI rotation completely fails` |

### Pattern: `hardcoded_domains`
| # | Sample Hit (`File:Line: Snippet`) |
|---|---|
| 1 | `Frontend/src/middleware.ts:L51: "medcoresystem.orbitsoftware.xyz",` |
| 2 | `Frontend/src/middleware.ts:L53: "127.0.0.1",` |
| 3 | `Frontend/src/lib/api.ts:L12: return 'https://test-medcore.orbitsoftware.xyz/wp-json';` |
| 4 | `Frontend/src/lib/api.ts:L15: const API_URL = process.env.NEXT_PUBLIC_API_URL \|\| (process.env.NODE_ENV === 'development' ? 'http://localhost/wp-json/mce/v1' : 'https://te` |
| 5 | `Frontend/src/lib/auditMiddleware.ts:L122: ip_address: '127.0.0.1', // Placeholder as real IP is server-side` |
| 6 | `Frontend/src/lib/tenantStorage.ts:L25: return base ? `${base}/mce/v1` : 'https://test-medcore.orbitsoftware.xyz/wp-json/mce/v1';` |
| 7 | `Frontend/src/store/useAuthStore.ts:L101: ip_address: '127.0.0.1',` |
| 8 | `Frontend/src/app/api/admin-ai/route.ts:L15: const rawBase = process.env.NEXT_PUBLIC_API_URL \|\| 'https://test-medcore.orbitsoftware.xyz/wp-json/mce/v1';` |
| 9 | `Frontend/src/app/api/ai-doctor/route.ts:L105: const rawBase = process.env.NEXT_PUBLIC_API_URL \|\| 'https://test-medcore.orbitsoftware.xyz/wp-json/mce/v1';` |
| 10 | `Frontend/src/app/api/ai-wallet/route.ts:L12: const rawBase = getMedCoreApiBase() \|\| process.env.NEXT_PUBLIC_API_URL \|\| 'https://test-medcore.orbitsoftware.xyz/wp-json';` |
| 11 | `Frontend/src/app/api/ai-wallet/route.ts:L43: const rawBase = getMedCoreApiBase() \|\| process.env.NEXT_PUBLIC_API_URL \|\| 'https://test-medcore.orbitsoftware.xyz/wp-json';` |
| 12 | `Frontend/src/app/api/desktop-version/route.ts:L15: download_url: data.download_url \|\| "https://test-medcore.orbitsoftware.xyz/wp-content/uploads/MedCore-Desktop-App.zip",` |
| 13 | `Frontend/src/app/api/desktop-version/route.ts:L27: download_url: "https://test-medcore.orbitsoftware.xyz/wp-content/uploads/MedCore-Desktop-App.zip",` |
| 14 | `Frontend/src/app/api/storage/[tenant]/[key]/route.ts:L10: 'https://test-medcore.orbitsoftware.xyz/wp-json';` |
| 15 | `Frontend/src/components/reception/AddVisitModal.tsx:L590: ip_address: '127.0.0.1',` |
| 16 | `Frontend/src/app/[locale]/(public)/layout.tsx:L29: © 2026 MedCore. Developed by <span className="font-bold text-foreground/80">OrbitSoftware.xyz</span>` |
| 17 | `Frontend/src/app/[locale]/(public)/layout.tsx:L34: href="https://test-medcore.orbitsoftware.xyz/wp-content/uploads/MedCore-Desktop-App.zip"` |
| 18 | `Frontend/src/app/[locale]/(public)/download/page.tsx:L37: href={downloadUrl \|\| "https://test-medcore.orbitsoftware.xyz/wp-content/uploads/MedCore-Desktop-App.zip"}` |
| 19 | `Backend/MedCorePlugin/includes/api/class-api-saas-extended.php:L119: $app_url = defined('MEDCORE_APP_URL') ? MEDCORE_APP_URL : 'https://medcoresystem.orbitsoftware.xyz';` |
| 20 | `Backend/MedCorePlugin/includes/api/class-api-system.php:L60: $allowed_hosts = [ 'test-medcore.orbitsoftware.xyz', 'localhost', '127.0.0.1' ];` |
| 21 | `Backend/MedCorePlugin/includes/api/class-api-tenants.php:L198: $app_url = defined('MEDCORE_APP_URL') ? MEDCORE_APP_URL : 'https://medcoresystem.orbitsoftware.xyz';` |
| 22 | `Backend/MedCorePlugin/includes/api/class-api-tenants.php:L334: $app_url = defined('MEDCORE_APP_URL') ? MEDCORE_APP_URL : 'https://medcoresystem.orbitsoftware.xyz';` |
| 23 | `Backend/MedCorePlugin/includes/security/class-medcore-cors.php:L18: 'https://medcoresystem.orbitsoftware.xyz',` |
| 24 | `Backend/MedCorePlugin/includes/security/class-medcore-cors.php:L19: 'http://localhost:3000',` |
| 25 | `Backend/MedCorePlugin/includes/security/class-medcore-cors.php:L20: 'http://localhost:3001'` |

### Pattern: `localStorage_sessionStorage`
| # | Sample Hit (`File:Line: Snippet`) |
|---|---|
| 1 | `Frontend/src/lib/api.ts:L48: const current = JSON.parse(localStorage.getItem(key) \|\| '[]');` |
| 2 | `Frontend/src/lib/api.ts:L51: localStorage.setItem(key, JSON.stringify(next));` |
| 3 | `Frontend/src/lib/api.ts:L73: const rawTenant = localStorage.getItem('mc_tenant')?.trim();` |
| 4 | `Frontend/src/lib/api.ts:L78: const token = (tenant ? (localStorage.getItem(`mc_token_${tenant}`) \|\| localStorage.getItem(`mc_token_${rawTenant}`)) : null)` |
| 5 | `Frontend/src/lib/api.ts:L79: \|\| localStorage.getItem('mc_token')` |
| 6 | `Frontend/src/lib/api.ts:L80: \|\| localStorage.getItem('medcore_token');` |
| 7 | `Frontend/src/lib/offlineSync.ts:L37: return String(localStorage.getItem('mc_tenant') \|\| '').trim();` |
| 8 | `Frontend/src/lib/offlineSync.ts:L73: let id = localStorage.getItem(key);` |
| 9 | `Frontend/src/lib/offlineSync.ts:L78: localStorage.setItem(key, id);` |
| 10 | `Frontend/src/lib/tenantStorage.ts:L5: //  HYBRID TENANT STORAGE — localStorage-first, server-sync in background` |
| 11 | `Frontend/src/lib/tenantStorage.ts:L10: return window.localStorage.getItem(key);` |
| 12 | `Frontend/src/lib/tenantStorage.ts:L18: window.localStorage.setItem(key, value);` |
| 13 | `Frontend/src/lib/tenantStorage.ts:L90: for (let i = 0; i < window.localStorage.length; i++) {` |
| 14 | `Frontend/src/lib/tenantStorage.ts:L91: const k = window.localStorage.key(i);` |
| 15 | `Frontend/src/lib/tenantStorage.ts:L93: window.localStorage.removeItem(k);` |
| 16 | `Frontend/src/lib/tenantStorage.ts:L386: window.localStorage.removeItem(name);` |
| 17 | `Frontend/src/lib/tenantSwitch.ts:L1: // Clears all hospital-specific data from localStorage when switching hospitals` |
| 18 | `Frontend/src/lib/tenantSwitch.ts:L33: localStorage.getItem("medcore_last_hospital_code") \|\|` |
| 19 | `Frontend/src/lib/tenantSwitch.ts:L34: localStorage.getItem("mc_tenant") \|\|` |
| 20 | `Frontend/src/lib/tenantSwitch.ts:L39: localStorage.removeItem(key);` |
| 21 | `Frontend/src/lib/tenantSwitch.ts:L45: localStorage.removeItem(`${targetCode}_${key}`);` |
| 22 | `Frontend/src/lib/tenantSwitch.ts:L52: for (let i = 0; i < localStorage.length; i++) {` |
| 23 | `Frontend/src/lib/tenantSwitch.ts:L53: const k = localStorage.key(i);` |
| 24 | `Frontend/src/lib/tenantSwitch.ts:L58: toRemove.forEach((k) => localStorage.removeItem(k));` |
| 25 | `Frontend/src/lib/tenantSwitch.ts:L79: const lastCode = localStorage.getItem("medcore_last_hospital_code");` |

### Pattern: `mock_dummy_fake`
| # | Sample Hit (`File:Line: Snippet`) |
|---|---|
| 1 | `Frontend/src/store/useClinicalStore.ts:L240: // Fall back gracefully to local state or mock` |
| 2 | `Frontend/src/store/useInpatientStore.ts:L210: // We do not rely on local fake beds.` |
| 3 | `Frontend/src/lib/api/clinical.ts:L86: * @deprecated Test/offline mock only.` |
| 4 | `Frontend/src/components/modules/NursingModule.tsx:L40: // Generate some deterministic mock dates based on id length` |
| 5 | `Frontend/src/components/modules/lab/TestPanelOrdering.tsx:L149: // Convert selected definitions into LabTestPanels with mock generic parameters` |
| 6 | `Frontend/src/components/modules/lab/TestPanelOrdering.tsx:L169: // Add a generic mock parameter so validation screen works out of the box` |
| 7 | `Frontend/src/app/[locale]/(public)/tutorials/page.tsx:L24: // Fallback dummy data in case the WP plugin isn't active or empty` |
| 8 | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L277: // 21. mc_nicu_telemetry (ISS-MOCK-02)` |
| 9 | `Backend/MedCorePlugin/includes/core/class-medcore-schema-v1-1.php:L298: // 22. mc_nicu_growth_logs (ISS-MOCK-02)` |

### Pattern: `parseFloat`
| # | Sample Hit (`File:Line: Snippet`) |
|---|---|
| 1 | `Frontend/src/store/useFinanceStore.ts:L59: const amount = parseFloat(d.paid_amount \|\| d.net_amount \|\| d.gross_amount \|\| 0);` |
| 2 | `Frontend/src/store/useLabStore.ts:L226: const numVal = typeof match.value === 'number' ? match.value : parseFloat(String(match.value));` |
| 3 | `Frontend/src/components/clinics/DoctorFinancialDashboard.tsx:L78: const amt = parseFloat(e.amount \|\| 0);` |
| 4 | `Frontend/src/components/clinics/DoctorFinancialDashboard.tsx:L175: const lineAmount = parseFloat(line.amount \|\| 0);` |
| 5 | `Frontend/src/components/clinics/DoctorFinancialDashboard.tsx:L192: const returnedAmount = parseFloat(data?.amount \|\| 0);` |
| 6 | `Frontend/src/components/clinics/DoctorFinancialDashboard.tsx:L299: const amt = parseFloat(e.amount \|\| 0);` |
| 7 | `Frontend/src/components/clinics/DoctorFinancialDashboard.tsx:L677: <span className="font-black text-lg font-mono text-emerald-600">+{parseFloat(line.amount).toFixed(2)} EGP</span>` |
| 8 | `Frontend/src/components/modules/FinanceModule.tsx:L50: {getPaymentMethodName(s.method)}: {parseFloat(s.amount \|\| 0).toLocaleString()} ج.م` |
| 9 | `Frontend/src/components/modules/definitions/ConditionsForm.tsx:L192: onChange={(e) => handleUpdateRequirement(idx, 'quantity', parseFloat(e.target.value) \|\| 0)}` |
| 10 | `Frontend/src/components/modules/definitions/DoctorsForm.tsx:L249: onChange={(e) => setFormData({...formData, salaryAmount: parseFloat(e.target.value) \|\| 0})}` |
| 11 | `Frontend/src/components/modules/definitions/EmployeesForm.tsx:L194: onChange={e => setFormData({...formData, salaryAmount: parseFloat(e.target.value) \|\| undefined})}` |
| 12 | `Frontend/src/components/modules/definitions/EmployeesForm.tsx:L214: onChange={e => setFormData({...formData, workingUnitsPerFrequency: parseFloat(e.target.value) \|\| undefined})}` |
| 13 | `Frontend/src/components/modules/definitions/EmployeesForm.tsx:L227: onChange={e => setFormData({...formData, shiftHours: parseFloat(e.target.value) \|\| undefined})}` |
| 14 | `Frontend/src/components/modules/definitions/ExternalLabForm.tsx:L149: onChange={(e) => handlePriceListChange(test.id, parseFloat(e.target.value) \|\| 0)}` |
| 15 | `Frontend/src/components/modules/definitions/NursesForm.tsx:L198: onChange={e => setFormData({...formData, salaryAmount: parseFloat(e.target.value) \|\| undefined})}` |
| 16 | `Frontend/src/components/modules/definitions/NursesForm.tsx:L218: onChange={e => setFormData({...formData, workingUnitsPerFrequency: parseFloat(e.target.value) \|\| undefined})}` |
| 17 | `Frontend/src/components/modules/definitions/NursesForm.tsx:L231: onChange={e => setFormData({...formData, shiftHours: parseFloat(e.target.value) \|\| undefined})}` |
| 18 | `Frontend/src/components/modules/hr/StaffPayrollModule.tsx:L133: let amount = parseFloat(adjAmount);` |
| 19 | `Frontend/src/components/modules/inventory/AddStockItemModal.tsx:L186: onChange={(e) => setPrice(parseFloat(e.target.value))}` |
| 20 | `Frontend/src/components/modules/inventory/AddStockItemModal.tsx:L198: onChange={(e) => setPublicPrice(parseFloat(e.target.value))}` |
| 21 | `Frontend/src/components/modules/inventory/EditStockItemModal.tsx:L176: onChange={(e) => setPrice(parseFloat(e.target.value))}` |
| 22 | `Frontend/src/components/modules/inventory/EditStockItemModal.tsx:L188: onChange={(e) => setPublicPrice(parseFloat(e.target.value))}` |
| 23 | `Frontend/src/components/modules/settings/FinancialRulesModule.tsx:L129: onChange={(e) => updateBaseRule(selectedRole, rule.id, parseFloat(e.target.value) \|\| 0)}` |
| 24 | `Frontend/src/components/modules/settings/FinancialRulesModule.tsx:L202: onChange={(e) => updateException(excSelectedPersonId, excSelectedRole, rv.ruleId, parseFloat(e.target.value) \|\| 0)}` |
| 25 | `Frontend/src/components/modules/settings/FinancialRulesModule.tsx:L233: const val = parseFloat((document.getElementById("newExcValue") as HTMLInputElement).value);` |

### Pattern: `return_true_perm`
| # | Sample Hit (`File:Line: Snippet`) |
|---|---|
| 1 | `Backend/MedCorePlugin/includes/api/class-api-auth.php:L9: 'permission_callback' => '__return_true'` |
| 2 | `Backend/MedCorePlugin/includes/api/class-api-auth.php:L14: 'permission_callback' => '__return_true'` |
| 3 | `Backend/MedCorePlugin/includes/api/class-api-auth.php:L19: 'permission_callback' => '__return_true'` |
| 4 | `Backend/MedCorePlugin/includes/api/class-api-auth.php:L24: 'permission_callback' => '__return_true'` |
| 5 | `Backend/MedCorePlugin/includes/api/class-api-auth.php:L29: 'permission_callback' => '__return_true'` |
| 6 | `Backend/MedCorePlugin/includes/api/class-api-auth.php:L34: 'permission_callback' => '__return_true'` |
| 7 | `Backend/MedCorePlugin/includes/api/class-api-auth.php:L39: 'permission_callback' => '__return_true'` |
| 8 | `Backend/MedCorePlugin/includes/api/class-api-auth.php:L44: 'permission_callback' => '__return_true'` |
| 9 | `Backend/MedCorePlugin/includes/api/class-api-desktop.php:L9: 'permission_callback' => '__return_true' // INTENTIONALLY PUBLIC: Bootstrap endpoint for app updates` |
| 10 | `Backend/MedCorePlugin/includes/api/class-api-desktop.php:L14: 'permission_callback' => '__return_true'` |
| 11 | `Backend/MedCorePlugin/includes/api/class-api-desktop.php:L19: 'permission_callback' => '__return_true' // INTENTIONALLY PUBLIC: Bootstrap endpoint to check if hospital exists before login` |
| 12 | `Backend/MedCorePlugin/includes/api/class-api-staff.php:L9: 'permission_callback' => '__return_true'` |
| 13 | `Backend/MedCorePlugin/includes/api/class-api-staff.php:L15: 'permission_callback' => '__return_true'` |
| 14 | `Backend/MedCorePlugin/includes/api/class-api-staff.php:L20: 'permission_callback' => '__return_true'` |
| 15 | `Backend/MedCorePlugin/includes/api/class-api-staff.php:L40: 'permission_callback' => '__return_true'` |
| 16 | `Backend/MedCorePlugin/includes/api/class-api-staff.php:L45: 'permission_callback' => '__return_true'` |
| 17 | `Backend/MedCorePlugin/includes/api/class-api-staff.php:L50: 'permission_callback' => '__return_true'` |
| 18 | `Backend/MedCorePlugin/includes/api/class-api-staff.php:L55: 'permission_callback' => '__return_true'` |
| 19 | `Backend/MedCorePlugin/includes/api/class-api-staff.php:L60: 'permission_callback' => '__return_true'` |
| 20 | `Backend/MedCorePlugin/includes/api/class-api-system.php:L15: 'permission_callback' => '__return_true'` |

### Pattern: `ts_ignore_eslint_disable`
| # | Sample Hit (`File:Line: Snippet`) |
|---|---|
| 1 | `Frontend/src/lib/auditMiddleware.ts:L94: // @ts-ignore` |
| 2 | `Frontend/src/components/modules/hr/AttendanceStatsPanel.tsx:L49: // @ts-ignore` |
| 3 | `Frontend/src/components/modules/hr/AttendanceStatsPanel.tsx:L51: // @ts-ignore` |
| 4 | `Frontend/src/components/modules/hr/AttendanceStatsPanel.tsx:L53: // @ts-ignore` |
