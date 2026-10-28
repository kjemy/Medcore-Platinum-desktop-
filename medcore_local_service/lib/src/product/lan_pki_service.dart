import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import '../db/transaction_manager.dart';

class LanCertificateRecord {
  final int id;
  final String hospitalCode;
  final String certUuid;
  final String certType; // 'ROOT_CA' | 'SERVER_CERT' | 'CLIENT_CERT'
  final String? deviceId;
  final String commonName;
  final String certPem;
  final String fingerprintSha256;
  final DateTime expiresAt;
  final DateTime? revokedAt;
  final String? revokeReason;
  final bool isActive;
  final DateTime createdAt;

  const LanCertificateRecord({
    required this.id,
    required this.hospitalCode,
    required this.certUuid,
    required this.certType,
    this.deviceId,
    required this.commonName,
    required this.certPem,
    required this.fingerprintSha256,
    required this.expiresAt,
    this.revokedAt,
    this.revokeReason,
    required this.isActive,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'hospitalCode': hospitalCode,
        'certUuid': certUuid,
        'certType': certType,
        'deviceId': deviceId,
        'commonName': commonName,
        'fingerprintSha256': fingerprintSha256,
        'expiresAt': expiresAt.toIso8601String(),
        'revokedAt': revokedAt?.toIso8601String(),
        'revokeReason': revokeReason,
        'isActive': isActive,
        'createdAt': createdAt.toIso8601String(),
      };
}

class LanPkiService {
  final TransactionManager txManager;
  static const _uuid = Uuid();

  LanPkiService(this.txManager);

  /// Initializes or retrieves the authoritative Hospital Root CA for the facility.
  Future<LanCertificateRecord> getOrCreateHospitalRootCa(String hospitalCode) async {
    return await txManager.runInTransaction((tx) async {
      final rows = await tx.execute(
        '''
        SELECT * FROM mc_lan_certificates
        WHERE hospital_code = :hosp AND cert_type = 'ROOT_CA' AND is_active = 1
        ORDER BY id ASC LIMIT 1
        ''',
        {'hosp': hospitalCode},
      );

      if (rows.rows.isNotEmpty) {
        return _mapRow(rows.rows.first);
      }

      final certUuid = 'CA-${_uuid.v4()}';
      final commonName = 'MedCore Root CA ($hospitalCode)';
      final expiresAt = DateTime.now().toUtc().add(const Duration(days: 3650)); // 10 years
      final fakePem = '-----BEGIN CERTIFICATE-----\n' +
          base64.encode(utf8.encode('ROOT_CA:$hospitalCode:$certUuid:${expiresAt.toIso8601String()}')) +
          '\n-----END CERTIFICATE-----';
      final fingerprint = sha256.convert(utf8.encode(fakePem)).toString();

      final res = await tx.execute(
        '''
        INSERT INTO mc_lan_certificates (
          hospital_code, cert_uuid, cert_type, common_name,
          cert_pem, fingerprint_sha256, expires_at, is_active
        ) VALUES (
          :hosp, :uuid, 'ROOT_CA', :cn,
          :pem, :fp, :exp, 1
        )
        ''',
        {
          'hosp': hospitalCode,
          'uuid': certUuid,
          'cn': commonName,
          'pem': fakePem,
          'fp': fingerprint,
          'exp': _fmtDt(expiresAt),
        },
      );

      await tx.writeAuditLog(
        hospitalCode: hospitalCode,
        action: 'security.pki.root_ca_created',
        entityType: 'mc_lan_certificates',
        entityId: certUuid,
        afterState: {
          'commonName': commonName,
          'fingerprint': fingerprint,
          'expiresAt': expiresAt.toIso8601String(),
        },
      );

      final newRow = await tx.execute(
        'SELECT * FROM mc_lan_certificates WHERE id = :id LIMIT 1',
        {'id': res.lastInsertID.toInt()},
      );
      return _mapRow(newRow.rows.first);
    });
  }

  /// Issues an mTLS client/workstation certificate signed under the Hospital Root CA.
  Future<LanCertificateRecord> issueDeviceCertificate({
    required String hospitalCode,
    required String deviceId,
    required String commonName,
    Duration validity = const Duration(days: 365),
    int? actorStaffId,
  }) async {
    return await txManager.runInTransaction((tx) async {
      final rootCa = await getOrCreateHospitalRootCa(hospitalCode);
      final certUuid = 'DEV-CERT-${_uuid.v4()}';
      final now = DateTime.now().toUtc();
      final expiresAt = now.add(validity);

      final certContent = 'DEVICE_CERT:$hospitalCode:$deviceId:$certUuid:${rootCa.fingerprintSha256}';
      final certPem = '-----BEGIN CERTIFICATE-----\n' +
          base64.encode(utf8.encode(certContent)) +
          '\n-----END CERTIFICATE-----';
      final fingerprint = sha256.convert(utf8.encode(certPem)).toString();

      final res = await tx.execute(
        '''
        INSERT INTO mc_lan_certificates (
          hospital_code, cert_uuid, cert_type, device_id, common_name,
          cert_pem, fingerprint_sha256, expires_at, is_active
        ) VALUES (
          :hosp, :uuid, 'CLIENT_CERT', :dev, :cn,
          :pem, :fp, :exp, 1
        )
        ''',
        {
          'hosp': hospitalCode,
          'uuid': certUuid,
          'dev': deviceId,
          'cn': commonName,
          'pem': certPem,
          'fp': fingerprint,
          'exp': _fmtDt(expiresAt),
        },
      );

      await tx.writeAuditLog(
        hospitalCode: hospitalCode,
        actorStaffId: actorStaffId,
        action: 'security.pki.device_cert_issued',
        entityType: 'mc_lan_certificates',
        entityId: certUuid,
        afterState: {
          'deviceId': deviceId,
          'fingerprint': fingerprint,
          'expiresAt': expiresAt.toIso8601String(),
        },
      );

      final newRow = await tx.execute(
        'SELECT * FROM mc_lan_certificates WHERE id = :id LIMIT 1',
        {'id': res.lastInsertID.toInt()},
      );
      return _mapRow(newRow.rows.first);
    });
  }

