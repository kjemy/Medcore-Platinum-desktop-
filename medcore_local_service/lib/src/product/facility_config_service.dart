import 'dart:convert';
import '../db/db_client.dart';
import '../db/transaction_manager.dart';
import '../security/permissions_catalog.dart';
import '../security/rbac_evaluator.dart';

/// Requirement level for a configurable patient field in a facility profile.
enum PatientFieldRequirement {
  hidden,
  optional,
  required;

  static PatientFieldRequirement fromString(String? raw) {
    switch ((raw ?? '').trim().toUpperCase()) {
      case 'REQUIRED':
        return PatientFieldRequirement.required;
      case 'HIDDEN':
      case 'DISABLED':
        return PatientFieldRequirement.hidden;
      default:
        return PatientFieldRequirement.optional;
    }
  }

  String toWire() => name.toUpperCase();
}

/// Canonical MedCore Modules that can be enabled or disabled per installation/edition.
class MedCoreModuleCatalog {
  static const List<String> allModules = [
    'Patients',
    'Appointments',
    'Reception',
    'Shifts',
    'Doctors',
    'Nursing',
    'Inpatient',
    'ICU',
    'Surgery',
    'Dialysis',
    'Laboratory',
    'Radiology',
    'Pharmacy',
    'Finance',
    'CommandCenter',
    'HR',
    'AI',
  ];

  static const List<String> supportedEditions = [
    'SILVER',
    'GOLD',
    'PLATINUM',
    'ADVANCED',
    'ENTERPRISE_LAN',
  ];

  static const List<String> supportedFacilityTypes = [
    'GENERAL_HOSPITAL',
    'SPECIALIZED_CLINIC',
    'DENTAL_CLINIC',
    'DAY_SURGERY_CENTER',
    'DIAGNOSTIC_CENTER',
  ];

  /// Default module presets per edition (can be customized per installation by Technician).
  static Map<String, bool> defaultModulesForEdition(String edition) {
    final normalized = edition.trim().toUpperCase();
    final map = <String, bool>{
      for (final m in allModules) m: true,
    };
    if (normalized == 'SILVER') {
      map['Inpatient'] = false;
      map['ICU'] = false;
      map['Surgery'] = false;
      map['Dialysis'] = false;
      map['AI'] = false;
      map['CommandCenter'] = false;
    } else if (normalized == 'GOLD') {
      map['ICU'] = false;
      map['Dialysis'] = false;
      map['AI'] = false;
    }
    return map;
  }

  /// Default patient field requirement profile per facility type.
  /// Core identity fields (`mrn`, `fullName`, `phone`, `gender`) are structural invariants;
  /// all extended clinical, demographic, insurance, inpatient, ICU, and nursing intake fields
  /// are 100% configuration-driven.
  static Map<String, PatientFieldRequirement> defaultPatientFieldsForFacilityType(
    String facilityType,
  ) {
    final normalized = facilityType.trim().toUpperCase();
    if (normalized == 'DENTAL_CLINIC' || normalized == 'SPECIALIZED_CLINIC') {
      return {
        'dateOfBirth': PatientFieldRequirement.optional,
        'age': PatientFieldRequirement.optional,
        'nationalId': PatientFieldRequirement.optional,
        'bloodGroup': PatientFieldRequirement.hidden,
        'address': PatientFieldRequirement.optional,
        'insuranceCompanyId': PatientFieldRequirement.optional,
        'insurancePolicyNo': PatientFieldRequirement.optional,
        'emergencyContactName': PatientFieldRequirement.hidden,
        'emergencyContactPhone': PatientFieldRequirement.hidden,
        'allergies': PatientFieldRequirement.optional,
        'chronicConditions': PatientFieldRequirement.optional,
        'inpatientAdmissionNotes': PatientFieldRequirement.hidden,
        'icuTriageNotes': PatientFieldRequirement.hidden,
        'nursingIntakeAssessment': PatientFieldRequirement.hidden,
      };
    }
    return {
      'dateOfBirth': PatientFieldRequirement.optional,
      'age': PatientFieldRequirement.optional,
      'nationalId': PatientFieldRequirement.optional,
      'bloodGroup': PatientFieldRequirement.optional,
      'address': PatientFieldRequirement.optional,
      'insuranceCompanyId': PatientFieldRequirement.optional,
      'insurancePolicyNo': PatientFieldRequirement.optional,
      'emergencyContactName': PatientFieldRequirement.optional,
      'emergencyContactPhone': PatientFieldRequirement.optional,
      'allergies': PatientFieldRequirement.optional,
      'chronicConditions': PatientFieldRequirement.optional,
      'inpatientAdmissionNotes': PatientFieldRequirement.optional,
      'icuTriageNotes': PatientFieldRequirement.optional,
      'nursingIntakeAssessment': PatientFieldRequirement.optional,
    };
  }

