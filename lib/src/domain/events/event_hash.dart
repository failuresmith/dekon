import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'canonical_json.dart';

String payloadHash(Map<String, Object?> payload) {
  final canonical = canonicalJsonEncode(payload);
  return sha256.convert(utf8.encode(canonical)).toString();
}
