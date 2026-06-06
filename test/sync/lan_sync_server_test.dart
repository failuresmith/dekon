import 'dart:convert';
import 'dart:io';

import 'package:dekon/src/application/application.dart';
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
const _secondPeerDeviceId = '019e9239-1111-7000-8000-000000000002';
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

      final body = await _json(response);
      final peer = await harness.store.trustedPeer(_peerDeviceId);

      expect(response.statusCode, 200);
      expect(body['assigned_display_name'], 'Cashier-1');
      expect(peer?.displayName, 'Cashier-1');
    });
  });

  test('pairing assigns stable sequential cashier names', () async {
    await _withHarness((harness) async {
      final pairing = harness.server.createPairingPayload(
        baseUrl: 'http://localhost',
      );
      Future<Map<String, Object?>> pair(String deviceId) async {
        final response = await harness.server.handler(
          Request(
            'POST',
            Uri.parse('http://localhost/pair'),
            body: jsonEncode({
              'device_id': deviceId,
              'display_name': 'Cashier Device',
              'pairing_secret': pairing.pairingSecret,
            }),
          ),
        );
        expect(response.statusCode, 200);
        return _json(response);
      }

      final first = await pair(_peerDeviceId);
      final second = await pair(_secondPeerDeviceId);
      final firstRetry = await pair(_peerDeviceId);

      expect(first['assigned_display_name'], 'Cashier-1');
      expect(second['assigned_display_name'], 'Cashier-2');
      expect(firstRetry['assigned_display_name'], 'Cashier-1');
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
      expect(body['assigned_display_name'], 'Cashier-1');
      expect(peer?.sharedSecret, pairing.pairingSecret);
      expect(peer?.displayName, 'Cashier-1');
    });
  });

  test('server can run without exposing a pairing QR', () async {
    final db = await CoreDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
      singleInstance: false,
    );
    final repository = await DekonRepository.open(database: db);
    final server = repository.createLanSyncServer();
    try {
      await server.start(
        address: InternetAddress.loopbackIPv4,
        enablePairing: false,
      );

      expect(server.isRunning, true);
      expect(server.serverUrl, startsWith('http://'));
      expect(server.pairingQrData, isNull);

      final pairing = server.startPairing();

      expect(pairing.baseUrl, server.serverUrl);
      expect(server.pairingQrData, isNotNull);
    } finally {
      await server.stop();
      await repository.close();
    }
  });

  test('records redacted peer messages for pairing exchange', () async {
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

      final messages = harness.activityBus.peerMessageSnapshot();
      final request = messages.first;
      final reply = messages.last;

      expect(response.statusCode, 200);
      expect(messages, hasLength(2));
      expect(request.direction, SyncPeerMessageDirection.received);
      expect(request.path, '/pair');
      expect(request.summary, 'Pairing request');
      expect(request.bodyPreview, contains('"pairing_secret": "[redacted]"'));
      expect(request.bodyPreview, isNot(contains(pairing.pairingSecret)));
      expect(reply.direction, SyncPeerMessageDirection.sent);
      expect(reply.statusCode, 200);
      expect(reply.summary, 'Pairing result');
      expect(reply.bodyPreview, contains('"shared_secret": "[redacted]"'));
      expect(reply.bodyPreview, isNot(contains(pairing.pairingSecret)));
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
                'assigned_display_name': 'Cashier-1',
              }),
              200,
            );
          }
          if (request.url.path == '/events') {
            return http.Response(
              jsonEncode({
                'events': const [],
                'next_cursor': null,
                'has_more': false,
              }),
              200,
            );
          }
          if (request.url.path == '/cashier/inventory-snapshot') {
            return http.Response(
              jsonEncode({'projection_version': 0, 'products': const []}),
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
      final localDevice = await harness.db.query(
        'devices',
        columns: ['display_name'],
        where: 'device_id = ?',
        whereArgs: [harness.localDeviceId],
        limit: 1,
      );

      expect(peer?.baseUrl, baseUrl);
      expect(peer?.sharedSecret, _sharedSecret);
      expect(localDevice.single['display_name'], 'Cashier-1');
    });
  });

  test('unpaired cashier receives peer_unpaired on next sync', () async {
    final mainDb = await CoreDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
      singleInstance: false,
    );
    final cashierDb = await CoreDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
      singleInstance: false,
    );
    final mainRepository = await DekonRepository.open(database: mainDb);
    final cashierRepository = await DekonRepository.open(database: cashierDb);
    final server = LanSyncServer(
      store: mainRepository.createSyncStore(),
      now: () => _now,
    );
    final client = LanSyncClient(
      store: cashierRepository.createSyncStore(),
      client: _serverBackedClient(server),
      now: () => _now,
    );
    try {
      final pairing = server.createPairingPayload(baseUrl: 'http://main.local');
      final peer = await client.pairWithServer(pairing);
      final mainFiltersBefore = await mainRepository.cashierReportFilters();

      await server.unpairCashier(
        cashierRepository.createSyncStore().localDeviceId,
      );

      final mainFiltersAfter = await mainRepository.cashierReportFilters();

      expect(mainFiltersBefore, hasLength(1));
      expect(mainFiltersAfter, isEmpty);
      await expectLater(
        client.pingPeer(peer.deviceId),
        throwsA(isA<CashierUnpairedException>()),
      );
    } finally {
      client.close();
      await server.stop();
      await mainRepository.close();
      await cashierRepository.close();
    }
  });

  test('manual address pairing syncs when cashier clock is ahead', () async {
    final mainDb = await CoreDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
      singleInstance: false,
    );
    final cashierDb = await CoreDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
      singleInstance: false,
    );
    final mainRepository = await DekonRepository.open(database: mainDb);
    final cashierRepository = await DekonRepository.open(database: cashierDb);
    final server = LanSyncServer(
      store: mainRepository.createSyncStore(),
      now: () => _now,
    )..createPairingPayload(baseUrl: 'http://main.local:4321');
    final client = LanSyncClient(
      store: cashierRepository.createSyncStore(),
      client: _serverBackedClient(server),
      now: () => _now.add(const Duration(hours: 1)),
    );
    try {
      final product = await mainRepository.createProduct(
        name: 'Clock Skew Tea',
        barcode: 'CLOCK-SKEW-TEA',
      );

      await client.pairWithManualAddress(
        'main.local:4321',
        displayName: 'Clock Skew Register',
      );
      final syncedProduct = await cashierRepository.productById(
        product.productId,
      );

      expect(syncedProduct?.name, 'Clock Skew Tea');
    } finally {
      client.close();
      await server.stop();
      await mainRepository.close();
      await cashierRepository.close();
    }
  });

  test('pairing pushes cashier events and pulls main inventory', () async {
    final mainDb = await CoreDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
      singleInstance: false,
    );
    final cashierDb = await CoreDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
      singleInstance: false,
    );
    final mainRepository = await DekonRepository.open(database: mainDb);
    final cashierRepository = await DekonRepository.open(database: cashierDb);
    final server = LanSyncServer(
      store: mainRepository.createSyncStore(),
      now: () => _now,
    );
    final client = LanSyncClient(
      store: cashierRepository.createSyncStore(),
      client: _serverBackedClient(server),
      now: () => _now,
    );
    try {
      final product = await mainRepository.createProduct(
        name: 'Pairing Tea',
        barcode: 'PAIRING-TEA',
        salePriceMinor: 400,
        purchaseCostMinor: 150,
      );
      await mainRepository.recordPurchase([
        TransactionLineDraft(product: product, quantity: 5),
      ]);
      final cashierStore = cashierRepository.createSyncStore();
      final cashierSale = makeTestEvent(
        eventId: '019e9239-2222-7000-8000-000000600001',
        deviceId: cashierStore.localDeviceId,
        type: EventTypes.inventorySaleRecorded,
        entityId: 'cashier-sale-1',
        physicalTimeMillis: _now
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
        createdAt: _now.add(const Duration(minutes: 1)),
        payload: {
          'occurred_at': _now.add(const Duration(minutes: 1)).toIso8601String(),
          'total_minor': 800,
          'line_items': [
            {
              'product_id': product.productId,
              'quantity': 2,
              'unit_price_minor': 400,
            },
          ],
        },
      );
      expect((await cashierStore.importEvents([cashierSale])).accepted, [
        cashierSale.eventId,
      ]);

      final pairing = server.createPairingPayload(baseUrl: 'http://main.local');
      await client.pairWithServer(pairing, displayName: 'Front Register');
      final reportRange = _dayRange(_now);
      final mainProduct = await mainRepository.productById(product.productId);
      final cashierProduct = await cashierRepository.productById(
        product.productId,
      );
      final cashierReport = await mainRepository.reportSummary(
        range: reportRange,
        deviceId: cashierStore.localDeviceId,
      );
      final cashierFilters = await mainRepository.cashierReportFilters();

      expect(mainProduct?.quantity, 3);
      expect(cashierProduct?.quantity, 3);
      expect(cashierReport.salesMinor, 800);
      expect(cashierReport.purchasesMinor, 0);
      expect(
        cashierFilters
            .singleWhere(
              (cashier) => cashier.deviceId == cashierStore.localDeviceId,
            )
            .label,
        'Cashier-1',
      );
    } finally {
      client.close();
      await server.stop();
      await mainRepository.close();
      await cashierRepository.close();
    }
  });

  test('cashier sale command is idempotent and uses Main prices', () async {
    await _withHarness((harness) async {
      await harness.trustPeer();
      await harness.store.importEvents([
        _productCreated(
          20,
          deviceId: harness.localDeviceId,
          entityId: 'command-product-1',
          barcode: 'COMMAND-1',
        ),
        _purchaseRecorded(
          21,
          deviceId: harness.localDeviceId,
          productId: 'command-product-1',
          quantity: 5,
        ),
      ]);

      final command = CashierSaleCommand(
        commandId: _eventId(22),
        occurredAt: _now,
        lines: const [
          CashierSaleCommandLine(productId: 'command-product-1', quantity: 2),
        ],
      );
      final first = await harness.postCashierSale(command);
      final second = await harness.postCashierSale(command);
      final inventory = (await harness.db.query(
        'inventory_projection',
        where: 'product_id = ?',
        whereArgs: ['command-product-1'],
      )).single;
      final event = first['event'] as Map<String, Object?>;
      final payload = event['payload'] as Map<String, Object?>;
      final line = (payload['line_items'] as List).single as Map;

      expect(first['duplicate'], false);
      expect(second['duplicate'], true);
      expect(inventory['quantity'], 3);
      expect(payload['total_minor'], 200);
      expect(line['unit_price_minor'], 100);
      expect(await EventStore(harness.db).count(), 3);
    });
  });

  test('cashier sale command rejects insufficient Main stock', () async {
    await _withHarness((harness) async {
      await harness.trustPeer();
      await harness.store.importEvents([
        _productCreated(
          23,
          deviceId: harness.localDeviceId,
          entityId: 'short-product-1',
          barcode: 'SHORT-1',
        ),
        _purchaseRecorded(
          24,
          deviceId: harness.localDeviceId,
          productId: 'short-product-1',
          quantity: 1,
        ),
      ]);

      final response = await harness.postCashierSaleResponse(
        CashierSaleCommand(
          commandId: _eventId(25),
          occurredAt: _now,
          lines: const [
            CashierSaleCommandLine(productId: 'short-product-1', quantity: 2),
          ],
        ),
      );
      final body = await _json(response);
      final inventory = (await harness.db.query(
        'inventory_projection',
        where: 'product_id = ?',
        whereArgs: ['short-product-1'],
      )).single;

      expect(response.statusCode, HttpStatus.conflict);
      expect(body['error'], CashierSaleCommandException.insufficientStock);
      expect(body['product_ids'], ['short-product-1']);
      expect(inventory['quantity'], 1);
      expect(await EventStore(harness.db).count(), 2);
    });
  });

  test('locked cashier recordSale submits a retry-safe sale command', () async {
    final mainDb = await CoreDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
      singleInstance: false,
    );
    final cashierDb = await CoreDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
      singleInstance: false,
    );
    final mainRepository = await DekonRepository.open(database: mainDb);
    final cashierRepository = await DekonRepository.open(database: cashierDb);
    final server = mainRepository.createLanSyncServer();
    final client = cashierRepository.createLanSyncClient();
    try {
      final product = await mainRepository.createProduct(
        name: 'Command Tea',
        barcode: 'COMMAND-TEA',
        salePriceMinor: 400,
        purchaseCostMinor: 150,
      );
      await mainRepository.recordPurchase([
        TransactionLineDraft(product: product, quantity: 5),
      ]);
      await server.start(address: InternetAddress.loopbackIPv4);
      final pairing = SyncPairingPayload.fromQrJson(server.pairingQrData!);
      await client.pairWithServer(pairing);
      await cashierRepository.lockDeviceRole(DeviceRole.cashierDevice);
      final cashierProduct = await cashierRepository.productById(
        product.productId,
      );

      await cashierRepository.recordSale([
        TransactionLineDraft(product: cashierProduct!, quantity: 2),
      ]);
      final mainProduct = await mainRepository.productById(product.productId);
      final updatedCashierProduct = await cashierRepository.productById(
        product.productId,
      );
      final cashierHistory = await cashierRepository.transactionHistory(
        TransactionHistoryKind.sale,
        scope: ReportScope.localDevice,
      );

      expect(mainProduct?.quantity, 3);
      expect(updatedCashierProduct?.quantity, 3);
      expect(cashierHistory.single.totalMinor, 800);
    } finally {
      client.close();
      await server.stop();
      await mainRepository.close();
      await cashierRepository.close();
    }
  });

  test('waiting cashier pull receives new main transactions', () async {
    final mainDb = await CoreDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
      singleInstance: false,
    );
    final cashierDb = await CoreDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
      singleInstance: false,
    );
    final mainRepository = await DekonRepository.open(database: mainDb);
    final cashierRepository = await DekonRepository.open(database: cashierDb);
    final server = mainRepository.createLanSyncServer();
    final client = LanSyncClient(
      store: cashierRepository.createSyncStore(),
      client: _serverBackedClient(server),
    );
    try {
      final product = await mainRepository.createProduct(
        name: 'Waiting Tea',
        barcode: 'WAITING-TEA',
        salePriceMinor: 400,
        purchaseCostMinor: 150,
      );
      final pairing = server.createPairingPayload(baseUrl: 'http://main.local');
      final peer = await client.pairWithServer(
        pairing,
        displayName: 'Front Register',
      );

      final waitingPull = client.pullFromPeer(
        peer.deviceId,
        waitForEvents: true,
        waitTimeout: const Duration(seconds: 1),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await mainRepository.recordPurchase([
        TransactionLineDraft(product: product, quantity: 4),
      ]);
      final result = await waitingPull.timeout(const Duration(seconds: 2));
      final cashierProduct = await cashierRepository.productById(
        product.productId,
      );

      expect(result.accepted, isNotEmpty);
      expect(cashierProduct?.quantity, 4);
    } finally {
      client.close();
      await server.stop();
      await mainRepository.close();
      await cashierRepository.close();
    }
  });

  test('duplicate POST is idempotent and reports duplicate IDs', () async {
    await _withHarness((harness) async {
      await harness.trustPeer();
      final event = _saleRecorded(1);
      final first = await harness.postEvents([event]);
      final second = await harness.postEvents([event]);
      final state = await harness.store.state();

      expect(first['accepted'], [event.eventId]);
      expect(second['duplicate'], [event.eventId]);
      expect(state.eventCount, 1);
    });
  });

  test('GET events returns cashier-safe product and stock changes', () async {
    await _withHarness((harness) async {
      await harness.trustPeer();
      await EventStore(harness.db).append(
        _productCreated(1, deviceId: harness.localDeviceId, barcode: 'A-1'),
      );
      await EventStore(harness.db).append(
        _purchaseRecorded(
          2,
          deviceId: harness.localDeviceId,
          productId: 'product-1',
          quantity: 5,
        ),
      );

      final response = await harness.getEvents(limit: 10);
      final events = response['events'] as List;
      final product = events.cast<Map>().singleWhere(
        (event) => event['type'] == EventTypes.productCreated,
      );
      final productPayload = product['payload'] as Map;
      final stock = events.cast<Map>().singleWhere(
        (event) => event['type'] == EventTypes.inventoryAdjustmentRecorded,
      );
      final stockPayload = stock['payload'] as Map;
      final stockLine = (stockPayload['line_items'] as List).single as Map;

      expect(productPayload['sale_price_minor'], 100);
      expect(productPayload.containsKey('purchase_cost_minor'), false);
      expect(productPayload.containsKey('sku'), false);
      expect(stockPayload.containsKey('total_minor'), false);
      expect(stockLine['product_id'], 'product-1');
      expect(stockLine['quantity_delta'], 5);
      expect(stockLine.containsKey('unit_cost_minor'), false);
    });
  });

  test('inventory snapshot returns Cashier-safe product cache', () async {
    final db = await CoreDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
      singleInstance: false,
    );
    final repository = await DekonRepository.open(database: db);
    final store = repository.createSyncStore();
    final server = LanSyncServer(store: store, now: () => _now);
    try {
      await store.trustPeer(
        deviceId: _peerDeviceId,
        displayName: 'Peer',
        sharedSecret: _sharedSecret,
        baseUrl: 'http://localhost',
      );
      final product = await repository.createProduct(
        name: 'Snapshot Tea',
        barcode: 'SNAP-TEA',
        sku: 'PRIVATE-SKU',
        salePriceMinor: 700,
        purchaseCostMinor: 300,
      );
      await repository.recordPurchase([
        TransactionLineDraft(product: product, quantity: 6),
      ]);

      final uri = Uri.parse('http://localhost/cashier/inventory-snapshot');
      final response = await server.handler(
        Request('GET', uri, headers: _authHeaders('GET', uri, const [])),
      );
      final body = await response.readAsString();
      final decoded = jsonDecode(body) as Map<String, Object?>;
      final products = decoded['products'] as List;
      final snapshotProduct = products.single as Map<String, Object?>;

      expect(response.statusCode, 200);
      expect(decoded['projection_version'], 2);
      expect(snapshotProduct['product_id'], product.productId);
      expect(snapshotProduct['name'], 'Snapshot Tea');
      expect(snapshotProduct['barcode'], 'SNAP-TEA');
      expect(snapshotProduct['sale_price_minor'], 700);
      expect(snapshotProduct['stock_quantity'], 6);
      expect(body, isNot(contains('purchase_cost_minor')));
      expect(body, isNot(contains('unit_cost_minor')));
      expect(body, isNot(contains('PRIVATE-SKU')));
    } finally {
      await server.stop();
      await repository.close();
    }
  });

  test('client applies Cashier inventory snapshot transactionally', () async {
    final mainDb = await CoreDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
      singleInstance: false,
    );
    final cashierDb = await CoreDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
      singleInstance: false,
    );
    final mainRepository = await DekonRepository.open(database: mainDb);
    final cashierRepository = await DekonRepository.open(database: cashierDb);
    final server = LanSyncServer(
      store: mainRepository.createSyncStore(),
      now: () => _now,
    );
    final client = LanSyncClient(
      store: cashierRepository.createSyncStore(),
      client: _serverBackedClient(server),
      now: () => _now,
    );
    try {
      final product = await mainRepository.createProduct(
        name: 'Snapshot Beans',
        barcode: 'SNAP-BEANS',
        salePriceMinor: 900,
        purchaseCostMinor: 450,
      );
      await mainRepository.recordPurchase([
        TransactionLineDraft(product: product, quantity: 8),
      ]);
      final pairing = server.createPairingPayload(baseUrl: 'http://main.local');
      final peer = await client.pairWithServer(pairing);

      await mainRepository.updateProduct(
        ProductSummary(
          productId: product.productId,
          name: 'Renamed Beans',
          barcode: product.barcode,
          sku: product.sku,
          unit: product.unit,
          salePriceMinor: product.salePriceMinor,
          purchaseCostMinor: 600,
          active: product.active,
          quantity: product.quantity,
        ),
      );
      await client.fetchAndApplyCashierInventorySnapshot(peer.deviceId);
      final cashierProduct = await cashierRepository.productById(
        product.productId,
      );
      final lastApplied = await cashierRepository
          .createSyncStore()
          .lastAppliedCashierProjectionVersion();

      expect(cashierProduct?.name, 'Renamed Beans');
      expect(cashierProduct?.quantity, 8);
      expect(cashierProduct?.salePriceMinor, 900);
      expect(cashierProduct?.purchaseCostMinor, 0);
      expect(lastApplied, 3);
    } finally {
      client.close();
      await server.stop();
      await mainRepository.close();
      await cashierRepository.close();
    }
  });

  test('client applies projection updates and repairs version gaps', () async {
    final mainDb = await CoreDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
      singleInstance: false,
    );
    final cashierDb = await CoreDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
      singleInstance: false,
    );
    final mainRepository = await DekonRepository.open(database: mainDb);
    final cashierRepository = await DekonRepository.open(database: cashierDb);
    final server = LanSyncServer(
      store: mainRepository.createSyncStore(),
      now: () => _now,
    );
    final client = LanSyncClient(
      store: cashierRepository.createSyncStore(),
      client: _serverBackedClient(server),
      now: () => _now,
    );
    final updates = <Map<String, Object?>>[];
    final subscription = mainRepository.cashierProjectionUpdates.listen(
      updates.add,
    );
    try {
      final product = await mainRepository.createProduct(
        name: 'Projection Beans',
        barcode: 'PROJECTION-BEANS',
        salePriceMinor: 900,
        purchaseCostMinor: 450,
      );
      await mainRepository.recordPurchase([
        TransactionLineDraft(product: product, quantity: 8),
      ]);
      await _flushStream();
      updates.clear();
      final pairing = server.createPairingPayload(baseUrl: 'http://main.local');
      final peer = await client.pairWithServer(pairing);
      final initialLastApplied = await cashierRepository
          .createSyncStore()
          .lastAppliedCashierProjectionVersion();

      expect(initialLastApplied, 2);

      await mainRepository.updateProduct(
        _copyProduct(product, name: 'Renamed Projection Beans'),
      );
      await _flushStream();
      final renameUpdate = updates.single;
      final renameStatus = await client.applyCashierProjectionMessage(
        peer.deviceId,
        jsonEncode(renameUpdate),
      );
      final renamedCashierProduct = await cashierRepository.productById(
        product.productId,
      );

      expect(renameStatus, CashierProjectionApplyStatus.applied);
      expect(renamedCashierProduct?.name, 'Renamed Projection Beans');
      expect(renamedCashierProduct?.purchaseCostMinor, 0);

      final duplicateStatus = await client.applyCashierProjectionMessage(
        peer.deviceId,
        jsonEncode(renameUpdate),
      );
      final duplicateLastApplied = await cashierRepository
          .createSyncStore()
          .lastAppliedCashierProjectionVersion();

      expect(duplicateStatus, CashierProjectionApplyStatus.duplicate);
      expect(duplicateLastApplied, 3);

      updates.clear();
      final stockedProduct = await mainRepository.productById(
        product.productId,
      );
      await mainRepository.recordSale([
        TransactionLineDraft(product: stockedProduct!, quantity: 2),
      ]);
      await _flushStream();
      final saleStatus = await client.applyCashierProjectionMessage(
        peer.deviceId,
        jsonEncode(updates.single),
      );
      final soldCashierProduct = await cashierRepository.productById(
        product.productId,
      );

      expect(saleStatus, CashierProjectionApplyStatus.applied);
      expect(soldCashierProduct?.quantity, 6);

      updates.clear();
      final afterSale = await mainRepository.productById(product.productId);
      await mainRepository.updateProduct(
        _copyProduct(afterSale!, name: 'Gap Repaired Beans'),
      );
      await mainRepository.recordPurchase([
        TransactionLineDraft(product: afterSale, quantity: 1),
      ]);
      await _flushStream();
      expect(updates, hasLength(2));
      final gapStatus = await client.applyCashierProjectionMessage(
        peer.deviceId,
        jsonEncode(updates.last),
      );
      final gapRepairedProduct = await cashierRepository.productById(
        product.productId,
      );
      final gapRepairedVersion = await cashierRepository
          .createSyncStore()
          .lastAppliedCashierProjectionVersion();

      expect(gapStatus, CashierProjectionApplyStatus.gap);
      expect(gapRepairedProduct?.name, 'Gap Repaired Beans');
      expect(gapRepairedProduct?.quantity, 7);
      expect(gapRepairedVersion, 6);

      updates.clear();
      final afterRepair = await mainRepository.productById(product.productId);
      await mainRepository.updateProduct(
        _copyProduct(afterRepair!, name: 'Snapshot Required Beans'),
      );
      await _flushStream();
      final snapshotStatus = await client.applyCashierProjectionMessage(
        peer.deviceId,
        jsonEncode(
          serializeCashierSnapshotRequiredMessage(projectionVersion: 7),
        ),
      );
      final snapshotRepairedProduct = await cashierRepository.productById(
        product.productId,
      );
      final snapshotRepairedVersion = await cashierRepository
          .createSyncStore()
          .lastAppliedCashierProjectionVersion();

      expect(snapshotStatus, CashierProjectionApplyStatus.snapshotRequired);
      expect(snapshotRepairedProduct?.name, 'Snapshot Required Beans');
      expect(snapshotRepairedProduct?.quantity, 7);
      expect(snapshotRepairedVersion, 7);
    } finally {
      await subscription.cancel();
      client.close();
      await server.stop();
      await mainRepository.close();
      await cashierRepository.close();
    }
  });

  test(
    'projection WebSocket authenticates and streams sanitized updates',
    () async {
      final mainDb = await CoreDatabase.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
        singleInstance: false,
      );
      final cashierDb = await CoreDatabase.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
        singleInstance: false,
      );
      final mainRepository = await DekonRepository.open(database: mainDb);
      final cashierRepository = await DekonRepository.open(database: cashierDb);
      final server = mainRepository.createLanSyncServer();
      final client = cashierRepository.createLanSyncClient();
      try {
        await server.start(address: InternetAddress.loopbackIPv4);
        final wsUri = Uri.parse(
          server.serverUrl!,
        ).replace(scheme: 'ws', path: '/cashier/projection-stream');

        await expectLater(
          WebSocket.connect(wsUri.toString()),
          throwsA(isA<WebSocketException>()),
        );

        final pairing = SyncPairingPayload.fromQrJson(server.pairingQrData!);
        final peer = await client.pairWithServer(pairing);
        final socket = await client.openCashierProjectionStream(peer.deviceId);
        addTearDown(socket.close);
        final nextMessage = socket.first.timeout(const Duration(seconds: 2));

        await mainRepository.createProduct(
          name: 'Socket Tea',
          barcode: 'SOCKET-TEA',
          sku: 'PRIVATE-SOCKET-SKU',
          salePriceMinor: 1200,
          purchaseCostMinor: 500,
        );
        final message = await nextMessage;
        final decoded = jsonDecode(message as String) as Map<String, Object?>;
        final payload = decoded['payload'] as Map<String, Object?>;
        final product = payload['product'] as Map<String, Object?>;

        expect(decoded['type'], cashierProjectionProductUpsert);
        expect(product['name'], 'Socket Tea');
        expect(product['sale_price_minor'], 1200);
        expect(message, isNot(contains('purchase_cost_minor')));
        expect(message, isNot(contains('PRIVATE-SOCKET-SKU')));
      } finally {
        client.close();
        await server.stop();
        await mainRepository.close();
        await cashierRepository.close();
      }
    },
  );

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
      final event = _saleRecorded(
        3,
        schemaVersion: EventSchema.currentVersion + 1,
      );

      final response = await harness.postEvents([event]);
      final state = await harness.store.state();

      expect(response['unsupported'], [event.eventId]);
      expect(state.unsupportedEventCount, 1);
    });
  });

  test('cashier product mutations are rejected before projection', () async {
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
      final state = await harness.store.state();

      expect(response['accepted'], isEmpty);
      expect(
        response['rejected'],
        containsAll([
          {'event_id': fieldSet.eventId, 'reason': 'permission_denied'},
          {'event_id': created.eventId, 'reason': 'permission_denied'},
        ]),
      );
      expect(rows, isEmpty);
      expect(state.eventCount, 0);
    });
  });

  test('POST applies transactions in creation-time order', () async {
    await _withHarness((harness) async {
      await harness.trustPeer();
      final productId = 'ordered-product-1';
      final laterSale = _saleRecorded(
        6,
        eventId: _eventId(6),
        productId: productId,
        quantity: 1,
        physicalTimeMillis: 1000,
        createdAt: _now.add(const Duration(seconds: 1)),
      );
      final earlierSale = _saleRecorded(
        7,
        eventId: _eventId(7),
        productId: productId,
        quantity: 2,
        physicalTimeMillis: 2000,
        createdAt: _now,
      );

      final response = await harness.postEvents([laterSale, earlierSale]);
      final inventory = (await harness.db.query(
        'inventory_projection',
        where: 'product_id = ?',
        whereArgs: [productId],
      )).single;

      expect(response['accepted'], [earlierSale.eventId, laterSale.eventId]);
      expect(inventory['quantity'], -3);
    });
  });

  test('cashier cannot spoof another device ID in posted events', () async {
    await _withHarness((harness) async {
      await harness.trustPeer();
      final spoofed = _saleRecorded(8, deviceId: _secondPeerDeviceId);

      final response = await harness.postEvents([spoofed]);
      final state = await harness.store.state();

      expect(response['accepted'], isEmpty);
      expect(response['rejected'], [
        {'event_id': spoofed.eventId, 'reason': 'permission_denied'},
      ]);
      expect(state.eventCount, 0);
    });
  });
}