  static const Map<String, Map<String, String>> patientFieldDefinitions = {
    'dateOfBirth': {'label': 'Date of Birth (YYYY-MM-DD)', 'category': 'DEMOGRAPHICS'},
    'age': {'label': 'Age (Years)', 'category': 'DEMOGRAPHICS'},
    'nationalId': {'label': 'National ID / Passport', 'category': 'DEMOGRAPHICS'},
    'bloodGroup': {'label': 'Blood Group', 'category': 'CLINICAL'},
    'address': {'label': 'Residential Address', 'category': 'DEMOGRAPHICS'},
    'insuranceCompanyId': {'label': 'Insurance Provider Code', 'category': 'FINANCIAL'},
    'insurancePolicyNo': {'label': 'Insurance Policy Number', 'category': 'FINANCIAL'},
    'emergencyContactName': {'label': 'Emergency Contact Name', 'category': 'EMERGENCY'},
    'emergencyContactPhone': {'label': 'Emergency Contact Phone', 'category': 'EMERGENCY'},
    'allergies': {'label': 'Known Allergies (comma-separated)', 'category': 'CLINICAL'},
    'chronicConditions': {'label': 'Chronic Conditions (comma-separated)', 'category': 'CLINICAL'},
    'inpatientAdmissionNotes': {'label': 'Inpatient Pre-Admission Intake', 'category': 'INPATIENT'},
    'icuTriageNotes': {'label': 'ICU / Critical Care Acuity Notes', 'category': 'ICU'},
    'nursingIntakeAssessment': {'label': 'Nursing Initial Triage Notes', 'category': 'NURSING'},
  };

  static String _stripPermissionSuffix(String key) {
    if (key.endsWith('_all')) return key.substring(0, key.length - 4);
    if (key.endsWith('_secure')) return key.substring(0, key.length - 7);
    return key;
  }

  /// Maps any canonical UI permission key or backend dot-notation permission key
  /// to its authoritative MedCore module for fail-closed entitlement enforcement.
  static String? resolveModuleForPermission(String rawPermission) {
    final mappedList = PermissionsCatalog.backendToUiPermissions[rawPermission];
    final mapped = (mappedList != null && mappedList.isNotEmpty) ? mappedList.first : rawPermission;
    final base = _stripPermissionSuffix(mapped);

    if (base == 'patients') return 'Patients';
    if (base == 'appointments') return 'Appointments';
    if (base == 'shifts') return 'Shifts';
    if (base == 'reception' || base.startsWith('reception_')) return 'Reception';
    if (base == 'clinic' ||
        base.startsWith('clinic_') ||
        base == 'doctor' ||
        base.startsWith('doctor_')) {
      return 'Doctors';
    }
    if (base == 'nurse' || base.startsWith('nurse_')) return 'Nursing';
    if (base == 'inpatient' || base.startsWith('inpatient_')) return 'Inpatient';
    if (base == 'icu_nicu' || base.startsWith('icu_nicu_')) return 'ICU';
    if (base == 'surgery' || base.startsWith('surgery_')) return 'Surgery';
    if (base == 'dialysis' || base.startsWith('dialysis_')) return 'Dialysis';
    if (base == 'lab' || base.startsWith('lab_')) return 'Laboratory';
    if (base == 'rad' || base.startsWith('rad_')) return 'Radiology';
    if (base == 'pharmacy_inventory' ||
        base.startsWith('pharmacy_') ||
        base.startsWith('inventory_')) {
      return 'Pharmacy';
    }
    if (base == 'finance' || base.startsWith('finance_')) return 'Finance';
    if (base == 'HMS_summary' ||
        base == 'CommandCenter' ||
        base.startsWith('CommandCenter_')) {
      return 'CommandCenter';
    }
    if (base == 'hr_settings' || base.startsWith('hr_')) return 'HR';
    if (base == 'ai' || base.startsWith('ai_') || rawPermission.startsWith('ai.')) {
      return 'AI';
    }
    // Core platform/system permissions (`dashboard`, `settings_*`, `security_Center`)
    // remain accessible for system administration/diagnostics.
    return null;
  }
}

