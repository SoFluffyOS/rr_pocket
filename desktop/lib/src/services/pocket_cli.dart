import 'dart:async';
import 'dart:io';

import 'package:rr_pocket/src/constants.dart';
import 'package:rr_pocket/src/models/models.dart';
import 'package:rr_pocket/src/services/flutter_device.dart';
import 'package:rr_pocket/src/services/phone.dart';
import 'package:rr_pocket/src/services/project_files.dart';

/// The `pocket` command: pairs with the phone, then stands behind the
/// `pocket` custom device, so a stock `flutter run -d pocket` runs a project
/// on the phone over Wi-Fi. No adb, no Android SDK.
///
/// ```sh
/// pocket pair <phone address> <code>     # once
/// pocket pin                             # in a project
/// flutter run -d pocket
/// ```
///
/// Flutter calls the rest: `ping`, `install <flutter_assets> <app>`,
/// `run <app>`, `uninstall <app>`.
class PocketCli {
  PocketCli({PocketConfig? config, Map<String, String>? environment})
      : config = config ?? PocketConfig(),
        environment = environment ?? Platform.environment;

  final PocketConfig config;

  /// Flutter sets FLUTTER_ROOT when it calls the tool.
  final Map<String, String> environment;

  /// Runs [args] and returns the exit code.
  Future<int> call(List<String> args) async {
    try {
      return await switch (args) {
        ['pair', final address, final code] => pair(address, code),
        ['ping'] => ping(),
        ['pin'] => pin(Directory.current),
        ['install', final bundle, _] => _recordInstall(() => install(bundle)),
        ['run', ...] => run(),
        ['uninstall', ...] => stop(),
        _ => usage(),
      };
    } on PocketException catch (e) {
      stderr.writeln('RR Pocket: ${e.message}');
      return 1;
    } on SocketException catch (e) {
      stderr.writeln(
        'RR Pocket: cannot reach the phone (${e.message}). Is RR Pocket '
        'open, on the same Wi-Fi?',
      );
      return 1;
    } catch (e) {
      stderr.writeln('RR Pocket: ${describePhoneError(e)}');
      return 1;
    }
  }

  Future<int> usage() async {
    stderr.writeln(
      'usage: pocket pair <phone address> <code>   (once)\n'
      '       pocket pin                           (in a project)\n'
      '       then: flutter run -d $deviceId',
    );
    return 64;
  }

  Future<int> pair(String address, String code) async {
    final parsed = PhoneAddress.tryParse(address);
    if (parsed == null) {
      throw PocketException(
        '"$address" is not an address; type it as RR Pocket shows it',
      );
    }
    final phone = Phone(parsed.host, parsed.port, normalizePairingCode(code));
    final hello = await phone.hello();
    await phone.save(config);
    stdout.writeln(
      'Paired with ${hello['name']} at $parsed '
      '(Flutter ${hello['flutterVersion']}).',
    );
    await registerDevice(runFlutterProcess, await currentHelperCommand());
    stdout.writeln('Run a project on it with: flutter run -d $deviceId');
    return 0;
  }

  Future<int> ping() async {
    await (await Phone.load(config)).hello();
    return 0;
  }

  /// Pins the project's Android plugins to the versions RR Pocket carries,
  /// in its pubspec_overrides.yaml, then resolves.
  Future<int> pin(Directory project) async {
    final hello = await (await Phone.load(config)).hello();
    final written = await writePins(hello, project);
    stdout.writeln(
      'Pinned ${written.pins.length} plugins in ${written.file.path}.',
    );
    final got = await runFlutterProcess(
      ['pub', 'get'],
      workingDirectory: project.path,
    );
    stdout.write(got.stdout);
    stderr.write(got.stderr);
    return got.exitCode;
  }

