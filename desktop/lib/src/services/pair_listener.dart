import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:rr_pocket/src/constants.dart';
import 'package:rr_pocket/src/models/models.dart';
import 'package:rr_pocket/src/services/phone.dart';

typedef PairedPhone = ({Phone phone, Map<String, Object?> hello});

/// The user closed the QR code before a phone scanned it.
class PairingCancelled extends PocketException {
  const PairingCancelled() : super('pairing was cancelled');
}

/// Checks a phone that posted its address and code: its `/hello`, with the
/// code. Throws when the computer can't reach it.
typedef VerifyPhone = Future<Map<String, Object?>> Function(Phone phone);

/// The computer's side of "A QR code on the computer" (docs/pairing.md):
/// listens for the phone that scans [link], checks it can reach that phone
/// with the code it sent, and stops after the first pairing.
///
/// The QR page ([pageUri], for Lumide's panel) is served to this computer
/// only: the token in it must not reach anyone else on the network.
class PairListener {
  PairListener._(this._server, this.link, this._verify, Duration lifetime) {
    _server.listen(_handle);
    _expiry = Timer(lifetime, () {
      _fail(
        const PocketException('no phone scanned the code; show it again'),
      );
    });
  }

  static Future<PairListener> start({
    required String computer,
    required List<String> hosts,
    required VerifyPhone verify,
    Duration lifetime = const Duration(minutes: 5),
    String? token,
    int port = 0,
  }) async {
    if (hosts.isEmpty) {
      throw const PocketException(
        'this computer has no address on a local network for the phone to '
        'reach; connect it to the phone\'s Wi-Fi',
      );
    }
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    final link = PairLink(
      hosts: hosts,
      port: server.port,
      token: token ?? newPairingToken(),
      name: computer,
    );
    return PairListener._(server, link, verify, lifetime);
  }

  final HttpServer _server;
  final PairLink link;
  final VerifyPhone _verify;
  late final Timer _expiry;
  final _paired = Completer<PairedPhone>();
  bool _checking = false;
  bool _used = false;

  /// The phone that paired; fails when the listener closes or expires
  /// first.
  Future<PairedPhone> get paired => _paired.future;

  /// The page with the QR code, for this computer only.
  Uri get pageUri => Uri.parse('http://127.0.0.1:${_server.port}/qr');

  Future<void> close() async {
    _fail(const PairingCancelled());
    await _server.close(force: true);
  }

  void _fail(PocketException error) {
    _expiry.cancel();
    if (_paired.isCompleted) return;
    _paired.completeError(error);
    unawaited(_paired.future.then((_) {}, onError: (Object _) {}));
    unawaited(_server.close(force: true));
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/qr') return await _page(request);
      if (request.method == 'POST' && path == '/pair') {
        return await _pair(request);
      }
      await _reply(request, 404, {'error': 'not found'});
    } catch (error) {
      await _reply(request, 500, {'error': '$error'});
    }
  }

  Future<void> _page(HttpRequest request) async {
    final remote = request.connectionInfo?.remoteAddress;
    if (remote == null || !remote.isLoopback) {
      return _reply(request, 403, {'error': 'this page is for this computer'});
    }
    request.response.headers.contentType = ContentType.html;
    request.response.write(qrPage(link));
    await request.response.close();
  }

  Future<void> _pair(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      return _reply(request, 400, {'error': 'not JSON'});
    }
    if (json is! Map) return _reply(request, 400, {'error': 'not an object'});
    final token = json['token'];
    if (token is! String || _used || !sameToken(token, link.token)) {
      return _reply(request, 403, {
        'error': 'this code is not the one showing; scan it again',
      });
    }
    if (_checking) {
      return _reply(request, 409, {'error': 'already pairing a phone'});
    }
    final address = json['address'];
    final code = json['code'];
    final port = switch (json['port']) {
      final int port => port,
      _ => controlPort,
    };
    if (address is! String || code is! String) {
      return _reply(request, 400, {'error': 'address and code are needed'});
    }
    _checking = true;
    final phone = Phone(address, port, normalizePairingCode(code));
    try {
      final hello = await _verify(phone);
      _used = true;
      await _reply(request, 200, {'computer': link.name});
      _expiry.cancel();
      if (!_paired.isCompleted) _paired.complete((phone: phone, hello: hello));
      unawaited(_server.close(force: true));
    } catch (error) {
      phone.close();
      final shown = PhoneAddress(address, port);
      await _reply(request, 502, {
        'error': 'the computer could not reach the phone at $shown '
            '(${describePhoneError(error)}); are both on the same network?',
      });
    } finally {
      _checking = false;
    }
  }

  static Future<void> _reply(
    HttpRequest request,
    int status,
    Map<String, Object?> body,
  ) async {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  }
}

/// The page Lumide shows: the QR code, and what to do with it.
String qrPage(PairLink link) {
  const escape = HtmlEscape();
  return '''<!doctype html>
<html><head><meta charset="utf-8"><title>Pair with RR Pocket</title>
<style>
  body { margin: 0; min-height: 100vh; display: flex; align-items: center;
    justify-content: center; background: #171b1e; color: #e4e1db;
    font: 15px -apple-system, "Segoe UI", sans-serif; }
  main { text-align: center; max-width: 420px; padding: 24px; }
  .code { background: #fff; padding: 16px; border-radius: 16px;
    display: inline-block; }
  h1 { font-size: 20px; margin: 20px 0 8px; }
  p { color: #9aa7ae; line-height: 1.5; margin: 4px 0; }
</style></head>
<body><main>
  <div class="code">${qrSvg(link.toUri().toString(), pixels: 280)}</div>
  <h1>Scan with RR Pocket</h1>
  <p>On the phone, open RR Pocket and tap <b>Scan QR code</b>, or point the
  camera at it.</p>
  <p>Pairing with ${escape.convert(link.name)}. This code works once.</p>
</main></body></html>''';
}