class BrandingAppearanceConfig {
  final String appDisplayName;
  final String facilityDisplayName;
  final String? logoPathOrUrl;
  final String editionLabel;
  final String primaryColorHex;
  final String themeMode; // LIGHT | DARK | SYSTEM
  final double fontScale; // 0.85 .. 1.30
  final String uiDensity; // COMPACT | STANDARD | COMFORTABLE

  const BrandingAppearanceConfig({
    required this.appDisplayName,
    required this.facilityDisplayName,
    this.logoPathOrUrl,
    required this.editionLabel,
    this.primaryColorHex = '#0F766E',
    this.themeMode = 'LIGHT',
    this.fontScale = 1.0,
    this.uiDensity = 'STANDARD',
  });

  factory BrandingAppearanceConfig.fromJson(
    Map<String, dynamic> json, {
    required String fallbackFacilityName,
    required String fallbackEdition,
  }) {
    final rawScale = (json['fontScale'] is num)
        ? (json['fontScale'] as num).toDouble()
        : double.tryParse(json['fontScale']?.toString() ?? '1.0') ?? 1.0;
    final clampedScale = rawScale.clamp(0.85, 1.30);

    final rawColor = (json['primaryColorHex'] ?? '#0F766E').toString().trim();
    final validColor = RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(rawColor) ? rawColor.toUpperCase() : '#0F766E';

    final rawTheme = (json['themeMode'] ?? 'LIGHT').toString().trim().toUpperCase();
    final validTheme = const {'LIGHT', 'DARK', 'SYSTEM'}.contains(rawTheme) ? rawTheme : 'LIGHT';

    final rawDensity = (json['uiDensity'] ?? 'STANDARD').toString().trim().toUpperCase();
    final validDensity =
        const {'COMPACT', 'STANDARD', 'COMFORTABLE'}.contains(rawDensity) ? rawDensity : 'STANDARD';

    final rawLogo = json['logoPathOrUrl']?.toString().trim();

    return BrandingAppearanceConfig(
      appDisplayName: (json['appDisplayName'] ?? 'MedCore Platinum Desktop').toString().trim(),
      facilityDisplayName: (json['facilityDisplayName'] ?? fallbackFacilityName).toString().trim(),
      logoPathOrUrl: (rawLogo != null && rawLogo.isNotEmpty) ? rawLogo : null,
      editionLabel: (json['editionLabel'] ?? 'MedCore $fallbackEdition').toString().trim(),
      primaryColorHex: validColor,
      themeMode: validTheme,
      fontScale: clampedScale,
      uiDensity: validDensity,
    );
  }

  Map<String, dynamic> toJson() => {
        'appDisplayName': appDisplayName,
        'facilityDisplayName': facilityDisplayName,
        'logoPathOrUrl': logoPathOrUrl,
        'editionLabel': editionLabel,
        'primaryColorHex': primaryColorHex,
        'themeMode': themeMode,
        'fontScale': fontScale,
        'uiDensity': uiDensity,
      };
}

class FacilityConfigurationRecord {
  final String hospitalCode;
  final String facilityName;
  final String facilityType;
  final String branchCode;
  final String installationIdentity;
  final String edition;
  final String? subscriptionStartsUtc;
  final String? subscriptionExpiresUtc;
  final Map<String, bool> enabledModules;
  final Map<String, PatientFieldRequirement> patientFields;
  final BrandingAppearanceConfig branding;
  final Map<String, dynamic> networkConfig;
  final Map<String, dynamic> backupConfig;
  final Map<String, dynamic> remoteHybridConfig;
  final int configVersion;
  final bool isPersistedInConfigTable;
  final String? updatedAt;

  const FacilityConfigurationRecord({
    required this.hospitalCode,
    required this.facilityName,
    required this.facilityType,
    required this.branchCode,
    required this.installationIdentity,
    required this.edition,
    this.subscriptionStartsUtc,
    this.subscriptionExpiresUtc,
    required this.enabledModules,
    required this.patientFields,
    required this.branding,
    required this.networkConfig,
    required this.backupConfig,
    required this.remoteHybridConfig,
    required this.configVersion,
    required this.isPersistedInConfigTable,
    this.updatedAt,
  });

