import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// RR Pocket's control server, as far as the computer sees it: checks the
/// pairing code, answers `/hello`, takes a bundle, runs and stops.
class FakePhone {
  FakePhone._(this._server, this.code, this.plugins, this.engineRevision);

  static Future<FakePhone> start({
    String code = '12345678',
    Map<String, String> plugins = const {'shared_preferences': '2.5.6'},
    String engineRevision = 'engine-a',
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
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
