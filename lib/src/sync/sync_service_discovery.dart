import 'package:flutter/services.dart';

import 'sync_protocol.dart';

abstract class SyncServiceDiscovery {
  const SyncServiceDiscovery();

  Future<void> registerMainService({
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
  Future<void> registerMainService({
    required String deviceId,
    required int port,
  }) async {}

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
  Future<void> registerMainService({
    required String deviceId,
    required int port,
  }) async {
    try {
      await _channel.invokeMethod<void>('registerMainService', {
        'deviceId': deviceId,
        'port': port,
        'protocolVersion': syncProtocolVersion,
      });
    } on MissingPluginException {
      return;
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
    final deviceId = map['deviceId'];
    final protocolVersion = map['protocolVersion'];
    if (serviceName is! String ||
        host is! String ||
        port is! int ||
        deviceId is! String ||
        protocolVersion is! int ||
        host.trim().isEmpty ||
        deviceId.trim().isEmpty ||
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
