import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:rr_pocket/src/services/phone.dart';
import 'package:rr_pocket/src/services/pinned_tls.dart';

/// The code a phone gave, and the certificate it gave it over: what the
/// computer pins from then on.
typedef GivenCode = ({String code, String fingerprint});

/// Asks the phone at [host] to pair with this computer, named [computer];
/// the phone asks its user, so this waits up to [timeout] for a tap
/// (docs/pairing.md, "Found on the network"). The phone's certificate is
/// trusted as first seen: nothing vouches for it yet.
Future<GivenCode> requestPairing(
  String host,
  int port,
  String computer, {
  Duration timeout = const Duration(seconds: 70),
}) async {
  final seen = FirstSeen();
  try {
    // The timeout covers the connection too: a phone that takes it and
    // never finishes the handshake counts as no answer.
    final (status, json, text) = await _post(
      host,
      port,
      {'computer': computer},
      seen,
      timeout,
    ).timeout(timeout);
    if (status == 200) return _given(json, seen);
    if (status == 404) {
      throw const PocketException(
        'this RR Pocket is too old to pair this way; update it, or type '
        'the address and code',
      );
    }
    throw PocketException('${json?['error'] ?? 'pairing failed ($text)'}');
  } on TimeoutException {
    throw const PocketException('no answer on the phone');
  }
}

/// Redeems the QR code's [token] at the phone that proved it scanned it,
/// over TLS pinned to the [fingerprint] it sent (docs/pairing.md, "A QR
/// code on the computer"). Returns the pairing code.
Future<String> redeemPairing(
  String host,
  int port,
  String fingerprint,
  String token, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final pinned = FirstSeen()..fingerprint = fingerprint;
  final (status, json, text) =
      await _post(host, port, {'token': token}, pinned, timeout);
  if (status == 200) return _given(json, pinned).code;
  throw PocketException('${json?['error'] ?? 'pairing failed ($text)'}');
}

GivenCode _given(Map<String, Object?>? json, FirstSeen seen) {
  final fingerprint = seen.fingerprint;
  if (json?['code'] case final String code
      when code.isNotEmpty && fingerprint != null) {
    return (code: code, fingerprint: fingerprint);
  }
  throw const PocketException('the phone answered without a code');
}

Future<(int, Map<String, Object?>?, String)> _post(
  String host,
  int port,
  Map<String, Object?> body,
  FirstSeen check,
  Duration timeout,
) async {
  final client = HttpClient(context: pinnedContext())
    ..connectionTimeout = const Duration(seconds: 5)
    ..badCertificateCallback =
        (certificate, _, __) => check.trusts(certificate);
  try {
    final request = await client.postUrl(
      Uri(scheme: 'https', host: host, port: port, path: '/pair'),
    );
    // RR Pocket reads a body by its Content-Length; it has no chunked
    // decoding, so the length is set rather than streamed.
    final bytes = utf8.encode(jsonEncode(body));
    request.headers.contentType = ContentType.json;
    request.contentLength = bytes.length;
    request.add(bytes);
    final response = await request.close().timeout(timeout);
    final text = await utf8.decodeStream(response).timeout(timeout);
    return (response.statusCode, _decode(text), text);
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
