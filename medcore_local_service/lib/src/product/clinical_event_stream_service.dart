import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';

/// Real-Time Clinical Event Stream & Critical Alerts Service (Batch 15).
/// Provides authenticated, tenant-isolated live SSE (Server-Sent Events) and message
/// dispatch for Doctor Queues, ER Triage, and Critical Laboratory Panic Alerts.
class ClinicalEventStreamService {
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  static const _uuid = Uuid();

  /// Publishes a clinical event. Guaranteed tenant-isolated.
  void publishEvent({
    required String hospitalCode,
    required String topic,
    required Map<String, dynamic> payload,
    String? eventType,
  }) {
    final event = {
      'id': 'EVT-${_uuid.v4()}',
      'hospitalCode': hospitalCode,
      'topic': topic,
      'eventType': eventType ?? 'CLINICAL_EVENT',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'payload': payload,
    };
    _controller.add(event);
  }

  /// Subscribes to a stream of SSE strings filtered strictly by the caller's hospitalCode.
  Stream<String> createSseStream({
    required String hospitalCode,
    Set<String>? filterTopics,
  }) {
    return _controller.stream
        .where((evt) => evt['hospitalCode'] == hospitalCode)
        .where((evt) {
          if (filterTopics == null || filterTopics.isEmpty) return true;
          return filterTopics.contains(evt['topic']);
        })
        .map((evt) {
          final jsonStr = jsonEncode(evt);
          return 'id: ${evt['id']}\nevent: ${evt['eventType']}\ndata: $jsonStr\n\n';
        });
  }

  /// Broadcasts a critical laboratory panic alert (CLN-003).
  void broadcastLabPanicAlert({
    required String hospitalCode,
    required int orderId,
    required String testName,
    required String panicValue,
    required String patientName,
  }) {
    publishEvent(
      hospitalCode: hospitalCode,
      topic: 'lab:panic_alerts',
      eventType: 'CRITICAL_PANIC_ALERT',
      payload: {
        'orderId': orderId,
        'testName': testName,
        'panicValue': panicValue,
        'patientName': patientName,
        'alertLevel': 'HIGH_CRITICAL',
      },
    );
  }

  /// Broadcasts a doctor queue update when reception checks in a visit.
  void broadcastDoctorQueueUpdate({
    required String hospitalCode,
    required int doctorId,
    required String visitNumber,
    required String patientName,
    required String priority,
  }) {
    publishEvent(
      hospitalCode: hospitalCode,
      topic: 'doctor:queue:$doctorId',
      eventType: 'DOCTOR_QUEUE_UPDATE',
      payload: {
        'doctorId': doctorId,
        'visitNumber': visitNumber,
        'patientName': patientName,
        'priority': priority,
      },
    );
  }

  void dispose() {
    _controller.close();
  }
}
