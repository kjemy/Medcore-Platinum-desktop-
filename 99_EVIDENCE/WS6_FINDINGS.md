# WS6 — Frontend Navigation, Pages, Stores & UI Reference (`Project 3`)

> **Classification**: `FACT` (Code Inventory) & `UI DESIGN REFERENCE` (Design System Tokens).

## 1. Canonical Sidebar Navigation Tree (19 Top-Level Sections / 63 Subpages = 82 Nodes)
- **Authoritative Source**: `Frontend/src/lib/navigationConfig.ts:21-888` (`CANONICAL_NAVIGATION_CONFIG`) & `Frontend/src/components/Sidebar.tsx:240-452`.

| # | Section ID | Arabic Label | English Label | Route / Children Count | Required Permission Key | License Module Key |
|---|---|---|---|---|---|---|
| 1 | `dashboard` | لوحة القيادة | Dashboard | `/dashboard` (Standalone) | `dashboard` | Core |
| 2 | `patients` | سجل المرضى | Patients Registry | `/patients` (Standalone) | `patients` | Core |
| 3 | `appointments` | المواعيد والحجوزات | Appointments | `/appointments` (Standalone) | `appointments` | `appointments` |
| 4 | `HMS_summary` | الملخص العام للمستشفى | Hospital Summary | `/summary` (Standalone) | `HMS_summary` | Core |
| 5 | `shifts` | الورديات والخزينة | Shifts & Cashier | `/shifts` (Standalone) | `shifts` | Core |
| 6 | `reception` | الاستقبال والطوارئ | Reception & ER | 5 Subpages (`/reception/*`) | `reception_*` | `reception` |
| 7 | `clinic` | العيادات الخارجية | Outpatient Clinics | 5 Subpages (`/clinic/*`) | `clinic_*` | `clinics` |
| 8 | `CommandCenter` | مركز القيادة | Command Center | 3 Subpages (`/command-center/*`) | `CommandCenter_*` | `command_center` |
| 9 | `doctor` | بوابة الطبيب | Doctor Portal | 3 Subpages (`/doctor/*`) | `doctor_*` | `doctor_portal` |
| 10 | `nurse` | محطة التمريض | Nursing Station | 5 Subpages (`/nurse/*`) | `nurse_*` | `nursing` |
| 11 | `inpatient` | القسم الداخلي والتنويم | Inpatient & Wards | 4 Subpages (`/inpatient/*`) | `inpatient_*` | `inpatient` |
| 12 | `icu_nicu` | العناية المركزة والحضانات | ICU & NICU | 4 Subpages (`/icu-nicu/*`) | `icu_nicu_*` | `icu_nicu` |
| 13 | `surgery` | العمليات الجراحية | Surgery & OR | 3 Subpages (`/surgery/*`) | `surgery_*` | `surgery` |
| 14 | `dialysis` | وحدة الغسيل الكلوي | Dialysis Unit | 4 Subpages (`/dialysis/*`) | `dialysis_*` | `dialysis` |
| 15 | `lab` | المختبر والتحاليل | Laboratory | 6 Subpages (`/lab/*`) | `lab_*` | `laboratory` |
| 16 | `rad` | الأشعة والتصوير | Radiology | 3 Subpages (`/rad/*`) | `rad_*` | `radiology` |
| 17 | `pharmacy_inventory` | الصيدلية والمخازن | Pharmacy & Inventory | 6 Subpages (`/pharmacy-inventory/*`) | `pharmacy_inventory_*` | `pharmacy_inventory` |
| 18 | `finance` | الإدارة المالية والحسابات | Finance & Accounting | 5 Subpages (`/finance/*`) | `finance_*` | `finance` |
| 19 | `hr_settings` | الموارد البشرية والإعدادات | HR & Settings | 7 Subpages (`/hr/*`, `/settings/*`, `/security`) | `hr_*` / `settings_*` | `hr` / Core |

## 2. Complete Next.js App Router Page Inventory (104 Pages)

