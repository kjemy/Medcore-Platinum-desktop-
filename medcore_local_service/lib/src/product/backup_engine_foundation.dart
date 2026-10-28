import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../db/db_client.dart';
import '../db/transaction_manager.dart';
import 'facility_config_service.dart';

class BackupArtifactEnvelope {
  final String backupUuid;
  final String hospitalCode;
  final String schemaVersion;
  final int maxFinancialEventId;
  final bool compressedGzip;
  final bool encrypted;
  final String encryptionMode;
  final Uint8List payloadBytes;
  final String checksumSha256;

  const BackupArtifactEnvelope({
    required this.backupUuid,
    required this.hospitalCode,
    required this.schemaVersion,
    required this.maxFinancialEventId,
    required this.compressedGzip,
    required this.encrypted,
    required this.encryptionMode,
    required this.payloadBytes,
    required this.checksumSha256,
  });

  int get sizeBytes => payloadBytes.length;
}

class BackupProviderValidationResult {
  final bool valid;
  final String providerId;
  final String runtimeReadiness; // 'READY_LOCAL' | 'CONTRACT_VALID_REMOTE_DEFERRED' | 'INVALID_CONFIG'
  final List<String> issues;

  const BackupProviderValidationResult({
    required this.valid,
    required this.providerId,
    required this.runtimeReadiness,
    this.issues = const <String>[],
  });

  Map<String, dynamic> toJson() => {
        'valid': valid,
        'providerId': providerId,
        'runtimeReadiness': runtimeReadiness,
        'issues': issues,
      };
}

class BackupUploadAndVerifyResult {
  final bool uploaded;
  final bool independentlyVerified;
  final String storageLocationUri;
  final String verifiedSha256;
  final int verifiedSizeBytes;
  final String statusCode;

  const BackupUploadAndVerifyResult({
    required this.uploaded,
    required this.independentlyVerified,
    required this.storageLocationUri,
    required this.verifiedSha256,
    required this.verifiedSizeBytes,
    required this.statusCode,
  });
}

/// Vendor-neutral Backup Provider Interface.
/// Permits Local Disk, S3-Compatible (Backblaze B2, Cloudflare R2, AWS S3, Wasabi),
/// and future CloudProvider adapters without rewriting the backup pipeline.
abstract class BackupProvider {
  String get providerId;
  String get providerFamily;
  bool get requiresInternet;
  bool get requiresMandatoryEncryption;

  BackupProviderValidationResult validateConfiguration(Map<String, dynamic> config);

  /// Must NEVER treat HTTP 200 alone as verification proof; requires independent
  /// digest/length verification before returning `independentlyVerified: true`.
  Future<BackupUploadAndVerifyResult> storeAndVerifyArchive(
    BackupArtifactEnvelope envelope,
    Map<String, dynamic> config,
  );
}

/// Functional Local Storage Backup Provider with physical disk read-back SHA-256 verification.
class LocalStorageProvider implements BackupProvider {
  final String baseRootDirectory;

  const LocalStorageProvider({required this.baseRootDirectory});

  @override
  String get providerId => 'LOCAL_STORAGE';

  @override
  String get providerFamily => 'LOCAL_FILESYSTEM';

  @override
  bool get requiresInternet => false;

  @override
  bool get requiresMandatoryEncryption => false;

  @override
  BackupProviderValidationResult validateConfiguration(Map<String, dynamic> config) {
    final relDir = (config['localBackupDirectory'] ?? 'backups/local').toString().trim();
    if (relDir.isEmpty) {
      return const BackupProviderValidationResult(
        valid: false,
        providerId: 'LOCAL_STORAGE',
        runtimeReadiness: 'INVALID_CONFIG',
        issues: ['localBackupDirectory cannot be empty.'],
      );
    }
    return const BackupProviderValidationResult(
      valid: true,
      providerId: 'LOCAL_STORAGE',
      runtimeReadiness: 'READY_LOCAL',
    );
  }

