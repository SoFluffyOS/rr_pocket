import 'dart:convert';

import 'package:rr_pocket/src/constants.dart';

/// The `pocket` custom device: Flutter calls [helper] with `ping`,
/// `install`, `run` and `uninstall`.
Map<String, Object?> deviceConfig(List<String> helper) {
  List<String> call(List<String> args) => [...helper, ...args];
  return {
    'id': deviceId,
    'label': pluginName,
    'sdkNameAndVersion': 'RR Pocket over Wi-Fi',
    'platform': 'linux-arm64',
    'enabled': true,
    'ping': call(['ping']),
    'pingSuccessRegex': null,
    'postBuild': null,
    'install': call(['install', r'${localPath}', r'${appName}']),
    'uninstall': call(['uninstall', r'${appName}']),
    'runDebug': call(['run', r'${appName}']),
    'forwardPort': null,
    'forwardPortSuccessRegex': null,
    'screenshot': null,
    'readLogs': null,
  };
}

/// The command Flutter runs to reach this tool, saved in its settings.
///
/// It runs `package:rr_pocket/pocket.dart` with the package config this
/// copy runs with ([packageConfig]): an installed package's stays at the
/// same path across upgrades, unlike the snapshot pub runs, which is named
/// after the Dart version. Not `dart pub global run`: that runs the tool in
/// a child process, which never hears Flutter stop it, so the app would
/// stay open on the phone. Without a package config, [script] itself.
List<String> helperCommand({
  required String dart,
  required String? packageConfig,
  required String script,
}) {
  if (packageConfig == null) return [dart, script];
  return [dart, '--packages=$packageConfig', cliLibrary];
}

/// The Flutter SDK's folder, from `flutter --version --machine`, whose
/// output can start with other lines (a lock wait, an upgrade notice).
String? parseFlutterRoot(String machineVersion) {
  final start = machineVersion.indexOf('{');
  final end = machineVersion.lastIndexOf('}');
  if (start < 0 || end < start) return null;
  try {
    final json = jsonDecode(machineVersion.substring(start, end + 1));
    if (json case {'flutterRoot': final String root} when root.isNotEmpty) {
      return root;
    }
    return null;
  } on FormatException {
    return null;
  }
}

/// The `dart` that ships with the Flutter SDK at [flutterRoot].
String flutterDart(String flutterRoot, {required bool windows}) {
  final executable = switch (windows) {
    true => 'dart.exe',
    false => 'dart',
  };
  final separator = switch (windows) {
    true => r'\',
    false => '/',
  };
  return [flutterRoot, 'bin', 'cache', 'dart-sdk', 'bin', executable]
      .join(separator);
}
