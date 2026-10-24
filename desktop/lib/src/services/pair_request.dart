import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:rr_pocket/src/services/phone.dart';

/// Asks the phone at [host] to pair with this computer, named [computer];
/// the phone asks its user, so this waits up to [timeout] for a tap. Returns
/// the pairing code (docs/pairing.md, "Found on the network").
Future<String> requestPairing(
  String host,
  int port,
  String computer, {
  Duration timeout = const Duration(seconds: 70),
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final request = await client.post(host, port, '/pair');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'computer': computer}));
    final response = await request.close().timeout(timeout);
    final text = await utf8.decodeStream(response).timeout(timeout);
    final json = _decode(text);
    if (response.statusCode == 200) {
      if (json?['code'] case final String code when code.isNotEmpty) {
        return code;
      }
      throw const PocketException('the phone answered without a code');
    }
    if (response.statusCode == 404) {
      throw const PocketException(
        'this RR Pocket is too old to pair this way; update it, or type '
        'the address and code',
      );
    }
    throw PocketException('${json?['error'] ?? 'pairing failed ($text)'}');
  } on TimeoutException {
    throw const PocketException('no answer on the phone');
  } finally {
    client.close(force: true);
  }
}

Map<String, Object?>? _decode(String text) {
  try {
    final json = jsonDecode(text);
    if (json is Map<String, Object?>) return json;
    return null;
  } on FormatException {
    return null;
  }
}
