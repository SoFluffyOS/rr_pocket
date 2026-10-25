import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// How the fake phone's user answers `POST /pair`.
enum PairAnswer { allow, refuse, noAnswer, busy }

/// RR Pocket's control server, as far as the computer sees it: over TLS
/// with its own certificate, checks the pairing code, answers `/hello`,
/// takes a bundle, runs and stops.
class FakePhone {
  FakePhone._(this._server, this.code, this.plugins, this.engineRevision);

  /// The phone's certificate, or another phone's, and what a computer pins
  /// for it. Test-only keys, made with openssl.
  static SecurityContext identity([String name = 'phone']) => SecurityContext()
    ..useCertificateChain('test/support/${name}_cert.pem')
    ..usePrivateKey('test/support/${name}_key.pem');

  static String fingerprintOf([String name = 'phone']) {
    final pem = File('test/support/${name}_cert.pem').readAsStringSync();
    final body =
        pem.split('\n').where((line) => !line.startsWith('-----')).join();
    return sha256.convert(base64.decode(body)).toString();
  }

  /// The certificate this phone serves, as a computer pins it.
  final fingerprint = fingerprintOf();

  /// A QR code's token the user allowed, for `POST /pair {"token"}`.
  String? offeredToken;

  PairAnswer pairAnswer = PairAnswer.allow;

  /// The computer names that asked to pair.
  final pairRequests = <String>[];

  static Future<FakePhone> start({
    String code = '12345678',
    Map<String, String> plugins = const {'shared_preferences': '2.5.6'},
    String engineRevision = 'engine-a',
  }) async {
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      identity(),
    );
    final phone = FakePhone._(server, code, plugins, engineRevision);
    server.listen(phone._handle);
    return phone;
  }

  final HttpServer _server;
  final String code;
  final Map<String, String> plugins;
  final String engineRevision;

  /// Requests that carried the right code, as `METHOD /path`.
  final requests = <String>[];

  /// The bundle's files by path, unpacked.
  final bundle = <String, List<int>>{};

  int get port => _server.port;

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    // RR Pocket's server reads a body by its Content-Length only: a chunked
    // one arrives empty there, so it fails here.
    if (request.headers.chunkedTransferEncoding) {
      response.statusCode = 400;
      response.write(jsonEncode({'error': 'send a Content-Length'}));
      return response.close();
    }
    if (request.method == 'POST' && request.uri.path == '/pair') {
      final body = jsonDecode(await utf8.decodeStream(request)) as Map;
      if (body['token'] case final String token) {
        final allowed = token == offeredToken;
        if (allowed) offeredToken = null;
        response.statusCode = allowed ? 200 : 403;
        response.write(jsonEncode(switch (allowed) {
          true => {'code': code},
          false => {'error': 'this pairing QR code has expired or was used'},
        }));
        return response.close();
      }
      pairRequests.add('${body['computer']}');
      final (status, reply) = switch (pairAnswer) {
        PairAnswer.allow => (200, {'code': code}),
        PairAnswer.refuse => (403, {'error': 'pairing refused on the phone'}),
        PairAnswer.noAnswer => (408, {'error': 'no answer on the phone'}),
        PairAnswer.busy => (409, {'error': 'another computer is asking'}),
      };
      response.statusCode = status;
      response.write(jsonEncode(reply));
      return response.close();
    }
    if (request.headers.value('authorization') != 'Bearer $code') {
      response.statusCode = 401;
      response.write(jsonEncode({'error': 'wrong pairing code'}));
      return response.close();
    }
    final path = request.uri.path;
    requests.add('${request.method} $path');
    if (request.method == 'PUT' && path.startsWith('/bundle/')) {
      final body =
          await request.fold<List<int>>([], (all, b) => all..addAll(b));
      bundle[Uri.decodeComponent(path.substring('/bundle/'.length))] =
          gzip.decode(body);
      response.write('{}');
      return response.close();
    }
    await request.drain<void>();
    final reply = switch (path) {
      '/hello' => {
          'name': 'Test Phone',
          'flutterVersion': '3.47.7',
          'engineRevision': engineRevision,
          'vmRelayPort': 8101,
          'plugins': plugins,
        },
      '/run' => {'vmPath': '/abc=/'},
      _ => <String, Object?>{},
    };
    response.write(jsonEncode(reply));
    await response.close();
  }
}
