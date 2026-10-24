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
/// An installed package runs from a snapshot named after the Dart version
/// ([script] ends in `.snapshot`), which an upgrade replaces, so it is
/// called through `dart pub global run`. Otherwise this is a checkout, and
/// Flutter runs `bin/pocket.dart` from [packageRoot].
List<String> helperCommand({
  required String dart,
  required Uri script,
  required String packageRoot,
  required String separator,
}) {
  if (script.path.endsWith('.snapshot')) {
    return [dart, 'pub', 'global', 'run', '$packageName:$cliExecutable'];
  }
  return [
    dart,
    [packageRoot, 'bin', '$cliExecutable.dart'].join(separator)
  ];
}
