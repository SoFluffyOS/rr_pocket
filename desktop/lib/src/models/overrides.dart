import 'package:rr_pocket/src/constants.dart';

/// A plugin RR Pocket carries at a version the project can't take without a
/// breaking change (semver): pinning it may not compile.
typedef BreakingPin = ({String name, String theirs, String ours});

/// The plugins of [carried] the project uses, at RR Pocket's versions,
/// except those across a breaking change, which go to `breaking` unless
/// [all].
///
/// A `*_flutter_libs` plugin carries only a native library for packages
/// released in lockstep with it (isar_community and its generator): the
/// project's packages that share its prefix and were at its version move
/// with it, or pub could not resolve the pin.
({Map<String, String> pins, List<BreakingPin> breaking}) planPins({
  required Map<String, String> carried,
  required Map<String, String> used,
  bool all = false,
}) {
  final pins = <String, String>{};
  final breaking = <BreakingPin>[];
  for (final MapEntry(key: name, value: version) in carried.entries) {
    final theirs = used[name];
    if (theirs == null) continue;
    if (!all && isBreakingChange(theirs, version)) {
      breaking.add((name: name, theirs: theirs, ours: version));
      continue;
    }
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
  return (pins: pins, breaking: breaking);
}

/// Every pin, breaking ones included.
Map<String, String> pinsFor({
  required Map<String, String> carried,
  required Map<String, String> used,
}) =>
    planPins(carried: carried, used: used, all: true).pins;

/// Whether going from version [from] to [to] can break code, by semver as
/// pub reads it: a different major version, for 0.x a different minor, for
/// 0.0.x a different patch. Going down counts too, since it can take away
/// what the project uses. Versions that don't parse count as breaking.
bool isBreakingChange(String from, String to) {
  final a = _version(from);
  final b = _version(to);
  if (a == null || b == null) return from != to;
  if (_compare(b, a) < 0) return true;
  if (a.$1 != b.$1) return true;
  if (a.$1 == 0 && a.$2 != b.$2) return true;
  return a.$1 == 0 && a.$2 == 0 && a.$3 != b.$3;
}

(int, int, int)? _version(String version) {
  final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(version);
  if (match == null) return null;
  final parts = [
    for (final group in [match.group(1), match.group(2), match.group(3)])
      int.tryParse(group ?? ''),
  ];
  if (parts case [final major?, final minor?, final patch?]) {
    return (major, minor, patch);
  }
  return null;
}

int _compare((int, int, int) a, (int, int, int) b) {
  if (a.$1 != b.$1) return a.$1.compareTo(b.$1);
  if (a.$2 != b.$2) return a.$2.compareTo(b.$2);
  return a.$3.compareTo(b.$3);
}

/// [breaking], one per line, for a message.
String describeBreaking(List<BreakingPin> breaking) => [
      for (final pin in breaking) '  ${pin.name} ${pin.theirs} -> ${pin.ours}',
    ].join('\n');

const _libsSuffix = '_flutter_libs';

/// Whether `pocket pin` wrote [overrides], so it may replace them.
bool isOurOverrides(String overrides) =>
    overrides.startsWith(overridesHeader) ||
    overrides.startsWith(oldOverridesHeader);

/// The pubspec_overrides.yaml that pins [pins], sorted by name.
/// Each pin notes what the project had before ([was]), so a later
/// `pocket pin` judges breaking changes against that, not its own pin.
String renderOverrides(
  Map<String, String> pins, {
  Map<String, String> was = const {},
}) {
  final names = pins.keys.toList()..sort();
  String line(String name) => switch (was[name]) {
        final before? when before != pins[name] =>
          '  $name: ${pins[name]}  # was $before\n',
        _ => '  $name: ${pins[name]}\n',
      };
  return '$overridesHeader: the Android plugin versions RR Pocket carries.\n'
      'dependency_overrides:\n'
      '${[for (final name in names) line(name)].join()}';
}

/// What `renderOverrides` noted the project had before each pin.
Map<String, String> parseWas(String overrides) => {
      for (final match in RegExp(
        r'^  (\w+): \S+  # was (\S+)$',
        multiLine: true,
      ).allMatches(overrides))
        if ((match.group(1), match.group(2)) case (final name?, final before?))
          name: before,
    };

/// The lines to add by hand when the project has its own overrides.
String overridesByHand(Map<String, String> pins) {
  final names = pins.keys.toList()..sort();
  return [for (final name in names) '  $name: ${pins[name]}'].join('\n');
}

/// "1 plugin", "3 plugins".
String plugins(int count) => switch (count) {
      1 => '1 plugin',
      _ => '$count plugins',
    };
