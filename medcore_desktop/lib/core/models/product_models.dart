import 'package:flutter/material.dart';

class BrandingConfig {
  final String appDisplayName;
  final String facilityDisplayName;
  final String? logoPathOrUrl;
  final String editionLabel;
  final String primaryColorHex;
  final String themeMode; // LIGHT | DARK | SYSTEM
  final double fontScale;
  final String uiDensity; // COMPACT | STANDARD | COMFORTABLE

  const BrandingConfig({
    this.appDisplayName = 'MedCore Platinum Desktop',
    this.facilityDisplayName = 'MedCore Facility',
    this.logoPathOrUrl,
    this.editionLabel = 'MedCore PLATINUM',
    this.primaryColorHex = '#0F766E',
    this.themeMode = 'LIGHT',
    this.fontScale = 1.0,
    this.uiDensity = 'STANDARD',
  });

  factory BrandingConfig.fromJson(Map<String, dynamic> json) {
    final scaleRaw = json['fontScale'];
    final scale = (scaleRaw is num)
        ? scaleRaw.toDouble()
        : double.tryParse(scaleRaw?.toString() ?? '1.0') ?? 1.0;

    return BrandingConfig(
      appDisplayName: (json['appDisplayName'] ?? 'MedCore Platinum Desktop').toString(),
      facilityDisplayName: (json['facilityDisplayName'] ?? 'MedCore Facility').toString(),
      logoPathOrUrl: json['logoPathOrUrl']?.toString(),
      editionLabel: (json['editionLabel'] ?? 'MedCore PLATINUM').toString(),
      primaryColorHex: (json['primaryColorHex'] ?? '#0F766E').toString(),
      themeMode: (json['themeMode'] ?? 'LIGHT').toString().toUpperCase(),
      fontScale: scale.clamp(0.85, 1.30),
      uiDensity: (json['uiDensity'] ?? 'STANDARD').toString().toUpperCase(),
    );
  }

  Color get seedColor {
    final hex = primaryColorHex.replaceFirst('#', '').trim();
    if (hex.length == 6) {
      final parsed = int.tryParse('FF$hex', radix: 16);
      if (parsed != null) return Color(parsed);
    }
    return const Color(0xFF0F766E);
  }

  ThemeMode get flutterThemeMode {
    switch (themeMode) {
      case 'DARK':
        return ThemeMode.dark;
      case 'SYSTEM':
        return ThemeMode.system;
      default:
        return ThemeMode.light;
    }
  }

