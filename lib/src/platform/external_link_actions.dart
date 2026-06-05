import 'package:flutter/services.dart';

typedef ExternalLinkLauncher = Future<void> Function(Uri uri);

Future<void> openExternalHttpsLink(Uri uri) {
  return const ExternalLinkActions().openHttps(uri);
}

class ExternalLinkActions {
  const ExternalLinkActions();

  static const _channel = MethodChannel('xyz.infinica.dekon/app_actions');

  Future<void> openHttps(Uri uri) async {
    if (uri.scheme != 'https') {
      throw const ExternalLinkException();
    }
    try {
      await _channel.invokeMethod<void>('openUrl', {'url': uri.toString()});
    } on PlatformException {
      throw const ExternalLinkException();
    } on MissingPluginException {
      throw const ExternalLinkException();
    }
  }
}

class ExternalLinkException implements Exception {
  const ExternalLinkException();
}
