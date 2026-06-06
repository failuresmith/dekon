import 'package:flutter/services.dart';

import 'sync_protocol.dart';

abstract class SyncServiceDiscovery {
  const SyncServiceDiscovery();

  Future<SyncDiscoveryAdvertisement> registerMainService({
    required String deviceId,
    required int port,
  });

  Future<void> unregisterMainService();

  Future<List<DiscoveredSyncService>> discoverMainServices({
    Duration timeout = const Duration(seconds: 3),
  });
}

class NoopSyncServiceDiscovery extends SyncServiceDiscovery {
  const NoopSyncServiceDiscovery();

  @override
  Future<SyncDiscoveryAdvertisement> registerMainService({
    required String deviceId,
    required int port,
  }) async {
    return const SyncDiscoveryAdvertisement.unsupported();
  }

  @override
  Future<void> unregisterMainService() async {}

  @override
  Future<List<DiscoveredSyncService>> discoverMainServices({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    return const [];
  }
}

class AndroidSyncServiceDiscovery extends SyncServiceDiscovery {
  const AndroidSyncServiceDiscovery({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('xyz.infinica.dekon/sync_discovery');

  final MethodChannel _channel;

  @override
  Future<SyncDiscoveryAdvertisement> registerMainService({
    required String deviceId,
    required int port,
  }) async {
    try {
      await _channel.invokeMethod<void>('registerMainService', {
        'deviceId': deviceId,
        'port': port,
        'protocolVersion': syncProtocolVersion,
      });
      return SyncDiscoveryAdvertisement.advertising(
        deviceId: deviceId,
        port: port,
      );
    } on MissingPluginException {
      return const SyncDiscoveryAdvertisement.unsupported();
    } on PlatformException catch (error) {
      return SyncDiscoveryAdvertisement.failed(failureCode: error.code);
    } on Object {
      return const SyncDiscoveryAdvertisement.failed();
    }
  }

  @override
  Future<void> unregisterMainService() async {
    try {
      await _channel.invokeMethod<void>('unregisterMainService');
    } on MissingPluginException {
      return;
    }
  }

  @override
  Future<List<DiscoveredSyncService>> discoverMainServices({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    Object? response;
    try {
      response = await _channel.invokeMethod<Object?>('discoverMainServices', {
        'timeoutMillis': timeout.inMilliseconds,
      });
    } on MissingPluginException {
      return const [];
    }
    if (response is! List) return const [];
    return [
      for (final item in response)
        if (item is Map)
          DiscoveredSyncService.fromPlatformMap(
            Map<Object?, Object?>.from(item),
          ),
    ].whereType<DiscoveredSyncService>().toList(growable: false);
  }
}

enum SyncDiscoveryAdvertisementState {
  inactive,
  unsupported,
  advertising,
  failed,
}

class SyncDiscoveryAdvertisement {
  const SyncDiscoveryAdvertisement._({
    required this.state,
    this.deviceId,
    this.port,
    this.checkedAt,
    this.failureCode,
  });

  const SyncDiscoveryAdvertisement.inactive()
    : this._(state: SyncDiscoveryAdvertisementState.inactive);

  const SyncDiscoveryAdvertisement.unsupported({DateTime? checkedAt})
    : this._(
        state: SyncDiscoveryAdvertisementState.unsupported,
        checkedAt: checkedAt,
      );

  const SyncDiscoveryAdvertisement.advertising({
    required String deviceId,
    required int port,
    DateTime? checkedAt,
  }) : this._(
         state: SyncDiscoveryAdvertisementState.advertising,
         deviceId: deviceId,
         port: port,
         checkedAt: checkedAt,
       );

  const SyncDiscoveryAdvertisement.failed({
    String? failureCode,
    DateTime? checkedAt,
  }) : this._(
         state: SyncDiscoveryAdvertisementState.failed,
         checkedAt: checkedAt,
         failureCode: failureCode,
       );

  final SyncDiscoveryAdvertisementState state;
  final String? deviceId;
  final int? port;
  final DateTime? checkedAt;
  final String? failureCode;

  bool get needsAttention =>
      state == SyncDiscoveryAdvertisementState.failed ||
      state == SyncDiscoveryAdvertisementState.unsupported;

  SyncDiscoveryAdvertisement checked(DateTime dateTime) {
    return switch (state) {
      SyncDiscoveryAdvertisementState.inactive =>
        const SyncDiscoveryAdvertisement.inactive(),
      SyncDiscoveryAdvertisementState.unsupported =>
        SyncDiscoveryAdvertisement.unsupported(checkedAt: dateTime),
      SyncDiscoveryAdvertisementState.advertising =>
        SyncDiscoveryAdvertisement.advertising(
          deviceId: deviceId ?? '',
          port: port ?? 0,
          checkedAt: dateTime,
        ),
      SyncDiscoveryAdvertisementState.failed =>
        SyncDiscoveryAdvertisement.failed(
          checkedAt: dateTime,
          failureCode: failureCode,
        ),
    };
  }
}

class DiscoveredSyncService {
  const DiscoveredSyncService({
    required this.serviceName,
    required this.host,
    required this.port,
    required this.deviceId,
    required this.protocolVersion,
  });

  final String serviceName;
  final String host;
  final int port;
  final String deviceId;
  final int protocolVersion;

  String get baseUrl => 'http://${_urlHost(host)}:$port';

  static DiscoveredSyncService? fromPlatformMap(Map<Object?, Object?> map) {
    final serviceName = map['serviceName'];
    final host = map['host'];
    final port = map['port'];
    final deviceId = map['deviceId'] ?? '';
    final protocolVersion = map['protocolVersion'] ?? 0;
    if (serviceName is! String ||
        host is! String ||
        port is! int ||
        deviceId is! String ||
        protocolVersion is! int ||
        host.trim().isEmpty ||
        port <= 0) {
      return null;
    }
    return DiscoveredSyncService(
      serviceName: serviceName,
      host: host,
      port: port,
      deviceId: deviceId,
      protocolVersion: protocolVersion,
    );
  }

  static String _urlHost(String host) {
    final safeHost = host.replaceAll('%', '%25');
    if (safeHost.contains(':') && !safeHost.startsWith('[')) {
      return '[$safeHost]';
    }
    return safeHost;
  }
}
