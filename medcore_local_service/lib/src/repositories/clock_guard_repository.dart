import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import '../db/db_client.dart';
import '../db/transaction_manager.dart';
import '../security/clock_guard_key_manager.dart';
import '../security/maintenance_token_service.dart';
import '../security/process_identity.dart';
import '../security/trusted_time_evidence.dart';

class ClockTamperException implements Exception {
  final String message;
  ClockTamperException(this.message);
  @override
  String toString() => 'ClockTamperException: $message';
}

class ClockGuardRecord {
  final int id;
  final String hospitalCode;
  final DateTime maxObservedUtc;
  final String? lastEventUuid;
  final int lastBootMonotonicMs;
  final String? processBootId;
  final bool rollbackDetected;
  final int? rollbackDeltaSeconds;
  final DateTime? lockedAtUtc;
  final String? unlockedByMaintenanceTokenId;
  final String hmacSeal;
  final DateTime updatedAt;

  const ClockGuardRecord({
    required this.id,
    required this.hospitalCode,
    required this.maxObservedUtc,
    this.lastEventUuid,
    required this.lastBootMonotonicMs,
    this.processBootId,
    required this.rollbackDetected,
    this.rollbackDeltaSeconds,
    this.lockedAtUtc,
    this.unlockedByMaintenanceTokenId,
    required this.hmacSeal,
    required this.updatedAt,
  });
}

class ClockEvaluationResult {
  final DateTime effectiveTime;
  final bool rollbackDetected;
  final int? rollbackDeltaSeconds;
  final ClockGuardRecord record;

  const ClockEvaluationResult({
    required this.effectiveTime,
    required this.rollbackDetected,
    this.rollbackDeltaSeconds,
    required this.record,
  });
}

class ClockGuardRepository {
  final SqlExecutor db;
  final ClockGuardKeyManager keyManager;
  final MaintenanceTokenService maintenanceTokenService;
  final TrustedTimeVerifier trustedTimeVerifier;
  final String securityRootDirectory;
  static final Stopwatch _stopwatch = Stopwatch()..start();
  static final String _processBootUuid = ProcessIdentity.current();
  static String get currentProcessBootId => _processBootUuid;

  ClockGuardRepository(
    this.db, {
    ClockGuardKeyManager? keyManager,
    MaintenanceTokenService? maintenanceTokenService,
    TrustedTimeVerifier? trustedTimeVerifier,
    String? securityRootDirectory,
  })  : keyManager = keyManager ?? ClockGuardKeyManager.fromFile(),
        maintenanceTokenService = maintenanceTokenService ?? MaintenanceTokenService(),
        trustedTimeVerifier = trustedTimeVerifier ?? TrustedTimeVerifier.production(),
        securityRootDirectory = securityRootDirectory ?? 'runtime/security/tenant_roots';

  bool verifyHmacSeal(ClockGuardRecord record) {
    return keyManager.verifySeal(record: record);
  }

  Future<ClockGuardRecord?> getClockGuard(String hospitalCode) async {
    final res = await db.execute(
      'SELECT * FROM mc_clock_guard WHERE hospital_code = :hosp LIMIT 1',
      {'hosp': hospitalCode},
    );
    if (res.rows.isEmpty) return null;
    return _mapRow(res.rows.first);
  }