  bool isModuleEnabled(String moduleName) {
    return enabledModules[moduleName] ?? true;
  }

  Map<String, dynamic> toPublicBootstrapJson() => {
        'hospitalCode': hospitalCode,
        'facilityName': facilityName,
        'facilityType': facilityType,
        'branchCode': branchCode,
        'edition': edition,
        'branding': branding.toJson(),
        'networkMode': {
          'allowLanConnections': networkConfig['allowLanConnections'] ?? true,
          'allowWifiConnections': networkConfig['allowWifiConnections'] ?? true,
          'requireExplicitDevicePairing': true,
          'mariaDbLoopbackOnly': true,
          'tlsRuntimeStatus': networkConfig['tlsRuntimeStatus'] ?? 'TLS_CERT_INFRASTRUCTURE_PENDING',
        },
        'configVersion': configVersion,
      };

  Map<String, dynamic> toFullJson() => {
        'hospitalCode': hospitalCode,
        'facilityName': facilityName,
        'facilityType': facilityType,
        'branchCode': branchCode,
        'installationIdentity': installationIdentity,
        'edition': edition,
        'subscriptionStartsUtc': subscriptionStartsUtc,
        'subscriptionExpiresUtc': subscriptionExpiresUtc,
        'enabledModules': enabledModules,
        'patientFields': {
          for (final entry in patientFields.entries) entry.key: entry.value.toWire(),
        },
        'patientFieldCatalog': MedCoreModuleCatalog.patientFieldDefinitions,
        'branding': branding.toJson(),
        'networkConfig': networkConfig,
        'backupConfig': backupConfig,
        'remoteHybridConfig': remoteHybridConfig,
        'configVersion': configVersion,
        'isPersistedInConfigTable': isPersistedInConfigTable,
        'updatedAt': updatedAt,
      };
}

class FacilityConfigService {
  final DbClient db;
  final TransactionManager txManager;

  FacilityConfigService(this.db) : txManager = TransactionManager(db);