| # | Route Path | Source File | Lines |
|---|---|---|---|
| 1 | `/[locale]/(dashboard)/attendance` | `Frontend/src/app/[locale]/(dashboard)/attendance/page.tsx` | 7 |
| 2 | `/[locale]/(dashboard)/finance` | `Frontend/src/app/[locale]/(dashboard)/finance/page.tsx` | 7 |
| 3 | `/[locale]/(dashboard)/hiring` | `Frontend/src/app/[locale]/(dashboard)/hiring/page.tsx` | 7 |
| 4 | `/[locale]/(dashboard)/hr` | `Frontend/src/app/[locale]/(dashboard)/hr/page.tsx` | 7 |
| 5 | `/[locale]/(dashboard)/inventory` | `Frontend/src/app/[locale]/(dashboard)/inventory/page.tsx` | 7 |
| 6 | `/[locale]/(dashboard)/payroll` | `Frontend/src/app/[locale]/(dashboard)/payroll/page.tsx` | 7 |
| 7 | `/[locale]/(dashboard)/prices` | `Frontend/src/app/[locale]/(dashboard)/prices/page.tsx` | 7 |
| 8 | `/[locale]/(dashboard)/purchasing` | `Frontend/src/app/[locale]/(dashboard)/purchasing/page.tsx` | 7 |
| 9 | `/[locale]/(dashboard)/reception` | `Frontend/src/app/[locale]/(dashboard)/reception/page.tsx` | 3 |
| 10 | `/[locale]/(public)` | `Frontend/src/app/[locale]/(public)/page.tsx` | 63 |
| 11 | `/[locale]/(public)/checkout/[planId]` | `Frontend/src/app/[locale]/(public)/checkout/[planId]/page.tsx` | 376 |
| 12 | `/[locale]/(public)/download` | `Frontend/src/app/[locale]/(public)/download/page.tsx` | 84 |
| 13 | `/[locale]/(public)/features` | `Frontend/src/app/[locale]/(public)/features/page.tsx` | 47 |
| 14 | `/[locale]/(public)/forgot-password` | `Frontend/src/app/[locale]/(public)/forgot-password/page.tsx` | 227 |
| 15 | `/[locale]/(public)/help` | `Frontend/src/app/[locale]/(public)/help/page.tsx` | 104 |
| 16 | `/[locale]/(public)/login` | `Frontend/src/app/[locale]/(public)/login/page.tsx` | 16 |
| 17 | `/[locale]/(public)/pricing` | `Frontend/src/app/[locale]/(public)/pricing/page.tsx` | 14 |
| 18 | `/[locale]/(public)/tutorials` | `Frontend/src/app/[locale]/(public)/tutorials/page.tsx` | 38 |
| 19 | `/[locale]/activate` | `Frontend/src/app/[locale]/activate/page.tsx` | 360 |
| 20 | `/[locale]/dashboard` | `Frontend/src/app/[locale]/dashboard/page.tsx` | 301 |
| 21 | `/[locale]/dashboard/admin-ai` | `Frontend/src/app/[locale]/dashboard/admin-ai/page.tsx` | 263 |
| 22 | `/[locale]/dashboard/ai-doctor` | `Frontend/src/app/[locale]/dashboard/ai-doctor/page.tsx` | 25 |
| 23 | `/[locale]/dashboard/appointments` | `Frontend/src/app/[locale]/dashboard/appointments/page.tsx` | 484 |
| 24 | `/[locale]/dashboard/attendance` | `Frontend/src/app/[locale]/dashboard/attendance/page.tsx` | 13 |
| 25 | `/[locale]/dashboard/clinical/dialysis` | `Frontend/src/app/[locale]/dashboard/clinical/dialysis/page.tsx` | 4 |
| 26 | `/[locale]/dashboard/clinical/dialysis-inventory` | `Frontend/src/app/[locale]/dashboard/clinical/dialysis-inventory/page.tsx` | 4 |
| 27 | `/[locale]/dashboard/clinical/dialysis/sessions` | `Frontend/src/app/[locale]/dashboard/clinical/dialysis/sessions/page.tsx` | 4 |
| 28 | `/[locale]/dashboard/clinical/endoscopy` | `Frontend/src/app/[locale]/dashboard/clinical/endoscopy/page.tsx` | 256 |
| 29 | `/[locale]/dashboard/clinical/icu` | `Frontend/src/app/[locale]/dashboard/clinical/icu/page.tsx` | 12 |
| 30 | `/[locale]/dashboard/clinical/icu-inventory` | `Frontend/src/app/[locale]/dashboard/clinical/icu-inventory/page.tsx` | 37 |
| 31 | `/[locale]/dashboard/clinical/nicu` | `Frontend/src/app/[locale]/dashboard/clinical/nicu/page.tsx` | 12 |
| 32 | `/[locale]/dashboard/clinical/nicu-inventory` | `Frontend/src/app/[locale]/dashboard/clinical/nicu-inventory/page.tsx` | 34 |
| 33 | `/[locale]/dashboard/clinical/oncology` | `Frontend/src/app/[locale]/dashboard/clinical/oncology/page.tsx` | 215 |
| 34 | `/[locale]/dashboard/clinical/physiotherapy` | `Frontend/src/app/[locale]/dashboard/clinical/physiotherapy/page.tsx` | 309 |
| 35 | `/[locale]/dashboard/clinical/rooms` | `Frontend/src/app/[locale]/dashboard/clinical/rooms/page.tsx` | 12 |
| 36 | `/[locale]/dashboard/clinical/rooms-inventory` | `Frontend/src/app/[locale]/dashboard/clinical/rooms-inventory/page.tsx` | 30 |
| 37 | `/[locale]/dashboard/clinical/surgeries` | `Frontend/src/app/[locale]/dashboard/clinical/surgeries/page.tsx` | 562 |
| 38 | `/[locale]/dashboard/clinical/surgeries-inventory` | `Frontend/src/app/[locale]/dashboard/clinical/surgeries-inventory/page.tsx` | 30 |
| 39 | `/[locale]/dashboard/clinical/surgery-booking` | `Frontend/src/app/[locale]/dashboard/clinical/surgery-booking/page.tsx` | 13 |
| 40 | `/[locale]/dashboard/clinics/doctor` | `Frontend/src/app/[locale]/dashboard/clinics/doctor/page.tsx` | 1318 |
| 41 | `/[locale]/dashboard/clinics/examination` | `Frontend/src/app/[locale]/dashboard/clinics/examination/page.tsx` | 323 |
| 42 | `/[locale]/dashboard/clinics/inventory` | `Frontend/src/app/[locale]/dashboard/clinics/inventory/page.tsx` | 131 |
| 43 | `/[locale]/dashboard/clinics/templates` | `Frontend/src/app/[locale]/dashboard/clinics/templates/page.tsx` | 51 |
| 44 | `/[locale]/dashboard/complaints` | `Frontend/src/app/[locale]/dashboard/complaints/page.tsx` | 11 |
| 45 | `/[locale]/dashboard/debug` | `Frontend/src/app/[locale]/dashboard/debug/page.tsx` | 114 |
| 46 | `/[locale]/dashboard/diagnostics/lab` | `Frontend/src/app/[locale]/dashboard/diagnostics/lab/page.tsx` | 12 |
| 47 | `/[locale]/dashboard/diagnostics/lab-inventory` | `Frontend/src/app/[locale]/dashboard/diagnostics/lab-inventory/page.tsx` | 24 |
| 48 | `/[locale]/dashboard/diagnostics/radiology` | `Frontend/src/app/[locale]/dashboard/diagnostics/radiology/page.tsx` | 12 |
| 49 | `/[locale]/dashboard/diagnostics/radiology-inventory` | `Frontend/src/app/[locale]/dashboard/diagnostics/radiology-inventory/page.tsx` | 20 |
| 50 | `/[locale]/dashboard/doctors` | `Frontend/src/app/[locale]/dashboard/doctors/page.tsx` | 410 |
| 51 | `/[locale]/dashboard/finance` | `Frontend/src/app/[locale]/dashboard/finance/page.tsx` | 11 |
| 52 | `/[locale]/dashboard/finance/contracts` | `Frontend/src/app/[locale]/dashboard/finance/contracts/page.tsx` | 13 |
| 53 | `/[locale]/dashboard/finance/doctor-profits` | `Frontend/src/app/[locale]/dashboard/finance/doctor-profits/page.tsx` | 146 |
| 54 | `/[locale]/dashboard/finance/payroll` | `Frontend/src/app/[locale]/dashboard/finance/payroll/page.tsx` | 13 |
| 55 | `/[locale]/dashboard/finance/settlements` | `Frontend/src/app/[locale]/dashboard/finance/settlements/page.tsx` | 206 |
| 56 | `/[locale]/dashboard/finance/treasury` | `Frontend/src/app/[locale]/dashboard/finance/treasury/page.tsx` | 13 |
| 57 | `/[locale]/dashboard/hiring` | `Frontend/src/app/[locale]/dashboard/hiring/page.tsx` | 13 |
| 58 | `/[locale]/dashboard/hr` | `Frontend/src/app/[locale]/dashboard/hr/page.tsx` | 185 |
| 59 | `/[locale]/dashboard/hr/attendance` | `Frontend/src/app/[locale]/dashboard/hr/attendance/page.tsx` | 13 |
| 60 | `/[locale]/dashboard/hr/attendance-kiosk` | `Frontend/src/app/[locale]/dashboard/hr/attendance-kiosk/page.tsx` | 95 |
| 61 | `/[locale]/dashboard/hr/investigations` | `Frontend/src/app/[locale]/dashboard/hr/investigations/page.tsx` | 12 |
| 62 | `/[locale]/dashboard/hr/nursing` | `Frontend/src/app/[locale]/dashboard/hr/nursing/page.tsx` | 13 |
| 63 | `/[locale]/dashboard/hr/payroll` | `Frontend/src/app/[locale]/dashboard/hr/payroll/page.tsx` | 13 |
| 64 | `/[locale]/dashboard/hr/recruitment` | `Frontend/src/app/[locale]/dashboard/hr/recruitment/page.tsx` | 13 |
| 65 | `/[locale]/dashboard/hr/schedules` | `Frontend/src/app/[locale]/dashboard/hr/schedules/page.tsx` | 12 |
| 66 | `/[locale]/dashboard/insurance` | `Frontend/src/app/[locale]/dashboard/insurance/page.tsx` | 12 |
| 67 | `/[locale]/dashboard/inventory` | `Frontend/src/app/[locale]/dashboard/inventory/page.tsx` | 13 |
| 68 | `/[locale]/dashboard/inventory/central-dispense` | `Frontend/src/app/[locale]/dashboard/inventory/central-dispense/page.tsx` | 28 |
| 69 | `/[locale]/dashboard/inventory/dispense` | `Frontend/src/app/[locale]/dashboard/inventory/dispense/page.tsx` | 12 |
| 70 | `/[locale]/dashboard/inventory/main` | `Frontend/src/app/[locale]/dashboard/inventory/main/page.tsx` | 12 |
| 71 | `/[locale]/dashboard/inventory/prices` | `Frontend/src/app/[locale]/dashboard/inventory/prices/page.tsx` | 13 |
| 72 | `/[locale]/dashboard/inventory/purchasing` | `Frontend/src/app/[locale]/dashboard/inventory/purchasing/page.tsx` | 13 |
| 73 | `/[locale]/dashboard/my-nursing-tasks` | `Frontend/src/app/[locale]/dashboard/my-nursing-tasks/page.tsx` | 12 |
| 74 | `/[locale]/dashboard/my-portal` | `Frontend/src/app/[locale]/dashboard/my-portal/page.tsx` | 78 |
| 75 | `/[locale]/dashboard/nursing-management` | `Frontend/src/app/[locale]/dashboard/nursing-management/page.tsx` | 12 |
| 76 | `/[locale]/dashboard/patients` | `Frontend/src/app/[locale]/dashboard/patients/page.tsx` | 135 |
| 77 | `/[locale]/dashboard/patients/insurance` | `Frontend/src/app/[locale]/dashboard/patients/insurance/page.tsx` | 421 |
| 78 | `/[locale]/dashboard/payroll` | `Frontend/src/app/[locale]/dashboard/payroll/page.tsx` | 13 |
| 79 | `/[locale]/dashboard/pharmacy/catalog` | `Frontend/src/app/[locale]/dashboard/pharmacy/catalog/page.tsx` | 11 |
| 80 | `/[locale]/dashboard/pharmacy/interactions` | `Frontend/src/app/[locale]/dashboard/pharmacy/interactions/page.tsx` | 11 |
| 81 | `/[locale]/dashboard/pharmacy/pos` | `Frontend/src/app/[locale]/dashboard/pharmacy/pos/page.tsx` | 11 |
| 82 | `/[locale]/dashboard/pharmacy/prescriptions` | `Frontend/src/app/[locale]/dashboard/pharmacy/prescriptions/page.tsx` | 12 |
| 83 | `/[locale]/dashboard/prices` | `Frontend/src/app/[locale]/dashboard/prices/page.tsx` | 13 |
| 84 | `/[locale]/dashboard/purchasing` | `Frontend/src/app/[locale]/dashboard/purchasing/page.tsx` | 13 |
| 85 | `/[locale]/dashboard/quality/control` | `Frontend/src/app/[locale]/dashboard/quality/control/page.tsx` | 139 |
| 86 | `/[locale]/dashboard/quality/infection` | `Frontend/src/app/[locale]/dashboard/quality/infection/page.tsx` | 141 |
| 87 | `/[locale]/dashboard/quality/investigations` | `Frontend/src/app/[locale]/dashboard/quality/investigations/page.tsx` | 12 |
| 88 | `/[locale]/dashboard/reception` | `Frontend/src/app/[locale]/dashboard/reception/page.tsx` | 177 |
| 89 | `/[locale]/dashboard/reception/clinic/[id]` | `Frontend/src/app/[locale]/dashboard/reception/clinic/[id]/page.tsx` | 887 |
| 90 | `/[locale]/dashboard/reception/inventory` | `Frontend/src/app/[locale]/dashboard/reception/inventory/page.tsx` | 29 |
| 91 | `/[locale]/dashboard/reception/waiting` | `Frontend/src/app/[locale]/dashboard/reception/waiting/page.tsx` | 51 |
| 92 | `/[locale]/dashboard/reports` | `Frontend/src/app/[locale]/dashboard/reports/page.tsx` | 12 |
| 93 | `/[locale]/dashboard/settings` | `Frontend/src/app/[locale]/dashboard/settings/page.tsx` | 26 |
| 94 | `/[locale]/dashboard/settings/ai-usage` | `Frontend/src/app/[locale]/dashboard/settings/ai-usage/page.tsx` | 17 |
| 95 | `/[locale]/dashboard/settings/audit-log` | `Frontend/src/app/[locale]/dashboard/settings/audit-log/page.tsx` | 514 |
| 96 | `/[locale]/dashboard/settings/definitions` | `Frontend/src/app/[locale]/dashboard/settings/definitions/page.tsx` | 21 |
| 97 | `/[locale]/dashboard/settings/financial-rules` | `Frontend/src/app/[locale]/dashboard/settings/financial-rules/page.tsx` | 13 |
| 98 | `/[locale]/dashboard/settings/quotas` | `Frontend/src/app/[locale]/dashboard/settings/quotas/page.tsx` | 17 |
| 99 | `/[locale]/dashboard/settings/roles` | `Frontend/src/app/[locale]/dashboard/settings/roles/page.tsx` | 575 |
| 100 | `/[locale]/dashboard/settings/security` | `Frontend/src/app/[locale]/dashboard/settings/security/page.tsx` | 144 |
| 101 | `/[locale]/dashboard/withdrawals` | `Frontend/src/app/[locale]/dashboard/withdrawals/page.tsx` | 17 |
| 102 | `/[locale]/employee/attendance` | `Frontend/src/app/[locale]/employee/attendance/page.tsx` | 5 |
| 103 | `/[locale]/feedback` | `Frontend/src/app/[locale]/feedback/page.tsx` | 191 |
| 104 | `/[locale]/set-password` | `Frontend/src/app/[locale]/set-password/page.tsx` | 194 |

