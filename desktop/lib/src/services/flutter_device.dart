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

/// How Flutter calls this running copy of the tool back (see
/// [helperCommand]).
Future<List<String>> currentHelperCommand() async {
  return helperCommand(
    dart: Platform.resolvedExecutable,
    script: Platform.script,
    packageRoot: await _packageRoot(),
    separator: Platform.pathSeparator,
  );
}

/// This package's folder: from the package config, or the script's.
Future<String> _packageRoot() async {
  try {
    final library = await Isolate.resolvePackageUri(
      Uri.parse('package:$packageName/$packageName.dart'),
    );
    if (library != null && library.isScheme('file')) {
      return File.fromUri(library).parent.parent.path;
    }
  } catch (_) {
    // Running without a package config.
  }
  return File.fromUri(Platform.script).parent.parent.path;
}