  /// Evaluates host wall clock against persisted high-water mark with FAIL-CLOSED keyed HMAC verification.
  /// Strictly isolates each tenant; no cross-tenant global MAX or leakage permitted.
  Future<ClockEvaluationResult> evaluateAndUpdateClock({
    required String hospitalCode,
    required DateTime currentWallClock,
    String? eventUuid,
    Duration driftTolerance = const Duration(seconds: 5),
  }) async {
    final nowUtc = currentWallClock.toUtc();
    final monoMs = _stopwatch.elapsedMilliseconds;

    // 1. Fetch current tenant clock guard row with FOR UPDATE lock
    final res = await db.execute(
      'SELECT * FROM mc_clock_guard WHERE hospital_code = :hosp LIMIT 1 FOR UPDATE',
      {'hosp': hospitalCode},
    );

    final hadSecurityRoot = await _verifyOrInitializeSecurityRoot(
      hospitalCode,
      res.rows.isNotEmpty ? _mapRow(res.rows.first) : null,
    );

    if (res.rows.isEmpty) {
      if (hadSecurityRoot) {
        throw ClockTamperException('Established security root exists but mc_clock_guard is missing; refusing reinitialization.');
      }
      // Adversarial State Destruction Check (F-02 Fix):
      // State deletion must NEVER be treated as clean first-initialization.
      // 1. Authoritative check: Inspect durable initialization fact in mc_tenants
      final tenantRes = await db.execute(
        'SELECT clock_guard_initialized_at FROM mc_tenants WHERE hospital_code = :hosp LIMIT 1 FOR UPDATE',
        {'hosp': hospitalCode},
      );

      if (tenantRes.rows.isNotEmpty) {
        final initAt = tenantRes.rows.first.colByName('clock_guard_initialized_at');
        if (initAt != null && initAt.isNotEmpty) {
          throw ClockTamperException(
            'Security state deletion detected: mc_clock_guard record missing for established tenant $hospitalCode '
            '(tenant was previously initialized at $initAt). Out-of-band state destruction rejected.',
          );
        }
      }

      // 2. Secondary activity check (sessions, staff logins)
      final sessionCountRes = await db.execute(
        'SELECT COUNT(*) as c FROM mc_auth_sessions WHERE hospital_code = :hosp',
        {'hosp': hospitalCode},
      );
      final staffLoginRes = await db.execute(
        'SELECT COUNT(*) as c FROM mc_staff WHERE hospital_code = :hosp AND last_login_at IS NOT NULL',
        {'hosp': hospitalCode},
      );

      final sCount = int.parse(sessionCountRes.rows.first.colByName('c') ?? '0');
      final stLoginCount = int.parse(staffLoginRes.rows.first.colByName('c') ?? '0');

      if (sCount > 0 || stLoginCount > 0) {
        throw ClockTamperException(
          'Security state deletion detected: mc_clock_guard record missing for established tenant $hospitalCode '
          '($sCount sessions, $stLoginCount staff logins exist).',
        );
      }

      // Genuine clean first installation for this tenant:
      // Establish mc_clock_guard and immutably anchor clock_guard_initialized_at in mc_tenants
      final effectiveTime = nowUtc;
      final currentEventUuid = eventUuid ?? _processBootUuid;
      final seal = keyManager.computeKeyedSeal(
        hospitalCode: hospitalCode,
        maxObservedUtc: effectiveTime,
        lastBootMonotonicMs: monoMs,
        processBootId: _processBootUuid,
        rollbackDetected: false,
        rollbackDeltaSeconds: null,
        lockedAtUtc: null,
        unlockedByMaintenanceTokenId: null,
        lastEventUuid: currentEventUuid,
      );

      final maxIdRes = await db.execute('SELECT COALESCE(MAX(id), 0) + 1 AS next_id FROM mc_clock_guard');
      final nextId = int.parse(maxIdRes.rows.first.colByName('next_id') ?? '1');

      await db.execute(
        '''
        INSERT INTO mc_clock_guard (
          id, hospital_code, max_observed_utc, last_event_uuid,
          last_boot_monotonic_ms, process_boot_id, rollback_detected, rollback_delta_seconds,
          locked_at_utc, hmac_seal
        ) VALUES (
          :id, :hosp, :max_utc, :event_uuid,
          :mono_ms, :boot_id, 0, NULL,
          NULL, :seal
        )
        ''',
        {
          'id': nextId,
          'hosp': hospitalCode,
          'max_utc': _fmtDt3(effectiveTime),
          'event_uuid': currentEventUuid,
          'mono_ms': monoMs,
          'boot_id': _processBootUuid,
          'seal': seal,
        },
      );

      // Immutably anchor initialization timestamp in mc_tenants
      await db.execute(
        '''
        UPDATE mc_tenants
        SET clock_guard_initialized_at = :init_time
        WHERE hospital_code = :hosp AND clock_guard_initialized_at IS NULL
        ''',
        {
          'hosp': hospitalCode,
          'init_time': _fmtDt3(effectiveTime),
        },
      );

      final rec = (await getClockGuard(hospitalCode))!;
      return ClockEvaluationResult(
        effectiveTime: effectiveTime,
        rollbackDetected: false,
        rollbackDeltaSeconds: null,
        record: rec,
      );
    }

    // Existing record: FAIL-CLOSED verification of keyed HMAC covering all 8 functional security fields
    final record = _mapRow(res.rows.first);
    if (!keyManager.verifySeal(record: record)) {
      throw ClockTamperException(
        'Integrity verification failed for mc_clock_guard on hospital $hospitalCode. Database row was altered out-of-band.',
      );
    }

    if (record.processBootId != _processBootUuid && nowUtc.isBefore(record.maxObservedUtc)) {
      throw ClockTamperException('UNTRUSTED_DOWNTIME_CLOCK: process boundary mismatch (persisted=${record.processBootId}, current=$_processBootUuid); trusted time recovery is required.');
    }

    DateTime highestObserved = record.maxObservedUtc;
    DateTime effectiveTime;
    bool isRollback = record.rollbackDetected;
    int? rollbackDelta = record.rollbackDeltaSeconds;
    DateTime? lockedAt = record.lockedAtUtc;

    if (nowUtc.isAfter(highestObserved) || nowUtc.isAtSameMomentAs(highestObserved)) {
      // Normal forward progression
      effectiveTime = nowUtc;
      highestObserved = nowUtc;
      // If time recovered past highest observed, clear rollback lock
      if (isRollback) {
        isRollback = false;
        rollbackDelta = null;
        lockedAt = null;
      }
    } else {
      // Host clock is behind highest observed time
      effectiveTime = highestObserved;
      // Millisecond-precision drift calculation prevents integer-second truncation
      final deltaMs = highestObserved.difference(nowUtc).inMilliseconds;
      if (deltaMs > driftTolerance.inMilliseconds) {
        isRollback = true;
        rollbackDelta = (deltaMs + 999) ~/ 1000;
        lockedAt ??= nowUtc;
      }
    }

    final seal = keyManager.computeKeyedSeal(
      hospitalCode: hospitalCode,
      maxObservedUtc: highestObserved,
      lastBootMonotonicMs: monoMs,
      processBootId: _processBootUuid,
      rollbackDetected: isRollback,
      rollbackDeltaSeconds: rollbackDelta,
      lockedAtUtc: lockedAt,
      unlockedByMaintenanceTokenId: record.unlockedByMaintenanceTokenId,
      lastEventUuid: eventUuid ?? record.lastEventUuid,
    );

    await db.execute(
      '''
      UPDATE mc_clock_guard
      SET max_observed_utc = :max_utc,
          last_event_uuid = :event_uuid,
          last_boot_monotonic_ms = :mono_ms,
          process_boot_id = :boot_id,
          rollback_detected = :rb_detected,
          rollback_delta_seconds = :rb_delta,
          locked_at_utc = :locked_at,
          hmac_seal = :seal
      WHERE id = :id
      ''',
      {
        'id': record.id,
        'max_utc': _fmtDt3(highestObserved),
        'event_uuid': eventUuid ?? record.lastEventUuid,
        'mono_ms': monoMs,
        'boot_id': _processBootUuid,
        'rb_detected': isRollback ? 1 : 0,
        'rb_delta': rollbackDelta,
        'locked_at': lockedAt != null ? _fmtDt(lockedAt) : null,
        'seal': seal,
      },
    );

    final updatedRec = (await getClockGuard(hospitalCode))!;
    return ClockEvaluationResult(
      effectiveTime: effectiveTime,
      rollbackDetected: isRollback,
      rollbackDeltaSeconds: rollbackDelta,
      record: updatedRec,
    );
  }