## 3. Complete Zustand State Store Inventory (48 Stores)

| # | Store Name | Source File | Lines | Uses `persist` / `tenantStorage` | Storage Keys | Classification |
|---|---|---|---|---|---|---|
| 1 | `defaultLabTests` | `Frontend/src/store/defaultLabTests.ts` | 2102 | persist=False, tenantStorage=False, localStorage=False | `None` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 2 | `defaultRadiology` | `Frontend/src/store/defaultRadiology.ts` | 95 | persist=False, tenantStorage=False, localStorage=False | `أشعة عادية على الصدر (CXR PA), أشعة عادية على الصدر (CXR AP), أشعة عادية على الصدر (CXR Lateral), أشعة عادية على البطن (KUB), أشعة عادية على البطن في وضع الوقوف (Erect Abdomen), أشعة عادية على الجمجمة (Skull AP/Lat), أشعة عادية على الجيوب الأنفية (Water, أشعة عادية على الرقبة (Cervical Spine AP/Lat), أشعة عادية على العمود الفقري الصدري (Thoracic Spine), أشعة عادية على العمود الفقري القطني (Lumbosacral Spine), أشعة عادية على الحوض (Pelvis AP), أشعة عادية على مفصل الكتف (Shoulder Joint), أشعة عادية على مفصل الكوع (Elbow Joint), أشعة عادية على مفصل الرسغ (Wrist Joint), أشعة عادية على اليد (Hand), أشعة عادية على مفصل الفخذ (Hip Joint), أشعة عادية على مفصل الركبة (Knee Joint AP/Lat), أشعة عادية على مفصل الكاحل (Ankle Joint), أشعة عادية على القدم (Foot), موجات صوتية على البطن والحوض (Abdomen & Pelvis US), موجات صوتية على الكبد والمرارة (Hepatobiliary US), موجات صوتية على الكلى والمسالك البولية (Renal US), موجات صوتية على الحوض (Pelvic US), موجات صوتية مهبلية (TVS), موجات صوتية لمتابعة الحمل (Obstetric US), موجات صوتية رباعية الأبعاد للحمل (4D Obstetric US), موجات صوتية على الغدة الدرقية (Thyroid US), موجات صوتية على الثدي (Breast US), موجات صوتية على الخصيتين (Scrotal US), دوبلر على أوردة الساقين (Venous Doppler Lower Limb), دوبلر على شرايين الساقين (Arterial Doppler Lower Limb), دوبلر على أوعية الرقبة (Carotid Doppler), موجات صوتية على القلب (Echocardiogram), أشعة مقطعية على المخ بدون صبغة (CT Brain Non-Contrast), أشعة مقطعية على الصدر بدون صبغة (CT Chest HRCT), أشعة مقطعية على البطن والحوض بدون صبغة (CT Abdomen & Pelvis), أشعة مقطعية على الجيوب الأنفية (CT Paranasal Sinuses), أشعة مقطعية على العمود الفقري العنقي (CT Cervical Spine), أشعة مقطعية على العمود الفقري القطني (CT Lumbosacral Spine), أشعة مقطعية المسالك البولية بدون صبغة (CT KUB), أشعة مقطعية على المخ بالصبغة (CT Brain with Contrast), أشعة مقطعية على الصدر بالصبغة (CT Chest with Contrast), أشعة مقطعية على البطن والحوض بالصبغة (CT Abdomen/Pelvis Contrast), أشعة مقطعية ثلاثية المراحل على الكبد (Triphasic CT Liver), أشعة مقطعية لشرايين الرئة (CT Pulmonary Angiography CTPA), أشعة مقطعية على شرايين المخ (CT Angiography Brain), أشعة مقطعية على الشريان الأورطي (CT Aortogram), رنين مغناطيسي على المخ (MRI Brain), رنين مغناطيسي على العمود الفقري العنقي (MRI Cervical Spine), رنين مغناطيسي على العمود الفقري القطني (MRI Lumbosacral Spine), رنين مغناطيسي على مفصل الركبة (MRI Knee Joint), رنين مغناطيسي على مفصل الكتف (MRI Shoulder Joint), رنين مغناطيسي على الحوض (MRI Pelvis), رنين مغناطيسي على القنوات المرارية (MRCP), رنين مغناطيسي على المخ بالصبغة (MRI Brain with Contrast), رنين مغناطيسي على الغدة النخامية بالصبغة (MRI Pituitary Contrast), رنين مغناطيسي على البطن والحوض بالصبغة (MRI Abdomen/Pelvis Contrast), رنين مغناطيسي على الثدي بالصبغة (MRI Breast Contrast), أشعة الماموجرام على الثديين (Bilateral Mammography), قياس هشاشة العظام (DEXA Scan - 2 Sites), قياس هشاشة العظام للجسم كله (DEXA Total Body), أشعة بالصبغة على المريء (Barium Swallow), أشعة بالصبغة على المعدة (Barium Meal), أشعة بالصبغة على القولون (Barium Enema), أشعة بالصبغة على المسالك البولية (IVP), أشعة صاعدة على مجرى البول (Ascending Urethrography), أشعة بالصبغة على الرحم والأنابيب (HSG), مسح ذري بوزيتروني للجسم كله (PET/CT Whole Body), مسح ذري على العظام (Bone Scan), مسح ذري على الغدة الدرقية (Thyroid Scan), مسح ذري على عضلة القلب (Myocardial Perfusion Scan), بذل سائل من البطن تحت الموجات (Ascitic Tapping under US), أخذ عينة من الكبد تحت الموجات (Liver Biopsy under US), أخذ عينة من الثدي تحت الموجات (Breast Trucut Biopsy)` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 3 | `useAccountingStore` | `Frontend/src/store/useAccountingStore.ts` | 107 | persist=True, tenantStorage=True, localStorage=False | `accounting-storage` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 4 | `useAiContextStore` | `Frontend/src/store/useAiContextStore.ts` | 11 | persist=False, tenantStorage=False, localStorage=False | `None` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 5 | `useAiUsageStore` | `Frontend/src/store/useAiUsageStore.ts` | 137 | persist=True, tenantStorage=False, localStorage=True | `ai-usage-multi-wallet` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 6 | `useAppointmentStore` | `Frontend/src/store/useAppointmentStore.ts` | 85 | persist=True, tenantStorage=True, localStorage=False | `appointment-storage` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 7 | `useAuditStore` | `Frontend/src/store/useAuditStore.ts` | 174 | persist=True, tenantStorage=True, localStorage=True | `audit-log-storage` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 8 | `useAuthStore` | `Frontend/src/store/useAuthStore.ts` | 157 | persist=True, tenantStorage=True, localStorage=True | `Authentication, medcore-auth-storage` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 9 | `useClinicalStore` | `Frontend/src/store/useClinicalStore.ts` | 306 | persist=True, tenantStorage=True, localStorage=False | `clinical-storage` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 10 | `useClinicalTemplatesStore` | `Frontend/src/store/useClinicalTemplatesStore.ts` | 172 | persist=True, tenantStorage=True, localStorage=False | `clinical-templates-storage` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 11 | `useComplaintsStore` | `Frontend/src/store/useComplaintsStore.ts` | 112 | persist=True, tenantStorage=True, localStorage=False | `complaints-store` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 12 | `useContractsStore` | `Frontend/src/store/useContractsStore.ts` | 50 | persist=True, tenantStorage=True, localStorage=False | `medcore-contracts-store` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 13 | `useDebugStore` | `Frontend/src/store/useDebugStore.ts` | 55 | persist=True, tenantStorage=True, localStorage=False | `debug-store` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 14 | `useDefinitionsStore` | `Frontend/src/store/useDefinitionsStore.ts` | 980 | persist=True, tenantStorage=True, localStorage=False | `جنيه مصري, دولار أمريكي, يورو, Neonatal CPAP, Neonatal Ventilator, Phototherapy Unit, Micro-Syringe Pump, Neonatal Monitor, Radiant Warmer, قسطرة وريد سري (UVC), قسطرة شريان سري (UAC), PICC Line (Neonatal), Peripheral IV (PIV), أنبوب تغذية عن طريق الفم (OGT), أنبوب تغذية عن طريق الأنف (NGT), Mechanical Ventilator, Patient Monitor, Infusion Pump, Syringe Pump, Defibrillator, Air Mattress, ABG Analyzer, ECG Machine, Suction Machine, CRRT Machine, Central Venous Catheter (CVC), Arterial Line (A-Line), Peripheral IV (PIV), PICC Line, Foley Catheter, Nasogastric Tube (NGT), Chest Tube, Jackson-Pratt Drain (JP), Intracranial Pressure (ICP) Monitor, Core Temperature Probe, Mechanical Ventilator, Patient Monitor, Infusion Pump, Syringe Pump, Defibrillator, Air Mattress, ABG Analyzer, ECG Machine, Suction Machine, CRRT Machine, Neonatal CPAP, Neonatal Ventilator, Phototherapy Unit, Micro-Syringe Pump, Neonatal Monitor, Radiant Warmer, definitions-storage, جنيه مصري, دولار أمريكي, يورو, Mechanical Ventilator, Patient Monitor, Infusion Pump, Syringe Pump, Defibrillator, Air Mattress, ABG Analyzer, ECG Machine, Suction Machine, CRRT Machine, Neonatal CPAP, Neonatal Ventilator, Phototherapy Unit, Micro-Syringe Pump, Neonatal Monitor, Radiant Warmer` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 15 | `useDialysisStore` | `Frontend/src/store/useDialysisStore.ts` | 100 | persist=True, tenantStorage=True, localStorage=False | `dialysis-module` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 16 | `useDoctorStore` | `Frontend/src/store/useDoctorStore.ts` | 289 | persist=True, tenantStorage=True, localStorage=False | `Dr. Sameh Al-Khatib, Dr. Mona Al-Saeed, Dr. Tariq Al-Mansoor, doctor-storage` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 17 | `useDoctorsStore` | `Frontend/src/store/useDoctorsStore.ts` | 52 | persist=True, tenantStorage=True, localStorage=False | `medcore-doctors-store` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 18 | `useEncounterStore` | `Frontend/src/store/useEncounterStore.ts` | 101 | persist=True, tenantStorage=True, localStorage=False | `encounter-storage` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 19 | `useFinanceStore` | `Frontend/src/store/useFinanceStore.ts` | 163 | persist=True, tenantStorage=True, localStorage=False | `finance-storage` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 20 | `useHrStore` | `Frontend/src/store/useHrStore.ts` | 78 | persist=True, tenantStorage=True, localStorage=False | `hr-storage` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 21 | `useIcuStore` | `Frontend/src/store/useIcuStore.ts` | 394 | persist=True, tenantStorage=True, localStorage=False | `النبض (HR), متوسط الضغط (MAP), الضغط المركزي (CVP), نسبة الأكسجين (SpO2), مقياس غلاسكو (GCS), FiO2, PEEP, Urine Output, icu-store` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 22 | `useInpatientStore` | `Frontend/src/store/useInpatientStore.ts` | 275 | persist=True, tenantStorage=True, localStorage=False | `inpatient-storage` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 23 | `useInsuranceStore` | `Frontend/src/store/useInsuranceStore.ts` | 74 | persist=True, tenantStorage=True, localStorage=False | `insurance-store` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 24 | `useInventoryStore` | `Frontend/src/store/useInventoryStore.ts` | 422 | persist=False, tenantStorage=True, localStorage=False | `None` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 25 | `useInvestigationsStore` | `Frontend/src/store/useInvestigationsStore.ts` | 58 | persist=True, tenantStorage=True, localStorage=False | `medcore-investigations` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 26 | `useLabStore` | `Frontend/src/store/useLabStore.ts` | 326 | persist=True, tenantStorage=True, localStorage=False | `lab-storage` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 27 | `useLayoutStore` | `Frontend/src/store/useLayoutStore.ts` | 2 | persist=False, tenantStorage=False, localStorage=False | `None` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 28 | `useLicenseStore` | `Frontend/src/store/useLicenseStore.ts` | 172 | persist=False, tenantStorage=False, localStorage=True | `None` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 29 | `useMedicalRecordsStore` | `Frontend/src/store/useMedicalRecordsStore.ts` | 174 | persist=True, tenantStorage=True, localStorage=False | `medical-records-storage` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 30 | `useModuleStore` | `Frontend/src/store/useModuleStore.ts` | 428 | persist=True, tenantStorage=True, localStorage=False | `Paracetamol 500mg IV Flacon, Surgical Gloves Size 7.5 Powder-Free, IV Cannula 20G Pink, Ceftriaxone 1g Injection, Saline 0.9% 500ml Infusion, General Consultation (كشف عام), Specialist Consultation (كشف استشاري), Complete Blood Count (CBC), Chest X-Ray PA View, ICU Bed Stay per 24 Hours, admin, dr_sameh, nurse_mona, rec_sara, module-storage` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 31 | `useNicuAdmissionStore` | `Frontend/src/store/useNicuAdmissionStore.ts` | 171 | persist=False, tenantStorage=False, localStorage=False | `None` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 32 | `useNicuRecordStore` | `Frontend/src/store/useNicuRecordStore.ts` | 361 | persist=True, tenantStorage=True, localStorage=False | `nicu-records-storage` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 33 | `useNicuStore` | `Frontend/src/store/useNicuStore.ts` | 233 | persist=True, tenantStorage=True, localStorage=False | `nicu-storage` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 34 | `useNotificationStore` | `Frontend/src/store/useNotificationStore.ts` | 52 | persist=False, tenantStorage=False, localStorage=False | `None` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 35 | `useNursingTasksStore` | `Frontend/src/store/useNursingTasksStore.ts` | 153 | persist=True, tenantStorage=True, localStorage=False | `nursing-tasks-storage` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 36 | `usePatientStore` | `Frontend/src/store/usePatientStore.ts` | 185 | persist=True, tenantStorage=True, localStorage=False | `patient-storage` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 37 | `usePayrollHistoryStore` | `Frontend/src/store/usePayrollHistoryStore.ts` | 57 | persist=True, tenantStorage=True, localStorage=False | `payroll-history-store` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 38 | `usePayrollRulesStore` | `Frontend/src/store/usePayrollRulesStore.ts` | 200 | persist=True, tenantStorage=True, localStorage=False | `غياب بعذر مقبول, غياب بدون عذر, إجازة مرضية معتمدة, إجازة مرضية غير معتمدة, غياب يوم قبل/بعد إجازة رسمية, تأخير أقل من 15 دقيقة, تأخير 15 - 30 دقيقة, تأخير 30 - 60 دقيقة, تأخير أكثر من ساعة, انصراف مبكر بدون إذن, إهمال في العمل, عدم إطاعة الأوامر, مخالفة الزي الموحد, عدم حمل البطاقة التعريفية, مخالفة مكافحة العدوى, خطأ طبي / إهمال تمريضي, تدخين في مكان غير مخصص, استخدام الهاتف في غير العمل, النوم أثناء النبطشية, سوء سلوك مع زميل, شكوى مريض محققة, إتلاف عهدة / جهاز, إهدار المستهلكات الطبية, تأخير تسليم تقرير/نبطشية, تبديل نبطشية بدون إذن, بدل سهر / نبطشية ليلية, بدل عدوى, بدل مخاطر, بدل وجبة, بدل انتقال, بدل استدعاء (On-Call), بدل رعاية مركزة, بدل إشراف, بدل تدريب, بدل سكن, ساعات عمل إضافية (أيام عادية), عمل في إجازة رسمية / جمعة, إضافي ليلي, الحد الأقصى للغياب الشهري, الحد الأدنى لساعات العمل, مكافأة موظف الشهر, مكافأة تقييم ممتاز من مريض, مكافأة مقترح تطوير, مكافأة التزام كامل (0 غياب), منحة الأعياد / سنوية, payroll-rules-store` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 39 | `usePayrollStore` | `Frontend/src/store/usePayrollStore.ts` | 78 | persist=True, tenantStorage=True, localStorage=False | `payroll-store` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 40 | `usePharmacyStore` | `Frontend/src/store/usePharmacyStore.ts` | 200 | persist=True, tenantStorage=True, localStorage=False | `pharmacy-storage` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 41 | `usePrescriptionStore` | `Frontend/src/store/usePrescriptionStore.ts` | 71 | persist=True, tenantStorage=True, localStorage=False | `prescription-autocomplete-storage` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 42 | `useQualityStore` | `Frontend/src/store/useQualityStore.ts` | 96 | persist=True, tenantStorage=True, localStorage=False | `quality-storage` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 43 | `useRadiologyStore` | `Frontend/src/store/useRadiologyStore.ts` | 239 | persist=True, tenantStorage=True, localStorage=False | `radiology-storage` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 44 | `useReceiptStore` | `Frontend/src/store/useReceiptStore.ts` | 31 | persist=True, tenantStorage=True, localStorage=False | `receipt-storage` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 45 | `useReceptionStore` | `Frontend/src/store/useReceptionStore.ts` | 1746 | persist=True, tenantStorage=True, localStorage=False | `عيادة الباطنة والقلب, عيادة الأطفال, عيادة العظام, Checkup, Checkup, reception-storage` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 46 | `useSchedulesStore` | `Frontend/src/store/useSchedulesStore.ts` | 117 | persist=True, tenantStorage=True, localStorage=False | `schedules-storage` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 47 | `useSurgeryBookingStore` | `Frontend/src/store/useSurgeryBookingStore.ts` | 266 | persist=True, tenantStorage=True, localStorage=False | `surgery-booking-storage` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |
| 48 | `useWardStore` | `Frontend/src/store/useWardStore.ts` | 172 | persist=False, tenantStorage=True, localStorage=False | `None` | F (Web Zustand Container) + A/B (Domain Rules/State inside) |

