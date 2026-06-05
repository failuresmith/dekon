import 'dart:convert';

import 'package:dekon/src/domain/events/events.dart';
import 'package:dekon/src/persistence/persistence.dart';
import 'package:dekon/src/sync/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/event_fixtures.dart';

const _peerDeviceId = '019e9239-1111-7000-8000-000000000001';
const _sharedSecret = 'test-shared-secret';
final _now = DateTime.utc(2026, 6, 4, 12);

void main() {
  setUpAll(sqfliteFfiInit);

  test('rejects unauthenticated event POST', () async {
    await _withHarness((harness) async {
      final response = await harness.server.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/events'),
          body: jsonEncode({'events': []}),
        ),
      );

      expect(response.statusCode, 401);
    });
  });

  test('QR pairing stores a trusted peer', () async {
    await _withHarness((harness) async {
      final pairing = harness.server.createPairingPayload(
        baseUrl: 'http://localhost',
      );
      final response = await harness.server.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/pair'),
          body: jsonEncode({
            'device_id': _peerDeviceId,
            'display_name': 'Counter phone',
            'pairing_secret': pairing.pairingSecret,
          }),
        ),
      );

      final peer = await harness.store.trustedPeer(_peerDeviceId);

      expect(response.statusCode, 200);
      expect(peer?.displayName, 'Counter phone');
    });
  });

  test('manual pairing stores a trusted peer during active pairing', () async {
    await _withHarness((harness) async {
      final pairing = harness.server.createPairingPayload(
        baseUrl: 'http://localhost',
      );
      final response = await harness.server.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/pair'),
          body: jsonEncode({
            'device_id': _peerDeviceId,
            'display_name': 'Counter phone',
            'manual_pairing': true,
          }),
        ),
      );
      final body = await _json(response);
      final peer = await harness.store.trustedPeer(_peerDeviceId);

      expect(response.statusCode, 200);
      expect(body['shared_secret'], pairing.pairingSecret);
      expect(peer?.sharedSecret, pairing.pairingSecret);
    });
  });

  test('manual address client stores returned shared secret', () async {
    await _withHarness((harness) async {
      const baseUrl = 'http://192.168.1.10:1234';
      final client = LanSyncClient(
        store: harness.store,
        client: MockClient((request) async {
          if (request.url.toString() == '$baseUrl/device') {
            return http.Response(
              jsonEncode({
                'protocol_version': syncProtocolVersion,
                'event_schema_version': EventSchema.currentVersion,
                'device_id': _peerDeviceId,
                'display_name': 'Main device',
              }),
              200,
            );
          }
          if (request.url.toString() == '$baseUrl/pair') {
            final body = jsonDecode(request.body) as Map<String, Object?>;
            expect(body['manual_pairing'], true);
            return http.Response(
              jsonEncode({
                'protocol_version': syncProtocolVersion,
                'event_schema_version': EventSchema.currentVersion,
                'device_id': _peerDeviceId,
                'display_name': 'Main device',
                'shared_secret': _sharedSecret,
              }),
              200,
            );
          }
          return http.Response('not found', 404);
        }),
      );
      addTearDown(client.close);

      await client.pairWithManualAddress(
        '192.168.1.10:1234',
        displayName: 'Counter phone',
      );
      final peer = await harness.store.trustedPeer(_peerDeviceId);

      expect(peer?.baseUrl, baseUrl);
      expect(peer?.sharedSecret, _sharedSecret);
    });
  });

  test('duplicate POST is idempotent and reports duplicate IDs', () async {
    await _withHarness((harness) async {
      await harness.trustPeer();
      final event = _productCreated(1, barcode: 'COF-1');
      final first = await harness.postEvents([event]);
      final second = await harness.postEvents([event]);
      final state = await harness.store.state();

      expect(first['accepted'], [event.eventId]);
      expect(second['duplicate'], [event.eventId]);
      expect(state.eventCount, 1);
    });
  });

  test('GET events resumes from returned cursor', () async {
    await _withHarness((harness) async {
      await harness.trustPeer();
      await EventStore(harness.db).append(
        _productCreated(1, deviceId: harness.localDeviceId, barcode: 'A-1'),
      );
      await EventStore(harness.db).append(
        _productCreated(
          2,
          deviceId: harness.localDeviceId,
          barcode: 'B-1',
          physicalTimeMillis: 2000,
        ),
      );

      final first = await harness.getEvents(limit: 1);
      final cursor = first['next_cursor'] as String;
      final second = await harness.getEvents(since: cursor, limit: 1);

      expect(first['events'], hasLength(1));
      expect(first['has_more'], true);
      expect((second['events'] as List).single['event_id'], _eventId(2));
    });
  });

  test('future schema events are stored as unsupported', () async {
    await _withHarness((harness) async {
      await harness.trustPeer();
      final event = _productCreated(
        3,
        schemaVersion: EventSchema.currentVersion + 1,
        type: 'future.product_changed',
      );

      final response = await harness.postEvents([event]);
      final state = await harness.store.state();

      expect(response['unsupported'], [event.eventId]);
      expect(state.unsupportedEventCount, 1);
    });
  });

  test('out-of-order product events converge after POST', () async {
    await _withHarness((harness) async {
      await harness.trustPeer();
      final productId = 'remote-product-1';
      final created = _productCreated(
        4,
        entityId: productId,
        barcode: 'REMOTE-1',
        name: 'Old Name',
        physicalTimeMillis: 1000,
      );
      final fieldSet = makeTestEvent(
        eventId: _eventId(5),
        deviceId: _peerDeviceId,
        type: EventTypes.productFieldSet,
        entityId: productId,
        payload: const {'field': 'name', 'value': 'Remote Tea'},
        physicalTimeMillis: 2000,
        createdAt: _now,
      );

      final response = await harness.postEvents([fieldSet, created]);
      final rows = await harness.db.query(
        'products_projection',
        where: 'product_id = ?',
        whereArgs: [productId],
      );

      expect(response['accepted'], [fieldSet.eventId, created.eventId]);
      expect(rows.single['name'], 'Remote Tea');
      expect(rows.single['barcode'], 'REMOTE-1');
    });
  });
}