ReportDateRange _dayRange(DateTime dateTime) {
  final local = dateTime.toLocal();
  final start = DateTime(local.year, local.month, local.day);
  return ReportDateRange(
    startLocal: start,
    endLocalExclusive: start.add(const Duration(days: 1)),
  );
}

ProductSummary _copyProduct(
  ProductSummary product, {
  String? name,
  String? barcode,
  String? sku,
  String? unit,
  int? salePriceMinor,
  int? purchaseCostMinor,
  bool? active,
}) {
  return ProductSummary(
    productId: product.productId,
    name: name ?? product.name,
    barcode: barcode ?? product.barcode,
    sku: sku ?? product.sku,
    unit: unit ?? product.unit,
    salePriceMinor: salePriceMinor ?? product.salePriceMinor,
    purchaseCostMinor: purchaseCostMinor ?? product.purchaseCostMinor,
    active: active ?? product.active,
    quantity: product.quantity,
  );
}

Future<void> _flushStream() {
  return Future<void>.delayed(Duration.zero);
}

Future<void> _withHarness(Future<void> Function(_Harness harness) body) async {
  final db = await CoreDatabase.open(
    path: inMemoryDatabasePath,
    factory: databaseFactoryFfi,
    singleInstance: false,
  );
  final localDeviceId = await DeviceIdentityRepository(db).getOrCreate();
  final activityBus = SyncActivityBus();
  final store = SyncStore(
    database: db,
    localDeviceId: localDeviceId,
    activityBus: activityBus,
    now: () => _now,
  );
  final server = LanSyncServer(store: store, now: () => _now);
  final harness = _Harness(db, store, server, localDeviceId, activityBus);
  try {
    await body(harness);
  } finally {
    await server.stop();
    await activityBus.close();
    await db.close();
  }
}