## 4. Complete Modals, Dialogs & Forms Inventory (70 Components)

| # | Component Name | Component File | Lines |
|---|---|---|---|
| 1 | `LoginForm` | `Frontend/src/components/LoginForm.tsx` | 318 |
| 2 | `DynamicTemplateForm` | `Frontend/src/components/clinics/DynamicTemplateForm.tsx` | 546 |
| 3 | `MedicalRecordModal` | `Frontend/src/components/clinics/MedicalRecordModal.tsx` | 41 |
| 4 | `PastMedicalHistoryForm` | `Frontend/src/components/clinics/PastMedicalHistoryForm.tsx` | 218 |
| 5 | `TemplateBuilderModal` | `Frontend/src/components/clinics/TemplateBuilderModal.tsx` | 212 |
| 6 | `FileViewerModal` | `Frontend/src/components/common/FileViewerModal.tsx` | 67 |
| 7 | `NewBookingModal` | `Frontend/src/components/modules/appointments/NewBookingModal.tsx` | 202 |
| 8 | `AiReportGeneratorModal` | `Frontend/src/components/modules/clinics/AiReportGeneratorModal.tsx` | 178 |
| 9 | `BranchesForm` | `Frontend/src/components/modules/definitions/BranchesForm.tsx` | 123 |
| 10 | `ClinicsForm` | `Frontend/src/components/modules/definitions/ClinicsForm.tsx` | 177 |
| 11 | `ConditionsForm` | `Frontend/src/components/modules/definitions/ConditionsForm.tsx` | 271 |
| 12 | `CurrencyForm` | `Frontend/src/components/modules/definitions/CurrencyForm.tsx` | 56 |
| 13 | `DoctorsForm` | `Frontend/src/components/modules/definitions/DoctorsForm.tsx` | 693 |
| 14 | `EmployeesForm` | `Frontend/src/components/modules/definitions/EmployeesForm.tsx` | 409 |
| 15 | `ExternalLabForm` | `Frontend/src/components/modules/definitions/ExternalLabForm.tsx` | 234 |
| 16 | `IcuDevicesForm` | `Frontend/src/components/modules/definitions/IcuDevicesForm.tsx` | 361 |
| 17 | `IcuForm` | `Frontend/src/components/modules/definitions/IcuForm.tsx` | 408 |
| 18 | `IncubatorsForm` | `Frontend/src/components/modules/definitions/IncubatorsForm.tsx` | 211 |
| 19 | `InsuranceForm` | `Frontend/src/components/modules/definitions/InsuranceForm.tsx` | 297 |
| 20 | `LabForm` | `Frontend/src/components/modules/definitions/LabForm.tsx` | 299 |
| 21 | `NicuDevicesForm` | `Frontend/src/components/modules/definitions/NicuDevicesForm.tsx` | 361 |
| 22 | `NicuRoomsForm` | `Frontend/src/components/modules/definitions/NicuRoomsForm.tsx` | 205 |
| 23 | `NursesForm` | `Frontend/src/components/modules/definitions/NursesForm.tsx` | 431 |
| 24 | `OperatingRoomsForm` | `Frontend/src/components/modules/definitions/OperatingRoomsForm.tsx` | 160 |
| 25 | `PaymentMethodsForm` | `Frontend/src/components/modules/definitions/PaymentMethodsForm.tsx` | 162 |
| 26 | `RadiologyForm` | `Frontend/src/components/modules/definitions/RadiologyForm.tsx` | 296 |
| 27 | `ReferralsForm` | `Frontend/src/components/modules/definitions/ReferralsForm.tsx` | 300 |
| 28 | `RoomsForm` | `Frontend/src/components/modules/definitions/RoomsForm.tsx` | 311 |
| 29 | `ServicesForm` | `Frontend/src/components/modules/definitions/ServicesForm.tsx` | 191 |
| 30 | `ClinicSchedulesForm` | `Frontend/src/components/modules/hr/schedules/ClinicSchedulesForm.tsx` | 273 |
| 31 | `EmployeeSchedulesForm` | `Frontend/src/components/modules/hr/schedules/EmployeeSchedulesForm.tsx` | 299 |
| 32 | `NurseSchedulesForm` | `Frontend/src/components/modules/hr/schedules/NurseSchedulesForm.tsx` | 296 |
| 33 | `Apache2CalculatorModal` | `Frontend/src/components/modules/icu/Apache2CalculatorModal.tsx` | 192 |
| 34 | `IcuAdmissionForm` | `Frontend/src/components/modules/icu/IcuAdmissionForm.tsx` | 496 |
| 35 | `IcuAdmissionModal` | `Frontend/src/components/modules/icu/IcuAdmissionModal.tsx` | 328 |
| 36 | `IcuDischargeModal` | `Frontend/src/components/modules/icu/IcuDischargeModal.tsx` | 807 |
| 37 | `SofaCalculatorModal` | `Frontend/src/components/modules/icu/SofaCalculatorModal.tsx` | 187 |
| 38 | `BedAllocationModal` | `Frontend/src/components/modules/inpatient/BedAllocationModal.tsx` | 144 |
| 39 | `StockRequestModal` | `Frontend/src/components/modules/inpatient/StockRequestModal.tsx` | 175 |
| 40 | `WardTransferModal` | `Frontend/src/components/modules/inpatient/WardTransferModal.tsx` | 136 |
| 41 | `AddStockItemModal` | `Frontend/src/components/modules/inventory/AddStockItemModal.tsx` | 290 |
| 42 | `CategoriesManagerModal` | `Frontend/src/components/modules/inventory/CategoriesManagerModal.tsx` | 132 |
| 43 | `EditStockItemModal` | `Frontend/src/components/modules/inventory/EditStockItemModal.tsx` | 243 |
| 44 | `RequestStockModal` | `Frontend/src/components/modules/inventory/RequestStockModal.tsx` | 147 |
| 45 | `StockVoucherModal` | `Frontend/src/components/modules/inventory/StockVoucherModal.tsx` | 174 |
| 46 | `ApgarScoreModal` | `Frontend/src/components/modules/nicu/ApgarScoreModal.tsx` | 213 |
| 47 | `NicuAdmissionForm` | `Frontend/src/components/modules/nicu/NicuAdmissionForm.tsx` | 355 |
| 48 | `NicuDischargeModal` | `Frontend/src/components/modules/nicu/NicuDischargeModal.tsx` | 511 |
| 49 | `PatientDetailsModal` | `Frontend/src/components/modules/patients/PatientDetailsModal.tsx` | 203 |
| 50 | `PatientMedicalHistoryModal` | `Frontend/src/components/modules/patients/PatientMedicalHistoryModal.tsx` | 67 |
| 51 | `PatientRegistrationModal` | `Frontend/src/components/modules/patients/PatientRegistrationModal.tsx` | 342 |
| 52 | `DicomPreviewModal` | `Frontend/src/components/modules/radiology/DicomPreviewModal.tsx` | 197 |
| 53 | `AiTokensDistributionModal` | `Frontend/src/components/modules/settings/AiTokensDistributionModal.tsx` | 201 |
| 54 | `ResourceTopUpModal` | `Frontend/src/components/modules/settings/ResourceTopUpModal.tsx` | 235 |
| 55 | `WardAdmissionForm` | `Frontend/src/components/modules/ward/WardAdmissionForm.tsx` | 180 |
| 56 | `WardDischargeModal` | `Frontend/src/components/modules/ward/WardDischargeModal.tsx` | 356 |
| 57 | `WardTransferModal` | `Frontend/src/components/modules/ward/WardTransferModal.tsx` | 214 |
| 58 | `AddVisitModal` | `Frontend/src/components/reception/AddVisitModal.tsx` | 1428 |
| 59 | `EditVisitModal` | `Frontend/src/components/reception/EditVisitModal.tsx` | 283 |
| 60 | `IcuPatientFinanceModal` | `Frontend/src/components/reception/IcuPatientFinanceModal.tsx` | 473 |
| 61 | `NicuPatientFinanceModal` | `Frontend/src/components/reception/NicuPatientFinanceModal.tsx` | 475 |
| 62 | `PrintReceiptModal` | `Frontend/src/components/reception/PrintReceiptModal.tsx` | 361 |
| 63 | `RefundVisitModal` | `Frontend/src/components/reception/RefundVisitModal.tsx` | 140 |
| 64 | `SurgeryPatientFinanceModal` | `Frontend/src/components/reception/SurgeryPatientFinanceModal.tsx` | 441 |
| 65 | `VisitDetailsModal` | `Frontend/src/components/reception/VisitDetailsModal.tsx` | 226 |
| 66 | `WardPatientFinanceModal` | `Frontend/src/components/reception/WardPatientFinanceModal.tsx` | 473 |
| 67 | `WithdrawalApprovalModal` | `Frontend/src/components/reception/WithdrawalApprovalModal.tsx` | 185 |
| 68 | `UniversalEvaluationForm` | `Frontend/src/components/reports/UniversalEvaluationForm.tsx` | 404 |
| 69 | `CollectPaymentModal` | `Frontend/src/components/shared/CollectPaymentModal.tsx` | 44 |
| 70 | `UniversalReceiptModal` | `Frontend/src/components/shared/UniversalReceiptModal.tsx` | 311 |