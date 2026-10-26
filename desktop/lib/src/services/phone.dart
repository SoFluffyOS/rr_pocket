import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:rr_pocket/src/constants.dart';
import 'package:rr_pocket/src/services/pinned_tls.dart';

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
      // Also what an RR Pocket from before TLS gives.
      TlsException() => 'the phone at that address is not the RR Pocket this '
          'computer paired with (it was reinstalled, its data was cleared, '
          'or it is another device). Update RR Pocket if it is old, then '
          'pair again: pocket pair',
      TimeoutException() =>
        'the phone did not answer in time; unlock it and open RR Pocket',
      HttpException(:final message) => 'the connection failed ($message)',
      _ => '$error',
    };

/// What to compare after pairing by a route that trusted the first
/// certificate that answered: found on the network, or typed in.
String checkCertificate(String fingerprint, {required bool cli}) {
  final again = switch (cli) {
    true => 'run pocket forget, then pocket pair --qr',
    false => 'forget this phone and pair by QR code',
  };
  return 'Check that RR Pocket shows certificate '
      '${shortFingerprint(fingerprint)} under its code. If it shows another, '
      'this computer paired with some other device: $again.';
}

/// Makes [file] readable and writable by this account only. On Windows the
/// pairing lives under the user's own `%APPDATA%`, private already.
Future<void> makePrivate(File file) async {
  if (Platform.isWindows) return;
  final result = await Process.run(executableChmod, ['600', file.path]);
  if (result.exitCode != 0) {
    throw PocketException(
      'could not make ${file.path} private: ${result.stderr}'.trim(),
    );
  }
}

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

/// RR Pocket's control server on the phone, over TLS pinned to the phone's
/// certificate. Without a [fingerprint] (pairing typed in), it trusts the
/// first certificate it sees and keeps that one.
class Phone {
  Phone(this.host, this.port, this.code, {String? fingerprint})
      : _check = FirstSeen()..fingerprint = fingerprint;

  final String host;
  final int port;
  final String code;
  final FirstSeen _check;
  late final _client = HttpClient(context: pinnedContext())
    ..connectionTimeout = connectionTimeout
    ..badCertificateCallback = (certificate, _, __) => trusts(certificate);

  /// The phone's certificate as pinned; null before it first answered.
  String? get fingerprint => _check.fingerprint;

  /// Whether [certificate] is this phone's.
  bool trusts(X509Certificate certificate) => _check.trusts(certificate);

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
    // A pairing from before TLS has no fingerprint: pairing again makes one.
    if (json
        case {
          'host': final String host,
          'port': final int port,
          'code': final String code,
          'fingerprint': final String fingerprint,
        }) {
      return Phone(host, port, code, fingerprint: fingerprint);
    }
    return null;
  }

  static Future<Phone> load(PocketConfig config) async {
    if (await tryLoad(config) case final phone?) return phone;
    throw const PocketException(
      'not paired yet: run pocket pair',
    );
  }

  /// Readable by this account only: the code lets whoever has it run code
  /// on the phone. It is written beside, made private while still empty,
  /// then moved into place, so no other account can read it even briefly.
  Future<void> save(PocketConfig config) async {
    final file = config.deviceFile;
    await file.parent.create(recursive: true);
    final fingerprint = this.fingerprint;
    if (fingerprint == null) {
      throw const PocketException('the phone has not answered yet; pair again');
    }
    final draft = File('${file.path}.tmp');
    await draft.writeAsString('');
    await makePrivate(draft);
    await draft.writeAsString(
      jsonEncode({
        'host': host,
        'port': port,
        'code': code,
        'fingerprint': fingerprint,
      }),
    );
    await draft.rename(file.path);
  }

  Future<Map<String, Object?>> hello() =>
      call('GET', '/hello', timeout: const Duration(seconds: 10));

  /// The running app's `print` output, line by line, until the app stops.
  Stream<String> logs() async* {
    final request = await _client.openUrl('GET', _uri('/logs'));
    request.headers.set('authorization', 'Bearer $code');
    final response = await request.close();
    yield* response.transform(utf8.decoder).transform(const LineSplitter());
  }

  /// Fails with a [TimeoutException] when the phone has not answered
  /// within [timeout]: one that took the connection and then went quiet
  /// (asleep, off the Wi-Fi) would otherwise hold Flutter's ping, or a run,
  /// for good.
  Future<Map<String, Object?>> call(
    String method,
    String path, {
    List<int>? body,
    bool gzip = false,
    Duration timeout = requestTimeout,
  }) async {
    final (status, bytes) = await _exchange(
      method,
      path,
      body: body,
      gzip: gzip,
      timeout: timeout,
    );
    final text = utf8.decode(bytes, allowMalformed: true);
    final json = _decode(text);
    if (status != 200) {
      throw PocketException('$method $path: ${json?['error'] ?? text}');
    }
    if (json == null) throw PocketException('$method $path: $text');
    return json;
  }

  /// What the phone's screen shows, as a PNG.
  Future<List<int>> screenshot() async {
    final (status, bytes) = await _exchange('GET', '/screenshot');
    if (status == 404) {
      throw const PocketException(
        'this RR Pocket takes no screenshots; update it',
      );
    }
    if (status != 200) {
      final text = utf8.decode(bytes, allowMalformed: true);
      throw PocketException('screenshot: ${_decode(text)?['error'] ?? text}');
    }
    return bytes;
  }

  Future<(int, List<int>)> _exchange(
    String method,
    String path, {
    List<int>? body,
    bool gzip = false,
    Duration timeout = requestTimeout,
  }) async {
    HttpClientRequest? sent;
    Future<(int, List<int>)> exchange() async {
      final request = sent = await _client.openUrl(method, _uri(path));
      request.headers.set('authorization', 'Bearer $code');
      if (gzip) request.headers.set('content-encoding', 'gzip');
      request.contentLength = body?.length ?? 0;
      if (body != null) request.add(body);
      final response = await request.close();
      final bytes = await response.fold<BytesBuilder>(
        BytesBuilder(copy: false),
        (all, chunk) => all..add(chunk),
      );
      return (response.statusCode, bytes.takeBytes());
    }

    final (status, bytes) = await exchange().timeout(
      timeout,
      onTimeout: () {
        sent?.abort();
        throw TimeoutException('$method $path', timeout);
      },
    );
    if (status == 401) {
      throw const PocketException(
        'the phone refused the pairing code; pair again',
      );
    }
    return (status, bytes);
  }

  /// [path] may hold escapes (`%2F`), kept as they are.
  Uri _uri(String path) =>
      Uri.parse('${Uri(scheme: 'https', host: host, port: port)}$path');

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