  /// Loads authoritative facility configuration from `mc_facility_config`,
  /// falling back deterministically to `mc_tenants` + `mc_license_state` defaults
  /// when a tenant has not yet been customized in Technician Mode.
  Future<FacilityConfigurationRecord> getConfiguration(
    String hospitalCode, {
    SqlExecutor? executor,
  }) async {
    final sql = executor ?? db;
    final cleanCode = hospitalCode.trim();
    if (cleanCode.isEmpty) {
      throw ArgumentError('hospitalCode is required to load facility configuration.');
    }

    final cfgRes = await sql.execute(
      'SELECT * FROM mc_facility_config WHERE hospital_code = :hosp LIMIT 1',
      {'hosp': cleanCode},
    );

    if (cfgRes.rows.isNotEmpty) {
      final r = cfgRes.rows.first;
      final facilityName = r.colByName('facility_name') ?? cleanCode;
      final facilityType = r.colByName('facility_type') ?? 'GENERAL_HOSPITAL';
      final edition = r.colByName('edition') ?? 'PLATINUM';

      final rawModules = _decodeMap(r.colByName('enabled_modules_json'));
      final modules = <String, bool>{
        for (final m in MedCoreModuleCatalog.allModules)
          m: rawModules.containsKey(m) ? rawModules[m] == true : true,
      };

      final defaultFields = MedCoreModuleCatalog.defaultPatientFieldsForFacilityType(facilityType);
      final rawFields = _decodeMap(r.colByName('patient_fields_config_json'));
      final fields = <String, PatientFieldRequirement>{
        for (final key in MedCoreModuleCatalog.patientFieldDefinitions.keys)
          key: rawFields.containsKey(key)
              ? PatientFieldRequirement.fromString(rawFields[key]?.toString())
              : (defaultFields[key] ?? PatientFieldRequirement.optional),
      };

      final branding = BrandingAppearanceConfig.fromJson(
        _decodeMap(r.colByName('branding_appearance_json')),
        fallbackFacilityName: facilityName,
        fallbackEdition: edition,
      );

      return FacilityConfigurationRecord(
        hospitalCode: cleanCode,
        facilityName: facilityName,
        facilityType: facilityType,
        branchCode: r.colByName('branch_code') ?? 'MAIN',
        installationIdentity: r.colByName('installation_identity') ?? 'INST-$cleanCode-MAIN',
        edition: edition,
        subscriptionStartsUtc: r.colByName('subscription_starts_utc'),
        subscriptionExpiresUtc: r.colByName('subscription_expires_utc'),
        enabledModules: modules,
        patientFields: fields,
        branding: branding,
        networkConfig: _normalizeNetworkConfig(_decodeMap(r.colByName('network_config_json'))),
        backupConfig: _normalizeBackupConfig(_decodeMap(r.colByName('backup_config_json'))),
        remoteHybridConfig: _normalizeHybridConfig(_decodeMap(r.colByName('remote_hybrid_config_json'))),
        configVersion: int.tryParse(r.colByName('config_version') ?? '1') ?? 1,
        isPersistedInConfigTable: true,
        updatedAt: r.colByName('updated_at'),
      );
    }

    // Fallback: inspect mc_tenants and mc_license_state without fabricating non-existent rows
    final tenantRes = await sql.execute(
      'SELECT name, edition FROM mc_tenants WHERE hospital_code = :hosp LIMIT 1',
      {'hosp': cleanCode},
    );
    final tenantName = tenantRes.rows.isNotEmpty
        ? (tenantRes.rows.first.colByName('name') ?? cleanCode)
        : cleanCode;
    final tenantEdition = tenantRes.rows.isNotEmpty
        ? (tenantRes.rows.first.colByName('edition') ?? 'ENTERPRISE_LAN')
        : 'ENTERPRISE_LAN';

    final licRes = await sql.execute(
      'SELECT edition, entitled_modules_json, issued_at_utc, expires_at_utc FROM mc_license_state WHERE hospital_code = :hosp LIMIT 1',
      {'hosp': cleanCode},
    );

    final modules = <String, bool>{
      for (final m in MedCoreModuleCatalog.allModules) m: true,
    };
    String? subStart;
    String? subEnd;
    if (licRes.rows.isNotEmpty) {
      final lr = licRes.rows.first;
      subStart = lr.colByName('issued_at_utc');
      subEnd = lr.colByName('expires_at_utc');
      final entitledRaw = lr.colByName('entitled_modules_json');
      if (entitledRaw != null && entitledRaw.trim().isNotEmpty) {
        try {
          final parsed = jsonDecode(entitledRaw);
          if (parsed is Map) {
            for (final m in MedCoreModuleCatalog.allModules) {
              if (parsed.containsKey(m)) modules[m] = parsed[m] == true;
            }
          } else if (parsed is List) {
            final allowed = parsed.map((e) => e.toString()).toSet();
            for (final m in MedCoreModuleCatalog.allModules) {
              modules[m] = allowed.contains(m);
            }
          }
        } catch (_) {}
      }
    }

    return FacilityConfigurationRecord(
      hospitalCode: cleanCode,
      facilityName: tenantName,
      facilityType: 'GENERAL_HOSPITAL',
      branchCode: 'MAIN',
      installationIdentity: 'INST-$cleanCode-MAIN',
      edition: tenantEdition,
      subscriptionStartsUtc: subStart,
      subscriptionExpiresUtc: subEnd,
      enabledModules: modules,
      patientFields: MedCoreModuleCatalog.defaultPatientFieldsForFacilityType('GENERAL_HOSPITAL'),
      branding: BrandingAppearanceConfig(
        appDisplayName: 'MedCore Platinum Desktop',
        facilityDisplayName: tenantName,
        editionLabel: 'MedCore $tenantEdition',
      ),
      networkConfig: _normalizeNetworkConfig(const <String, dynamic>{}),
      backupConfig: _normalizeBackupConfig(const <String, dynamic>{}),
      remoteHybridConfig: _normalizeHybridConfig(const <String, dynamic>{}),
      configVersion: 0,
      isPersistedInConfigTable: false,
    );
  }

  /// Enforces configured module entitlement fail-closed on every backend API call!
  Future<void> enforceModuleEntitlement({
    required String hospitalCode,
    required String requiredPermission,
  }) async {
    final moduleName = MedCoreModuleCatalog.resolveModuleForPermission(requiredPermission);
    if (moduleName == null) return;

    final config = await getConfiguration(hospitalCode);
    if (!config.isModuleEnabled(moduleName)) {
      throw RbacForbiddenException(
        code: 'MODULE_NOT_ENTITLED',
        message:
            'Module "$moduleName" is disabled for facility ${config.facilityName} (Edition: ${config.edition}).',
        requiredPermission: requiredPermission,
      );
    }
  }

