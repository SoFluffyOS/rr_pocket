// RR Pocket's side on the computer: pairs with the phone, then stands behind
// the `pocket` custom device, so a stock `flutter run -d pocket` runs a
// project on the phone over Wi-Fi. Needs only the Dart that ships with
// Flutter: no adb, no Android SDK.
//
//   dart tool/pocket.dart pair <phone address> <code>     once
//   dart tool/pocket.dart pin                              in a project
//   flutter run -d pocket
//
// The tool calls the rest: ping, install <flutter_assets> <app>, run <app>,
// uninstall <app>.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const deviceId = 'pocket';
const controlPort = 8100;

Future<void> main(List<String> args) async {
  try {
    exitCode = await switch (args) {
      ['pair', final address, final code] => pair(address, code),
      ['ping'] => ping(),
      ['pin'] => pin(Directory.current),
      ['install', final bundle, _] => recordInstall(() => install(bundle)),
      ['run', ...] => run(),
      ['uninstall', ...] => stop(),
      _ => usage(),
    };
  } on PocketException catch (e) {
    stderr.writeln('RR Pocket: ${e.message}');
    exitCode = 1;
  } on SocketException catch (e) {
    stderr.writeln(
      'RR Pocket: cannot reach the phone (${e.message}). Is RR Pocket open, '
      'on the same Wi-Fi?',
    );
    exitCode = 1;
  }
  // HttpClient keeps the process alive otherwise.
  exit(exitCode);
}

Future<int> usage() async {
  stderr.writeln(
    'usage: dart pocket.dart pair <phone address> <code>   (once)\n'
    '       dart pocket.dart pin                           (in a project)\n'
    '       then: flutter run -d $deviceId',
  );
  return 64;
}

Future<int> pair(String address, String code) async {
  final (host, port) = switch (address.split(':')) {
    [final host, final port] => (host, int.parse(port)),
    _ => (address, controlPort),
  };
  final phone = Phone(host, port, code.replaceAll(RegExp(r'[\s-]'), ''));
  final hello = await phone.hello();
  await phone.save();
  stdout.writeln(
    'Paired with ${hello['name']} at $host (Flutter ${hello['flutterVersion']}).',
  );
  await registerDevice();
  stdout.writeln('Run a project on it with: flutter run -d $deviceId');
  return 0;
}

/// Adds the `pocket` custom device, replacing an older entry.
Future<void> registerDevice() async {
  final dart = Platform.resolvedExecutable;
  final script = File.fromUri(Platform.script).absolute.path;
  List<String> helper(List<String> args) => [dart, script, ...args];
  final config = {
    'id': deviceId,
    'label': 'RR Pocket',
    'sdkNameAndVersion': 'RR Pocket over Wi-Fi',
    'platform': 'linux-arm64',
    'enabled': true,
    'ping': helper(['ping']),
    'pingSuccessRegex': null,
    'postBuild': null,
    'install': helper(['install', r'${localPath}', r'${appName}']),
    'uninstall': helper(['uninstall', r'${appName}']),
    'runDebug': helper(['run', r'${appName}']),
    'forwardPort': null,
    'forwardPortSuccessRegex': null,
    'screenshot': null,
    'readLogs': null,
  };
  final flutter = Platform.isWindows ? 'flutter.bat' : 'flutter';
  await Process.run(flutter, ['config', '--enable-custom-devices']);
  await Process.run(flutter, ['custom-devices', 'delete', '-d', deviceId]);
  final added = await Process.run(flutter, [
    'custom-devices',
    'add',
    '--json=${jsonEncode(config)}',
  ]);
  if (added.exitCode != 0) {
    throw PocketException('flutter custom-devices add failed: ${added.stderr}');
  }
}

Future<int> ping() async {
  await (await Phone.load()).hello();
  return 0;
}

