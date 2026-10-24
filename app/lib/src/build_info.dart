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
  static const plugins = [
    'audio_session',
    'battery_plus',
    'camera',
    'connectivity_plus',
    'device_info_plus',
    'file_picker',
    'flutter_local_notifications',
    'flutter_secure_storage',
    'geolocator',
    'gms_check',
    'image_picker',
    'in_app_review',
    'isar_community_flutter_libs',
    'just_audio',
    'local_auth',
    'package_info_plus',
    'path_provider',
    'permission_handler',
    'qr_code_scanner_plus',
    'record',
    'sensors_plus',
    'share_plus',
    'shared_preferences',
    'sqflite',
    'url_launcher',
    'vibration',
    'video_player',
    'wakelock_plus',
    'webview_flutter',
  ];
}