  /// Validates incoming patient registration payload against the facility's
  /// configured `REQUIRED` / `HIDDEN` field matrix.
  void validatePatientPayloadAgainstFacilityConfig({
    required FacilityConfigurationRecord config,
    required Map<String, dynamic> body,
  }) {
    for (final entry in config.patientFields.entries) {
      final fieldKey = entry.key;
      final reqLevel = entry.value;
      if (reqLevel == PatientFieldRequirement.required) {
        final val = body[fieldKey];
        final isEmpty = val == null ||
            (val is String && val.trim().isEmpty) ||
            (val is List && val.isEmpty);
        if (isEmpty) {
          throw ArgumentError(
            'MISSING_REQUIRED_PATIENT_FIELD: Field "$fieldKey" is required by ${config.facilityName} (${config.facilityType}) configuration.',
          );
        }
      }
    }
  }

  /// Atomically updates `mc_facility_config`, synchronizes `mc_tenants` (`name`, `edition`),
  /// and writes an immutable audit log entry. Must ONLY be invoked from Protected Technician Mode!
  Future<FacilityConfigurationRecord> saveConfigurationFromTechnician({
    required String hospitalCode,
    required String technicianSessionUuid,
    required Map<String, dynamic> payload,
    String? deviceId,
    String? ipAddress,
  }) async {
    return await txManager.runInTransaction((tx) async {
      final existing = await getConfiguration(hospitalCode, executor: tx);

      final tenantCheck = await tx.execute(
        'SELECT id FROM mc_tenants WHERE hospital_code = :hosp LIMIT 1',
        {'hosp': hospitalCode},
      );
      if (tenantCheck.rows.isEmpty) {
        throw StateError('Hospital tenant $hospitalCode does not exist in mc_tenants.');
      }

      final facilityName =
          (payload['facilityName'] ?? existing.facilityName).toString().trim();
      if (facilityName.isEmpty) {
        throw ArgumentError('facilityName cannot be empty.');
      }

      final facilityType = (payload['facilityType'] ?? existing.facilityType)
          .toString()
          .trim()
          .toUpperCase();
      if (!MedCoreModuleCatalog.supportedFacilityTypes.contains(facilityType)) {
        throw ArgumentError(
          'Unsupported facilityType "$facilityType". Allowed: ${MedCoreModuleCatalog.supportedFacilityTypes.join(', ')}',
        );
      }

      final edition =
          (payload['edition'] ?? existing.edition).toString().trim().toUpperCase();
      if (!MedCoreModuleCatalog.supportedEditions.contains(edition)) {
        throw ArgumentError(
          'Unsupported edition "$edition". Allowed: ${MedCoreModuleCatalog.supportedEditions.join(', ')}',
        );
      }

      final branchCode =
          (payload['branchCode'] ?? existing.branchCode).toString().trim();
      final installationIdentity =
          (payload['installationIdentity'] ?? existing.installationIdentity)
              .toString()
              .trim();

      final subStart = _normalizeOptionalDateTime(
        payload.containsKey('subscriptionStartsUtc')
            ? payload['subscriptionStartsUtc']?.toString()
            : existing.subscriptionStartsUtc,
      );
      final subEnd = _normalizeOptionalDateTime(
        payload.containsKey('subscriptionExpiresUtc')
            ? payload['subscriptionExpiresUtc']?.toString()
            : existing.subscriptionExpiresUtc,
      );

      final updatedModules = Map<String, bool>.from(existing.enabledModules);
      if (payload['applyEditionModulePreset'] == true) {
        updatedModules.addAll(MedCoreModuleCatalog.defaultModulesForEdition(edition));
      }
      if (payload['enabledModules'] is Map) {
        final rawMods = Map<String, dynamic>.from(payload['enabledModules'] as Map);
        for (final m in MedCoreModuleCatalog.allModules) {
          if (rawMods.containsKey(m)) {
            updatedModules[m] = rawMods[m] == true;
          }
        }
      }

      final updatedPatientFields =
          Map<String, PatientFieldRequirement>.from(existing.patientFields);
      if (payload['applyFacilityTypePatientPreset'] == true) {
        updatedPatientFields.addAll(
          MedCoreModuleCatalog.defaultPatientFieldsForFacilityType(facilityType),
        );
      }
      if (payload['patientFields'] is Map) {
        final rawPf = Map<String, dynamic>.from(payload['patientFields'] as Map);
        for (final k in MedCoreModuleCatalog.patientFieldDefinitions.keys) {
          if (rawPf.containsKey(k)) {
            updatedPatientFields[k] =
                PatientFieldRequirement.fromString(rawPf[k]?.toString());
          }
        }
      }

      final brandingMap = <String, dynamic>{
        ...existing.branding.toJson(),
        if (payload['branding'] is Map)
          ...Map<String, dynamic>.from(payload['branding'] as Map),
      };
      if (payload['branding'] is! Map ||
          !(payload['branding'] as Map).containsKey('facilityDisplayName')) {
        brandingMap['facilityDisplayName'] = facilityName;
      }
      if (payload['branding'] is! Map ||
          !(payload['branding'] as Map).containsKey('editionLabel')) {
        brandingMap['editionLabel'] = 'MedCore $edition';
      }
      final updatedBranding = BrandingAppearanceConfig.fromJson(
        brandingMap,
        fallbackFacilityName: facilityName,
        fallbackEdition: edition,
      );

      final updatedNetwork = _normalizeNetworkConfig({
        ...existing.networkConfig,
        if (payload['networkConfig'] is Map)
          ...Map<String, dynamic>.from(payload['networkConfig'] as Map),
      });

      final updatedBackup = _normalizeBackupConfig({
        ...existing.backupConfig,
        if (payload['backupConfig'] is Map)
          ...Map<String, dynamic>.from(payload['backupConfig'] as Map),
      });

      final updatedHybrid = _normalizeHybridConfig({
        ...existing.remoteHybridConfig,
        if (payload['remoteHybridConfig'] is Map)
          ...Map<String, dynamic>.from(payload['remoteHybridConfig'] as Map),
      });

      final nextVersion = existing.configVersion + 1;

      await tx.execute(
        '''
        INSERT INTO mc_facility_config (
          hospital_code, facility_name, facility_type, branch_code, installation_identity,
          edition, subscription_starts_utc, subscription_expires_utc,
          enabled_modules_json, patient_fields_config_json, branding_appearance_json,
          network_config_json, backup_config_json, remote_hybrid_config_json,
          config_version, updated_by_tech_session
        ) VALUES (
          :hosp, :fname, :ftype, :branch, :inst,
          :edition, :sub_start, :sub_end,
          :mods_json, :pf_json, :brand_json,
          :net_json, :bak_json, :hyb_json,
          :ver, :tech_sess
        )
        ON DUPLICATE KEY UPDATE
          facility_name = VALUES(facility_name),
          facility_type = VALUES(facility_type),
          branch_code = VALUES(branch_code),
          installation_identity = VALUES(installation_identity),
          edition = VALUES(edition),
          subscription_starts_utc = VALUES(subscription_starts_utc),
          subscription_expires_utc = VALUES(subscription_expires_utc),
          enabled_modules_json = VALUES(enabled_modules_json),
          patient_fields_config_json = VALUES(patient_fields_config_json),
          branding_appearance_json = VALUES(branding_appearance_json),
          network_config_json = VALUES(network_config_json),
          backup_config_json = VALUES(backup_config_json),
          remote_hybrid_config_json = VALUES(remote_hybrid_config_json),
          config_version = VALUES(config_version),
          updated_by_tech_session = VALUES(updated_by_tech_session)
        ''',
        {
          'hosp': hospitalCode,
          'fname': facilityName,
          'ftype': facilityType,
          'branch': branchCode.isEmpty ? 'MAIN' : branchCode,
          'inst': installationIdentity.isEmpty
              ? 'INST-$hospitalCode-MAIN'
              : installationIdentity,
          'edition': edition,
          'sub_start': subStart,
          'sub_end': subEnd,
          'mods_json': jsonEncode(updatedModules),
          'pf_json': jsonEncode({
            for (final e in updatedPatientFields.entries) e.key: e.value.toWire(),
          }),
          'brand_json': jsonEncode(updatedBranding.toJson()),
          'net_json': jsonEncode(updatedNetwork),
          'bak_json': jsonEncode(updatedBackup),
          'hyb_json': jsonEncode(updatedHybrid),
          'ver': nextVersion,
          'tech_sess': technicianSessionUuid,
        },
      );

      // Keep mc_tenants name & edition synchronized with authoritative facility config
      await tx.execute(
        '''
        UPDATE mc_tenants
        SET name = :fname, edition = :edition
        WHERE hospital_code = :hosp
        ''',
        {
          'fname': facilityName,
          'edition': edition,
          'hosp': hospitalCode,
        },
      );

      await tx.writeAuditLog(
        hospitalCode: hospitalCode,
        actorRole: 'TECHNICIAN_SERVICE',
        deviceId: deviceId,
        action: 'technician.facility_config.updated',
        entityType: 'mc_facility_config',
        entityId: hospitalCode,
        beforeState: existing.toFullJson(),
        afterState: {
          'facilityName': facilityName,
          'facilityType': facilityType,
          'edition': edition,
          'configVersion': nextVersion,
          'technicianSessionUuid': technicianSessionUuid,
        },
        ipAddress: ipAddress,
      );

      return await getConfiguration(hospitalCode, executor: tx);
    });
  }

