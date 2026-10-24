import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:rr_pocket/src/constants.dart';

/// What went wrong, in words for the user.
class PocketException implements Exception {
  const PocketException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// [error] from talking to the phone, in words for the user.
String describePhoneError(Object error) => switch (error) {
      PocketException(:final message) => message,
      SocketException() =>
        'cannot reach the phone. Is RR Pocket open, on the same Wi-Fi?',
      TimeoutException() => 'the phone did not answer in time',
      HttpException(:final message) => 'the connection failed ($message)',
      _ => '$error',
    };

/// Where the pairing is kept: `~/.config/rr_pocket` (`%APPDATA%\rr_pocket`
/// on Windows), shared by the `pocket` command and the Lumide plugin.
class PocketConfig {
  PocketConfig([String? directory]) : directory = directory ?? defaultDirectory;

  final String directory;

  static String get defaultDirectory {
    final home = Platform.environment[Platform.isWindows ? 'APPDATA' : 'HOME'];
    return Platform.isWindows ? '$home\\rr_pocket' : '$home/.config/rr_pocket';
  }

  File get deviceFile => _file('device.json');

  /// Why the last install failed, left for `run` to read.
  File get installFailedFile => _file('install_failed');

  /// The command the `pocket` device was last registered with, so it is
  /// registered again only when that changes.
  File get registeredFile => _file('device_registered.json');

  File _file(String name) => File('$directory${Platform.pathSeparator}$name');
}

/// RR Pocket's control server on the phone.
class Phone {
  Phone(this.host, this.port, this.code);

  final String host;
  final int port;
  final String code;
  final _client = HttpClient()..connectionTimeout = connectionTimeout;

  /// The paired phone, or null before pairing. A pairing file that can't
  /// be read, such as one cut short, counts as none: pairing again fixes it.
  static Future<Phone?> tryLoad(PocketConfig config) async {
    final file = config.deviceFile;
    if (!await file.exists()) return null;
    final Object? json;
    try {
      json = jsonDecode(await file.readAsString());
    } on FormatException {
      return null;
    }
    if (json
        case {
          'host': final String host,
          'port': final int port,
          'code': final String code,
        }) {
      return Phone(host, port, code);
    }
    return null;
  }

  static Future<Phone> load(PocketConfig config) async {
    if (await tryLoad(config) case final phone?) return phone;
    throw const PocketException(
      'not paired yet: pocket pair <address> <code>',
    );
  }

  Future<void> save(PocketConfig config) async {
    final file = config.deviceFile;
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({'host': host, 'port': port, 'code': code}),
    );
  }

  Future<Map<String, Object?>> hello() => call('GET', '/hello');

  /// The running app's `print` output, line by line, until the app stops.
  Stream<String> logs() async* {
    final request = await _client.open('GET', host, port, '/logs');
    request.headers.set('authorization', 'Bearer $code');
    final response = await request.close();
    yield* response.transform(utf8.decoder).transform(const LineSplitter());
  }

  Future<Map<String, Object?>> call(
    String method,
    String path, {
    List<int>? body,
    bool gzip = false,
  }) async {
    final request = await _client.open(method, host, port, path);
    request.headers.set('authorization', 'Bearer $code');
    if (gzip) request.headers.set('content-encoding', 'gzip');
    request.contentLength = body?.length ?? 0;
    if (body != null) request.add(body);
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    if (response.statusCode == 401) {
      throw const PocketException(
        'the phone refused the pairing code; pair again',
      );
    }
    final json = _decode(text);
    if (response.statusCode != 200) {
      throw PocketException('$method $path: ${json?['error'] ?? text}');
    }
    if (json == null) throw PocketException('$method $path: $text');
    return json;
  }

  /// Ends the connections a long-lived process would otherwise keep.
  void close() => _client.close(force: true);

  static Map<String, Object?>? _decode(String text) {
    try {
      final json = jsonDecode(text);
      if (json is Map<String, Object?>) return json;
      return null;
    } on FormatException {
      return null;
    }
  }
}