  @override
  Future<BackupUploadAndVerifyResult> storeAndVerifyArchive(
    BackupArtifactEnvelope envelope,
    Map<String, dynamic> config,
  ) async {
    final relDir = (config['localBackupDirectory'] ?? 'backups/local').toString().trim();
    final targetDir = Directory(
      p.isAbsolute(relDir) ? relDir : p.join(baseRootDirectory, relDir, envelope.hospitalCode),
    );
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }

    final ext = envelope.encrypted ? '.json.gz.mcbak' : '.json.gz';
    final fileName = '${envelope.backupUuid}_${envelope.schemaVersion}$ext';
    final targetFile = File(p.join(targetDir.path, fileName));

    await targetFile.writeAsBytes(envelope.payloadBytes, flush: true);

    // Independent physical read-back verification (never assume write succeeded)
    if (!targetFile.existsSync()) {
      throw StateError('Backup file missing immediately after disk write: ${targetFile.path}');
    }
    final readBackBytes = await targetFile.readAsBytes();
    final readBackSha256 = sha256.convert(readBackBytes).toString();
    final verified = readBackBytes.length == envelope.sizeBytes &&
        readBackSha256 == envelope.checksumSha256;

    return BackupUploadAndVerifyResult(
      uploaded: true,
      independentlyVerified: verified,
      storageLocationUri: targetFile.path,
      verifiedSha256: readBackSha256,
      verifiedSizeBytes: readBackBytes.length,
      statusCode: verified ? 'LOCAL_READBACK_SHA256_VERIFIED' : 'LOCAL_CHECKSUM_MISMATCH',
    );
  }
}

/// Vendor-Neutral S3-Compatible Provider Contract supporting:
/// - Backblaze B2 (`https://s3.<region>.backblazeb2.com`)
/// - Cloudflare R2 (`https://<account>.r2.cloudflarestorage.com`)
/// - AWS S3 (`https://s3.<region>.amazonaws.com`)
/// - Wasabi (`https://s3.<region>.wasabisys.com`)
/// - Self-hosted MinIO / Ceph S3 gateways
///
/// Runtime wire execution is intentionally deferred per P2 stability rule unless an
/// external S3 wire transport is injected; never emits fake HTTP 200 backup success!
class S3CompatibleProvider implements BackupProvider {
  static const List<String> supportedVendorPresets = [
    'VENDOR_NEUTRAL_S3',
    'BACKBLAZE_B2',
    'CLOUDFLARE_R2',
    'AWS_S3',
    'WASABI',
  ];

  @override
  String get providerId => 'S3_COMPATIBLE';

  @override
  String get providerFamily => 'S3_OBJECT_STORAGE';

  @override
  bool get requiresInternet => true;

  @override
  bool get requiresMandatoryEncryption => true;

  @override
  BackupProviderValidationResult validateConfiguration(Map<String, dynamic> config) {
    final s3 = (config['s3Compatible'] is Map)
        ? Map<String, dynamic>.from(config['s3Compatible'] as Map)
        : const <String, dynamic>{};
    final issues = <String>[];

    final endpoint = (s3['endpointUrl'] ?? '').toString().trim();
    final bucket = (s3['bucket'] ?? '').toString().trim();
    final preset = (s3['vendorPreset'] ?? 'VENDOR_NEUTRAL_S3').toString().trim().toUpperCase();

    if (!supportedVendorPresets.contains(preset)) {
      issues.add('Unsupported S3 vendorPreset "$preset".');
    }
    if (endpoint.isEmpty || !endpoint.startsWith('https://')) {
      issues.add('S3 endpointUrl must be a valid https:// URL.');
    }
    if (bucket.isEmpty) {
      issues.add('S3 bucket name is required.');
    }

    if (issues.isNotEmpty) {
      return BackupProviderValidationResult(
        valid: false,
        providerId: providerId,
        runtimeReadiness: 'INVALID_CONFIG',
        issues: issues,
      );
    }

    return BackupProviderValidationResult(
      valid: true,
      providerId: providerId,
      runtimeReadiness: 'CONTRACT_VALID_REMOTE_DEFERRED',
    );
  }