  static String? _normalizeOptionalDateTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(raw.trim());
    if (parsed == null) {
      throw ArgumentError('Invalid ISO-8601 datetime value: "$raw".');
    }
    final u = parsed.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year}-${two(u.month)}-${two(u.day)} ${two(u.hour)}:${two(u.minute)}:${two(u.second)}';
  }

  static Map<String, dynamic> _normalizeNetworkConfig(Map<String, dynamic> raw) {
    return {
      'serviceBindMode': (raw['serviceBindMode'] ?? 'LOOPBACK_ONLY').toString(),
      'allowLanConnections': raw['allowLanConnections'] ?? true,
      'allowWifiConnections': raw['allowWifiConnections'] ?? true,
      'maxAuthorizedDevices': (raw['maxAuthorizedDevices'] is int)
          ? raw['maxAuthorizedDevices']
          : int.tryParse(raw['maxAuthorizedDevices']?.toString() ?? '25') ?? 25,
      'requireExplicitPairingApproval': true, // Security invariant: never disable
      'mariaDbBindAddress': '127.0.0.1', // Security invariant: never expose DB to LAN/Wi-Fi
      'tlsRuntimeStatus': 'TLS_CERT_INFRASTRUCTURE_PENDING',
    };
  }

  static Map<String, dynamic> _normalizeBackupConfig(Map<String, dynamic> raw) {
    final activeProvider =
        (raw['activeProvider'] ?? 'LOCAL_STORAGE').toString().trim().toUpperCase();
    return {
      'activeProvider': const {'LOCAL_STORAGE', 'S3_COMPATIBLE', 'CLOUD_ADAPTER'}
              .contains(activeProvider)
          ? activeProvider
          : 'LOCAL_STORAGE',
      'localBackupDirectory': (raw['localBackupDirectory'] ?? 'backups/local').toString(),
      'compressGzip': raw['compressGzip'] ?? true,
      'requireEncryptionForRemote': true,
      'verifyChecksumOnWrite': true,
      's3Compatible': {
        'vendorPreset': (raw['s3VendorPreset'] ??
                (raw['s3Compatible'] is Map
                    ? (raw['s3Compatible'] as Map)['vendorPreset']
                    : null) ??
                'VENDOR_NEUTRAL_S3')
            .toString(),
        'endpointUrl': (raw['s3Compatible'] is Map
                ? (raw['s3Compatible'] as Map)['endpointUrl']
                : '') ??
            '',
        'region': (raw['s3Compatible'] is Map
                ? (raw['s3Compatible'] as Map)['region']
                : 'auto') ??
            'auto',
        'bucket': (raw['s3Compatible'] is Map
                ? (raw['s3Compatible'] as Map)['bucket']
                : '') ??
            '',
        'keyPrefix': (raw['s3Compatible'] is Map
                ? (raw['s3Compatible'] as Map)['keyPrefix']
                : 'medcore-backups/') ??
            'medcore-backups/',
        'credentialsSource': 'ENV_OR_SECURE_KEYSTORE_ONLY',
      },
    };
  }

  static Map<String, dynamic> _normalizeHybridConfig(Map<String, dynamic> raw) {
    return {
      'operationalMode': 'LOCAL_FIRST',
      'internetRequiredForHospitalOperations': false,
      'remoteInternetAccessEnabled': false, // Explicitly deferred per P2 governance
      'futureCloudBackupReady': true,
      'futureRemoteGatewayReady': true,
      'futureOptionalRemoteReportingReady': raw['futureOptionalRemoteReportingReady'] ?? false,
    };
  }

  static Map<String, dynamic> _decodeMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return const <String, dynamic>{};
  }
}
