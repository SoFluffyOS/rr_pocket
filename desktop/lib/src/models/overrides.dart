import 'package:rr_pocket/src/constants.dart';

/// The plugins of [carried] the project uses, at RR Pocket's versions.
Map<String, String> pinsFor({
  required Map<String, String> carried,
  required Map<String, String> used,
}) =>
    {
      for (final MapEntry(key: name, value: version) in carried.entries)
        if (used.containsKey(name)) name: version,
    };

/// Whether `pocket pin` wrote [overrides], so it may replace them.
bool isOurOverrides(String overrides) =>
    overrides.startsWith(overridesHeader) ||
    overrides.startsWith(oldOverridesHeader);

/// The pubspec_overrides.yaml that pins [pins], sorted by name.
String renderOverrides(Map<String, String> pins) {
  final names = pins.keys.toList()..sort();
  return '$overridesHeader: the Android plugin versions RR Pocket carries.\n'
      'dependency_overrides:\n'
      '${[for (final name in names) '  $name: ${pins[name]}\n'].join()}';
}

/// The lines to add by hand when the project has its own overrides.
String overridesByHand(Map<String, String> pins) {
  final names = pins.keys.toList()..sort();
  return [for (final name in names) '  $name: ${pins[name]}'].join('\n');
}