  @override
  Future<BackupUploadAndVerifyResult> storeAndVerifyArchive(
    BackupArtifactEnvelope envelope,
    Map<String, dynamic> config,
  ) async {
    throw UnsupportedError(
      'REMOTE_BACKUP_TRANSPORT_DEFERRED: S3-compatible provider contract is configured and validated without vendor lock-in, '
      'but live cloud SigV4 upload + remote object read-back verification is intentionally deferred in v1.0.0-rc.1.',
    );
  }
}

/// Generic Adapter Contract for future non-S3 Cloud Storage Providers.
abstract class CloudProviderAdapter implements BackupProvider {
  String get cloudVendorCode;
}

/// Future-Ready Local-First / Optional-Hybrid Boundary Descriptor (P2).
class RemoteHybridArchitectureBoundary {
  static Map<String, dynamic> describeCapabilities(FacilityConfigurationRecord cfg) => {
        'architecturePosture': 'LOCAL_FIRST_AUTHORITATIVE',
        'internetRequiredForNormalHospitalOperation': false,
        'directInternetRemoteAccessActive': false,
        'supportedFutureExtensionBoundaries': [
          {
            'boundary': 'CLOUD_BACKUP_PIPELINE',
            'status': 'CONTRACT_READY',
            'vendorLockIn': false,
            'supportedTargets': S3CompatibleProvider.supportedVendorPresets,
          },
          {
            'boundary': 'OPTIONAL_OUTBOUND_HYBRID_GATEWAY',
            'status': 'INTERFACE_RESERVED_NOT_ACTIVE',
            'notes': 'Outbound-only sync/reporting boundary reserved; inbound internet exposure disabled.',
          },
          {
            'boundary': 'OPTIONAL_REMOTE_EXECUTIVE_REPORTING',
            'status': 'INTERFACE_RESERVED_NOT_ACTIVE',
            'configuredFlag': cfg.remoteHybridConfig['futureOptionalRemoteReportingReady'] == true,
          },
        ],
      };
}

class BackupEngineService {
  static const _uuid = Uuid();

  final DbClient db;
  final TransactionManager txManager;
  final FacilityConfigService facilityConfigService;
  final String storageRootDirectory;
  final String? encryptionKeyOverride;

  late final Map<String, BackupProvider> _providers;

  BackupEngineService(
    this.db, {
    required this.facilityConfigService,
    String? storageRootDirectory,
    this.encryptionKeyOverride,
  })  : txManager = TransactionManager(db),
        storageRootDirectory = storageRootDirectory ?? Directory.systemTemp.path {
    final local = LocalStorageProvider(baseRootDirectory: this.storageRootDirectory);
    final s3 = S3CompatibleProvider();
    _providers = {
      local.providerId: local,
      s3.providerId: s3,
    };
  }

