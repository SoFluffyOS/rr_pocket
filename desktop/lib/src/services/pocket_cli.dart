import 'dart:async';
import 'dart:io';

import 'package:rr_pocket/src/constants.dart';
import 'package:rr_pocket/src/models/models.dart';
import 'package:rr_pocket/src/services/computer.dart';
import 'package:rr_pocket/src/services/discovery.dart';
import 'package:rr_pocket/src/services/doctor.dart';
import 'package:rr_pocket/src/services/flutter_device.dart';
import 'package:rr_pocket/src/services/pair_listener.dart';
import 'package:rr_pocket/src/services/pair_request.dart';
import 'package:rr_pocket/src/services/phone.dart';
import 'package:rr_pocket/src/services/project_files.dart';
import 'package:rr_pocket/src/services/vm_tunnel.dart';

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
  PocketCli({
    PocketConfig? config,
    Map<String, String>? environment,
    Future<List<FoundPhone>> Function()? discover,
    Future<List<String>> Function()? addresses,
    RunFlutter? flutter,
    Future<List<String>> Function()? helperCommand,
    String? computer,
    String Function()? newToken,
    this.pairPort = 0,
  })  : config = config ?? PocketConfig(),
        _newToken = newToken ?? newPairingToken,
        environment = environment ?? Platform.environment,
        _discover = discover ?? discoverPhones,
        _addresses = addresses ?? localAddresses,
        _flutter = flutter ?? runFlutterProcess,
        _helperCommand = helperCommand ?? currentHelperCommand,
        _computer = computer ?? computerName();

  final PocketConfig config;
  final Future<List<FoundPhone>> Function() _discover;
  final Future<List<String>> Function() _addresses;
  final RunFlutter _flutter;
  final Future<List<String>> Function() _helperCommand;
  final String _computer;
  final String Function() _newToken;

  /// The port the QR listener takes; any free one by default.
  final int pairPort;

  /// Flutter sets FLUTTER_ROOT when it calls the tool.
  final Map<String, String> environment;

  /// Runs [args] and returns the exit code.
  Future<int> call(List<String> args) async {
    try {
      return await switch (args) {
        ['pair'] => pairFound(),
        ['pair', '--qr'] => pairByQr(),
        ['pair', final address, final code] => pair(address, code),
        ['forget'] => forget(),
        ['doctor'] => doctor(Directory.current),
        ['ping'] => ping(),
        ['pin'] => pin(Directory.current),
        ['pin', '--all'] => pin(Directory.current, all: true),
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
      'usage: pocket pair                          (once: finds the phone)\n'
      '       pocket pair --qr                     (shows a QR code to scan)\n'
      '       pocket pair <phone address> <code>   (typed, as the phone shows)\n'
      '       pocket forget                        (unpairs this computer)\n'
      '       pocket doctor                        (checks the setup, and a project)\n'
      '       pocket pin [--all]                   (in a project; --all: breaking changes too)\n'
      '       then: flutter run -d $deviceId',
    );
    return 64;
  }

  /// Pairs with the phone typed in: the last fallback (docs/pairing.md).
  Future<int> pair(String address, String code) async {
    final parsed = PhoneAddress.tryParse(address);
    if (parsed == null) {
      throw PocketException(
        '"$address" is not an address; type it as RR Pocket shows it',
      );
    }
    final phone = Phone(parsed.host, parsed.port, normalizePairingCode(code));
    return _finish(phone, await phone.hello());
  }

  /// Finds RR Pocket on the network and asks it to pair; the phone asks its
  /// user. Shows a QR code when no phone answers.
  Future<int> pairFound() async {
    stdout.writeln('Looking for RR Pocket on this network...');
    final phones = await _discover();
    if (phones.isEmpty) {
      stdout.writeln(
        'None found: the network may block that. Scan this QR code '
        'instead.\n',
      );
      return pairByQr();
    }
    final found = switch (phones) {
      [final only] => only,
      _ => _choose(phones),
    };
    if (found == null) return pairByQr();
    stdout.writeln(
      'Found ${found.name} at ${found.host}. Tap Allow on the phone...',
    );
    final given = await requestPairing(found.host, found.port, _computer);
    final phone = Phone(
      found.host,
      found.port,
      given.code,
      fingerprint: given.fingerprint,
    );
    return _finish(phone, await phone.hello());
  }

  /// Shows a QR code for the phone to scan, and waits for it.
  Future<int> pairByQr() async {
    final listener = await PairListener.start(
      computer: _computer,
      hosts: await _addresses(),
      verify: (phone) => phone.hello().timeout(const Duration(seconds: 10)),
      token: _newToken(),
      port: pairPort,
    );
    final cancel = ProcessSignal.sigint.watch().listen((_) {
      unawaited(listener.close());
    });
    try {
      stdout.writeln(
        qrTerminal(
          listener.link.toUri().toString(),
          ansi: stdout.hasTerminal && stdout.supportsAnsiEscapes,
        ),
      );
      stdout.writeln(
        '\nScan it with RR Pocket (Scan QR code) or the phone\'s camera, '
        'then tap Allow.\n'
        'Or type what the phone shows: pocket pair <address> <code>',
      );
      final paired = await listener.paired;
      return await _finish(paired.phone, paired.hello);
    } finally {
      await cancel.cancel();
      await listener.close();
    }
  }

  /// Asks which phone, or null for a QR code instead.
  FoundPhone? _choose(List<FoundPhone> phones) {
    stdout.writeln('Found ${phones.length} phones running RR Pocket:');
    for (final (index, phone) in phones.indexed) {
      stdout.writeln('  ${index + 1}. ${phone.name} (${phone.host})');
    }
    stdout.write('Pair with which? [1-${phones.length}, or q for a QR code] ');
    final answer = stdin.readLineSync()?.trim() ?? '';
    final index = int.tryParse(answer);
    if (index == null || index < 1 || index > phones.length) return null;
    return phones[index - 1];
  }

  Future<int> _finish(Phone phone, Map<String, Object?> hello) async {
    final address = PhoneAddress(phone.host, phone.port);
    await phone.save(config);
    stdout.writeln(
      'Paired with ${hello['name']} at $address '
      '(Flutter ${hello['flutterVersion']}).',
    );
    await ensureDeviceRegistered(
      _flutter,
      await _helperCommand(),
      config,
      force: true,
    );
    stdout.writeln('Run a project on it with: flutter run -d $deviceId');
    return 0;
  }

  /// Checks the setup, and [project] when it is one, and says what to fix.
  Future<int> doctor(Directory project) async {
    final checks = await runDoctor(
      config: config,
      flutter: _flutter,
      project: project,
    );
    stdout.writeln(describeDoctor(checks));
    return switch (checks.any((check) => check.state == DoctorState.problem)) {
      true => 1,
      false => 0,
    };
  }

  /// Forgets the paired phone. Flutter drops the device when its ping next
  /// fails; the phone keeps its code, so pairing again works.
  Future<int> forget() async {
    final phone = await Phone.tryLoad(config);
    if (phone == null) {
      stdout.writeln('RR Pocket is not paired with a phone.');
      return 0;
    }
    phone.close();
    for (final file in [config.deviceFile, config.installFailedFile]) {
      if (file.existsSync()) file.deleteSync();
    }
    stdout.writeln(
      'Forgot RR Pocket at ${PhoneAddress(phone.host, phone.port)}.',
    );
    return 0;
  }

  Future<int> ping() async {
    await (await Phone.load(config)).hello();
    return 0;
  }

  /// Pins the project's Android plugins to the versions RR Pocket carries,
  /// in its pubspec_overrides.yaml, then resolves.
  Future<int> pin(Directory project, {bool all = false}) async {
    final hello = await (await Phone.load(config)).hello();
    final written = await writePins(hello, project, all: all);
    stdout.writeln(
      'Pinned ${plugins(written.pins.length)} in ${written.file.path}.',
    );
    if (written.breaking.isNotEmpty) {
      stdout.writeln(
        'Not pinned, a breaking change from what the project uses:\n'
        '${describeBreaking(written.breaking)}\n'
        'Upgrade the project to those versions, or pin them anyway with '
        '`pocket pin --all` and fix what no longer compiles.',
      );
    }
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
  ///
  /// The address is this computer's end of a [VmTunnel] to the phone's VM
  /// relay, which speaks TLS; it lasts as long as this does.
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
    final relay = switch (hello['vmRelayPort']) {
      final int port => port,
      _ => throw const PocketException(
          'this RR Pocket has no VM relay; update it',
        ),
    };
    final tunnel = await VmTunnel.start(
      host: phone.host,
      port: relay,
      trusts: phone.trusts,
    );
    stdout.writeln(
      'The Dart VM service is listening on '
      'http://127.0.0.1:${tunnel.port}$vmPath',
    );
    unawaited(phone.logs().forEach(stdout.writeln).catchError((Object _) {}));
    await stopped.future;
    await phone.call('POST', '/stop').catchError((_) => <String, Object?>{});
    await tunnel.close();
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
  final carried = carriedFor(bundledPlugins(hello), project);
  final used = lockedVersions(project);
  if (bundledPlugins(hello).isEmpty) return;
  if (used == null) {
    stderr.writeln(
      'RR Pocket: found no pubspec.lock for ${project.path}, so plugin '
      'versions are not checked.',
    );
    return;
  }
  final check = PluginCheck.compare(
    carried: carried,
    used: used,
    android: androidPlugins(project) ?? const [],
  );
  if (check.differ.isNotEmpty) {
    final advice = switch (check.breaking.length == check.differ.length) {
      true => 'Upgrade the project to RR Pocket\'s versions, or run it on a '
          'custom build of RR Pocket.',
      false => 'Run `pocket pin` in the project (in Lumide: RR Pocket: Match '
          'Plugin Versions), then run again.',
    };
    final breaking = switch (check.breaking.isEmpty) {
      true => '',
      false => '\nA breaking change can\'t be pinned safely: upgrade the '
          'project to RR Pocket\'s version of ${check.breaking.join(', ')}, '
          'or `pocket pin --all` and fix what no longer compiles.',
    };
    throw PocketException(
      'plugin versions differ from RR Pocket\'s:\n'
      '  ${check.differ.join('\n  ')}\n'
      '$advice$breaking',
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
