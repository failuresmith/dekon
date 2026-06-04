import 'package:dekon/src/domain/events/events.dart';

const testDeviceId = '018f2f12-7b60-7a15-8c7d-000000000001';
const testEventId = '018f2f12-7b60-7a15-8c7d-000000000101';

EventEnvelope makeTestEvent({
  String eventId = testEventId,
  String deviceId = testDeviceId,
  String type = EventTypes.productCreated,
  String entityId = 'product-1',
  int schemaVersion = EventSchema.currentVersion,
  Map<String, Object?> payload = const {'name': 'Coffee', 'barcode': '123'},
  String? payloadHashOverride,
  int physicalTimeMillis = 1000,
  int logicalCounter = 0,
  DateTime? createdAt,
}) {
  final event = EventEnvelope.local(
    eventId: eventId,
    deviceId: deviceId,
    hlc: HybridLogicalTimestamp(
      physicalTimeMillis: physicalTimeMillis,
      logicalCounter: logicalCounter,
      nodeId: deviceId,
    ),
    type: type,
    entityId: entityId,
    payload: payload,
    schemaVersion: schemaVersion,
    createdAt: createdAt ?? DateTime.utc(2026),
  );
  if (payloadHashOverride == null) return event;
  return EventEnvelope(
    eventId: event.eventId,
    deviceId: event.deviceId,
    hlc: event.hlc,
    type: event.type,
    entityId: event.entityId,
    payload: event.payload,
    schemaVersion: event.schemaVersion,
    payloadHash: payloadHashOverride,
    createdAt: event.createdAt,
  );
}