  Future<bool> _verifyOrInitializeSecurityRoot(
    String hospitalCode,
    ClockGuardRecord? existingGuard, {
    bool allowAuthenticatedDbRestore = false,
  }) async {
    if (hospitalCode.trim().isEmpty) throw ClockTamperException('Empty tenant identity cannot establish a security root.');
    final rootResult = await db.execute(
      'SELECT hospital_code, installation_id, initialization_id, initialized_at_utc, state, hmac_seal '
      'FROM mc_security_root WHERE hospital_code = :hosp LIMIT 1 FOR UPDATE',
      {'hosp': hospitalCode},
    );
    final file = _securityRootFile(hospitalCode);
    final externalExists = file.existsSync();

    // Determine authoritative persistence state (Uninitialized vs. Established)
    final tenant = await db.execute(
      'SELECT clock_guard_initialized_at FROM mc_tenants WHERE hospital_code = :hosp LIMIT 1 FOR UPDATE',
      {'hosp': hospitalCode},
    );
    final sessions = await db.execute('SELECT COUNT(*) AS c FROM mc_auth_sessions WHERE hospital_code = :hosp', {'hosp': hospitalCode});
    final logins = await db.execute('SELECT COUNT(*) AS c FROM mc_staff WHERE hospital_code = :hosp AND last_login_at IS NOT NULL', {'hosp': hospitalCode});
    final clockRecords = await db.execute('SELECT COUNT(*) AS c FROM mc_clock_guard WHERE hospital_code = :hosp', {'hosp': hospitalCode});
    final init = tenant.rows.isEmpty ? null : tenant.rows.first.colByName('clock_guard_initialized_at');
    final sessionCount = int.tryParse(sessions.rows.first.colByName('c') ?? '0') ?? 0;
    final loginCount = int.tryParse(logins.rows.first.colByName('c') ?? '0') ?? 0;
    final clockCount = int.tryParse(clockRecords.rows.first.colByName('c') ?? '0') ?? 0;

    final isEstablished = (init != null && init.isNotEmpty) || sessionCount > 0 || loginCount > 0 || clockCount > 0;

    // STATE 1: Genuinely UNINITIALIZED / Clean Installation / Fresh Post-Factory-Reset State
    if (!isEstablished) {
      if (externalExists && rootResult.rows.isNotEmpty) {
        // Both exist: perform normal cryptographic verification
      } else if (externalExists && rootResult.rows.isEmpty) {
        // Disk anchor exists: backfill MariaDB
        final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final externalRoot = <String, String>{for (final e in data.entries) e.key: e.value.toString()};
        await db.execute(
          'INSERT INTO mc_security_root (hospital_code, installation_id, initialization_id, initialized_at_utc, state, hmac_seal) '
          'VALUES (:hosp, :inst, :iid, :created, :state, :seal) '
          'ON DUPLICATE KEY UPDATE state = VALUES(state)',
          {
            'hosp': externalRoot['hospital_code'],
            'inst': externalRoot['installation_id'],
            'iid': externalRoot['initialization_id'],
            'created': externalRoot['initialized_at_utc'],
            'state': externalRoot['state'],
            'seal': externalRoot['hmac_seal'],
          },
        );
        return true;
      } else {
        // Genuinely fresh state (no external anchor): cleanly initialize root
        if (rootResult.rows.isNotEmpty) {
          await db.execute('DELETE FROM mc_security_root WHERE hospital_code = :hosp', {'hosp': hospitalCode});
        }
        await _createSecurityRoot(hospitalCode, DateTime.now().toUtc());
        return false;
      }
    }

    // STATE 2: Cryptographically Authorized Maintenance Recovery for Established Tenant
    if (allowAuthenticatedDbRestore && rootResult.rows.isNotEmpty && !externalExists) {
      final row = rootResult.rows.first;
      final root = <String, String>{
        'hospital_code': row.colByName('hospital_code') ?? '',
        'installation_id': row.colByName('installation_id') ?? '',
        'initialization_id': row.colByName('initialization_id') ?? '',
        'initialized_at_utc': row.colByName('initialized_at_utc') == null
            ? ''
            : _fmtDt3(_parseUtc(row.colByName('initialized_at_utc'))),
        'state': row.colByName('state') ?? '',
        'hmac_seal': row.colByName('hmac_seal') ?? '',
      };
      final initializedAt = _parseUtc(root['initialized_at_utc']);
      final expected = keyManager.computeSecurityRootSeal(
        hospitalCode: hospitalCode,
        installationId: root['installation_id']!,
        initializationId: root['initialization_id']!,
        initializedAtUtc: initializedAt,
        state: root['state']!,
      );
      if (_constantTimeEquals(expected, root['hmac_seal']!)) {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(jsonEncode(root), flush: true);
        return true;
      }
    }

    // STATE 3: Established Tenant Verification — Strict Fail-Closed Anti-Tamper Enforcement
    if (rootResult.rows.isNotEmpty || externalExists) {
      if (!externalExists || (rootResult.rows.isEmpty && !allowAuthenticatedDbRestore)) {
        throw ClockTamperException('Security root is missing from MariaDB or protected local anchor; refusing reinitialization.');
      }
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final externalRoot = <String, String>{for (final e in data.entries) e.key: e.value.toString()};
      if (externalRoot['hospital_code'] != hospitalCode ||
          externalRoot['installation_id'] != keyManager.installationId || externalRoot['state'] != 'ACTIVE') {
        throw ClockTamperException('Protected local security root is invalid or misbound.');
      }
      if (rootResult.rows.isNotEmpty) {
        final row = rootResult.rows.first;
        final root = <String, String>{
          'hospital_code': row.colByName('hospital_code') ?? '',
          'installation_id': row.colByName('installation_id') ?? '',
          'initialization_id': row.colByName('initialization_id') ?? '',
          'initialized_at_utc': row.colByName('initialized_at_utc') == null
              ? ''
              : _fmtDt3(_parseUtc(row.colByName('initialized_at_utc'))),
          'state': row.colByName('state') ?? '',
          'hmac_seal': row.colByName('hmac_seal') ?? '',
        };
        if (!_sameRoot(root, externalRoot)) {
          throw ClockTamperException('MariaDB security root differs from the protected local anchor.');
        }
      }
      final root = externalRoot;
      if (root['hospital_code'] != hospitalCode ||
          root['installation_id'] != keyManager.installationId || root['state'] != 'ACTIVE') {
        throw ClockTamperException('Security root mismatch, invalid installation binding or invalid state.');
      }
      final initializedAt = _parseUtc(root['initialized_at_utc']);
      final expected = keyManager.computeSecurityRootSeal(
        hospitalCode: hospitalCode,
        installationId: root['installation_id']!,
        initializationId: root['initialization_id']!,
        initializedAtUtc: initializedAt,
        state: root['state']!,
      );
      if (!_constantTimeEquals(expected, root['hmac_seal']!)) {
        throw ClockTamperException('Security root HMAC verification failed.');
      }
      if (existingGuard != null && !keyManager.verifySeal(record: existingGuard)) {
        throw ClockTamperException('Clock guard HMAC verification failed under established security root.');
      }
      if (rootResult.rows.isEmpty) {
        await db.execute(
          'INSERT INTO mc_security_root (hospital_code, installation_id, initialization_id, initialized_at_utc, state, hmac_seal) '
          'VALUES (:hosp, :inst, :iid, :created, :state, :seal)',
          {
            'hosp': root['hospital_code'],
            'inst': root['installation_id'],
            'iid': root['initialization_id'],
            'created': root['initialized_at_utc'],
            'state': root['state'],
            'seal': root['hmac_seal'],
          },
        );
      }
      return true;
    }

    // Backfill an established pre-V013 installation only from an intact authenticated guard.
    if (existingGuard != null) {
      if (!keyManager.verifySeal(record: existingGuard)) {
        throw ClockTamperException('Cannot establish security root from unauthenticated clock state.');
      }
      await _createSecurityRoot(hospitalCode, existingGuard.maxObservedUtc);
      return false;
    }

    if (isEstablished) {
      throw ClockTamperException('Established tenant has no security root; refusing fresh clock initialization.');
    }
    await _createSecurityRoot(hospitalCode, DateTime.now().toUtc());
    return false;
  }

