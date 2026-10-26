import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:rr_pocket/src/models/models.dart';
import 'package:rr_pocket/src/services/flutter_device.dart';
import 'package:rr_pocket/src/services/phone.dart';
import 'package:rr_pocket/src/services/pinned_tls.dart';
import 'package:rr_pocket/src/services/project_files.dart';
import 'package:rr_pocket/src/services/reach.dart';

enum DoctorState { ok, warning, problem }

/// One thing `pocket doctor` checked: what it found, and what to do when
/// that is not right.
class DoctorCheck {
  const DoctorCheck(this.state, this.found, {this.fix});

  final DoctorState state;
  final String found;
  final String? fix;
}

/// Checks, in the order they depend on each other, everything that has to
/// be right for `flutter run -d pocket`: the pairing, the phone answering,
/// the Flutter on the PATH, the `pocket` device, and, given a [project],
/// its plugins. A phone that moved to a new address is followed there
/// ([reachPhone], with [discover]).
Future<List<DoctorCheck>> runDoctor({
  required PocketConfig config,
  required RunFlutter flutter,
  Directory? project,
  Future<List<FoundPhone>> Function()? discover,
}) async {
  final checks = <DoctorCheck>[];
  final paired = await Phone.tryLoad(config);
  paired?.close();
  Map<String, Object?>? hello;
  if (paired == null) {
    checks.add(const DoctorCheck(
      DoctorState.problem,
      'Not paired with a phone.',
      fix: 'Open RR Pocket on the phone, then run `pocket pair`.',
    ));
  } else {
    final address = PhoneAddress(paired.host, paired.port);
    try {
      final (phone, answer) = await reachPhone(
        config,
        discover: discover ?? () async => const [],
      ).timeout(const Duration(seconds: 15));
      hello = answer;
      phone.close();
      final now = PhoneAddress(phone.host, phone.port);
      final moved = switch ('$now' == '$address') {
        true => '',
        false => ', moved from $address; pairing updated',
      };
      checks.add(DoctorCheck(
        DoctorState.ok,
        'RR Pocket answers at $now (Flutter ${answer['flutterVersion']}, '
        '${bundledPlugins(answer).length} plugin packages, certificate '
        '${shortFingerprint(phone.fingerprint ?? '')}$moved).',
      ));
    } catch (error) {
      checks.add(DoctorCheck(
        DoctorState.problem,
        'RR Pocket at $address does not answer: ${describePhoneError(error)}.',
        fix: 'Open RR Pocket on the phone, on the same Wi-Fi as this '
            'computer.',
      ));
    }
  }

  final version = await flutter(['--version', '--machine']);
  final sdk = _json(version.stdout);
  final ours = '${sdk?['frameworkVersion'] ?? 'unknown'}';
  if (version.exitCode != 0 || sdk == null) {
    checks.add(const DoctorCheck(
      DoctorState.problem,
      'No working `flutter` on the PATH.',
      fix: 'Install Flutter, or put its bin folder on the PATH.',
    ));
  } else if (hello == null) {
    checks.add(DoctorCheck(DoctorState.ok, 'Flutter $ours on the PATH.'));
  } else if (sdk['engineRevision'] == hello['engineRevision']) {
    checks.add(DoctorCheck(
      DoctorState.ok,
      'Flutter $ours on the PATH, the same as RR Pocket.',
    ));
  } else {
    checks.add(DoctorCheck(
      DoctorState.problem,
      'Flutter $ours on the PATH; RR Pocket runs Flutter '
      '${hello['flutterVersion']}. Projects built with $ours won\'t run on it.',
      fix: 'Use Flutter ${hello['flutterVersion']} for the project, for '
          'example `fvm use ${hello['flutterVersion']}`.',
    ));
  }

  final settings = await flutter(['config', '--list']);
  final enabled =
      RegExp(r'enable-custom-devices:\s*true').hasMatch(settings.stdout);
  if (!enabled) {
    checks.add(const DoctorCheck(
      DoctorState.problem,
      'Flutter\'s custom devices are off, so `pocket` is not a device.',
      fix: 'Run `pocket pair` again: it turns them on.',
    ));
  } else {
    checks.add(await _registrationCheck(config));
  }

  if (project != null &&
      File('${project.path}${Platform.pathSeparator}pubspec.yaml')
          .existsSync()) {
    checks.addAll(_projectChecks(project, hello));
  }
  return checks;
}

