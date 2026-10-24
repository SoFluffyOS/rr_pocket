import 'dart:convert';
import 'dart:io';

import 'package:rr_pocket/src/models/models.dart';
import 'package:rr_pocket/src/services/phone.dart';

/// The pubspec.lock that resolves [project]: its own, or, for a member of a
/// pub workspace (`resolution: workspace`), the workspace root's above it.
/// Null before `flutter pub get`.
File? findLock(Directory project) {
  final own = _file(project, 'pubspec.lock');
  if (own.existsSync()) return own;
  final pubspec = _file(project, 'pubspec.yaml');
  if (!pubspec.existsSync() ||
      !RegExp(r'^resolution:\s*workspace', multiLine: true)
          .hasMatch(pubspec.readAsStringSync())) {
    return null;
  }
  var folder = project.absolute.parent;
  while (true) {
    final root = _file(folder, 'pubspec.yaml');
    if (root.existsSync() && isWorkspacePubspec(root.readAsStringSync())) {
      final lock = _file(folder, 'pubspec.lock');
      return switch (lock.existsSync()) {
        true => lock,
        false => null,
      };
    }
    final parent = folder.parent;
    if (parent.path == folder.path) return null;
    folder = parent;
  }
}

File _file(Directory folder, String name) =>
    File('${folder.path}${Platform.pathSeparator}$name');

/// Package versions from the pubspec.lock that resolves [project], or null
/// without one.
Map<String, String>? lockedVersions(Directory project) {
  final lock = findLock(project);
  if (lock == null) return null;
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

/// Writes pubspec_overrides.yaml next to the pubspec.lock that resolves the
/// project (a pub workspace's root, where pub reads overrides), pinning its
/// Android plugins to the versions RR Pocket carries, and returns the pins.
/// `flutter pub get` comes after.
Future<({File file, Map<String, String> pins})> writePins(
  Map<String, Object?> hello,
  Directory project,
) async {
  final lock = findLock(project);
  if (lock == null) {
    throw PocketException(
      'no pubspec.lock for ${project.path}; run flutter pub get',
    );
  }
  final used = parseLockedVersions(lock.readAsStringSync());
  final pins = pinsFor(carried: bundledPlugins(hello), used: used);
  final file = File(
    '${lock.parent.path}${Platform.pathSeparator}pubspec_overrides.yaml',
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
