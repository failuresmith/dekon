import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

abstract final class SyncAuthHeaders {
  static const deviceId = 'x-dekon-device-id';
  static const timestamp = 'x-dekon-timestamp';
  static const bodyHash = 'x-dekon-body-sha256';
  static const signature = 'x-dekon-signature';
}

abstract final class SyncSecrets {
  static String generate({int bytes = 32}) {
    final random = Random.secure();
    final values = List<int>.generate(bytes, (_) => random.nextInt(256));
    return base64Url.encode(values).replaceAll('=', '');
  }

  static String hash(String secret) {
    return sha256.convert(utf8.encode(secret)).toString();
  }
}

class SyncAuthenticator {
  const SyncAuthenticator({
    this.maxClockSkew = const Duration(minutes: 5),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration maxClockSkew;
  final DateTime Function() _now;

  Map<String, String> signHeaders({
    required String method,
    required Uri uri,
    required List<int> bodyBytes,
    required String deviceId,
    required String sharedSecret,
    DateTime? timestamp,
  }) {
    final signedAt = (timestamp ?? _now()).toUtc().toIso8601String();
    final bodyHash = _bodyHash(bodyBytes);
    return {
      SyncAuthHeaders.deviceId: deviceId,
      SyncAuthHeaders.timestamp: signedAt,
      SyncAuthHeaders.bodyHash: bodyHash,
      SyncAuthHeaders.signature: _signature(
        method: method,
        uri: uri,
        timestamp: signedAt,
        bodyHash: bodyHash,
        sharedSecret: sharedSecret,
      ),
    };
  }

  bool verify({
    required Map<String, String> headers,
    required String method,
    required Uri uri,
    required List<int> bodyBytes,
    required String sharedSecret,
  }) {
    final timestamp = headers[SyncAuthHeaders.timestamp];
    final bodyHash = headers[SyncAuthHeaders.bodyHash];
    final signature = headers[SyncAuthHeaders.signature];
    if (timestamp == null || bodyHash == null || signature == null) {
      return false;
    }
    final parsed = DateTime.tryParse(timestamp)?.toUtc();
    if (parsed == null || _outsideClockWindow(parsed)) return false;
    if (!_constantTimeEquals(bodyHash, _bodyHash(bodyBytes))) return false;
    final expected = _signature(
      method: method,
      uri: uri,
      timestamp: timestamp,
      bodyHash: bodyHash,
      sharedSecret: sharedSecret,
    );
    return _constantTimeEquals(signature, expected);
  }

  String signStateResponse({
    required String nonce,
    required String deviceId,
    required String sharedSecret,
  }) {
    return _stateResponseSignature(
      nonce: nonce,
      deviceId: deviceId,
      sharedSecret: sharedSecret,
    );
  }

  bool verifyStateResponse({
    required String nonce,
    required String deviceId,
    required String sharedSecret,
    required String signature,
  }) {
    final expected = _stateResponseSignature(
      nonce: nonce,
      deviceId: deviceId,
      sharedSecret: sharedSecret,
    );
    return _constantTimeEquals(signature, expected);
  }

  bool _outsideClockWindow(DateTime timestamp) {
    final current = _now().toUtc();
    final delta = current.isAfter(timestamp)
        ? current.difference(timestamp)
        : timestamp.difference(current);
    return delta > maxClockSkew;
  }

  String _signature({
    required String method,
    required Uri uri,
    required String timestamp,
    required String bodyHash,
    required String sharedSecret,
  }) {
    final canonical = [
      method.toUpperCase(),
      _pathAndQuery(uri),
      timestamp,
      bodyHash,
    ].join('\n');
    final digest = Hmac(
      sha256,
      utf8.encode(sharedSecret),
    ).convert(utf8.encode(canonical));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  String _bodyHash(List<int> bodyBytes) {
    return sha256.convert(bodyBytes).toString();
  }

  String _pathAndQuery(Uri uri) {
    final path = uri.path.isEmpty ? '/' : uri.path;
    return uri.hasQuery ? '$path?${uri.query}' : path;
  }

  String _stateResponseSignature({
    required String nonce,
    required String deviceId,
    required String sharedSecret,
  }) {
    final canonical = ['sync_state_response', nonce, deviceId].join('\n');
    final digest = Hmac(
      sha256,
      utf8.encode(sharedSecret),
    ).convert(utf8.encode(canonical));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  bool _constantTimeEquals(String left, String right) {
    if (left.length != right.length) return false;
    var diff = 0;
    for (var i = 0; i < left.length; i++) {
      diff |= left.codeUnitAt(i) ^ right.codeUnitAt(i);
    }
    return diff == 0;
  }
}
