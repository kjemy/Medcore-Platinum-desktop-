import 'dart:convert';
import 'dart:io';
import 'package:medcore_local_service/medcore_local_service.dart';
import 'test_db_config.dart';

void main(List<String> args) async {
  final testDbName = 'medcore_clock_test';
  final dbConfig = testDbConfig(databaseName: testDbName, maxConnections: 2);

  final db = DbClient(dbConfig);
  try {
    final mode = args.isNotEmpty ? args[0] : 'evaluate';
    final hosp = args.length > 1 ? args[1] : 'HOSP_PROC_01';
    final timeStr = args.length > 2 ? args[2] : DateTime.now().toUtc().toIso8601String();
    final time = DateTime.parse(timeStr);

    final rootDir = args.length > 3 ? args[3] : 'runtime/security/tenant_roots';
    final clockRepo = ClockGuardRepository(db, securityRootDirectory: rootDir);

    if (mode == 'evaluate') {
      final res = await clockRepo.evaluateAndUpdateClock(
        hospitalCode: hosp,
        currentWallClock: time,
      );
      stdout.write(jsonEncode({
        'status': 'OK',
        'effectiveTime': res.effectiveTime.toIso8601String(),
        'rollbackDetected': res.rollbackDetected,
        'maxObservedUtc': res.record.maxObservedUtc.toIso8601String(),
      }));
    } else if (mode == 'read') {
      final rec = await clockRepo.getClockGuard(hosp);
      if (rec == null) {
        stdout.write(jsonEncode({'status': 'NOT_FOUND'}));
      } else {
        final validSeal = clockRepo.verifyHmacSeal(rec);
        stdout.write(jsonEncode({
          'status': 'OK',
          'maxObservedUtc': rec.maxObservedUtc.toIso8601String(),
          'rollbackDetected': rec.rollbackDetected,
          'validSeal': validSeal,
        }));
      }
    }
  } catch (e) {
    stderr.write(e.toString());
    exitCode = 1;
  } finally {
    await db.close();
  }
}