/// Pins the project's Android plugins to the versions RR Pocket carries, in
/// its pubspec_overrides.yaml, then resolves.
Future<int> pin(Directory project) async {
  final carried = bundledPlugins(await (await Phone.load()).hello());
  final used = lockedVersions(project);
  if (used == null) {
    throw PocketException(
      'no pubspec.lock in ${project.path}; run flutter pub get',
    );
  }
  final pins = {
    for (final MapEntry(key: name, value: version) in carried.entries)
      if (used.containsKey(name)) name: version,
  };
  final overrides = File('${project.path}/pubspec_overrides.yaml');
  if (overrides.existsSync() &&
      !overrides.readAsStringSync().startsWith(_overridesHeader)) {
    throw PocketException(
      '${overrides.path} exists and is not ours; add these by hand:\n'
      '${[for (final e in pins.entries) '  ${e.key}: ${e.value}'].join('\n')}',
    );
  }
  final names = pins.keys.toList()..sort();
  await overrides.writeAsString(
    '$_overridesHeader: the Android plugin versions RR Pocket carries.\n'
    'dependency_overrides:\n'
    '${[for (final name in names) '  $name: ${pins[name]}\n'].join()}',
  );
  stdout.writeln('Pinned ${pins.length} plugins in ${overrides.path}.');
  final flutter = Platform.isWindows ? 'flutter.bat' : 'flutter';
  final got = await Process.run(flutter, [
    'pub',
    'get',
  ], workingDirectory: project.path);
  stdout.write(got.stdout);
  stderr.write(got.stderr);
  return got.exitCode;
}

/// The tool runs the app even when install failed (it only logs the
/// failure), so install leaves its outcome where run checks it.
Future<int> recordInstall(Future<int> Function() install) async {
  final marker = File(
    '${Phone.configDirectory}${Platform.pathSeparator}install_failed',
  );
  if (marker.existsSync()) marker.deleteSync();
  try {
    return await install();
  } on PocketException catch (e) {
    await marker.parent.create(recursive: true);
    await marker.writeAsString(e.message);
    rethrow;
  }
}

/// Why the last install failed, if it did.
String? lastInstallFailure() {
  final marker = File(
    '${Phone.configDirectory}${Platform.pathSeparator}install_failed',
  );
  return marker.existsSync() ? marker.readAsStringSync() : null;
}

const _overridesHeader = '# Written by RR Pocket (dart pocket.dart pin)';

