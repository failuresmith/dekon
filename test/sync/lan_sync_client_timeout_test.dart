import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dekon/src/persistence/persistence.dart';
import 'package:dekon/src/sync/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _peerDeviceId = '019e9239-1111-7000-8000-000000000001';
const _sharedSecret = 'test-shared-secret';
const _fastTimeouts = LanSyncTimeouts(
  ping: Duration(milliseconds: 10),
  saleCommand: Duration(milliseconds: 10),
  inventorySnapshot: Duration(milliseconds: 10),
  eventPull: Duration(milliseconds: 10),
  eventPush: Duration(milliseconds: 10),
  longPollTransportMargin: Duration(milliseconds: 30),
  webSocketConnect: Duration(milliseconds: 10),
);

final _now = DateTime.utc(2026, 6, 4, 12);

void main() {
  setUpAll(sqfliteFfiInit);

  test('hung ping times out and a later ping can succeed', () async {
    await _withStore((db, store) async {
      await _trustMain(store);
      var requestCount = 0;
      final client = LanSyncClient(
        store: store,
        timeouts: _fastTimeouts,
        client: MockClient((request) {
          requestCount += 1;
          if (requestCount == 1) return Completer<http.Response>().future;
          return Future.value(_syncStateResponse());
        }),
        now: () => _now,
      );
      addTearDown(client.close);

      await expectLater(
        client.pingPeer(_peerDeviceId),
        throwsA(_timeoutWithCode(SyncTimeoutException.ping)),
      );
      expect(await _lastPeerError(db), SyncTimeoutException.ping);

      await client.pingPeer(_peerDeviceId);

      expect(requestCount, 2);
      expect(await _lastPeerError(db), isNull);
    });
  });

  test('hung snapshot fetch times out explicitly', () async {
    await _withStore((db, store) async {
      await _trustMain(store);
      final client = LanSyncClient(
        store: store,
        timeouts: _fastTimeouts,
        client: MockClient((_) => Completer<http.Response>().future),
        now: () => _now,
      );
      addTearDown(client.close);

      await expectLater(
        client.fetchAndApplyCashierInventorySnapshot(_peerDeviceId),
        throwsA(_timeoutWithCode(SyncTimeoutException.inventorySnapshot)),
      );

      expect(await _lastPeerError(db), SyncTimeoutException.inventorySnapshot);
    });
  });

  test('hung sale command times out without marking accepted', () async {
    await _withStore((db, store) async {
      await _trustMain(store);
      const commandId = '019e9239-2222-7000-8000-000000000001';
      await store.enqueueCashierSaleCommand(
        command: CashierSaleCommand(
          commandId: commandId,
          occurredAt: _now,
          lines: const [
            CashierSaleCommandLine(productId: 'product-1', quantity: 1),
          ],
        ),
        lines: const [
          CashierSaleOutboxLine(
            productId: 'product-1',
            productName: 'Tea',
            quantity: 1,
            unitPriceMinor: 100,
            lineTotalMinor: 100,
          ),
        ],
      );
      final client = LanSyncClient(
        store: store,
        timeouts: _fastTimeouts,
        client: MockClient((_) => Completer<http.Response>().future),
        now: () => _now,
      );
      addTearDown(client.close);

      await expectLater(
        client.drainCashierSaleOutbox(_peerDeviceId),
        throwsA(_timeoutWithCode(SyncTimeoutException.saleCommand)),
      );

      expect(
        await store.cashierSaleCommandStatus(commandId),
        CashierSaleCommandOutboxStatus.queued,
      );
      expect(await _lastPeerError(db), SyncTimeoutException.saleCommand);
    });
  });

  test('hung WebSocket connect times out explicitly', () async {
    await _withStore((db, store) async {
      await _trustMain(store);
      final client = LanSyncClient(
        store: store,
        timeouts: _fastTimeouts,
        webSocketConnector: (_, {headers}) => Completer<WebSocket>().future,
        now: () => _now,
      );
      addTearDown(client.close);

      await expectLater(
        client.openCashierProjectionStream(_peerDeviceId),
        throwsA(_timeoutWithCode(SyncTimeoutException.projectionStream)),
      );

      expect(await _lastPeerError(db), SyncTimeoutException.projectionStream);
    });
  });

  test('long-poll uses server wait timeout plus transport margin', () async {
    await _withStore((_, store) async {
      await _trustMain(store);
      final client = LanSyncClient(
        store: store,
        timeouts: _fastTimeouts,
        client: MockClient((request) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(request.url.queryParameters['wait'], 'true');
          expect(request.url.queryParameters['wait_ms'], '20');
          return http.Response(
            jsonEncode({
              'events': const [],
              'next_cursor': null,
              'has_more': false,
            }),
            HttpStatus.ok,
          );
        }),
        now: () => _now,
      );
      addTearDown(client.close);

      final result = await client.pullFromPeer(
        _peerDeviceId,
        waitForEvents: true,
        waitTimeout: const Duration(milliseconds: 20),
      );

      expect(result.hasEventOutcomes, false);
    });
  });
}

Matcher _timeoutWithCode(String code) {
  return isA<SyncTimeoutException>().having(
    (error) => error.code,
    'code',
    code,
  );
}

http.Response _syncStateResponse() {
  return http.Response(
    jsonEncode({
      'device_id': _peerDeviceId,
      'event_count': 0,
      'unsupported_event_count': 0,
      'trusted_peer_count': 1,
      'server_time': _now.toIso8601String(),
    }),
    HttpStatus.ok,
  );
}

Future<void> _trustMain(SyncStore store) {
  return store.trustPeer(
    deviceId: _peerDeviceId,
    displayName: 'Main',
    sharedSecret: _sharedSecret,
    baseUrl: 'http://127.0.0.1:$syncDefaultLanPort',
  );
}

Future<String?> _lastPeerError(Database db) async {
  final rows = await db.query(
    'sync_peers',
    columns: ['last_error'],
    where: 'peer_device_id = ?',
    whereArgs: [_peerDeviceId],
    limit: 1,
  );
  return rows.single['last_error'] as String?;
}

Future<void> _withStore(
  Future<void> Function(Database db, SyncStore store) body,
) async {
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
  try {
    await body(db, store);
  } finally {
    await db.close();
  }
}
