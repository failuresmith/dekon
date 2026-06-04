import 'package:dekon/src/domain/events/events.dart';
import 'package:dekon/src/persistence/persistence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/event_fixtures.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  Future<T> withStore<T>(Future<T> Function(EventStore store) body) async {
    final db = await CoreDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    try {
      return await body(EventStore(db, now: () => DateTime.utc(2026, 1, 2)));
    } finally {
      await db.close();
    }
  }

  test('stores local device identity once', () async {
    final db = await CoreDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    try {
      final repo = DeviceIdentityRepository(db, now: () => DateTime.utc(2026));

      final first = await repo.getOrCreate();
      final second = await repo.getOrCreate();

      expect(first, second);
      expect(first, matches(RegExp(r'^[0-9a-f-]{36}$')));
      final devices = await db.query('devices');
      expect(devices.single['device_id'], first);
      expect(devices.single['trust_status'], 'local');
    } finally {
      await db.close();
    }
  });

  test('appends events idempotently by event id', () async {
    await withStore((store) async {
      final event = makeTestEvent();

      final first = await store.append(event);
      final second = await store.append(event);

      expect(first.status, EventWriteStatus.accepted);
      expect(second.status, EventWriteStatus.duplicate);
      expect(await store.count(), 1);
    });
  });

  test('fails loudly on same event id with different payload', () async {
    await withStore((store) async {
      await store.append(makeTestEvent());

      expect(
        () => store.append(
          makeTestEvent(payload: const {'name': 'Tea', 'barcode': '123'}),
        ),
        throwsA(isA<ConflictingDuplicateEventException>()),
      );
      expect(await store.count(), 1);
    });
  });

  test('stores future schema events as unsupported', () async {
    await withStore((store) async {
      final event = makeTestEvent(
        schemaVersion: EventSchema.currentVersion + 1,
        type: 'future.event_type',
      );

      final result = await store.append(event);
      final unsupported = await store.fetchUnsupportedEvents();
      final events = await store.fetchEvents();

      expect(result.status, EventWriteStatus.unsupported);
      expect(unsupported.single.eventId, event.eventId);
      expect(unsupported.single.reason, contains('newer than supported'));
      expect(events.single.eventId, event.eventId);
    });
  });

  test('rolls back a batch when one event is invalid', () async {
    await withStore((store) async {
      expect(
        () => store.appendAll([
          makeTestEvent(),
          makeTestEvent(
            eventId: '018f2f12-7b60-7a15-8c7d-000000000102',
            payloadHashOverride: 'bad-hash',
          ),
        ]),
        throwsA(isA<EventValidationException>()),
      );

      expect(await store.count(), 0);
      expect(await store.fetchUnsupportedEvents(), isEmpty);
    });
  });
}
