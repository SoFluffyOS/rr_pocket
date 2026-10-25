import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:rr_pocket/src/pair_link.dart';
import 'package:rr_pocket/src/pairing.dart';

/// How a post to the computer ended.
sealed class PairResult {
  const PairResult();
}

class Paired extends PairResult {
  const Paired(this.computer);

  final String computer;
}

class PairFailed extends PairResult {
  const PairFailed(this.message);

  /// Says what happened and what to do next.
  final String message;
}

/// Tells the computer whose QR code was scanned where this phone is, trying
/// each of its addresses in turn (docs/pairing.md). Not the code: this post
/// is plain HTTP, so it carries the phone's certificate fingerprint, signed
/// with the QR code's token; the computer then gets the code over TLS.
class PairSender {
  const PairSender({
    this.connectTimeout = const Duration(seconds: 5),
    this.answerTimeout = const Duration(seconds: 20),
    this.offer = Pairing.offer,
  });

  /// Keeps the QR code's token on the phone for the computer to redeem.
  final Future<PairOffer?> Function(String token) offer;

  /// How long each address gets to accept the connection.
  final Duration connectTimeout;

  /// How long a computer that took the connection gets to answer. Longer
  /// than [connectTimeout]: it answers only after reaching this phone's
  /// `/hello`, which the computer gives up to 10 s.
  final Duration answerTimeout;

  Future<PairResult> send(PairLink link, Pairing phone) async {
    final address = phone.address;
    if (address == null) {
      return const PairFailed(
        'This phone has no Wi-Fi address. Connect it to the same Wi-Fi '
        'as your computer, then scan again.',
      );
    }
    final offered = await offer(link.token);
    if (offered == null) {
      return const PairFailed(
        'RR Pocket could not get ready to pair. Restart it, then scan again.',
      );
    }
    final body = jsonEncode({
      'name': phone.name,
      'address': address,
      'port': phone.port,
      'fingerprint': offered.fingerprint,
      'proof': offered.proof,
    });
    final client = HttpClient()..connectionTimeout = connectTimeout;
    try {
      for (final host in link.hosts) {
        final answer = await _post(client, link.pairUri(host), body);
        if (answer == null) continue;
        return switch (answer) {
          (status: 200, json: {'computer': final String computer})
              when computer.isNotEmpty =>
            Paired(computer),
          (status: 200, json: _) => Paired(link.name),
          (status: _, json: {'error': final String error}) => PairFailed(
            'Not paired: $error',
          ),
          (status: final status, json: _) => PairFailed(
            'Not paired: ${link.name} answered $status. '
            'Show a new QR code on it and scan again.',
          ),
        };
      }
      return PairFailed(
        'Could not reach ${link.name} at ${link.hosts.join(', ')}. '
        'Put this phone on the same Wi-Fi, or type the address and code '
        'on the computer.',
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Null when [uri] could not be reached or did not answer in time.
  Future<({int status, Object? json})?> _post(
    HttpClient client,
    Uri uri,
    String body,
  ) async {
    try {
      final request = await client.postUrl(uri);
      // A plain Content-Length, not chunked: any HTTP server reads it.
      final bytes = utf8.encode(body);
      request.headers.contentType = ContentType.json;
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close().timeout(answerTimeout);
      final text = await utf8.decodeStream(response).timeout(answerTimeout);
      final Object? json;
      try {
        json = jsonDecode(text);
      } on FormatException {
        return (status: response.statusCode, json: null);
      }
      return (status: response.statusCode, json: json);
    } on SocketException {
      return null;
    } on HttpException {
      return null;
    } on TimeoutException {
      return null;
    }
  }
}
