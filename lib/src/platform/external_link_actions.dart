import 'package:flutter/services.dart';

typedef ExternalLinkLauncher = Future<void> Function(Uri uri);
typedef TextShareLauncher = Future<void> Function({
  required String text,
  required String title,
});

Future<void> openExternalHttpsLink(Uri uri) {
  return const ExternalLinkActions().openHttps(uri);
}

Future<void> sharePlainText({required String text, required String title}) {
  return const ExternalLinkActions().shareText(text: text, title: title);
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

  Future<void> shareText({required String text, required String title}) async {
    if (text.trim().isEmpty) {
      throw const ExternalShareException();
    }
    try {
      await _channel.invokeMethod<void>('shareText', {
        'text': text,
        'title': title,
      });
    } on PlatformException {
      throw const ExternalShareException();
    } on MissingPluginException {
      throw const ExternalShareException();
    }
  }
}

class ExternalLinkException implements Exception {
  const ExternalLinkException();
}

class ExternalShareException implements Exception {
  const ExternalShareException();
}