  Future<void> _createSecurityRoot(String hospitalCode, DateTime initializedAtUtc) async {
    final initializationId = const Uuid().v4();
    final installationId = keyManager.installationId;
    const state = 'ACTIVE';
    final seal = keyManager.computeSecurityRootSeal(
      hospitalCode: hospitalCode,
      installationId: installationId,
      initializationId: initializationId,
      initializedAtUtc: initializedAtUtc,
      state: state,
    );
    final root = <String, String>{
      'hospital_code': hospitalCode,
      'installation_id': installationId,
      'initialization_id': initializationId,
      'initialized_at_utc': _fmtDt3(initializedAtUtc),
      'state': state,
      'hmac_seal': seal,
    };
    final file = _securityRootFile(hospitalCode);
    file.parent.createSync(recursive: true);
    final temp = File('${file.path}.tmp');
    temp.writeAsStringSync(jsonEncode(root), flush: true);
    if (file.existsSync()) {
      try {
        file.deleteSync();
      } catch (_) {}
    }
    temp.renameSync(file.path);
    await db.execute(
      'INSERT INTO mc_security_root (hospital_code, installation_id, initialization_id, initialized_at_utc, state, hmac_seal) '
      'VALUES (:hosp, :inst, :iid, :created, :state, :seal) '
      'ON DUPLICATE KEY UPDATE installation_id = VALUES(installation_id), initialization_id = VALUES(initialization_id), '
      'initialized_at_utc = VALUES(initialized_at_utc), state = VALUES(state), hmac_seal = VALUES(hmac_seal)',
      {'hosp': hospitalCode, 'inst': installationId, 'iid': initializationId, 'created': _fmtDt3(initializedAtUtc), 'state': state, 'seal': seal},
    );
  }

