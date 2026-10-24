import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:rr_pocket/src/models/models.dart';
import 'package:rr_pocket/src/services/flutter_device.dart';
import 'package:rr_pocket/src/services/phone.dart';
import 'package:rr_pocket/src/services/project_files.dart';

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
/// its plugins.
Future<List<DoctorCheck>> runDoctor({
  required PocketConfig config,
  required RunFlutter flutter,
  Directory? project,
}) async {
  final checks = <DoctorCheck>[];
  final phone = await Phone.tryLoad(config);
  Map<String, Object?>? hello;
  if (phone == null) {
    checks.add(const DoctorCheck(
      DoctorState.problem,
      'Not paired with a phone.',
      fix: 'Open RR Pocket on the phone, then run `pocket pair`.',
    ));
  } else {
    final address = PhoneAddress(phone.host, phone.port);
    try {
      hello = await phone.hello().timeout(const Duration(seconds: 10));
      checks.add(DoctorCheck(
        DoctorState.ok,
        'RR Pocket answers at $address (Flutter ${hello['flutterVersion']}, '
        '${bundledPlugins(hello).length} plugin packages).',
      ));
    } catch (error) {
      checks.add(DoctorCheck(
        DoctorState.problem,
        'RR Pocket at $address does not answer: ${describePhoneError(error)}.',
        fix: 'Open RR Pocket on the phone, on the same Wi-Fi as this '
            'computer. If its address changed, run `pocket pair` again.',
      ));
    } finally {
      phone.close();
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
  } else if (!await config.registeredFile.exists()) {
    checks.add(const DoctorCheck(
      DoctorState.warning,
      'The `pocket` device may not be registered with Flutter.',
      fix: 'Run `pocket pair` again: it registers the device.',
    ));
  } else {
    checks.add(const DoctorCheck(
      DoctorState.ok,
      'The `pocket` device is registered with Flutter.',
    ));
  }

  if (project != null &&
      File('${project.path}${Platform.pathSeparator}pubspec.yaml')
          .existsSync()) {
    checks.addAll(_projectChecks(project, hello));
  }
  return checks;
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