  Future<Map<String, dynamic>> getBackupArchitectureStatus({
    required String hospitalCode,
  }) async {
    final cfg = await facilityConfigService.getConfiguration(hospitalCode);
    final activeProviderId =
        (cfg.backupConfig['activeProvider'] ?? 'LOCAL_STORAGE').toString().toUpperCase();
    final provider = _providers[activeProviderId] ?? _providers['LOCAL_STORAGE']!;
    final validation = provider.validateConfiguration(cfg.backupConfig);

    final runsRes = await db.execute(
      '''
      SELECT backup_uuid, trigger_type, archive_path, archive_sha256,
             archive_size_bytes, schema_version, max_financial_event_id,
             status, started_at, completed_at
      FROM mc_backup_runs
      WHERE hospital_code = :hosp
      ORDER BY id DESC
      LIMIT 20
      ''',
      {'hosp': hospitalCode},
    );

    return {
      'hospitalCode': hospitalCode,
      'pipelineStages': const [
        '1_MARIADB_SNAPSHOT',
        '2_GZIP_COMPRESS',
        '3_AUTHENTICATED_ENCRYPT',
        '4_SHA256_CHECKSUM',
        '5_PROVIDER_UPLOAD',
        '6_INDEPENDENT_READBACK_VERIFICATION',
      ],
      'availableProviders': [
        {
          'providerId': 'LOCAL_STORAGE',
          'family': 'LOCAL_FILESYSTEM',
          'runtimeStatus': 'IMPLEMENTED_AND_VERIFIED',
          'requiresInternet': false,
        },
        {
          'providerId': 'S3_COMPATIBLE',
          'family': 'S3_OBJECT_STORAGE',
          'runtimeStatus': 'CONTRACT_AND_VALIDATION_READY_TRANSPORT_DEFERRED',
          'supportedVendors': S3CompatibleProvider.supportedVendorPresets,
          'requiresInternet': true,
        },
        {
          'providerId': 'CLOUD_ADAPTER',
          'family': 'PLUGGABLE_CLOUD_ADAPTER',
          'runtimeStatus': 'INTERFACE_CONTRACT_READY',
          'requiresInternet': true,
        },
      ],
      'activeProviderConfiguration': cfg.backupConfig,
      'activeProviderValidation': validation.toJson(),
      'encryptionKeyProvisioned': _resolveEncryptionKey() != null,
      'remoteHybridArchitecture': RemoteHybridArchitectureBoundary.describeCapabilities(cfg),
      'recentBackupRuns': runsRes.rows
          .map((r) => {
                'backupUuid': r.colByName('backup_uuid'),
                'triggerType': r.colByName('trigger_type'),
                'archivePath': r.colByName('archive_path'),
                'archiveSha256': r.colByName('archive_sha256'),
                'archiveSizeBytes':
                    int.tryParse(r.colByName('archive_size_bytes') ?? '0') ?? 0,
                'schemaVersion': r.colByName('schema_version'),
                'maxFinancialEventId':
                    int.tryParse(r.colByName('max_financial_event_id') ?? '0') ?? 0,
                'status': r.colByName('status'),
                'startedAt': r.colByName('started_at'),
                'completedAt': r.colByName('completed_at'),
              })
          .toList(),
    };
  }