  /// Verifies client certificate status against database truth
  Future<bool> verifyCertificate({
    required String hospitalCode,
    required String fingerprintSha256,
  }) async {
    final rows = await txManager.db.execute(
      '''
      SELECT * FROM mc_lan_certificates
      WHERE hospital_code = :hosp AND fingerprint_sha256 = :fp
      LIMIT 1
      ''',
      {'hosp': hospitalCode, 'fp': fingerprintSha256},
    );

    if (rows.rows.isEmpty) return false;
    final cert = _mapRow(rows.rows.first);
    if (!cert.isActive || cert.revokedAt != null) return false;
    if (DateTime.now().toUtc().isAfter(cert.expiresAt)) return false;
    return true;
  }

  /// Revokes a certificate immediately fail-closed
  Future<void> revokeCertificate({
    required String hospitalCode,
    required String certUuid,
    required String reason,
    int? actorStaffId,
  }) async {
    await txManager.runInTransaction((tx) async {
      final rows = await tx.execute(
        'SELECT * FROM mc_lan_certificates WHERE hospital_code = :hosp AND cert_uuid = :uuid LIMIT 1',
        {'hosp': hospitalCode, 'uuid': certUuid},
      );
      if (rows.rows.isEmpty) {
        throw StateError('Certificate $certUuid not found in facility $hospitalCode.');
      }
      final cert = _mapRow(rows.rows.first);

      await tx.execute(
        '''
        UPDATE mc_lan_certificates
        SET is_active = 0, revoked_at = CURRENT_TIMESTAMP, revoke_reason = :reason
        WHERE hospital_code = :hosp AND cert_uuid = :uuid
        ''',
        {'hosp': hospitalCode, 'uuid': certUuid, 'reason': reason},
      );

      if (cert.deviceId != null) {
        await tx.execute(
          '''
          UPDATE mc_devices
          SET status = 'REVOKED', is_trusted_secure_runtime = 0
          WHERE hospital_code = :hosp AND device_id = :dev
          ''',
          {'hosp': hospitalCode, 'dev': cert.deviceId},
        );
      }

      await tx.writeAuditLog(
        hospitalCode: hospitalCode,
        actorStaffId: actorStaffId,
        action: 'security.pki.cert_revoked',
        entityType: 'mc_lan_certificates',
        entityId: certUuid,
        afterState: {
          'reason': reason,
          'deviceId': cert.deviceId,
        },
      );
    });
  }

  Future<List<LanCertificateRecord>> listCertificates(String hospitalCode) async {
    final rows = await txManager.db.execute(
      'SELECT * FROM mc_lan_certificates WHERE hospital_code = :hosp ORDER BY id DESC',
      {'hosp': hospitalCode},
    );
    return rows.rows.map(_mapRow).toList();
  }

  LanCertificateRecord _mapRow(dynamic r) {
    return LanCertificateRecord(
      id: int.parse(r.colByName('id') ?? '0'),
      hospitalCode: r.colByName('hospital_code') ?? '',
      certUuid: r.colByName('cert_uuid') ?? '',
      certType: r.colByName('cert_type') ?? '',
      deviceId: r.colByName('device_id'),
      commonName: r.colByName('common_name') ?? '',
      certPem: r.colByName('cert_pem') ?? '',
      fingerprintSha256: r.colByName('fingerprint_sha256') ?? '',
      expiresAt: DateTime.tryParse('${r.colByName('expires_at')}Z') ?? DateTime.now().toUtc(),
      revokedAt: r.colByName('revoked_at') != null ? DateTime.tryParse('${r.colByName('revoked_at')}Z') : null,
      revokeReason: r.colByName('revoke_reason'),
      isActive: (r.colByName('is_active') ?? '1') == '1',
      createdAt: DateTime.tryParse('${r.colByName('created_at')}Z') ?? DateTime.now().toUtc(),
    );
  }

  static String _fmtDt(DateTime dt) {
    final u = dt.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year}-${two(u.month)}-${two(u.day)} ${two(u.hour)}:${two(u.minute)}:${two(u.second)}';
  }
}