  File _securityRootFile(String hospitalCode) {
    final dbName = db is DbClient ? (db as DbClient).config.databaseName : (db is TxContext ? (db as TxContext).databaseName : 'unknown');
    final key = sha256.convert(utf8.encode('$dbName:$hospitalCode')).toString();
    return File('$securityRootDirectory${Platform.pathSeparator}$key.json');
  }

  static bool _sameRoot(Map<String, String> a, Map<String, String> b) =>
      a.length == b.length && a.entries.every((entry) => b[entry.key] == entry.value);

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) { diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i); }
    return diff == 0;
  }

  /// Cryptographically authorized maintenance token recovery.
  /// Enforces:
  /// - Mandatory installation binding
  /// - Trusted effective security time expiration
  /// - Fail-closed downtime restart verification (Option A+B Hybrid: rejects unverified wall clocks across restarts)
  /// - Atomic replay protection via consumed nonces
  /// - Session revocation on clock reset
  /// - 100% ACID transaction atomicity covering audit logging
  Future<ClockGuardRecord> unlockWithMaintenanceToken({
    required String hospitalCode,
    required String rawMaintenanceToken,
    required String expectedInstallationId,
    TrustedTimeEvidence? trustedTimeEvidence,
    @Deprecated('Ignored for security decisions; trusted authority evidence is required.') DateTime? currentWallClock,
  }) async {
    if (db is DbClient) {
      final txManager = TransactionManager(db as DbClient);
      return await txManager.runInTransaction((tx) async {
        final txRepo = ClockGuardRepository(
          tx,
          keyManager: keyManager,
          maintenanceTokenService: maintenanceTokenService,
          trustedTimeVerifier: trustedTimeVerifier,
          securityRootDirectory: securityRootDirectory,
        );
        return await txRepo._executeUnlockWithinTransaction(
          hospitalCode: hospitalCode,
          rawMaintenanceToken: rawMaintenanceToken,
          expectedInstallationId: expectedInstallationId,
          trustedTimeEvidence: trustedTimeEvidence,
          tx: tx,
        );
      });
    }
    final executor = db;
    if (executor is TxContext && executor.isActive) {
      return await _executeUnlockWithinTransaction(
        hospitalCode: hospitalCode,
        rawMaintenanceToken: rawMaintenanceToken,
        expectedInstallationId: expectedInstallationId,
        trustedTimeEvidence: trustedTimeEvidence,
        tx: executor,
      );
    }
    throw StateError('Maintenance recovery requires DbClient-owned or active TxContext transaction.');
  }

  Future<ClockGuardRecord> _executeUnlockWithinTransaction({
    required String hospitalCode,
    required String rawMaintenanceToken,
    required String expectedInstallationId,
    required TrustedTimeEvidence? trustedTimeEvidence,
    required TxContext tx,
  }) async {
    if (!tx.isActive || !identical(db, tx)) {
      throw StateError('Maintenance recovery must execute entirely on its active TxContext.');
    }
    if (expectedInstallationId.trim().isEmpty) {
      throw ArgumentError('expectedInstallationId must be provided and non-empty.');
    }
    if (expectedInstallationId.trim() != keyManager.installationId) {
      throw MaintenanceTokenException('INSTALLATION_MISMATCH', 'Maintenance recovery installation does not match the protected installation key.');
    }

    // 1. Fetch existing clock guard with FOR UPDATE lock
    final res = await db.execute(
      'SELECT * FROM mc_clock_guard WHERE hospital_code = :hosp LIMIT 1 FOR UPDATE',
      {'hosp': hospitalCode},
    );
    if (res.rows.isEmpty) {
      throw MaintenanceTokenException('NO_CLOCK_RECORD', 'No clock guard record exists for $hospitalCode.');
    }
    final record = _mapRow(res.rows.first);

    await _verifyOrInitializeSecurityRoot(hospitalCode, record, allowAuthenticatedDbRestore: true);

    // 2. Verify current record HMAC seal (Fail-Closed)
    if (!keyManager.verifySeal(record: record)) {
      throw ClockTamperException(
        'Cannot execute maintenance recovery: mc_clock_guard row has tampered HMAC seal.',
      );
    }

    // Trusted authority evidence, not a caller assertion or local wall clock, is the only
    // source accepted for a maintenance operation after any downtime.
    final token = maintenanceTokenService.verifyAndParseToken(
      rawToken: rawMaintenanceToken,
      expectedHospitalCode: hospitalCode,
      expectedInstallationId: expectedInstallationId,
      trustedTimeEvidence: trustedTimeEvidence,
      trustedTimeVerifier: trustedTimeVerifier,
    );

    // 6. Atomic Replay Protection Check:
    final checkNonce = await db.execute(
      'SELECT id FROM mc_consumed_maintenance_tokens WHERE hospital_code = :hosp AND nonce = :nonce LIMIT 1 FOR UPDATE',
      {'hosp': hospitalCode, 'nonce': token.nonce},
    );
    if (checkNonce.rows.isNotEmpty || record.unlockedByMaintenanceTokenId == token.nonce) {
      throw MaintenanceTokenException(
        'NONCE_ALREADY_USED',
        'Maintenance token nonce ${token.nonce} has already been consumed for hospital $hospitalCode.',
      );
    }

    // 7. Atomically consume the nonce in the replay ledger
    final nowUtc = trustedTimeEvidence!.trustedUtc.toUtc();
    final monoMs = _stopwatch.elapsedMilliseconds;

    try {
      await db.execute(
        '''
        INSERT INTO mc_consumed_maintenance_tokens (
          hospital_code, installation_id, nonce, action, consumed_at_utc
        ) VALUES (
          :hosp, :inst, :nonce, :act, :consumed_at
        )
        ''',
        {
          'hosp': hospitalCode,
          'inst': token.installationId,
          'nonce': token.nonce,
          'act': token.action,
          'consumed_at': _fmtDt3(nowUtc),
        },
      );
    } catch (e) {
      if (e.toString().contains('1062') || e.toString().toLowerCase().contains('duplicate')) {
        throw MaintenanceTokenException(
          'NONCE_ALREADY_USED',
          'Maintenance token nonce ${token.nonce} has already been consumed for hospital $hospitalCode.',
        );
      }
      rethrow;
    }

    // 8. CRITICAL SECURITY INVARIANT:
    // If resetting clock backwards, immediately and permanently revoke ALL active sessions
    if (nowUtc.isBefore(record.maxObservedUtc)) {
      await db.execute(
        '''
        UPDATE mc_auth_sessions
        SET is_active = 0, revoked_at = CURRENT_TIMESTAMP, revoke_reason = 'MAINTENANCE_CLOCK_RESET'
        WHERE hospital_code = :hosp AND is_active = 1
        ''',
        {'hosp': hospitalCode},
      );
    }

    final newHighWater = nowUtc;
    final seal = keyManager.computeKeyedSeal(
      hospitalCode: hospitalCode,
      maxObservedUtc: newHighWater,
      lastBootMonotonicMs: monoMs,
      processBootId: _processBootUuid,
      rollbackDetected: false,
      rollbackDeltaSeconds: null,
      lockedAtUtc: null,
      unlockedByMaintenanceTokenId: token.nonce,
      lastEventUuid: _processBootUuid,
    );

    // 9. Update mc_clock_guard
    await db.execute(
      '''
      UPDATE mc_clock_guard
      SET max_observed_utc = :max_utc,
          last_boot_monotonic_ms = :mono_ms,
          process_boot_id = :boot_id,
          last_event_uuid = :event_uuid,
          rollback_detected = 0,
          rollback_delta_seconds = NULL,
          locked_at_utc = NULL,
          unlocked_by_maintenance_token_id = :token_id,
          hmac_seal = :seal
      WHERE hospital_code = :hosp
      ''',
      {
        'hosp': hospitalCode,
        'max_utc': _fmtDt3(newHighWater),
        'mono_ms': monoMs,
        'boot_id': _processBootUuid,
        'event_uuid': _processBootUuid,
        'token_id': token.nonce,
        'seal': seal,
      },
    );

    // 10. Write required structured security audit event inside the exact same ACID transaction
    await db.execute(
      '''
      INSERT INTO mc_audit_logs (
        hospital_code, actor_staff_id, actor_role, device_id,
        action, entity_type, entity_id, correlation_id,
        before_json, after_json, ip_address, created_at
      ) VALUES (
        :hosp, NULL, 'SYSTEM_MAINTENANCE_AUTHORITY', :inst,
        'MAINTENANCE_CLOCK_RECOVERY_APPLIED', 'mc_clock_guard', :entity_id, :nonce,
        :before_json, :after_json, NULL, CURRENT_TIMESTAMP(3)
      )
      ''',
      {
        'hosp': hospitalCode,
        'inst': token.installationId,
        'entity_id': record.id.toString(),
        'nonce': token.nonce,
        'before_json': jsonEncode({
          'maxObservedUtc': record.maxObservedUtc.toIso8601String(),
          'rollbackDetected': record.rollbackDetected,
          'lockedAtUtc': record.lockedAtUtc?.toIso8601String(),
        }),
        'after_json': jsonEncode({
          'maxObservedUtc': newHighWater.toIso8601String(),
          'rollbackDetected': false,
          'unlockedByMaintenanceTokenId': token.nonce,
        }),
      },
    );

    return (await getClockGuard(hospitalCode))!;
  }

  ClockGuardRecord _mapRow(dynamic r) {
    return ClockGuardRecord(
      id: int.parse(r.colByName('id') ?? '1'),
      hospitalCode: r.colByName('hospital_code') ?? '',
      maxObservedUtc: _parseUtc(r.colByName('max_observed_utc')),
      lastEventUuid: r.colByName('last_event_uuid'),
      lastBootMonotonicMs: int.parse(r.colByName('last_boot_monotonic_ms') ?? '0'),
      processBootId: r.colByName('process_boot_id'),
      rollbackDetected: (r.colByName('rollback_detected') ?? '0') == '1',
      rollbackDeltaSeconds: int.tryParse(r.colByName('rollback_delta_seconds') ?? ''),
      lockedAtUtc: r.colByName('locked_at_utc') != null && r.colByName('locked_at_utc')!.isNotEmpty
          ? _parseUtc(r.colByName('locked_at_utc'))
          : null,
      unlockedByMaintenanceTokenId: r.colByName('unlocked_by_maintenance_token_id'),
      hmacSeal: r.colByName('hmac_seal') ?? '',
      updatedAt: _parseUtc(r.colByName('updated_at')),
    );
  }

  static String _fmtDt3(DateTime dt) {
    final u = dt.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    return '${u.year}-${two(u.month)}-${two(u.day)} ${two(u.hour)}:${two(u.minute)}:${two(u.second)}.${three(u.millisecond)}';
  }

  static String _fmtDt(DateTime dt) {
    final u = dt.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year}-${two(u.month)}-${two(u.day)} ${two(u.hour)}:${two(u.minute)}:${two(u.second)}';
  }

  static DateTime _parseUtc(dynamic raw) {
    if (raw == null) return DateTime.now().toUtc();
    final str = raw.toString().trim();
    if (str.isEmpty) return DateTime.now().toUtc();
    final iso = str.contains('T') ? str : str.replaceFirst(' ', 'T');
    final withZ = iso.endsWith('Z') ? iso : '${iso}Z';
    return DateTime.tryParse(withZ) ?? DateTime.now().toUtc();
  }
}