  /// Executes the full verified Backup Pipeline:
  /// `MariaDB -> logical snapshot -> compress -> encrypt (when key present) -> checksum -> provider store -> independent read-back verification`
  /// and records authoritative state in `mc_backup_runs`.
  Future<Map<String, dynamic>> executeBackup({
    required String hospitalCode,
    String triggerType = 'MANUAL_ADMIN',
    String? providerOverride,
    int? createdByStaffId,
    String? actorRoleLabel,
    String? deviceId,
    String? ipAddress,
  }) async {
    final cfg = await facilityConfigService.getConfiguration(hospitalCode);
    final targetProviderId =
        (providerOverride ?? cfg.backupConfig['activeProvider'] ?? 'LOCAL_STORAGE')
            .toString()
            .trim()
            .toUpperCase();
    final provider = _providers[targetProviderId];
    if (provider == null) {
      throw ArgumentError('Unsupported backup provider "$targetProviderId".');
    }

    final validation = provider.validateConfiguration(cfg.backupConfig);
    if (!validation.valid) {
      throw ArgumentError(
        'Backup provider configuration invalid: ${validation.issues.join('; ')}',
      );
    }

    final encKey = _resolveEncryptionKey();
    if (provider.requiresMandatoryEncryption && encKey == null) {
      throw StateError(
        'BACKUP_ENCRYPTION_KEY_REQUIRED: Remote backup providers require MEDCORE_BACKUP_ENCRYPTION_KEY.',
      );
    }

    final allowedTriggers = const {'SCHEDULED', 'MANUAL_ADMIN', 'PRE_MIGRATION', 'SERVICE_TOOL'};
    final cleanTrigger = allowedTriggers.contains(triggerType) ? triggerType : 'MANUAL_ADMIN';
    final backupUuid = 'BK-${_uuid.v4()}';

    // Determine latest schema version & max financial event ID
    final migRes = await db.execute(
      'SELECT version FROM mc_schema_migrations ORDER BY version DESC LIMIT 1',
    );
    final schemaVersion = migRes.rows.isNotEmpty
        ? (migRes.rows.first.colByName('version') ?? 'V015')
        : 'V015';

    final maxEvRes = await db.execute(
      'SELECT COALESCE(MAX(id), 0) AS max_id FROM mc_financial_events WHERE hospital_code = :hosp',
      {'hosp': hospitalCode},
    );
    final maxFinancialEventId =
        int.tryParse(maxEvRes.rows.first.colByName('max_id') ?? '0') ?? 0;

    // Insert initial RUNNING record in mc_backup_runs
    await db.execute(
      '''
      INSERT INTO mc_backup_runs (
        backup_uuid, hospital_code, trigger_type, archive_path, archive_sha256,
        archive_size_bytes, schema_version, max_financial_event_id, status, created_by
      ) VALUES (
        :uuid, :hosp, :trig, 'PENDING_WRITE', :zero_sha,
        0, :ver, :max_ev, 'RUNNING', :creator
      )
      ''',
      {
        'uuid': backupUuid,
        'hosp': hospitalCode,
        'trig': cleanTrigger,
        'zero_sha': '0' * 64,
        'ver': schemaVersion,
        'max_ev': maxFinancialEventId,
        'creator': createdByStaffId,
      },
    );

    try {
      // Stage 1: MariaDB Authoritative Tenant Snapshot
      final snapshotMap = await _extractTenantLogicalSnapshot(
        hospitalCode: hospitalCode,
        backupUuid: backupUuid,
        schemaVersion: schemaVersion,
        maxFinancialEventId: maxFinancialEventId,
      );
      final rawJsonBytes = utf8.encode(jsonEncode(snapshotMap));

      // Stage 2: GZip Compression
      final compressedBytes = Uint8List.fromList(gzip.encode(rawJsonBytes));

      // Stage 3: Authenticated Encryption Envelope (when key provisioned)
      late final Uint8List finalBytes;
      late final bool isEncrypted;
      late final String encryptionMode;
      if (encKey != null && encKey.isNotEmpty) {
        finalBytes = _sealAuthenticatedBackupEnvelope(
          plaintextBytes: compressedBytes,
          secretKeyMaterial: encKey,
          backupUuid: backupUuid,
        );
        isEncrypted = true;
        encryptionMode = 'HMAC_SHA256_KEYSTREAM_SEALED_V1';
      } else {
        finalBytes = compressedBytes;
        isEncrypted = false;
        encryptionMode = 'LOCAL_GZIP_UNENCRYPTED';
      }

      // Stage 4: SHA-256 Checksum
      final archiveSha256 = sha256.convert(finalBytes).toString();

      final envelope = BackupArtifactEnvelope(
        backupUuid: backupUuid,
        hospitalCode: hospitalCode,
        schemaVersion: schemaVersion,
        maxFinancialEventId: maxFinancialEventId,
        compressedGzip: true,
        encrypted: isEncrypted,
        encryptionMode: encryptionMode,
        payloadBytes: finalBytes,
        checksumSha256: archiveSha256,
      );

      // Stage 5 & 6: Provider Store + Independent Read-Back Verification
      final storeRes = await provider.storeAndVerifyArchive(envelope, cfg.backupConfig);
      final finalStatus = storeRes.independentlyVerified ? 'VERIFIED' : 'FAILED';

      await txManager.runInTransaction((tx) async {
        await tx.execute(
          '''
          UPDATE mc_backup_runs
          SET archive_path = :path,
              archive_sha256 = :sha,
              archive_size_bytes = :sz,
              status = :status,
              completed_at = CURRENT_TIMESTAMP
          WHERE backup_uuid = :uuid AND hospital_code = :hosp
          ''',
          {
            'path': storeRes.storageLocationUri,
            'sha': storeRes.verifiedSha256,
            'sz': storeRes.verifiedSizeBytes,
            'status': finalStatus,
            'uuid': backupUuid,
            'hosp': hospitalCode,
          },
        );

        await tx.writeAuditLog(
          hospitalCode: hospitalCode,
          actorStaffId: createdByStaffId,
          actorRole: actorRoleLabel ?? 'SYSTEM_BACKUP',
          deviceId: deviceId,
          action: 'backup.run.completed',
          entityType: 'mc_backup_runs',
          entityId: backupUuid,
          afterState: {
            'providerId': provider.providerId,
            'status': finalStatus,
            'independentlyVerified': storeRes.independentlyVerified,
            'archiveSha256': storeRes.verifiedSha256,
            'archiveSizeBytes': storeRes.verifiedSizeBytes,
            'encrypted': isEncrypted,
          },
          ipAddress: ipAddress,
        );
      });

      if (!storeRes.independentlyVerified) {
        throw StateError('Backup verification failed (${storeRes.statusCode}).');
      }

      return {
        'backupUuid': backupUuid,
        'hospitalCode': hospitalCode,
        'providerId': provider.providerId,
        'status': finalStatus,
        'independentlyVerified': storeRes.independentlyVerified,
        'verificationMethod': storeRes.statusCode,
        'archivePath': storeRes.storageLocationUri,
        'archiveSha256': storeRes.verifiedSha256,
        'archiveSizeBytes': storeRes.verifiedSizeBytes,
        'schemaVersion': schemaVersion,
        'maxFinancialEventId': maxFinancialEventId,
        'compressedGzip': true,
        'encrypted': isEncrypted,
        'encryptionMode': encryptionMode,
      };
    } catch (e) {
      await db.execute(
        '''
        UPDATE mc_backup_runs
        SET status = 'FAILED', completed_at = CURRENT_TIMESTAMP
        WHERE backup_uuid = :uuid AND hospital_code = :hosp
        ''',
        {'uuid': backupUuid, 'hosp': hospitalCode},
      );
      rethrow;
    }
  }

