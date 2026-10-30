import 'dart:convert';
import 'package:shelf/shelf.dart';
import '../db/db_client.dart';
import 'commercial_entitlement_service.dart';

/// Server-Side Commercial Entitlement & Gating Middleware (Gate 6)
///
/// Follows the Khaled Universal Engineering Constitution:
/// 1. Centralized server-side enforcement (UI banners are purely informational; the API is authoritative).
/// 2. Implements strict `EXPIRED_READ_ONLY` mode:
///    - Clinical and administrative GET routes remain accessible for patient safety.
///    - All operational, financial, and clinical mutation routes (POST/PUT/DELETE) are blocked fail-closed.
/// 3. Rejects mutations with deterministic machine-readable status `SUBSCRIPTION_EXPIRED`.
class EntitlementMiddleware {
  final CommercialEntitlementService entitlementService;
  final DbClient db;

  EntitlementMiddleware({
    required this.entitlementService,
    required this.db,
  });

  Middleware get middleware => (Handler innerHandler) {
        return (Request req) async {
          final path = req.url.path;
          final method = req.method.toUpperCase();

          // 1. Always allow public endpoints
          if (_isPublicRoute(path)) {
            return await innerHandler(req);
          }

          // 2. Always allow technician & maintenance operations
          if (path.startsWith('api/v1/technician/')) {
            return await innerHandler(req);
          }

          // 3. Always allow read-only (GET/HEAD/OPTIONS) operations (Patient Safety Invariant)
          if (method == 'GET' || method == 'HEAD' || method == 'OPTIONS') {
            return await innerHandler(req);
          }

          // 4. For mutating operations (POST, PUT, DELETE, PATCH), enforce active commercial entitlement
          final hospitalCode = req.headers['x-tenant-id']?.trim() ?? 'HOSP_MAIN';
          final entitlement = await entitlementService.getActiveEntitlement(hospitalCode);

          if (!entitlement.isMutationAllowed) {
            // Log security rejection
            try {
              await db.execute(
                '''
                INSERT INTO mc_commercial_audit_log (
                  hospital_code, license_id, event_type, severity, details_json, created_at
                ) VALUES (
                  :hosp, :lid, 'mutation.blocked_expired', 'WARNING', :details, NOW(3)
                )
                ''',
                {
                  'hosp': hospitalCode,
                  'lid': entitlement.licenseId,
                  'details': jsonEncode({
                    'path': req.requestedUri.path,
                    'method': method,
                    'status': entitlement.status.toWire(),
                    'expiresAtUtc': entitlement.expiresAtUtc.toIso8601String(),
                  }),
                },
              );
            } catch (_) {}

            final errPayload = {
              'error': {
                'code': 'SUBSCRIPTION_EXPIRED',
                'message': 'Facility commercial entitlement is ${entitlement.status.toWire()}. '
                    'Read-only access is preserved for patient safety. New visits, shifts, and mutations are blocked.',
                'status': entitlement.status.toWire(),
                'licenseId': entitlement.licenseId,
                'expiresAtUtc': entitlement.expiresAtUtc.toIso8601String(),
              }
            };

            return Response(
              403,
              body: jsonEncode(errPayload),
              headers: {'content-type': 'application/json'},
            );
          }

          return await innerHandler(req);
        };
      };

  bool _isPublicRoute(String path) {
    return path == 'api/v1/health' ||
        path == 'api/v1/auth/csrf' ||
        path == 'api/v1/auth/login' ||
        path == 'api/v1/auth/logout' ||
        path == 'api/v1/facility/config' ||
        path.startsWith('api/v1/technician/bootstrap') ||
        path.startsWith('api/v1/technician/login');
  }
}
