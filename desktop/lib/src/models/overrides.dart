import 'package:rr_pocket/src/constants.dart';

/// The plugins of [carried] the project uses, at RR Pocket's versions.
///
/// A `*_flutter_libs` plugin carries only a native library for packages
/// released in lockstep with it (isar_community and its generator): the
/// project's packages that share its prefix and were at its version move
/// with it, or pub could not resolve the pin.
Map<String, String> pinsFor({
  required Map<String, String> carried,
  required Map<String, String> used,
}) {
  final pins = <String, String>{};
  for (final MapEntry(key: name, value: version) in carried.entries) {
    final theirs = used[name];
    if (theirs == null) continue;
    pins[name] = version;
    if (!name.endsWith(_libsSuffix)) continue;
    final family = name.substring(0, name.length - _libsSuffix.length);
    for (final MapEntry(key: sibling, value: siblingVersion) in used.entries) {
      if (sibling == name || siblingVersion != theirs) continue;
      if (sibling == family || sibling.startsWith('${family}_')) {
        pins[sibling] = version;
      }
    }
  }
  return pins;
}

const _libsSuffix = '_flutter_libs';

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