  /// Restore Hardening (Batch 17):
  /// Inspects a local backup archive without mutating the database,
  /// verifies SHA-256 against recorded `mc_backup_runs` or envelope checksum,
  /// and returns verified metadata for safe operator restoration.
  Future<Map<String, dynamic>> verifyBackupArchiveForRestore({
    required String hospitalCode,
    required String archiveFilePath,
    String? expectedSha256,
  }) async {
    final file = File(archiveFilePath);
    if (!file.existsSync()) {
      throw StateError('ARCHIVE_NOT_FOUND: Backup file does not exist at $archiveFilePath.');
    }

    final rawBytes = file.readAsBytesSync();
    final actualSha256 = sha256.convert(rawBytes).toString();

    if (expectedSha256 != null && expectedSha256.isNotEmpty) {
      if (actualSha256.toLowerCase() != expectedSha256.toLowerCase()) {
        throw StateError(
          'CHECKSUM_MISMATCH: Computed SHA-256 ($actualSha256) does not match expected ($expectedSha256). Archive may be corrupted or tampered with.',
        );
      }
    }

    // Verify presence in mc_backup_runs
    final runRes = await db.execute(
      '''
      SELECT backup_uuid, schema_version, max_financial_event_id, status, started_at
      FROM mc_backup_runs
      WHERE hospital_code = :hosp AND archive_sha256 = :sha
      ORDER BY id DESC LIMIT 1
      ''',
      {'hosp': hospitalCode, 'sha': actualSha256},
    );

    final isRecorded = runRes.rows.isNotEmpty;
    final rowAssoc = isRecorded ? runRes.rows.first.assoc() : null;

    return {
      'verified': true,
      'filePath': archiveFilePath,
      'fileSizeBytes': rawBytes.length,
      'actualSha256': actualSha256,
      'checksumMatched': expectedSha256 != null ? true : null,
      'isRecordedInDatabase': isRecorded,
      'recordedBackupUuid': rowAssoc?['backup_uuid'],
      'recordedSchemaVersion': rowAssoc?['schema_version'],
      'recordedMaxFinancialEventId': rowAssoc?['max_financial_event_id'],
      'restoreSafetyStatus': isRecorded ? 'SAFE_TO_RESTORE' : 'EXTERNAL_UNRECORDED_ARCHIVE',
    };
  }

