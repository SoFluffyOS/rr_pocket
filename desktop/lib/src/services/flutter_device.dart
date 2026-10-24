import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:rr_pocket/src/constants.dart';
import 'package:rr_pocket/src/models/models.dart';
import 'package:rr_pocket/src/services/phone.dart';

typedef FlutterResult = ({int exitCode, String stdout, String stderr});

/// Runs `flutter` with these arguments: straight from the `pocket` command,
/// through Lumide's shell from the plugin.
typedef RunFlutter = Future<FlutterResult> Function(
  List<String> arguments, {
  String? workingDirectory,
});

/// `flutter` from the PATH, as a terminal would run it.
Future<FlutterResult> runFlutterProcess(
  List<String> arguments, {
  String? workingDirectory,
}) async {
  final result = await Process.run(
    Platform.isWindows ? 'flutter.bat' : executableFlutter,
    arguments,
    workingDirectory: workingDirectory,
  );
  return (
    exitCode: result.exitCode,
    stdout: '${result.stdout}',
    stderr: '${result.stderr}',
  );
}

/// Adds the `pocket` custom device to Flutter's settings, replacing an
/// older entry, so `flutter run -d pocket` calls [helper].
Future<void> registerDevice(RunFlutter flutter, List<String> helper) async {
  await flutter(['config', '--enable-custom-devices']);
  await flutter(['custom-devices', 'delete', '-d', deviceId]);
  final added = await flutter([
    'custom-devices',
    'add',
    '--json=${jsonEncode(deviceConfig(helper))}',
  ]);
  if (added.exitCode != 0) {
    throw PocketException(
      'flutter custom-devices add failed: ${added.stderr}${added.stdout}',
    );
  }
}

/// Registers the `pocket` device unless it already is, with [helper];
/// returns whether it had to. A running `flutter daemon` reads custom devices
/// only when it starts, but pings them on every poll: registered before
/// pairing, the device appears as soon as pairing makes its ping succeed.
Future<bool> ensureDeviceRegistered(
  RunFlutter flutter,
  List<String> helper,
  PocketConfig config, {
  bool force = false,
}) async {
  final record = config.registeredFile;
  final wanted = jsonEncode(helper);
  if (!force &&
      await record.exists() &&
      await record.readAsString() == wanted) {
    return false;
  }
  await registerDevice(flutter, helper);
  await record.parent.create(recursive: true);
  await record.writeAsString(wanted);
  return true;
}

/// How Flutter calls this running copy of the tool back (see
/// [helperCommand]), with [dart] or the one running this.
Future<List<String>> currentHelperCommand({String? dart}) async {
  final config = await Isolate.packageConfig;
  return helperCommand(
    dart: dart ?? Platform.resolvedExecutable,
    packageConfig: switch (config) {
      final uri? when uri.isScheme('file') => uri.toFilePath(),
      _ => null,
    },
    script: Platform.script.toFilePath(),
  );
}

/// The `dart` of the Flutter SDK [flutter] runs, or null when it cannot
/// tell.
Future<String?> findFlutterDart(RunFlutter flutter) async {
  final result = await flutter(['--version', '--machine']);
  if (result.exitCode != 0) return null;
  final root = parseFlutterRoot(result.stdout);
  if (root == null) return null;
  final dart = flutterDart(root, windows: Platform.isWindows);
  if (!await File(dart).exists()) return null;
  return dart;
}
