import 'dart:convert';

/// Package versions from a pubspec.lock, with either line ending.
Map<String, String> parseLockedVersions(String lock) => {
      for (final match in RegExp(
        r'\n  (\w+):\n(?:    .*\n)*?    version: "([^"]+)"',
      ).allMatches(lock.replaceAll('\r\n', '\n')))
        if ((match.group(1), match.group(2)) case (final name?, final version?))
          name: version,
    };

/// The Android plugin packages a project resolves, implementations
/// included (url_launcher_android), from Flutter's
/// `.flutter-plugins-dependencies`. Dev dependencies (integration_test) are
/// left out: they never run in the app.
List<String> parseAndroidPlugins(String flutterPluginsDependencies) {
  final json = jsonDecode(flutterPluginsDependencies);
  if (json is! Map) return const [];
  final plugins = json['plugins'];
  if (plugins is! Map) return const [];
  final android = plugins['android'];
  if (android is! List) return const [];
  return [
    for (final plugin in android)
      if (plugin is Map &&
          plugin['name'] is String &&
          plugin['dev_dependency'] != true)
        plugin['name'] as String,
  ];
}

/// The plugins RR Pocket carries and their versions, from its `/hello`.
Map<String, String> bundledPlugins(Map<String, Object?> hello) {
  final plugins = hello['plugins'];
  if (plugins is! Map) return const {};
  return {
    for (final MapEntry(:key, :value) in plugins.entries) '$key': '$value',
  };
}

/// How a project's plugins compare with the ones RR Pocket carries.
///
/// A plugin's Dart side in the project and its Kotlin side in RR Pocket must
/// be the same version, and a plugin RR Pocket lacks throws when called.
class PluginCheck {
  const PluginCheck({required this.differ, required this.missing});

  factory PluginCheck.compare({
    required Map<String, String> carried,
    required Map<String, String> used,
    required List<String> android,
  }) {
    return PluginCheck(
      differ: [
        for (final MapEntry(key: name, value: version) in carried.entries)
          if (used[name] case final theirs? when theirs != version)
            '$name $theirs (RR Pocket has $version)',
      ],
      missing: [
        for (final name in android)
          if (!carried.containsKey(name)) name,
      ],
    );
  }

  /// `name version (RR Pocket has version)`, one per plugin.
  final List<String> differ;

  /// Android plugins the project uses that RR Pocket does not carry.
  final List<String> missing;
}