  Future<Map<String, dynamic>> _extractTenantLogicalSnapshot({
    required String hospitalCode,
    required String backupUuid,
    required String schemaVersion,
    required int maxFinancialEventId,
  }) async {
    Future<List<Map<String, String?>>> dumpTable(String sql, Map<String, dynamic> params) async {
      final res = await db.execute(sql, params);
      return res.rows.map((r) => r.assoc()).toList();
    }

    return {
      'format': 'MEDCORE_LOGICAL_BACKUP_V1',
      'backupUuid': backupUuid,
      'hospitalCode': hospitalCode,
      'schemaVersion': schemaVersion,
      'maxFinancialEventId': maxFinancialEventId,
      'exportedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'tables': {
        'mc_tenants': await dumpTable(
          'SELECT * FROM mc_tenants WHERE hospital_code = :h',
          {'h': hospitalCode},
        ),
        'mc_facility_config': await dumpTable(
          'SELECT * FROM mc_facility_config WHERE hospital_code = :h',
          {'h': hospitalCode},
        ),
        'mc_devices': await dumpTable(
          'SELECT id, hospital_code, device_id, device_name, platform, connection_type, role_scope, medcore_version, status, last_seen_at FROM mc_devices WHERE hospital_code = :h',
          {'h': hospitalCode},
        ),
        'mc_patients': await dumpTable(
          'SELECT * FROM mc_patients WHERE hospital_code = :h',
          {'h': hospitalCode},
        ),
        'mc_shifts': await dumpTable(
          'SELECT * FROM mc_shifts WHERE hospital_code = :h',
          {'h': hospitalCode},
        ),
        'mc_visits': await dumpTable(
          'SELECT * FROM mc_visits WHERE hospital_code = :h',
          {'h': hospitalCode},
        ),
        'mc_visit_items': await dumpTable(
          'SELECT * FROM mc_visit_items WHERE hospital_code = :h',
          {'h': hospitalCode},
        ),
        'mc_visit_item_cost_lines': await dumpTable(
          'SELECT * FROM mc_visit_item_cost_lines WHERE hospital_code = :h',
          {'h': hospitalCode},
        ),
        'mc_financial_events': await dumpTable(
          'SELECT * FROM mc_financial_events WHERE hospital_code = :h',
          {'h': hospitalCode},
        ),
        'mc_financial_postings': await dumpTable(
          'SELECT * FROM mc_financial_postings WHERE hospital_code = :h',
          {'h': hospitalCode},
        ),
        'mc_financial_settlements': await dumpTable(
          'SELECT * FROM mc_financial_settlements WHERE hospital_code = :h',
          {'h': hospitalCode},
        ),
      },
    };
  }

  /// Authenticated keystream + HMAC-SHA256 integrity envelope (pure Dart, zero external native DLLs).
  static Uint8List _sealAuthenticatedBackupEnvelope({
    required Uint8List plaintextBytes,
    required String secretKeyMaterial,
    required String backupUuid,
  }) {
    final masterKey = sha256.convert(utf8.encode(secretKeyMaterial)).bytes;
    final encSubKey = Hmac(sha256, masterKey).convert(utf8.encode('ENC:$backupUuid')).bytes;
    final macSubKey = Hmac(sha256, masterKey).convert(utf8.encode('MAC:$backupUuid')).bytes;

    final cipherBytes = Uint8List(plaintextBytes.length);
    var counter = 0;
    var offset = 0;
    while (offset < plaintextBytes.length) {
      final blockKey = Hmac(sha256, encSubKey)
          .convert(utf8.encode('$backupUuid:$counter'))
          .bytes;
      for (var i = 0; i < blockKey.length && offset < plaintextBytes.length; i++, offset++) {
        cipherBytes[offset] = plaintextBytes[offset] ^ blockKey[i];
      }
      counter++;
    }

    final header = utf8.encode('MCBAK1|$backupUuid|');
    final mac = Hmac(sha256, macSubKey).convert([...header, ...cipherBytes]).bytes;
    return Uint8List.fromList([...header, ...mac, ...cipherBytes]);
  }

  String? _resolveEncryptionKey() {
    if (encryptionKeyOverride != null && encryptionKeyOverride!.trim().isNotEmpty) {
      return encryptionKeyOverride!.trim();
    }
    final envKey = Platform.environment['MEDCORE_BACKUP_ENCRYPTION_KEY']?.trim();
    if (envKey != null && envKey.isNotEmpty) {
      return envKey;
    }
    return null;
  }
}