  VisualDensity get flutterVisualDensity {
    switch (uiDensity) {
      case 'COMPACT':
        return VisualDensity.compact;
      case 'COMFORTABLE':
        return VisualDensity.comfortable;
      default:
        return VisualDensity.standard;
    }
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

class FacilityConfigModel {
  final String hospitalCode;
  final String facilityName;
  final String facilityType;
  final String branchCode;
  final String installationIdentity;
  final String edition;
  final String? subscriptionStartsUtc;
  final String? subscriptionExpiresUtc;
  final Map<String, bool> enabledModules;
  final Map<String, String> patientFields; // key -> REQUIRED | OPTIONAL | HIDDEN
  final Map<String, Map<String, String>> patientFieldCatalog;
  final BrandingConfig branding;
  final Map<String, dynamic> networkConfig;
  final Map<String, dynamic> backupConfig;
  final Map<String, dynamic> remoteHybridConfig;
  final int configVersion;

  const FacilityConfigModel({
    required this.hospitalCode,
    required this.facilityName,
    this.facilityType = 'GENERAL_HOSPITAL',
    this.branchCode = 'MAIN',
    this.installationIdentity = 'INST-MAIN',
    this.edition = 'PLATINUM',
    this.subscriptionStartsUtc,
    this.subscriptionExpiresUtc,
    this.enabledModules = const <String, bool>{},
    this.patientFields = const <String, String>{},
    this.patientFieldCatalog = const <String, Map<String, String>>{},
    this.branding = const BrandingConfig(),
    this.networkConfig = const <String, dynamic>{},
    this.backupConfig = const <String, dynamic>{},
    this.remoteHybridConfig = const <String, dynamic>{},
    this.configVersion = 0,
  });

  bool isModuleEnabled(String moduleName) => enabledModules[moduleName] ?? true;

  String fieldRequirement(String fieldKey) =>
      (patientFields[fieldKey] ?? 'OPTIONAL').toUpperCase();

  factory FacilityConfigModel.fromFullJson(Map<String, dynamic> json) {
    final mods = <String, bool>{};
    if (json['enabledModules'] is Map) {
      for (final e in (json['enabledModules'] as Map).entries) {
        mods[e.key.toString()] = e.value == true;
      }
    }

    final pFields = <String, String>{};
    if (json['patientFields'] is Map) {
      for (final e in (json['patientFields'] as Map).entries) {
        pFields[e.key.toString()] = e.value.toString().toUpperCase();
      }
    }

    final catalog = <String, Map<String, String>>{};
    if (json['patientFieldCatalog'] is Map) {
      for (final e in (json['patientFieldCatalog'] as Map).entries) {
        if (e.value is Map) {
          catalog[e.key.toString()] = {
            for (final ce in (e.value as Map).entries)
              ce.key.toString(): ce.value.toString(),
          };
        }
      }
    }

    return FacilityConfigModel(
      hospitalCode: (json['hospitalCode'] ?? '').toString(),
      facilityName: (json['facilityName'] ?? 'MedCore Facility').toString(),
      facilityType: (json['facilityType'] ?? 'GENERAL_HOSPITAL').toString(),
      branchCode: (json['branchCode'] ?? 'MAIN').toString(),
      installationIdentity: (json['installationIdentity'] ?? '').toString(),
      edition: (json['edition'] ?? 'PLATINUM').toString(),
      subscriptionStartsUtc: json['subscriptionStartsUtc']?.toString(),
      subscriptionExpiresUtc: json['subscriptionExpiresUtc']?.toString(),
      enabledModules: mods,
      patientFields: pFields,
      patientFieldCatalog: catalog,
      branding: json['branding'] is Map
          ? BrandingConfig.fromJson(Map<String, dynamic>.from(json['branding'] as Map))
          : const BrandingConfig(),
      networkConfig: json['networkConfig'] is Map
          ? Map<String, dynamic>.from(json['networkConfig'] as Map)
          : const <String, dynamic>{},
      backupConfig: json['backupConfig'] is Map
          ? Map<String, dynamic>.from(json['backupConfig'] as Map)
          : const <String, dynamic>{},
      remoteHybridConfig: json['remoteHybridConfig'] is Map
          ? Map<String, dynamic>.from(json['remoteHybridConfig'] as Map)
          : const <String, dynamic>{},
      configVersion: int.tryParse(json['configVersion']?.toString() ?? '0') ?? 0,
    );
  }

  factory FacilityConfigModel.fromBootstrapJson(Map<String, dynamic> json) {
    return FacilityConfigModel(
      hospitalCode: (json['hospitalCode'] ?? '').toString(),
      facilityName: (json['facilityName'] ?? 'MedCore Facility').toString(),
      facilityType: (json['facilityType'] ?? 'GENERAL_HOSPITAL').toString(),
      branchCode: (json['branchCode'] ?? 'MAIN').toString(),
      edition: (json['edition'] ?? 'PLATINUM').toString(),
      branding: json['branding'] is Map
          ? BrandingConfig.fromJson(Map<String, dynamic>.from(json['branding'] as Map))
          : const BrandingConfig(),
      networkConfig: json['networkMode'] is Map
          ? Map<String, dynamic>.from(json['networkMode'] as Map)
          : const <String, dynamic>{},
      configVersion: int.tryParse(json['configVersion']?.toString() ?? '0') ?? 0,
    );
  }
}

class AuthenticatedStaffUser {
  final int id;
  final String hospitalCode;
  final String staffCode;
  final String fullName;
  final String email;
  final String role;
  final Set<String> effectivePermissions;
  final bool canEdit;
  final bool canDelete;
  final bool canCollectMoney;
  final bool canMakeRefunds;
  final String refundPolicy;

  const AuthenticatedStaffUser({
    required this.id,
    required this.hospitalCode,
    required this.staffCode,
    required this.fullName,
    required this.email,
    required this.role,
    required this.effectivePermissions,
    required this.canEdit,
    required this.canDelete,
    required this.canCollectMoney,
    required this.canMakeRefunds,
    required this.refundPolicy,
  });

  bool hasAnyPermission(Iterable<String> keys) {
    if (keys.isEmpty) return true;
    for (final k in keys) {
      if (effectivePermissions.contains(k) || effectivePermissions.contains('${k}_all')) {
        return true;
      }
    }
    return false;
  }

  factory AuthenticatedStaffUser.fromJson(Map<String, dynamic> json) {
    final perms = <String>{};
    if (json['effectivePermissions'] is List) {
      for (final p in json['effectivePermissions'] as List) {
        perms.add(p.toString());
      }
    }
    final flags = json['operationalFlags'] is Map
        ? Map<String, dynamic>.from(json['operationalFlags'] as Map)
        : const <String, dynamic>{};

    return AuthenticatedStaffUser(
      id: int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      hospitalCode: (json['hospitalCode'] ?? '').toString(),
      staffCode: (json['staffCode'] ?? '').toString(),
      fullName: (json['fullName'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      role: (json['role'] ?? 'Employee').toString(),
      effectivePermissions: perms,
      canEdit: flags['canEdit'] == true,
      canDelete: flags['canDelete'] == true,
      canCollectMoney: flags['canCollectMoney'] == true,
      canMakeRefunds: flags['canMakeRefunds'] == true,
      refundPolicy: (flags['refundPolicy'] ?? 'none').toString(),
    );
  }
}

class TechnicianSessionInfo {
  final String sessionUuid;
  final String hospitalCode;
  final String authMethod;
  final String deviceId;
  final String expiresAt;

  const TechnicianSessionInfo({
    required this.sessionUuid,
    required this.hospitalCode,
    required this.authMethod,
    required this.deviceId,
    required this.expiresAt,
  });

  factory TechnicianSessionInfo.fromJson(Map<String, dynamic> json) {
    return TechnicianSessionInfo(
      sessionUuid: (json['sessionUuid'] ?? '').toString(),
      hospitalCode: (json['hospitalCode'] ?? '').toString(),
      authMethod: (json['authMethod'] ?? '').toString(),
      deviceId: (json['deviceId'] ?? '').toString(),
      expiresAt: (json['expiresAt'] ?? '').toString(),
    );
  }
}