/// Sends the bundle: the kernel and the assets, not the engine's own
/// snapshots, which RR Pocket carries.
Future<int> install(String bundlePath) async {
  final phone = await Phone.load();
  final hello = await phone.hello();
  checkEngine(hello);
  // The bundle is <project>/build/flutter_assets.
  checkPlugins(hello, Directory(bundlePath).parent.parent);
  final bundle = Directory(bundlePath);
  const skipped = {
    'isolate_snapshot_data',
    'vm_snapshot_data',
    '.last_build_id',
  };
  final files = [
    for (final entity in bundle.listSync(recursive: true))
      if (entity is File && !skipped.contains(entity.uri.pathSegments.last))
        entity,
  ];
  final watch = Stopwatch()..start();
  var sent = 0;
  var raw = 0;
  await phone.call('POST', '/bundle/begin');
  for (final file in files) {
    final relative = file.path
        .substring(bundle.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    final bytes = await file.readAsBytes();
    final packed = GZipCodec(level: 1).encode(bytes);
    raw += bytes.length;
    sent += packed.length;
    await phone.call(
      'PUT',
      '/bundle/${Uri.encodeComponent(relative)}',
      body: packed,
      gzip: true,
    );
  }
  await phone.call('POST', '/bundle/commit');
  stdout.writeln(
    'Sent ${files.length} files, ${mb(raw)} as ${mb(sent)}, '
    'in ${watch.elapsedMilliseconds} ms.',
  );
  return 0;
}

/// Restarts RR Pocket into the bundle and prints the VM service's address,
/// which is how the tool finds it, then the app's `print` output, which is
/// how the tool shows it. Stays up like a running app would; when the tool
/// stops it, RR Pocket goes back to its own screen.
Future<int> run() async {
  if (lastInstallFailure() case final reason?) {
    throw PocketException('not running: $reason');
  }
  final phone = await Phone.load();
  final hello = await phone.hello();
  final result = await phone.call('POST', '/run');
  final vmPath = result['vmPath'] as String;
  final relay = hello['vmRelayPort'] as int;
  stdout.writeln(
    'The Dart VM service is listening on http://${phone.host}:$relay$vmPath',
  );
  final stopped = Completer<void>();
  for (final signal in [
    ProcessSignal.sigint,
    if (!Platform.isWindows) ProcessSignal.sigterm,
  ]) {
    signal.watch().listen((_) {
      if (!stopped.isCompleted) stopped.complete();
    });
  }
  unawaited(phone.logs().forEach(stdout.writeln).catchError((Object _) {}));
  await stopped.future;
  await phone.call('POST', '/stop').catchError((_) => <String, Object?>{});
  return 0;
}

Future<int> stop() async {
  await (await Phone.load()).call('POST', '/stop');
  return 0;
}

/// A plugin's Dart side in the project and its Kotlin side in RR Pocket must
/// be the same version, and a plugin RR Pocket lacks throws when called.
void checkPlugins(Map<String, Object?> hello, Directory project) {
  final carried = bundledPlugins(hello);
  final used = lockedVersions(project);
  if (carried.isEmpty || used == null) return;
  final differ = [
    for (final MapEntry(key: name, value: version) in carried.entries)
      if (used[name] case final theirs? when theirs != version)
        '$name $theirs (RR Pocket has $version)',
  ];
  if (differ.isNotEmpty) {
    throw PocketException(
      'plugin versions differ from RR Pocket\'s:\n  ${differ.join('\n  ')}\n'
      'Run `dart pocket.dart pin` in the project, then run again.',
    );
  }
  final missing = [
    for (final name in androidPlugins(project) ?? const <String>[])
      if (!carried.containsKey(name)) name,
  ];
  if (missing.isNotEmpty) {
    stderr.writeln(
      'RR Pocket does not carry ${missing.join(', ')}; calls to '
      '${missing.length == 1 ? 'it' : 'them'} will throw MissingPluginException.',
    );
  }
}

Map<String, String> bundledPlugins(Map<String, Object?> hello) => {
  for (final MapEntry(:key, :value)
      in ((hello['plugins'] as Map?) ?? const {}).entries)
    '$key': '$value',
};

/// Package versions from the project's pubspec.lock.
Map<String, String>? lockedVersions(Directory project) {
  final lock = File('${project.path}/pubspec.lock');
  if (!lock.existsSync()) return null;
  return {
    for (final match in RegExp(
      r'\n  (\w+):\n(?:    .*\n)*?    version: "([^"]+)"',
    ).allMatches(lock.readAsStringSync()))
      match.group(1)!: match.group(2)!,
  };
}

/// The Android plugin packages the project resolves, implementations
/// included (url_launcher_android), from Flutter's own list.
List<String>? androidPlugins(Directory project) {
  final file = File('${project.path}/.flutter-plugins-dependencies');
  if (!file.existsSync()) return null;
  final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final plugins = (json['plugins'] as Map?)?['android'] as List? ?? const [];
  return [for (final plugin in plugins) (plugin as Map)['name'] as String];
}

/// The project's kernel runs only on the engine that SDK was built for.
void checkEngine(Map<String, Object?> hello) {
  final ours = sdkVersions();
  if (ours == null) return;
  final theirs = hello['engineRevision'];
  if (theirs == ours['engineRevision']) return;
  throw PocketException(
    'this project uses Flutter ${ours['frameworkVersion']}, RR Pocket runs '
    'Flutter ${hello['flutterVersion']}. Use that version for this run '
    '(for example with fvm).',
  );
}

/// The running Flutter SDK's versions, from FLUTTER_ROOT (set by the tool).
Map<String, Object?>? sdkVersions() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return null;
  final file = File('$root/bin/cache/flutter.version.json');
  if (!file.existsSync()) return null;
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

String mb(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MB';

class Phone {
  Phone(this.host, this.port, this.code);

  final String host;
  final int port;
  final String code;
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 5);

  static String get configDirectory {
    final home = Platform.environment[Platform.isWindows ? 'APPDATA' : 'HOME'];
    return Platform.isWindows ? '$home\\rr_pocket' : '$home/.config/rr_pocket';
  }

  static File get _file =>
      File('$configDirectory${Platform.pathSeparator}device.json');

  static Future<Phone> load() async {
    if (!_file.existsSync()) {
      throw PocketException(
        'not paired yet: dart pocket.dart pair <address> <code>',
      );
    }
    final json = jsonDecode(await _file.readAsString()) as Map<String, Object?>;
    return Phone(
      json['host'] as String,
      json['port'] as int,
      json['code'] as String,
    );
  }

  Future<void> save() async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
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
    final json = jsonDecode(text) as Map<String, Object?>;
    if (response.statusCode == 401) {
      throw PocketException('the phone refused the pairing code; pair again');
    }
    if (response.statusCode != 200) {
      throw PocketException('$method $path: ${json['error'] ?? text}');
    }
    return json;
  }
}

class PocketException implements Exception {
  PocketException(this.message);

  final String message;
}