class _Harness {
  const _Harness(
    this.db,
    this.store,
    this.server,
    this.localDeviceId,
    this.activityBus,
  );

  final Database db;
  final SyncStore store;
  final LanSyncServer server;
  final String localDeviceId;
  final SyncActivityBus activityBus;

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

  Future<Map<String, Object?>> postCashierSale(
    CashierSaleCommand command,
  ) async {
    final response = await postCashierSaleResponse(command);
    expect(response.statusCode, 200);
    return _json(response);
  }

  Future<Response> postCashierSaleResponse(CashierSaleCommand command) async {
    final body = jsonEncode(command.toJson());
    final uri = Uri.parse('http://localhost/cashier/sales');
    return server.handler(
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

MockClient _serverBackedClient(LanSyncServer server) {
  return MockClient((request) async {
    final response = await server.handler(
      Request(
        request.method,
        request.url,
        headers: request.headers,
        body: request.bodyBytes,
      ),
    );
    return http.Response(
      await response.readAsString(),
      response.statusCode,
      headers: response.headers,
    );
  });
}

Map<String, String> _authHeaders(String method, Uri uri, List<int> bodyBytes) {
  return SyncAuthenticator(now: () => _now).signHeaders(
    method: method,
    uri: uri,
    bodyBytes: bodyBytes,
    deviceId: _peerDeviceId,
    sharedSecret: _sharedSecret,
    timestamp: _now,
  );
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

EventEnvelope _purchaseRecorded(
  int index, {
  String? deviceId,
  String productId = 'product-1',
  double quantity = 1,
  int physicalTimeMillis = 1000,
  DateTime? createdAt,
}) {
  return makeTestEvent(
    eventId: _eventId(index),
    deviceId: deviceId ?? _peerDeviceId,
    type: EventTypes.inventoryPurchaseRecorded,
    entityId: 'purchase-$index',
    payload: {
      'occurred_at': (createdAt ?? _now).toIso8601String(),
      'total_minor': (quantity * 50).round(),
      'line_items': [
        {'product_id': productId, 'quantity': quantity, 'unit_cost_minor': 50},
      ],
    },
    physicalTimeMillis: physicalTimeMillis,
    createdAt: createdAt ?? _now,
  );
}

EventEnvelope _saleRecorded(
  int index, {
  String? eventId,
  String? deviceId,
  String productId = 'product-1',
  double quantity = 1,
  int physicalTimeMillis = 1000,
  int schemaVersion = EventSchema.currentVersion,
  DateTime? createdAt,
}) {
  return makeTestEvent(
    eventId: eventId ?? _eventId(index),
    deviceId: deviceId ?? _peerDeviceId,
    type: EventTypes.inventorySaleRecorded,
    entityId: 'sale-$index',
    schemaVersion: schemaVersion,
    payload: {
      'occurred_at': (createdAt ?? _now).toIso8601String(),
      'total_minor': (quantity * 100).round(),
      'line_items': [
        {
          'product_id': productId,
          'quantity': quantity,
          'unit_price_minor': 100,
        },
      ],
    },
    physicalTimeMillis: physicalTimeMillis,
    createdAt: createdAt ?? _now,
  );
}

String _eventId(int index) {
  return '019e9239-0000-7000-8000-${index.toString().padLeft(12, '0')}';
}

Future<Map<String, Object?>> _json(Response response) async {
  return jsonDecode(await response.readAsString()) as Map<String, Object?>;
}
