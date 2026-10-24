import 'dart:io';

/// What this build of RR Pocket carries. A project runs here only if it was
/// compiled by the same Flutter version and uses no plugin outside the list.
abstract final class BuildInfo {
  /// Set by tool/build_apk.sh from `flutter --version`.
  static const flutterVersion = String.fromEnvironment(
    'RR_FLUTTER_VERSION',
    defaultValue: 'unknown',
  );

  static String get dartVersion => Platform.version.split(' ').first;

  /// The app-facing plugin packages in pubspec.yaml.
  static const plugins = ['path_provider', 'shared_preferences'];
}