Future<void> _withHarness(Future<void> Function(_Harness harness) body) async {
  final db = await CoreDatabase.open(
    path: inMemoryDatabasePath,
    factory: databaseFactoryFfi,
    singleInstance: false,
  );
  final localDeviceId = await DeviceIdentityRepository(db).getOrCreate();
  final store = SyncStore(
    database: db,
    localDeviceId: localDeviceId,
    now: () => _now,
  );
  final server = LanSyncServer(store: store, now: () => _now);
  final harness = _Harness(db, store, server, localDeviceId);
  try {
    await body(harness);
  } finally {
    await server.stop();
    await db.close();
  }
}

class _Harness {
  const _Harness(this.db, this.store, this.server, this.localDeviceId);

  final Database db;
  final SyncStore store;
  final LanSyncServer server;
  final String localDeviceId;

  Future<void> trustPeer() {
    return store.trustPeer(
      deviceId: _peerDeviceId,
      displayName: 'Peer',
      sharedSecret: _sharedSecret,
      baseUrl: 'http://localhost',
    );
  }

  Future<Map<String, Object?>> postEvents(List<EventEnvelope> events) async {
    final body = jsonEncode({
      'events': [for (final event in events) EventCodec.toJson(event)],
    });
    final uri = Uri.parse('http://localhost/events');
    final response = await server.handler(
      Request(
        'POST',
        uri,
        headers: {
          'content-type': 'application/json',
          ..._authHeaders('POST', uri, utf8.encode(body)),
        },
        body: body,
      ),
    );
    expect(response.statusCode, 200);
    return _json(response);
  }

  Future<Map<String, Object?>> getEvents({
    String? since,
    int limit = 100,
  }) async {
    final query = {'limit': limit.toString()};
    if (since != null) query['since'] = since;
    final uri = Uri.parse(
      'http://localhost/events',
    ).replace(queryParameters: query);
    final response = await server.handler(
      Request('GET', uri, headers: _authHeaders('GET', uri, const [])),
    );
    expect(response.statusCode, 200);
    return _json(response);
  }

  Map<String, String> _authHeaders(
    String method,
    Uri uri,
    List<int> bodyBytes,
  ) {
    return SyncAuthenticator(now: () => _now).signHeaders(
      method: method,
      uri: uri,
      bodyBytes: bodyBytes,
      deviceId: _peerDeviceId,
      sharedSecret: _sharedSecret,
      timestamp: _now,
    );
  }
}

EventEnvelope _productCreated(
  int index, {
  String? deviceId,
  String? entityId,
  String? barcode,
  String name = 'Coffee',
  int physicalTimeMillis = 1000,
  int schemaVersion = EventSchema.currentVersion,
  String type = EventTypes.productCreated,
}) {
  return makeTestEvent(
    eventId: _eventId(index),
    deviceId: deviceId ?? _peerDeviceId,
    type: type,
    entityId: entityId ?? 'product-$index',
    schemaVersion: schemaVersion,
    payload: {
      'name': name,
      'barcode': barcode ?? 'BAR-$index',
      'sku': null,
      'unit': 'each',
      'sale_price_minor': 100,
      'purchase_cost_minor': 50,
      'active': true,
    },
    physicalTimeMillis: physicalTimeMillis,
    createdAt: _now,
  );
}

String _eventId(int index) {
  return '019e9239-0000-7000-8000-${index.toString().padLeft(12, '0')}';
}

Future<Map<String, Object?>> _json(Response response) async {
  return jsonDecode(await response.readAsString()) as Map<String, Object?>;
}