/// Whether the `pocket` device Flutter calls still works: the Dart and the
/// package config it runs go away with the Flutter SDK or the pub cache
/// they came from, and then the device just stops showing up.
Future<DoctorCheck> _registrationCheck(PocketConfig config) async {
  const again = 'Run `pocket pair` again: it registers the device.';
  final record = config.registeredFile;
  if (!await record.exists()) {
    return const DoctorCheck(
      DoctorState.warning,
      'The `pocket` device may not be registered with Flutter.',
      fix: again,
    );
  }
  // A record from before it held the whole device is a list: no screenshots.
  if (_json(await record.readAsString())
      case {'ping': [final String dart, ...final rest]}) {
    const packages = '--packages=';
    final missing = [
      for (final path in [
        dart,
        for (final part in rest)
          if (part case final String option when option.startsWith(packages))
            option.substring(packages.length),
      ])
        if (!File(path).existsSync()) path,
    ];
    if (missing.isEmpty) {
      return const DoctorCheck(
        DoctorState.ok,
        'The `pocket` device is registered with Flutter.',
      );
    }
    return DoctorCheck(
      DoctorState.problem,
      'The `pocket` device runs ${missing.join(' and ')}, which no longer '
      'exists (a Flutter SDK or rr_pocket removed?), so Flutter does not '
      'list it.',
      fix: again,
    );
  }
  return const DoctorCheck(
    DoctorState.warning,
    'The `pocket` device was registered by an older rr_pocket, without '
    'screenshots.',
    fix: again,
  );
}

List<DoctorCheck> _projectChecks(
  Directory project,
  Map<String, Object?>? hello,
) {
  final used = lockedVersions(project);
  if (used == null) {
    return const [
      DoctorCheck(
        DoctorState.problem,
        'This project has no pubspec.lock.',
        fix: 'Run `flutter pub get`.',
      ),
    ];
  }
  if (hello == null) return const [];
  final check = PluginCheck.compare(
    carried: carriedFor(bundledPlugins(hello), project),
    used: used,
    android: androidPlugins(project) ?? const [],
  );
  final checks = <DoctorCheck>[];
  bool isBreaking(String line) =>
      check.breaking.contains(line.split(' ').first);
  final breaking = [
    for (final line in check.differ)
      if (isBreaking(line)) line,
  ];
  final pinnable = [
    for (final line in check.differ)
      if (!isBreaking(line)) line,
  ];
  if (pinnable.isNotEmpty) {
    checks.add(DoctorCheck(
      DoctorState.problem,
      'Plugin versions differ from RR Pocket\'s:\n'
      '${[for (final line in pinnable) '    $line'].join('\n')}',
      fix: 'Run `pocket pin` in the project.',
    ));
  }
  if (breaking.isNotEmpty) {
    checks.add(DoctorCheck(
      DoctorState.problem,
      'Plugin versions a breaking change from RR Pocket\'s:\n'
      '${[for (final line in breaking) '    $line'].join('\n')}',
      fix: 'Upgrade the project to RR Pocket\'s versions, or '
          '`pocket pin --all` and fix what no longer compiles.',
    ));
  }
  if (check.missing.isNotEmpty) {
    checks.add(DoctorCheck(
      DoctorState.warning,
      'RR Pocket does not carry ${check.missing.join(', ')}.',
      fix: 'Calls to those throw MissingPluginException on RR Pocket; run '
          'that part of the app on a regular build.',
    ));
  }
  if (checks.isEmpty) {
    checks.add(const DoctorCheck(
      DoctorState.ok,
      'The project\'s plugins match RR Pocket\'s.',
    ));
  }
  return checks;
}

/// [checks] as `pocket doctor` prints them.
String describeDoctor(List<DoctorCheck> checks) => [
      for (final check in checks)
        [
          '${_mark(check.state)} ${check.found}',
          if (check.fix case final fix?) '  → $fix',
        ].join('\n'),
    ].join('\n');

String _mark(DoctorState state) => switch (state) {
      DoctorState.ok => '✓',
      DoctorState.warning => '!',
      DoctorState.problem => '✗',
    };

Map<String, Object?>? _json(String text) {
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end < start) return null;
  try {
    final json = jsonDecode(text.substring(start, end + 1));
    if (json is Map<String, Object?>) return json;
    return null;
  } on FormatException {
    return null;
  }
}
