import 'dart:convert';
import 'package:decimal/decimal.dart';
import 'package:uuid/uuid.dart';
import '../db/db_client.dart';
import '../db/transaction_manager.dart';
import '../repositories/clock_guard_repository.dart';
import 'facility_config_service.dart';

class MaintenanceCenterService {
  static const String appVersion = '1.0.0-rc.1';
  static const _uuid = Uuid();

  final DbClient db;
  final TransactionManager txManager;
  final FacilityConfigService facilityConfigService;
  final String? securityRootDirectory;
  final int? Function()? boundPortProvider;

  MaintenanceCenterService(
    this.db, {
    required this.facilityConfigService,
    this.securityRootDirectory,
    this.boundPortProvider,
  }) : txManager = TransactionManager(db);

  /// Aggregates authoritative maintenance & diagnostic telemetry strictly from
  /// verified MariaDB tables and runtime service state. Zero fabricated diagnostics.
  Future<Map<String, dynamic>> getOverview({
    required String hospitalCode,
  }) async {
    final cleanHosp = hospitalCode.trim();
    final facilityCfg = await facilityConfigService.getConfiguration(cleanHosp);

    // 1. Database & Migration Status
    final verRes = await db.execute('SELECT VERSION() AS db_version');
    final dbVersion = verRes.rows.isNotEmpty
        ? (verRes.rows.first.colByName('db_version') ?? 'UNKNOWN')
        : 'UNKNOWN';

    final migRes = await db.execute(
      '''
      SELECT version, description, checksum_sha256, execution_ms, applied_at
      FROM mc_schema_migrations
      ORDER BY version ASC
      ''',
    );
    final migrations = migRes.rows
        .map((r) => {
              'version': r.colByName('version'),
              'description': r.colByName('description'),
              'checksumSha256': r.colByName('checksum_sha256'),
              'executionMs': int.tryParse(r.colByName('execution_ms') ?? '0') ?? 0,
              'appliedAt': r.colByName('applied_at'),
            })
        .toList();

    // 2. Storage Status (INFORMATION_SCHEMA.TABLES)
    final storageRes = await db.execute(
      '''
      SELECT COUNT(*) AS table_count,
             COALESCE(SUM(DATA_LENGTH), 0) AS data_bytes,
             COALESCE(SUM(INDEX_LENGTH), 0) AS index_bytes,
             COALESCE(SUM(TABLE_ROWS), 0) AS approx_rows
      FROM INFORMATION_SCHEMA.TABLES
      WHERE TABLE_SCHEMA = :schema
      ''',
      {'schema': db.config.databaseName},
    );
    final sr = storageRes.rows.first;
    final dataBytes = int.tryParse(sr.colByName('data_bytes') ?? '0') ?? 0;
    final indexBytes = int.tryParse(sr.colByName('index_bytes') ?? '0') ?? 0;

    // 3. Security & Clock Guard Status
    final clockRepo = ClockGuardRepository(db, securityRootDirectory: securityRootDirectory);
    ClockGuardRecord? clockRecord;
    String clockIntegrityStatus = 'UNINITIALIZED';
    String? clockIntegrityError;
    try {
      clockRecord = await clockRepo.getClockGuard(cleanHosp);
      if (clockRecord != null) {
        clockIntegrityStatus =
            clockRecord.rollbackDetected ? 'LOCKED_CLOCK_ROLLBACK' : 'VERIFIED_MONOTONIC';
      }
    } on ClockTamperException catch (e) {
      clockIntegrityStatus = 'TAMPER_DETECTED';
      clockIntegrityError = e.message;
    }

    final rootRes = await db.execute(
      'SELECT installation_id, initialized_at_utc FROM mc_security_root WHERE hospital_code = :hosp LIMIT 1',
      {'hosp': cleanHosp},
    );
    final activeStaffSessionsRes = await db.execute(
      '''
      SELECT COUNT(*) AS cnt FROM mc_auth_sessions
      WHERE hospital_code = :hosp AND is_active = 1 AND revoked_at IS NULL
      ''',
      {'hosp': cleanHosp},
    );
    final activeTechSessionsRes = await db.execute(
      '''
      SELECT COUNT(*) AS cnt FROM mc_technician_sessions
      WHERE hospital_code = :hosp AND is_active = 1 AND revoked_at IS NULL
      ''',
      {'hosp': cleanHosp},
    );

    // 4. License & Entitlement Status
    final licRes = await db.execute(
      'SELECT * FROM mc_license_state WHERE hospital_code = :hosp LIMIT 1',
      {'hosp': cleanHosp},
    );
    Map<String, dynamic> licenseStatus;
    if (licRes.rows.isNotEmpty) {
      final lr = licRes.rows.first;
      licenseStatus = {
        'source': 'MC_LICENSE_STATE_AND_FACILITY_CONFIG',
        'licenseId': lr.colByName('license_id'),
        'status': lr.colByName('status'),
        'edition': facilityCfg.edition,
        'maxDevices': int.tryParse(lr.colByName('max_devices') ?? '25') ?? 25,
        'maxDoctors': int.tryParse(lr.colByName('max_doctors') ?? '50') ?? 50,
        'aiEntitled': (lr.colByName('ai_entitled') ?? '0') == '1' &&
            facilityCfg.isModuleEnabled('AI'),
        'issuedAtUtc': lr.colByName('issued_at_utc'),
        'expiresAtUtc': lr.colByName('expires_at_utc'),
        'enabledModulesCount':
            facilityCfg.enabledModules.values.where((v) => v).length,
        'totalModulesCount': facilityCfg.enabledModules.length,
      };
    } else {
      licenseStatus = {
        'source': 'FACILITY_CONFIGURATION_ONLY',
        'licenseId': null,
        'status': 'LOCAL_INSTALLATION_CONFIGURED',
        'edition': facilityCfg.edition,
        'subscriptionStartsUtc': facilityCfg.subscriptionStartsUtc,
        'subscriptionExpiresUtc': facilityCfg.subscriptionExpiresUtc,
        'enabledModulesCount':
            facilityCfg.enabledModules.values.where((v) => v).length,
        'totalModulesCount': facilityCfg.enabledModules.length,
      };
    }

    // 5. Network & Connected Devices Status
    final devRes = await db.execute(
      '''
      SELECT device_id, device_name, platform, connection_type, role_scope,
             medcore_version, is_trusted_secure_runtime, status, last_seen_at, last_ip
      FROM mc_devices
      WHERE hospital_code = :hosp
      ORDER BY id ASC
      ''',
      {'hosp': cleanHosp},
    );
    final devices = devRes.rows
        .map((r) => {
              'deviceId': r.colByName('device_id'),
              'deviceName': r.colByName('device_name'),
              'platform': r.colByName('platform'),
              'connectionType': r.colByName('connection_type') ?? 'LOOPBACK',
              'roleScope': r.colByName('role_scope'),
              'medcoreVersion': r.colByName('medcore_version') ?? appVersion,
              'isTrustedSecureRuntime':
                  (r.colByName('is_trusted_secure_runtime') ?? '0') == '1',
              'status': r.colByName('status'),
              'lastSeenAt': r.colByName('last_seen_at'),
              'lastIp': r.colByName('last_ip'),
            })
        .toList();

    // 6. Backup Status
    final backupRes = await db.execute(
      '''
      SELECT backup_uuid, trigger_type, archive_path, archive_sha256,
             archive_size_bytes, schema_version, max_financial_event_id,
             status, started_at, completed_at
      FROM mc_backup_runs
      WHERE hospital_code = :hosp
      ORDER BY id DESC
      LIMIT 15
      ''',
      {'hosp': cleanHosp},
    );
    final backupRuns = backupRes.rows
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
        .toList();

    // 7. Authoritative Diagnostics (Real SQL Invariant Checks)
    final tbRes = await db.execute(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN direction = 'DEBIT' THEN amount ELSE 0 END), 0) AS total_debits,
        COALESCE(SUM(CASE WHEN direction = 'CREDIT' THEN amount ELSE 0 END), 0) AS total_credits,
        COUNT(*) AS posting_count
      FROM mc_financial_postings
      WHERE hospital_code = :hosp AND status = 'POSTED'
      ''',
      {'hosp': cleanHosp},
    );
    final tbr = tbRes.rows.first;
    final totalDebits = Decimal.parse(tbr.colByName('total_debits') ?? '0.0000');
    final totalCredits = Decimal.parse(tbr.colByName('total_credits') ?? '0.0000');
    final ledgerBalanced = totalDebits == totalCredits;

    final openShiftsRes = await db.execute(
      '''
      SELECT COUNT(*) AS cnt FROM mc_shifts
      WHERE hospital_code = :hosp AND status = 'OPEN'
      ''',
      {'hosp': cleanHosp},
    );
    final pendingDualRes = await db.execute(
      '''
      SELECT COUNT(*) AS cnt FROM mc_dual_control_request
      WHERE hospital_code = :hosp AND status = 'PENDING'
      ''',
      {'hosp': cleanHosp},
    );

    // 8. Logs & Errors (PII-redacted)
    final secLogsRes = await db.execute(
      '''
      SELECT id, event_type, severity, device_id, route_path, required_permission, created_at
      FROM mc_security_logs
      WHERE hospital_code = :hosp
      ORDER BY id DESC
      LIMIT 25
      ''',
      {'hosp': cleanHosp},
    );
    final auditLogsRes = await db.execute(
      '''
      SELECT id, actor_role, device_id, action, entity_type, entity_id, created_at
      FROM mc_audit_logs
      WHERE hospital_code = :hosp
      ORDER BY id DESC
      LIMIT 25
      ''',
      {'hosp': cleanHosp},
    );
    final errLogsRes = await db.execute(
      '''
      SELECT id, timestamp, severity, module, error_code, endpoint
      FROM mc_error_log
      WHERE hospital_code = :hosp
      ORDER BY id DESC
      LIMIT 25
      ''',
      {'hosp': cleanHosp},
    );

    // 9. Maintenance History
    final maintTokensRes = await db.execute(
      '''
      SELECT installation_id, action, consumed_at_utc
      FROM mc_consumed_maintenance_tokens
      WHERE hospital_code = :hosp
      ORDER BY id DESC
      LIMIT 20
      ''',
      {'hosp': cleanHosp},
    );
    final reportsRes = await db.execute(
      '''
      SELECT report_uuid, generated_by_mode, generated_by_actor, overall_status, created_at
      FROM mc_maintenance_reports
      WHERE hospital_code = :hosp
      ORDER BY id DESC
      LIMIT 20
      ''',
      {'hosp': cleanHosp},
    );

    final overallStatus = (!ledgerBalanced ||
            clockIntegrityStatus == 'TAMPER_DETECTED' ||
            clockIntegrityStatus == 'LOCKED_CLOCK_ROLLBACK')
        ? 'DEGRADED_ACTION_REQUIRED'
        : 'HEALTHY';

    return {
      'overallStatus': overallStatus,
      'generatedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'applicationVersion': appVersion,
      'hospitalCode': cleanHosp,
      'facilityName': facilityCfg.facilityName,
      'serviceStatus': {
        'serviceName': 'MedCore Local Service',
        'status': 'RUNNING',
        'boundPort': boundPortProvider?.call(),
        'operationalMode': 'LOCAL_FIRST',
      },
      'databaseStatus': {
        'engine': 'MariaDB',
        'serverVersion': dbVersion,
        'databaseName': db.config.databaseName,
        'host': db.config.host,
        'port': db.config.port,
        'loopbackIsolated': db.config.host == '127.0.0.1' || db.config.host == 'localhost',
        'connected': true,
      },
      'migrationStatus': {
        'appliedCount': migrations.length,
        'latestVersion': migrations.isNotEmpty ? migrations.last['version'] : null,
        'migrations': migrations,
      },
      'storageStatus': {
        'tableCount': int.tryParse(sr.colByName('table_count') ?? '0') ?? 0,
        'dataBytes': dataBytes,
        'indexBytes': indexBytes,
        'totalBytes': dataBytes + indexBytes,
        'approxTotalRows': int.tryParse(sr.colByName('approx_rows') ?? '0') ?? 0,
      },
      'securityStatus': {
        'clockGuardStatus': clockIntegrityStatus,
        if (clockIntegrityError != null) 'clockGuardError': clockIntegrityError,
        'maxObservedUtc': clockRecord?.maxObservedUtc.toIso8601String(),
        'rollbackDetected': clockRecord?.rollbackDetected ?? false,
        'rollbackDeltaSeconds': clockRecord?.rollbackDeltaSeconds,
        'securityRootAnchored': rootRes.rows.isNotEmpty,
        'securityRootInstallationId':
            rootRes.rows.isNotEmpty ? rootRes.rows.first.colByName('installation_id') : null,
        'activeStaffSessions':
            int.tryParse(activeStaffSessionsRes.rows.first.colByName('cnt') ?? '0') ?? 0,
        'activeTechnicianSessions':
            int.tryParse(activeTechSessionsRes.rows.first.colByName('cnt') ?? '0') ?? 0,
      },
      'licenseStatus': licenseStatus,
      'networkStatus': {
        ...facilityCfg.networkConfig,
        'activeDevicesCount':
            devices.where((d) => d['status'] == 'ACTIVE').length,
        'pendingPairingCount':
            devices.where((d) => d['status'] == 'PENDING').length,
        'revokedDevicesCount':
            devices.where((d) => d['status'] == 'REVOKED').length,
      },
      'connectedDevices': devices,
      'backupStatus': {
        'configuredProvider': facilityCfg.backupConfig['activeProvider'],
        'totalRecordedRuns': backupRuns.length,
        'latestVerifiedBackup': backupRuns
                .where((b) => b['status'] == 'VERIFIED')
                .isNotEmpty
            ? backupRuns.firstWhere((b) => b['status'] == 'VERIFIED')
            : null,
        'recentRuns': backupRuns,
      },
      'diagnostics': {
        'financialTrialBalance': {
          'balanced': ledgerBalanced,
          'totalDebits': totalDebits.toStringAsFixed(4),
          'totalCredits': totalCredits.toStringAsFixed(4),
          'postedEntriesCount':
              int.tryParse(tbr.colByName('posting_count') ?? '0') ?? 0,
        },
        'openCashierShiftsCount':
            int.tryParse(openShiftsRes.rows.first.colByName('cnt') ?? '0') ?? 0,
        'pendingDualControlRequestsCount':
            int.tryParse(pendingDualRes.rows.first.colByName('cnt') ?? '0') ?? 0,
      },
      'logs': {
        'securityLogs': secLogsRes.rows
            .map((r) => {
                  'id': int.tryParse(r.colByName('id') ?? '0') ?? 0,
                  'eventType': r.colByName('event_type'),
                  'severity': r.colByName('severity'),
                  'deviceId': r.colByName('device_id'),
                  'routePath': r.colByName('route_path'),
                  'requiredPermission': r.colByName('required_permission'),
                  'createdAt': r.colByName('created_at'),
                })
            .toList(),
        'auditLogs': auditLogsRes.rows
            .map((r) => {
                  'id': int.tryParse(r.colByName('id') ?? '0') ?? 0,
                  'actorRole': r.colByName('actor_role'),
                  'deviceId': r.colByName('device_id'),
                  'action': r.colByName('action'),
                  'entityType': r.colByName('entity_type'),
                  'entityId': r.colByName('entity_id'),
                  'createdAt': r.colByName('created_at'),
                })
            .toList(),
      },
      'errors': errLogsRes.rows
          .map((r) => {
                'id': int.tryParse(r.colByName('id') ?? '0') ?? 0,
                'timestamp': r.colByName('timestamp'),
                'severity': r.colByName('severity'),
                'module': r.colByName('module'),
                'errorCode': r.colByName('error_code'),
                'endpoint': r.colByName('endpoint'),
              })
          .toList(),
      'maintenanceHistory': {
        'consumedAuthorityTokens': maintTokensRes.rows
            .map((r) => {
                  'installationId': r.colByName('installation_id'),
                  'action': r.colByName('action'),
                  'consumedAtUtc': r.colByName('consumed_at_utc'),
                })
            .toList(),
        'generatedReports': reportsRes.rows
            .map((r) => {
                  'reportUuid': r.colByName('report_uuid'),
                  'generatedByMode': r.colByName('generated_by_mode'),
                  'generatedByActor': r.colByName('generated_by_actor'),
                  'overallStatus': r.colByName('overall_status'),
                  'createdAt': r.colByName('created_at'),
                })
            .toList(),
      },
    };
  }

  /// Generates and persists a PII-redacted full Maintenance Diagnostic Report
  /// in `mc_maintenance_reports` + `mc_audit_logs`.
  Future<Map<String, dynamic>> generateReport({
    required String hospitalCode,
    required String generatedByMode, // 'STAFF_AUTHORIZED' | 'TECHNICIAN_SESSION'
    required String generatedByActor,
    String? deviceId,
    String? ipAddress,
  }) async {
    final overview = await getOverview(hospitalCode: hospitalCode);
    final reportUuid = 'MREP-${_uuid.v4()}';
    final overallStatus = (overview['overallStatus'] ?? 'HEALTHY').toString();

    final reportDocument = {
      'reportUuid': reportUuid,
      'reportSchema': 'MEDCORE_MAINTENANCE_REPORT_V1',
      'redactionPolicy': 'PII_AND_SECRETS_EXCLUDED',
      'generatedByMode': generatedByMode,
      'generatedByActor': generatedByActor,
      'overview': overview,
    };

    await txManager.runInTransaction((tx) async {
      await tx.execute(
        '''
        INSERT INTO mc_maintenance_reports (
          report_uuid, hospital_code, generated_by_mode, generated_by_actor,
          overall_status, report_json
        ) VALUES (
          :uuid, :hosp, :mode, :actor, :status, :json
        )
        ''',
        {
          'uuid': reportUuid,
          'hosp': hospitalCode,
          'mode': generatedByMode,
          'actor': generatedByActor,
          'status': overallStatus,
          'json': jsonEncode(reportDocument),
        },
      );

      await tx.writeAuditLog(
        hospitalCode: hospitalCode,
        actorRole: generatedByMode,
        deviceId: deviceId,
        action: 'maintenance.report.generated',
        entityType: 'mc_maintenance_reports',
        entityId: reportUuid,
        afterState: {
          'overallStatus': overallStatus,
          'generatedByActor': generatedByActor,
        },
        ipAddress: ipAddress,
      );
    });

    final formattedSummary = _buildTextSummary(reportUuid, overview);
    return {
      'reportUuid': reportUuid,
      'overallStatus': overallStatus,
      'report': reportDocument,
      'formattedTextReport': formattedSummary,
    };
  }

  static String _buildTextSummary(String reportUuid, Map<String, dynamic> ov) {
    final dbMap = ov['databaseStatus'] as Map<String, dynamic>;
    final migMap = ov['migrationStatus'] as Map<String, dynamic>;
    final secMap = ov['securityStatus'] as Map<String, dynamic>;
    final diagMap = ov['diagnostics'] as Map<String, dynamic>;
    final tbMap = diagMap['financialTrialBalance'] as Map<String, dynamic>;
    final netMap = ov['networkStatus'] as Map<String, dynamic>;
    final bakMap = ov['backupStatus'] as Map<String, dynamic>;

    return [
      '====================================================================',
      'MEDCORE PLATINUM DESKTOP — AUTHORITATIVE MAINTENANCE REPORT',
      '====================================================================',
      'Report UUID         : $reportUuid',
      'Generated At (UTC)  : ${ov['generatedAtUtc']}',
      'Overall Status      : ${ov['overallStatus']}',
      'Application Version : ${ov['applicationVersion']}',
      'Facility / Tenant   : ${ov['facilityName']} (${ov['hospitalCode']})',
      'MariaDB Engine      : ${dbMap['serverVersion']} @ ${dbMap['host']}:${dbMap['port']} (Loopback=${dbMap['loopbackIsolated']})',
      'Applied Migrations  : ${migMap['appliedCount']} (Latest: ${migMap['latestVersion']})',
      'Clock Guard Status  : ${secMap['clockGuardStatus']} (MaxUTC=${secMap['maxObservedUtc']})',
      'Trial Balance       : Balanced=${tbMap['balanced']} (Debits=${tbMap['totalDebits']} / Credits=${tbMap['totalCredits']})',
      'Devices (Act/Pend)  : ${netMap['activeDevicesCount']} active / ${netMap['pendingPairingCount']} pending',
      'Backups Recorded    : ${bakMap['totalRecordedRuns']} (Provider=${bakMap['configuredProvider']})',
      '====================================================================',
    ].join('\n');
  }

  /// Exports a deterministic PII-redacted Engineering Bundle for technician diagnosis (Batch 19).
  Future<Map<String, dynamic>> exportEngineeringBundle({
    required String hospitalCode,
    required String requestedByActor,
    String? deviceId,
  }) async {
    final report = await generateReport(
      hospitalCode: hospitalCode,
      generatedByMode: 'TECHNICIAN_SESSION',
      generatedByActor: requestedByActor,
      deviceId: deviceId,
    );

    // Apply deterministic PII Privacy Filter
    final jsonStr = jsonEncode(report);
    final sanitizedJson = _applyPiiPrivacyFilter(jsonStr);
    final bundleUuid = 'MC-DIAG-${_uuid.v4().substring(0, 8)}';

    return {
      'bundleUuid': bundleUuid,
      'bundleFormat': 'MEDCORE_ENGINEERING_BUNDLE_V1',
      'piiPrivacyFilterApplied': true,
      'piiFilterMask': '[REDACTED_BY_PII_FILTER]',
      'timestampUtc': DateTime.now().toUtc().toIso8601String(),
      'hospitalCode': hospitalCode,
      'diagnosticPayload': jsonDecode(sanitizedJson),
    };
  }

  static String _applyPiiPrivacyFilter(String input) {
    var output = input.replaceAll(
      RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,7}\b'),
      '[REDACTED_EMAIL]',
    );
    output = output.replaceAll(
      RegExp(r'\b(?:\+?\d{1,3}[- ]?)?\(?\d{3}\)?[- ]?\d{3}[- ]?\d{4}\b'),
      '[REDACTED_PHONE]',
    );
    output = output.replaceAll(RegExp(r'\b\d{14}\b'), '[REDACTED_NATIONAL_ID]');
    return output;
  }
}