  /// Flutter runs the app even when install failed (it only logs the
  /// failure), so install leaves its outcome where run checks it, whatever
  /// the failure: otherwise run would start the bundle sent before.
  Future<int> _recordInstall(Future<int> Function() install) async {
    final marker = config.installFailedFile;
    if (marker.existsSync()) marker.deleteSync();
    try {
      return await install();
    } catch (e) {
      await marker.parent.create(recursive: true);
      await marker.writeAsString(describePhoneError(e));
      rethrow;
    }
  }

  /// Sends the bundle: the kernel and the assets, not the engine's own
  /// snapshots, which RR Pocket carries.
  Future<int> install(String bundlePath) async {
    final phone = await Phone.load(config);
    final hello = await phone.hello();
    checkEngine(hello, sdkVersions(environment));
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
      'Sent ${files.length} files, ${_mb(raw)} as ${_mb(sent)}, '
      'in ${watch.elapsedMilliseconds} ms.',
    );
    return 0;
  }

  /// Restarts RR Pocket into the bundle and prints the VM service's
  /// address, which is how Flutter finds it, then the app's `print` output,
  /// which is how Flutter shows it. Stays up like a running app would; when
  /// Flutter stops it, RR Pocket goes back to its own screen.
  Future<int> run() async {
    final marker = config.installFailedFile;
    if (marker.existsSync()) {
      throw PocketException('not running: ${marker.readAsStringSync()}');
    }
    // Listening first: Flutter may stop the run as soon as it has the
    // VM service's address.
    final stopped = Completer<void>();
    for (final signal in [
      ProcessSignal.sigint,
      if (!Platform.isWindows) ProcessSignal.sigterm,
    ]) {
      signal.watch().listen((_) {
        if (!stopped.isCompleted) stopped.complete();
      });
    }
    final phone = await Phone.load(config);
    final hello = await phone.hello();
    final result = await phone.call('POST', '/run');
    final vmPath = result['vmPath'];
    final relay = hello['vmRelayPort'];
    stdout.writeln(
      'The Dart VM service is listening on http://${phone.host}:$relay$vmPath',
    );
    unawaited(phone.logs().forEach(stdout.writeln).catchError((Object _) {}));
    await stopped.future;
    await phone.call('POST', '/stop').catchError((_) => <String, Object?>{});
    return 0;
  }

  Future<int> stop() async {
    await (await Phone.load(config)).call('POST', '/stop');
    return 0;
  }
}

/// The project's kernel runs only on the engine its SDK was built for.
void checkEngine(Map<String, Object?> hello, Map<String, Object?>? sdk) {
  if (sdk == null) return;
  if (hello['engineRevision'] == sdk['engineRevision']) return;
  throw PocketException(
    'this project uses Flutter ${sdk['frameworkVersion']}, RR Pocket runs '
    'Flutter ${hello['flutterVersion']}. Use that version for this run '
    '(for example with fvm).',
  );
}

/// Stops on plugin versions that differ from RR Pocket's, and warns about
/// plugins it lacks.
void checkPlugins(Map<String, Object?> hello, Directory project) {
  final carried = bundledPlugins(hello);
  final used = lockedVersions(project);
  if (carried.isEmpty || used == null) return;
  final check = PluginCheck.compare(
    carried: carried,
    used: used,
    android: androidPlugins(project) ?? const [],
  );
  if (check.differ.isNotEmpty) {
    throw PocketException(
      'plugin versions differ from RR Pocket\'s:\n'
      '  ${check.differ.join('\n  ')}\n'
      'Run `pocket pin` in the project (in Lumide: RR Pocket: Match Plugin '
      'Versions), then run again.',
    );
  }
  final missing = check.missing;
  if (missing.isEmpty) return;
  final pronoun = switch (missing.length) {
    1 => 'it',
    _ => 'them',
  };
  stderr.writeln(
    'RR Pocket does not carry ${missing.join(', ')}; calls to $pronoun will '
    'throw MissingPluginException.',
  );
}

String _mb(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MB';
