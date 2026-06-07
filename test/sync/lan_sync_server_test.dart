import 'dart:async';
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
      final rotatedPairing = SyncPairingPayload.fromQrJson(
        harness.server.pairingQrData!,
      );
      final sharedSecret = body['shared_secret'] as String;

      expect(response.statusCode, 200);
      expect(sharedSecret, isNot(pairing.pairingSecret));
      expect(body['assigned_display_name'], 'Cashier-1');
      expect(peer?.displayName, 'Cashier-1');
      expect(peer?.sharedSecret, sharedSecret);
      expect(rotatedPairing.pairingSecret, isNot(pairing.pairingSecret));
    });
  });

  test('pairing assigns stable cashier names and per-device secrets', () async {
    await _withHarness((harness) async {
      harness.server.createPairingPayload(baseUrl: 'http://localhost');
      Future<Map<String, Object?>> pair(String deviceId) async {
        final pairing = SyncPairingPayload.fromQrJson(
          harness.server.pairingQrData!,
        );
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
      expect(first['shared_secret'], isNot(second['shared_secret']));
    });
  });

  test('old pairing code cannot be reused after successful pairing', () async {
    await _withHarness((harness) async {
      final pairing = harness.server.createPairingPayload(
        baseUrl: 'http://localhost',
      );
      final first = await harness.server.handler(
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
      final second = await harness.server.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/pair'),
          body: jsonEncode({
            'device_id': _secondPeerDeviceId,
            'display_name': 'Second counter',
            'pairing_secret': pairing.pairingSecret,
          }),
        ),
      );
      final secondPeer = await harness.store.trustedPeer(_secondPeerDeviceId);

      expect(first.statusCode, 200);
      expect(second.statusCode, HttpStatus.unauthorized);
      expect(secondPeer, isNull);
    });
  });

  test('paired cashier authenticates with per-device shared secret', () async {
    await _withHarness((harness) async {
      final pairing = harness.server.createPairingPayload(
        baseUrl: 'http://localhost',
      );
      final pairResponse = await harness.server.handler(
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
      final body = await _json(pairResponse);
      final sharedSecret = body['shared_secret'] as String;
      final uri = Uri.parse('http://localhost/sync/state');
      Map<String, String> authHeaders(String secret) {
        return SyncAuthenticator(now: () => _now).signHeaders(
          method: 'GET',
          uri: uri,
          bodyBytes: const [],
          deviceId: _peerDeviceId,
          sharedSecret: secret,
          timestamp: _now,
        );
      }

      final accepted = await harness.server.handler(
        Request('GET', uri, headers: authHeaders(sharedSecret)),
      );
      final rejected = await harness.server.handler(
        Request('GET', uri, headers: authHeaders(pairing.pairingSecret)),
      );

      expect(pairResponse.statusCode, 200);
      expect(accepted.statusCode, 200);
      expect(rejected.statusCode, HttpStatus.unauthorized);
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
      final sharedSecret = body['shared_secret'] as String;

      expect(response.statusCode, 200);
      expect(sharedSecret, isNot(pairing.pairingSecret));
      expect(body['assigned_display_name'], 'Cashier-1');
      expect(peer?.sharedSecret, sharedSecret);
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

  test(
    'stopPairing prevents new pairing while keeping server active',
    () async {
      final db = await CoreDatabase.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
        singleInstance: false,
      );
      final repository = await DekonRepository.open(database: db);
      final discovery = _FakeSyncServiceDiscovery();
      final server = repository.createLanSyncServer(
        serviceDiscovery: discovery,
      );
      try {
        await server.start(address: InternetAddress.loopbackIPv4);
        final pairing = SyncPairingPayload.fromQrJson(server.pairingQrData!);
        final serverUrl = server.serverUrl;

        server.stopPairing();

        final response = await http.post(
          Uri.parse('$serverUrl/pair'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'device_id': _peerDeviceId,
            'display_name': 'Counter phone',
            'pairing_secret': pairing.pairingSecret,
          }),
        );

        expect(response.statusCode, HttpStatus.forbidden);
        expect(server.isRunning, true);
        expect(server.serverUrl, serverUrl);
        expect(server.pairingQrData, isNull);
        expect(
          server.discoveryAdvertisement.state,
          SyncDiscoveryAdvertisementState.advertising,
        );
        expect(discovery.unregisterCount, 0);
      } finally {
        await server.stop();
        await repository.close();
      }
    },
  );

  test('server uses the fixed sync port by default', () async {
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

      expect(Uri.parse(server.serverUrl!).port, syncDefaultLanPort);
    } finally {
      await server.stop();
      await repository.close();
    }
  });

  test(
    'server falls back to an ephemeral port when requested port is busy',
    () async {
      final busyServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
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
          port: busyServer.port,
          enablePairing: false,
        );

        final fallbackPort = Uri.parse(server.serverUrl!).port;
        expect(fallbackPort, isNot(busyServer.port));
        expect(fallbackPort, greaterThan(0));
      } finally {
        await server.stop();
        await repository.close();
        await busyServer.close(force: true);
      }
    },
  );

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
      expect(request.bodyContent, contains('"pairing_secret": "[redacted]"'));
      expect(request.bodyContent, isNot(contains(pairing.pairingSecret)));
      expect(reply.direction, SyncPeerMessageDirection.sent);
      expect(reply.statusCode, 200);
      expect(reply.summary, 'Pairing result');
      expect(reply.bodyContent, contains('"shared_secret": "[redacted]"'));
      expect(reply.bodyContent, isNot(contains(pairing.pairingSecret)));
    });
  });

  test(
    'existing trusted peer secret remains accepted for authentication',
    () async {
      await _withHarness((harness) async {
        await harness.trustPeer();
        final uri = Uri.parse('http://localhost/sync/state');

        final response = await harness.server.handler(
          Request('GET', uri, headers: _authHeaders('GET', uri, const [])),
        );
        final peer = await harness.store.trustedPeer(_peerDeviceId);

        expect(response.statusCode, 200);
        expect(peer?.lastAppliedCashierProjectionVersion, isNull);
      });
    },
  );

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

  test('main server advertises and unregisters discovery service', () async {
    await _withHarness((harness) async {
      final discovery = _FakeSyncServiceDiscovery();
      final server = LanSyncServer(
        store: harness.store,
        serviceDiscovery: discovery,
        now: () => _now,
      );
      try {
        await server.start(address: InternetAddress.loopbackIPv4);

        expect(discovery.registeredDeviceId, harness.localDeviceId);
        expect(discovery.registeredPort, greaterThan(0));
        expect(
          server.discoveryAdvertisement.state,
          SyncDiscoveryAdvertisementState.advertising,
        );
        expect(server.discoveryAdvertisement.port, discovery.registeredPort);

        await server.stop();

        expect(discovery.unregisterCount, 1);
        expect(
          server.discoveryAdvertisement.state,
          SyncDiscoveryAdvertisementState.inactive,
        );
      } finally {
        await server.stop();
      }
    });
  });

  test(
    'cashier refreshes stale main URL from authenticated discovery',
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
      final discovery = _FakeSyncServiceDiscovery();
      final server = mainRepository.createLanSyncServer(
        serviceDiscovery: discovery,
      );
      final client = cashierRepository.createLanSyncClient(
        serviceDiscovery: discovery,
      );
      try {
        await server.start(address: InternetAddress.loopbackIPv4);
        final pairing = SyncPairingPayload.fromQrJson(server.pairingQrData!);
        final peer = await client.pairWithServer(pairing);

        await cashierRepository.createSyncStore().updateTrustedPeerBaseUrl(
          deviceId: peer.deviceId,
          baseUrl: 'http://127.0.0.1:1',
        );

        await client.pingPeer(peer.deviceId);

        final refreshed = await cashierRepository.createSyncStore().trustedPeer(
          peer.deviceId,
        );
        expect(refreshed?.baseUrl, server.serverUrl);
        expect(discovery.discoverCount, greaterThanOrEqualTo(1));
      } finally {
        client.close();
        await server.stop();
        await mainRepository.close();
        await cashierRepository.close();
      }
    },
  );

  test(
    'cashier verifies discovered main URL when TXT identity is missing',
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
      final discovery = _FakeSyncServiceDiscovery();
      final server = mainRepository.createLanSyncServer(
        serviceDiscovery: discovery,
      );
      final client = cashierRepository.createLanSyncClient(
        serviceDiscovery: discovery,
      );
      try {
        await server.start(address: InternetAddress.loopbackIPv4);
        final pairing = SyncPairingPayload.fromQrJson(server.pairingQrData!);
        final peer = await client.pairWithServer(pairing);
        final serverUri = Uri.parse(server.serverUrl!);
        discovery.services
          ..clear()
          ..add(
            DiscoveredSyncService(
              serviceName: 'Dekon-without-txt',
              host: serverUri.host,
              port: serverUri.port,
              deviceId: '',
              protocolVersion: 0,
            ),
          );

        await cashierRepository.createSyncStore().updateTrustedPeerBaseUrl(
          deviceId: peer.deviceId,
          baseUrl: 'http://127.0.0.1:1',
        );

        await client.pingPeer(peer.deviceId);

        final refreshed = await cashierRepository.createSyncStore().trustedPeer(
          peer.deviceId,
        );
        expect(refreshed?.baseUrl, server.serverUrl);
      } finally {
        client.close();
        await server.stop();
        await mainRepository.close();
        await cashierRepository.close();
      }
    },
  );

  test(
    'cashier refreshes stale main URL before opening projection stream',
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
      final discovery = _FakeSyncServiceDiscovery();
      final server = mainRepository.createLanSyncServer(
        serviceDiscovery: discovery,
      );
      final client = cashierRepository.createLanSyncClient(
        serviceDiscovery: discovery,
      );
      WebSocket? socket;
      try {
        await server.start(address: InternetAddress.loopbackIPv4);
        final pairing = SyncPairingPayload.fromQrJson(server.pairingQrData!);
        final peer = await client.pairWithServer(pairing);
        await cashierRepository.createSyncStore().updateTrustedPeerBaseUrl(
          deviceId: peer.deviceId,
          baseUrl: 'http://127.0.0.1:1',
        );

        socket = await client.openCashierProjectionStream(peer.deviceId);

        final cashierDeviceId = cashierRepository
            .createSyncStore()
            .localDeviceId;
        final refreshed = await cashierRepository.createSyncStore().trustedPeer(
          peer.deviceId,
        );
        expect(server.isCashierConnected(cashierDeviceId), true);
        expect(refreshed?.baseUrl, server.serverUrl);
        expect(discovery.discoverCount, greaterThanOrEqualTo(1));
      } finally {
        await socket?.close();
        client.close();
        await server.stop();
        await mainRepository.close();
        await cashierRepository.close();
      }
    },
  );

  test('cashier probes fixed port subnet when mDNS finds nothing', () async {
    await _withHarness((harness) async {
      await harness.store.trustPeer(
        deviceId: _peerDeviceId,
        displayName: 'Main',
        sharedSecret: _sharedSecret,
        baseUrl: 'http://192.168.55.10:1234',
      );
      final discovery = _FakeSyncServiceDiscovery();
      final client = LanSyncClient(
        store: harness.store,
        serviceDiscovery: discovery,
        client: MockClient((request) async {
          if (request.url.host != '192.168.55.77' ||
              request.url.port != syncDefaultLanPort ||
              request.url.path != '/sync/state') {
            throw const SocketException('No sync server at this address.');
          }
          final nonce = request.url.queryParameters['nonce'];
          return http.Response(
            jsonEncode({
              'device_id': _peerDeviceId,
              'event_count': 0,
              'unsupported_event_count': 0,
              'trusted_peer_count': 1,
              if (nonce != null)
                'response_auth': {
                  'nonce': nonce,
                  'signature': SyncAuthenticator(now: () => _now)
                      .signStateResponse(
                        nonce: nonce,
                        deviceId: _peerDeviceId,
                        sharedSecret: _sharedSecret,
                      ),
                },
            }),
            200,
          );
        }),
      );
      try {
        await client.pingPeer(_peerDeviceId);

        final peer = await harness.store.trustedPeer(_peerDeviceId);
        expect(peer?.baseUrl, 'http://192.168.55.77:$syncDefaultLanPort');
        expect(discovery.discoverCount, 1);
      } finally {
        client.close();
      }
    });
  });

  test(
    'failed discovery attempts back off and throttle subnet scans',
    () async {
      await _withHarness((harness) async {
        await harness.store.trustPeer(
          deviceId: _peerDeviceId,
          displayName: 'Main',
          sharedSecret: _sharedSecret,
          baseUrl: 'http://192.168.55.10:1234',
        );
        final discovery = _FakeSyncServiceDiscovery();
        var now = _now;
        var probeCount = 0;
        final client = LanSyncClient(
          store: harness.store,
          serviceDiscovery: discovery,
          client: MockClient((_) async {
            probeCount += 1;
            throw const SocketException('No sync server at this address.');
          }),
          now: () => now,
        );
        try {
          final first = await client.refreshPeerBaseUrlFromDiscovery(
            _peerDeviceId,
            timeout: const Duration(milliseconds: 20),
          );
          final firstDiscoverCount = discovery.discoverCount;
          final firstProbeCount = probeCount;
          final second = await client.refreshPeerBaseUrlFromDiscovery(
            _peerDeviceId,
            timeout: const Duration(milliseconds: 20),
          );

          now = now.add(const Duration(seconds: 6));
          final third = await client.refreshPeerBaseUrlFromDiscovery(
            _peerDeviceId,
            timeout: const Duration(milliseconds: 20),
          );
          final thirdDiscoverCount = discovery.discoverCount;
          final thirdProbeCount = probeCount;

          now = now.add(const Duration(seconds: 6));
          final fourth = await client.refreshPeerBaseUrlFromDiscovery(
            _peerDeviceId,
            timeout: const Duration(milliseconds: 20),
          );

          expect(first, false);
          expect(second, false);
          expect(third, false);
          expect(fourth, false);
          expect(firstDiscoverCount, 1);
          expect(firstProbeCount, greaterThan(0));
          expect(discovery.discoverCount, thirdDiscoverCount);
          expect(probeCount, thirdProbeCount);
          expect(thirdDiscoverCount, 2);
          expect(thirdProbeCount, greaterThan(firstProbeCount));
        } finally {
          client.close();
        }
      });
    },
  );

  test('manual discovery scan bypasses automatic backoff', () async {
    await _withHarness((harness) async {
      await harness.store.trustPeer(
        deviceId: _peerDeviceId,
        displayName: 'Main',
        sharedSecret: _sharedSecret,
        baseUrl: 'http://192.168.55.10:1234',
      );
      final discovery = _FakeSyncServiceDiscovery();
      var probeCount = 0;
      final client = LanSyncClient(
        store: harness.store,
        serviceDiscovery: discovery,
        client: MockClient((_) async {
          probeCount += 1;
          throw const SocketException('No sync server at this address.');
        }),
      );
      try {
        await client.refreshPeerBaseUrlFromDiscovery(
          _peerDeviceId,
          timeout: const Duration(milliseconds: 20),
        );
        final automaticDiscoverCount = discovery.discoverCount;
        final automaticProbeCount = probeCount;

        final manual = await client.refreshPeerBaseUrlFromDiscovery(
          _peerDeviceId,
          timeout: const Duration(milliseconds: 20),
          forceScan: true,
        );

        expect(manual, false);
        expect(discovery.discoverCount, automaticDiscoverCount + 1);
        expect(probeCount, greaterThan(automaticProbeCount));
      } finally {
        client.close();
      }
    });
  });

  test(
    'discovery parser keeps host and port when TXT attributes are absent',
    () {
      final service = DiscoveredSyncService.fromPlatformMap({
        'serviceName': 'Dekon-main',
        'host': '192.168.1.55',
        'port': 41111,
      });

      expect(service, isNotNull);
      expect(service?.deviceId, '');
      expect(service?.protocolVersion, 0);
      expect(service?.baseUrl, 'http://192.168.1.55:41111');
    },
  );

  test('cashier rejects discovered URL without signed state proof', () async {
    await _withHarness((harness) async {
      await harness.store.trustPeer(
        deviceId: _peerDeviceId,
        displayName: 'Main',
        sharedSecret: _sharedSecret,
        baseUrl: 'http://old-main.local:1234',
      );
      final discovery = _FakeSyncServiceDiscovery(
        services: const [
          DiscoveredSyncService(
            serviceName: 'Spoof',
            host: 'spoof.local',
            port: 7777,
            deviceId: _peerDeviceId,
            protocolVersion: syncProtocolVersion,
          ),
        ],
      );
      final client = LanSyncClient(
        store: harness.store,
        serviceDiscovery: discovery,
        client: MockClient((request) async {
          if (request.url.host == 'old-main.local') {
            throw const SocketException('stale address');
          }
          return http.Response(
            jsonEncode({
              'device_id': _peerDeviceId,
              'event_count': 0,
              'unsupported_event_count': 0,
              'trusted_peer_count': 1,
            }),
            200,
          );
        }),
      );
      try {
        await expectLater(
          client.pingPeer(_peerDeviceId),
          throwsA(isA<SocketException>()),
        );
        final peer = await harness.store.trustedPeer(_peerDeviceId);

        expect(peer?.baseUrl, 'http://old-main.local:1234');
        expect(discovery.discoverCount, 1);
      } finally {
        client.close();
      }
    });
  });

  test(
    'cashier keeps original connection failure when discovery fails',
    () async {
      await _withHarness((harness) async {
        await harness.store.trustPeer(
          deviceId: _peerDeviceId,
          displayName: 'Main',
          sharedSecret: _sharedSecret,
          baseUrl: 'http://old-main.local:1234',
        );
        final discovery = _FakeSyncServiceDiscovery(
          discoverError: StateError('nsd failed'),
        );
        final client = LanSyncClient(
          store: harness.store,
          serviceDiscovery: discovery,
          client: MockClient((request) async {
            throw const SocketException('stale address');
          }),
        );
        try {
          await expectLater(
            client.pingPeer(_peerDeviceId),
            throwsA(isA<SocketException>()),
          );
          expect(discovery.discoverCount, 1);
        } finally {
          client.close();
        }
      });
    },
  );

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

  test('pairing pulls inventory and sale commands update Main', () async {
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

      final pairing = server.createPairingPayload(baseUrl: 'http://main.local');
      final peer = await client.pairWithServer(
        pairing,
        displayName: 'Front Register',
      );
      await cashierStore.enqueueCashierSaleCommand(
        command: CashierSaleCommand(
          commandId: '019e9239-2222-7000-8000-000000600001',
          occurredAt: _now.add(const Duration(minutes: 1)),
          lines: [
            CashierSaleCommandLine(productId: product.productId, quantity: 2),
          ],
        ),
        lines: [
          CashierSaleOutboxLine(
            productId: product.productId,
            productName: 'Pairing Tea',
            quantity: 2,
            unitPriceMinor: 400,
            lineTotalMinor: 800,
          ),
        ],
      );
      await client.drainCashierSaleOutbox(peer.deviceId);
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
      final updates = <Map<String, Object?>>[];
      final subscription = harness.activityBus.cashierProjectionUpdates.listen(
        updates.add,
      );
      addTearDown(subscription.cancel);
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
      await _flushStream();
      final inventory = (await harness.db.query(
        'inventory_projection',
        where: 'product_id = ?',
        whereArgs: ['command-product-1'],
      )).single;
      final event = first['event'] as Map<String, Object?>;
      final payload = event['payload'] as Map<String, Object?>;
      final line = (payload['line_items'] as List).single as Map;
      final projectionVersion = await harness.store
          .cashierInventoryProjectionVersion();

      expect(first['duplicate'], false);
      expect(second['duplicate'], true);
      expect(inventory['quantity'], 3);
      expect(projectionVersion, 1);
      expect(updates, hasLength(1));
      expect(payload['total_minor'], 200);
      expect(line['unit_price_minor'], 100);
      expect(line['cost_total_minor'], 100);
      expect(line['cost_allocations'], isNotEmpty);
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

  test(
    'offline locked cashier sale is queued and reserves local stock',
    () async {
      final db = await CoreDatabase.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
        singleInstance: false,
      );
      final repository = await DekonRepository.open(database: db);
      try {
        final product = await repository.createProduct(
          name: 'Offline Tea',
          barcode: 'OFFLINE-TEA',
          salePriceMinor: 400,
          purchaseCostMinor: 150,
        );
        await repository.recordPurchase([
          TransactionLineDraft(product: product, quantity: 5),
        ]);
        await repository.lockDeviceRole(DeviceRole.cashierDevice);

        final result = await repository.recordSale([
          TransactionLineDraft(product: product, quantity: 2),
        ]);
        final updatedProduct = await repository.productById(product.productId);
        final summary = await repository.cashierSaleOutboxSummary();
        final approvedHistory = await repository.transactionHistory(
          TransactionHistoryKind.sale,
        );
        final cashierLocalHistory = await repository.transactionHistory(
          TransactionHistoryKind.sale,
          includePendingCashierSales: true,
        );

        expect(result.status, SaleRecordStatus.queued);
        expect(summary.queuedCount, 1);
        expect(summary.conflictCount, 0);
        expect(updatedProduct?.quantity, 3);
        expect(approvedHistory, isEmpty);
        expect(cashierLocalHistory.single.totalMinor, 800);
        expect(cashierLocalHistory.single.pendingMainApproval, isTrue);
      } finally {
        await repository.close();
      }
    },
  );

  test('cashier sale outbox drains queued commands to main', () async {
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
        name: 'Outbox Tea',
        barcode: 'OUTBOX-TEA',
        salePriceMinor: 400,
        purchaseCostMinor: 150,
      );
      await mainRepository.recordPurchase([
        TransactionLineDraft(product: product, quantity: 5),
      ]);
      final pairing = server.createPairingPayload(baseUrl: 'http://main.local');
      final peer = await client.pairWithServer(pairing);
      final store = cashierRepository.createSyncStore();
      await store.enqueueCashierSaleCommand(
        command: CashierSaleCommand(
          commandId: _eventId(30),
          occurredAt: _now,
          lines: [
            CashierSaleCommandLine(productId: product.productId, quantity: 2),
          ],
        ),
        lines: [
          CashierSaleOutboxLine(
            productId: product.productId,
            productName: 'Outbox Tea',
            quantity: 2,
            unitPriceMinor: 400,
            lineTotalMinor: 800,
          ),
        ],
      );

      await client.drainCashierSaleOutbox(peer.deviceId);
      final mainProduct = await mainRepository.productById(product.productId);
      final cashierProduct = await cashierRepository.productById(
        product.productId,
      );
      final counts = await store.cashierSaleOutboxCounts();

      expect(mainProduct?.quantity, 3);
      expect(cashierProduct?.quantity, 3);
      expect(counts[CashierSaleCommandOutboxStatus.accepted], 1);
      expect(await store.hasCashierSaleOutboxConflict(), false);

      await client.syncWithPeer(peer.deviceId);

      final messages = cashierRepository.recentSyncPeerMessages();
      expect(
        messages.where(
          (message) =>
              message.direction == SyncPeerMessageDirection.received &&
              (message.bodyContent ?? '').contains('permission_denied'),
        ),
        isEmpty,
      );
    } finally {
      client.close();
      await server.stop();
      await mainRepository.close();
      await cashierRepository.close();
    }
  });

  test('cashier sale conflict pauses later outbox commands', () async {
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
        name: 'Conflict Tea',
        barcode: 'CONFLICT-TEA',
        salePriceMinor: 400,
        purchaseCostMinor: 150,
      );
      await mainRepository.recordPurchase([
        TransactionLineDraft(product: product, quantity: 2),
      ]);
      final pairing = server.createPairingPayload(baseUrl: 'http://main.local');
      final peer = await client.pairWithServer(pairing);
      await mainRepository.recordSale([
        TransactionLineDraft(product: product, quantity: 2),
      ]);
      final store = cashierRepository.createSyncStore();
      await store.enqueueCashierSaleCommand(
        command: CashierSaleCommand(
          commandId: _eventId(31),
          occurredAt: _now,
          lines: [
            CashierSaleCommandLine(productId: product.productId, quantity: 1),
          ],
        ),
        lines: [
          CashierSaleOutboxLine(
            productId: product.productId,
            productName: 'Conflict Tea',
            quantity: 1,
            unitPriceMinor: 400,
            lineTotalMinor: 400,
          ),
        ],
      );
      await store.enqueueCashierSaleCommand(
        command: CashierSaleCommand(
          commandId: _eventId(32),
          occurredAt: _now,
          lines: [
            CashierSaleCommandLine(productId: product.productId, quantity: 1),
          ],
        ),
        lines: [
          CashierSaleOutboxLine(
            productId: product.productId,
            productName: 'Conflict Tea',
            quantity: 1,
            unitPriceMinor: 400,
            lineTotalMinor: 400,
          ),
        ],
      );

      await client.drainCashierSaleOutbox(peer.deviceId);
      final counts = await store.cashierSaleOutboxCounts();
      final mainHistory = await mainRepository.transactionHistory(
        TransactionHistoryKind.sale,
      );

      expect(counts[CashierSaleCommandOutboxStatus.conflict], 1);
      expect(counts[CashierSaleCommandOutboxStatus.queued], 1);
      expect(counts[CashierSaleCommandOutboxStatus.accepted], isNull);
      expect(mainHistory, hasLength(1));

      await store.voidOldestConflictedCashierSaleCommand();
      final resolvedCounts = await store.cashierSaleOutboxCounts();

      expect(resolvedCounts[CashierSaleCommandOutboxStatus.voided], 1);
      expect(resolvedCounts[CashierSaleCommandOutboxStatus.conflict], isNull);
      expect(resolvedCounts[CashierSaleCommandOutboxStatus.queued], 1);
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

  test('cashier POST events sale is rejected without stock mutation', () async {
    await _withHarness((harness) async {
      await harness.trustPeer();
      const productId = 'legacy-sale-product-1';
      await harness.store.importEvents([
        _productCreated(
          40,
          deviceId: harness.localDeviceId,
          entityId: productId,
          barcode: 'LEGACY-SALE-1',
        ),
        _purchaseRecorded(
          41,
          deviceId: harness.localDeviceId,
          productId: productId,
          quantity: 5,
        ),
      ]);
      final projectionVersionBefore = await harness.store
          .cashierInventoryProjectionVersion();
      final updates = <Map<String, Object?>>[];
      final subscription = harness.activityBus.cashierProjectionUpdates.listen(
        updates.add,
      );
      addTearDown(subscription.cancel);

      final event = _saleRecorded(42, productId: productId, quantity: 2);
      final response = await harness.postEvents([event]);
      await _flushStream();
      final state = await harness.store.state();
      final projectionVersionAfter = await harness.store
          .cashierInventoryProjectionVersion();
      final inventory = (await harness.db.query(
        'inventory_projection',
        where: 'product_id = ?',
        whereArgs: [productId],
      )).single;

      expect(response['accepted'], isEmpty);
      expect(response['duplicate'], isEmpty);
      expect(response['rejected'], [
        {'event_id': event.eventId, 'reason': 'permission_denied'},
      ]);
      expect(inventory['quantity'], 5);
      expect(projectionVersionAfter, projectionVersionBefore);
      expect(updates, isEmpty);
      expect(state.eventCount, 2);
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

  test('client serializes concurrent projection messages in order', () async {
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
        name: 'Queued Beans',
        barcode: 'QUEUED-BEANS',
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

      await mainRepository.updateProduct(
        _copyProduct(product, name: 'Queued Beans Renamed'),
      );
      await mainRepository.recordPurchase([
        TransactionLineDraft(product: product, quantity: 1),
      ]);
      await _flushStream();

      final statuses = await Future.wait([
        client.applyCashierProjectionMessage(
          peer.deviceId,
          jsonEncode(updates[0]),
        ),
        client.applyCashierProjectionMessage(
          peer.deviceId,
          jsonEncode(updates[1]),
        ),
      ]);
      final cashierProduct = await cashierRepository.productById(
        product.productId,
      );
      final lastApplied = await cashierRepository
          .createSyncStore()
          .lastAppliedCashierProjectionVersion();

      expect(statuses, [
        CashierProjectionApplyStatus.applied,
        CashierProjectionApplyStatus.applied,
      ]);
      expect(cashierProduct?.name, 'Queued Beans Renamed');
      expect(cashierProduct?.quantity, 9);
      expect(lastApplied, 4);
    } finally {
      await subscription.cancel();
      client.close();
      await server.stop();
      await mainRepository.close();
      await cashierRepository.close();
    }
  });

  test(
    'client coalesces snapshot repairs and drops older queued messages',
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
      final server = LanSyncServer(
        store: mainRepository.createSyncStore(),
        now: () => _now,
      );
      var snapshotFetchCount = 0;
      final client = LanSyncClient(
        store: cashierRepository.createSyncStore(),
        client: _serverBackedClient(
          server,
          onRequest: (request) {
            if (request.url.path == '/cashier/inventory-snapshot') {
              snapshotFetchCount += 1;
            }
          },
        ),
        now: () => _now,
      );
      final updates = <Map<String, Object?>>[];
      final subscription = mainRepository.cashierProjectionUpdates.listen(
        updates.add,
      );
      try {
        final product = await mainRepository.createProduct(
          name: 'Repair Beans',
          barcode: 'REPAIR-BEANS',
          salePriceMinor: 900,
          purchaseCostMinor: 450,
        );
        await mainRepository.recordPurchase([
          TransactionLineDraft(product: product, quantity: 8),
        ]);
        await _flushStream();
        updates.clear();
        final pairing = server.createPairingPayload(
          baseUrl: 'http://main.local',
        );
        final peer = await client.pairWithServer(pairing);
        snapshotFetchCount = 0;

        await mainRepository.updateProduct(
          _copyProduct(product, name: 'Repair Beans Renamed'),
        );
        await mainRepository.recordPurchase([
          TransactionLineDraft(product: product, quantity: 1),
        ]);
        await _flushStream();

        final gapStatuses = await Future.wait([
          client.applyCashierProjectionMessage(
            peer.deviceId,
            jsonEncode(updates[1]),
          ),
          client.applyCashierProjectionMessage(
            peer.deviceId,
            jsonEncode(updates[0]),
          ),
          client.applyCashierProjectionMessage(
            peer.deviceId,
            jsonEncode(updates[1]),
          ),
        ]);
        final gapRepairedProduct = await cashierRepository.productById(
          product.productId,
        );
        final gapRepairedVersion = await cashierRepository
            .createSyncStore()
            .lastAppliedCashierProjectionVersion();

        expect(gapStatuses, [
          CashierProjectionApplyStatus.gap,
          CashierProjectionApplyStatus.duplicate,
          CashierProjectionApplyStatus.duplicate,
        ]);
        expect(snapshotFetchCount, 1);
        expect(gapRepairedProduct?.name, 'Repair Beans Renamed');
        expect(gapRepairedProduct?.quantity, 9);
        expect(gapRepairedVersion, 4);

        updates.clear();
        snapshotFetchCount = 0;
        final afterRepair = await mainRepository.productById(product.productId);
        await mainRepository.updateProduct(
          _copyProduct(afterRepair!, name: 'Snapshot Coalesced Beans'),
        );
        await _flushStream();
        final snapshotProjectionVersion =
            updates.single['projection_version'] as int;
        final snapshotMessage = jsonEncode(
          serializeCashierSnapshotRequiredMessage(
            projectionVersion: snapshotProjectionVersion,
          ),
        );

        final snapshotStatuses = await Future.wait([
          client.applyCashierProjectionMessage(peer.deviceId, snapshotMessage),
          client.applyCashierProjectionMessage(peer.deviceId, snapshotMessage),
        ]);
        final snapshotProduct = await cashierRepository.productById(
          product.productId,
        );
        final snapshotVersion = await cashierRepository
            .createSyncStore()
            .lastAppliedCashierProjectionVersion();

        expect(snapshotStatuses, [
          CashierProjectionApplyStatus.snapshotRequired,
          CashierProjectionApplyStatus.duplicate,
        ]);
        expect(snapshotFetchCount, 1);
        expect(snapshotProduct?.name, 'Snapshot Coalesced Beans');
        expect(snapshotVersion, snapshotProjectionVersion);
      } finally {
        await subscription.cancel();
        client.close();
        await server.stop();
        await mainRepository.close();
        await cashierRepository.close();
      }
    },
  );

  test('client bounds the projection message queue', () async {
    final db = await CoreDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
      singleInstance: false,
    );
    final repository = await DekonRepository.open(database: db);
    final store = repository.createSyncStore();
    final snapshotCompleter = Completer<http.Response>();
    final client = LanSyncClient(
      store: store,
      client: MockClient((request) {
        if (request.url.path == '/cashier/inventory-snapshot') {
          return snapshotCompleter.future;
        }
        return Future.value(http.Response('not found', 404));
      }),
      now: () => _now,
    );
    try {
      await store.trustPeer(
        deviceId: _peerDeviceId,
        displayName: 'Main',
        sharedSecret: _sharedSecret,
        baseUrl: 'http://main.local',
      );
      final message = jsonEncode(
        serializeCashierSnapshotRequiredMessage(projectionVersion: 1),
      );
      final queued = [
        for (var i = 0; i < 32; i++)
          client.applyCashierProjectionMessage(_peerDeviceId, message),
      ];

      await expectLater(
        client.applyCashierProjectionMessage(_peerDeviceId, message),
        throwsA(isA<SyncClientException>()),
      );
      snapshotCompleter.complete(
        http.Response(
          jsonEncode({'projection_version': 1, 'products': const []}),
          200,
        ),
      );
      final statuses = await Future.wait(queued);

      expect(statuses.first, CashierProjectionApplyStatus.snapshotRequired);
      expect(
        statuses.skip(1),
        everyElement(CashierProjectionApplyStatus.duplicate),
      );
    } finally {
      client.close();
      await repository.close();
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
        final cashierDeviceId = cashierRepository
            .createSyncStore()
            .localDeviceId;
        expect(server.isCashierConnected(cashierDeviceId), false);
        final socket = await client.openCashierProjectionStream(peer.deviceId);
        addTearDown(socket.close);
        expect(socket.pingInterval, const Duration(seconds: 15));
        expect(server.isCashierConnected(cashierDeviceId), true);
        server.stopPairing();
        expect(server.isRunning, true);
        expect(server.pairingQrData, isNull);
        expect(server.isCashierConnected(cashierDeviceId), true);
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

  test(
    'cashier reports applied projection version and main distinguishes lag',
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
      WebSocket? socket;
      try {
        final product = await mainRepository.createProduct(
          name: 'Ack Tea',
          barcode: 'ACK-TEA',
          salePriceMinor: 1200,
          purchaseCostMinor: 500,
        );
        await mainRepository.recordPurchase([
          TransactionLineDraft(product: product, quantity: 4),
        ]);
        final mainVersion = await mainRepository
            .createSyncStore()
            .cashierInventoryProjectionVersion();
        await server.start(address: InternetAddress.loopbackIPv4);
        final pairing = SyncPairingPayload.fromQrJson(server.pairingQrData!);
        final peer = await client.pairWithServer(pairing);
        await client.pingPeer(peer.deviceId);

        final currentFilter =
            (await mainRepository.cashierReportFilters()).single;
        final cashierDeviceId = cashierRepository
            .createSyncStore()
            .localDeviceId;
        socket = await client.openCashierProjectionStream(peer.deviceId);
        expect(server.isCashierConnected(cashierDeviceId), true);

        await mainRepository.updateProduct(
          _copyProduct(product, name: 'Lagging Ack Tea'),
        );
        final laggingFilter =
            (await mainRepository.cashierReportFilters()).single;

        await client.fetchAndApplyCashierInventorySnapshot(peer.deviceId);
        await client.pingPeer(peer.deviceId);
        final repairedFilter =
            (await mainRepository.cashierReportFilters()).single;

        expect(currentFilter.lastAppliedProjectionVersion, mainVersion);
        expect(currentFilter.currentProjectionVersion, mainVersion);
        expect(currentFilter.projectionLagging, false);
        expect(laggingFilter.lastAppliedProjectionVersion, mainVersion);
        expect(laggingFilter.currentProjectionVersion, mainVersion + 1);
        expect(laggingFilter.projectionLagging, true);
        expect(repairedFilter.lastAppliedProjectionVersion, mainVersion + 1);
        expect(repairedFilter.currentProjectionVersion, mainVersion + 1);
        expect(repairedFilter.projectionLagging, false);
      } finally {
        await socket?.close();
        client.close();
        await server.stop();
        await mainRepository.close();
        await cashierRepository.close();
      }
    },
  );

  test(
    'restore broadcasts snapshot repair and connected cashier refreshes',
    () async {
      final sourceDb = await CoreDatabase.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
        singleInstance: false,
      );
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
      final sourceRepository = await DekonRepository.open(database: sourceDb);
      final mainRepository = await DekonRepository.open(database: mainDb);
      final cashierRepository = await DekonRepository.open(database: cashierDb);
      final directory = await Directory.systemTemp.createTemp('dekon_restore_');
      final server = mainRepository.createLanSyncServer();
      final client = cashierRepository.createLanSyncClient();
      WebSocket? socket;
      try {
        final restoredSourceProduct = await sourceRepository.createProduct(
          name: 'Restored Socket Tea',
          barcode: 'RESTORE-SOCKET-TEA',
          sku: 'PRIVATE-RESTORE-SKU',
          salePriceMinor: 1300,
          purchaseCostMinor: 650,
        );
        await sourceRepository.recordPurchase([
          TransactionLineDraft(product: restoredSourceProduct, quantity: 7),
        ]);
        final export = await sourceRepository
            .createBackupService()
            .exportToDirectory(directory.path);
        final backupContents = await File(export.path).readAsString();

        await mainRepository.createProduct(
          name: 'Existing Main Product',
          barcode: 'EXISTING-MAIN',
          salePriceMinor: 900,
          purchaseCostMinor: 400,
        );
        final beforeVersion = await mainRepository
            .createSyncStore()
            .cashierInventoryProjectionVersion();
        await server.start(address: InternetAddress.loopbackIPv4);
        final pairing = SyncPairingPayload.fromQrJson(server.pairingQrData!);
        final peer = await client.pairWithServer(pairing);
        socket = await client.openCashierProjectionStream(peer.deviceId);
        final nextMessage = socket.first.timeout(const Duration(seconds: 2));

        final result = await mainRepository.restoreBackup(backupContents);
        final message = await nextMessage as String;
        final decoded = jsonDecode(message) as Map<String, Object?>;
        final afterVersion = await mainRepository
            .createSyncStore()
            .cashierInventoryProjectionVersion();
        final status = await client.applyCashierProjectionMessage(
          peer.deviceId,
          message,
        );
        final cashierProduct = await cashierRepository.productById(
          restoredSourceProduct.productId,
        );
        final cashierVersion = await cashierRepository
            .createSyncStore()
            .lastAppliedCashierProjectionVersion();

        expect(result.acceptedCount, 2);
        expect(afterVersion, beforeVersion + 1);
        expect(decoded['type'], cashierProjectionSnapshotRequired);
        expect(decoded['projection_version'], afterVersion);
        expect(message, isNot(contains('purchase_cost_minor')));
        expect(message, isNot(contains('PRIVATE-RESTORE-SKU')));
        expect(status, CashierProjectionApplyStatus.snapshotRequired);
        expect(cashierVersion, afterVersion);
        expect(cashierProduct?.name, 'Restored Socket Tea');
        expect(cashierProduct?.quantity, 7);
        expect(cashierProduct?.salePriceMinor, 1300);
        expect(cashierProduct?.purchaseCostMinor, 0);
        expect(cashierProduct?.sku, isNull);
      } finally {
        await socket?.close();
        client.close();
        await server.stop();
        await directory.delete(recursive: true);
        await sourceRepository.close();
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

  test('future schema sale events are rejected on legacy POST', () async {
    await _withHarness((harness) async {
      await harness.trustPeer();
      final event = _saleRecorded(
        3,
        schemaVersion: EventSchema.currentVersion + 1,
      );

      final response = await harness.postEvents([event]);
      final state = await harness.store.state();

      expect(response['accepted'], isEmpty);
      expect(response['unsupported'], isEmpty);
      expect(response['rejected'], [
        {'event_id': event.eventId, 'reason': 'permission_denied'},
      ]);
      expect(state.eventCount, 0);
      expect(state.unsupportedEventCount, 0);
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

  test(
    'cashier POST events sale batch is rejected before projection',
    () async {
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
        final inventory = await harness.db.query(
          'inventory_projection',
          where: 'product_id = ?',
          whereArgs: [productId],
        );
        final state = await harness.store.state();

        expect(response['accepted'], isEmpty);
        expect(
          response['rejected'],
          containsAll([
            {'event_id': earlierSale.eventId, 'reason': 'permission_denied'},
            {'event_id': laterSale.eventId, 'reason': 'permission_denied'},
          ]),
        );
        expect(inventory, isEmpty);
        expect(state.eventCount, 0);
      });
    },
  );

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

class _FakeSyncServiceDiscovery extends SyncServiceDiscovery {
  _FakeSyncServiceDiscovery({
    List<DiscoveredSyncService> services = const [],
    this.discoverError,
  }) : services = List.of(services);

  final List<DiscoveredSyncService> services;
  final Object? discoverError;
  String? registeredDeviceId;
  int? registeredPort;
  var unregisterCount = 0;
  var discoverCount = 0;

  @override
  Future<SyncDiscoveryAdvertisement> registerMainService({
    required String deviceId,
    required int port,
  }) async {
    registeredDeviceId = deviceId;
    registeredPort = port;
    services
      ..clear()
      ..add(
        DiscoveredSyncService(
          serviceName: 'Dekon-$deviceId',
          host: '127.0.0.1',
          port: port,
          deviceId: deviceId,
          protocolVersion: syncProtocolVersion,
        ),
      );
    return SyncDiscoveryAdvertisement.advertising(
      deviceId: deviceId,
      port: port,
    );
  }

  @override
  Future<void> unregisterMainService() async {
    unregisterCount += 1;
  }

  @override
  Future<List<DiscoveredSyncService>> discoverMainServices({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    discoverCount += 1;
    final error = discoverError;
    if (error != null) throw error;
    return List.of(services);
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

MockClient _serverBackedClient(
  LanSyncServer server, {
  void Function(http.Request request)? onRequest,
}) {
  return MockClient((request) async {
    onRequest?.call(request);
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
