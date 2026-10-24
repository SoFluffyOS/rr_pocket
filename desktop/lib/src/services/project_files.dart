import 'dart:convert';
import 'dart:io';

import 'package:rr_pocket/src/models/models.dart';
import 'package:rr_pocket/src/services/phone.dart';

/// Package versions from the project's pubspec.lock, or null without one.
Map<String, String>? lockedVersions(Directory project) {
  final lock = File('${project.path}${Platform.pathSeparator}pubspec.lock');
  if (!lock.existsSync()) return null;
  return parseLockedVersions(lock.readAsStringSync());
}

/// The Android plugin packages the project resolves, or null before
/// `flutter pub get`.
List<String>? androidPlugins(Directory project) {
  final file = File(
    '${project.path}${Platform.pathSeparator}.flutter-plugins-dependencies',
  );
  if (!file.existsSync()) return null;
  return parseAndroidPlugins(file.readAsStringSync());
}

/// The running Flutter SDK's versions, from FLUTTER_ROOT (set by the tool).
Map<String, Object?>? sdkVersions(Map<String, String> environment) {
  final root = environment['FLUTTER_ROOT'];
  if (root == null) return null;
  final file = File('$root/bin/cache/flutter.version.json');
  if (!file.existsSync()) return null;
  final json = jsonDecode(file.readAsStringSync());
  if (json is Map<String, Object?>) return json;
  return null;
}

/// Writes the project's pubspec_overrides.yaml, pinning its Android plugins
/// to the versions RR Pocket carries, and returns the pins. `flutter pub
/// get` comes after.
Future<({File file, Map<String, String> pins})> writePins(
  Map<String, Object?> hello,
  Directory project,
) async {
  final used = lockedVersions(project);
  if (used == null) {
    throw PocketException(
      'no pubspec.lock in ${project.path}; run flutter pub get',
    );
  }
  final pins = pinsFor(carried: bundledPlugins(hello), used: used);
  final file = File(
    '${project.path}${Platform.pathSeparator}pubspec_overrides.yaml',
  );
  if (file.existsSync() && !isOurOverrides(file.readAsStringSync())) {
    throw PocketException(
      '${file.path} exists and is not ours; add these by hand:\n'
      '${overridesByHand(pins)}',
    );
  }
  await file.writeAsString(renderOverrides(pins));
  return (file: file, pins: pins);
}
