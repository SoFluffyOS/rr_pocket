import 'dart:async';
import 'dart:io' show Directory;

import 'package:lumide_api/lumide_api.dart';
import 'package:rr_pocket/src/constants.dart';
import 'package:rr_pocket/src/models/models.dart';
import 'package:rr_pocket/src/services/flutter_device.dart';
import 'package:rr_pocket/src/services/phone.dart';
import 'package:rr_pocket/src/services/project_files.dart';
import 'package:rr_pocket/src/services/project_picker.dart';
import 'package:rr_pocket/src/services/status_bar_service.dart';

/// The Lumide commands: pair with the phone, match a project's plugin
/// versions, show the phone. Running is Flutter's: once paired, RR Pocket
/// is a device like any other.
class PocketCommands {
  PocketCommands(
    this.context, {
    required this.config,
    required this.statusBar,
    required this.projects,
    Future<List<String>> Function()? helperCommand,
  }) : _helperCommand = helperCommand ?? currentHelperCommand;

  final LumideContext context;
  final PocketConfig config;
  final StatusBarService statusBar;
  final ProjectPicker projects;
  final Future<List<String>> Function() _helperCommand;

  static const Duration helloTimeout = Duration(seconds: 10);

  /// Asks the phone how it is, and shows the answer in the status bar.
  Future<PhoneStatus> refresh() async {
    final phone = await Phone.tryLoad(config);
    if (phone == null) {
      await statusBar.update(const NotPaired());
      return const NotPaired();
    }
    final address = PhoneAddress(phone.host, phone.port).toString();
    PhoneStatus status;
    try {
      final hello = await phone.hello().timeout(helloTimeout);
      status = Reachable.fromHello(address, hello);
    } catch (error) {
      status = Unreachable(address: address, reason: describePhoneError(error));
    } finally {
      phone.close();
    }
    await statusBar.update(status);
    return status;
  }

  Future<void> pair() async {
    final typed = await context.window.showInputBox(
      title: 'Pair with RR Pocket',
      prompt: 'The address RR Pocket shows on the phone',
      placeHolder: '192.168.1.20',
    );
    if (typed == null || typed.trim().isEmpty) return;
    final address = PhoneAddress.tryParse(typed);
    if (address == null) {
      return _error(
        '"${typed.trim()}" is not an address. Type it as RR Pocket shows '
        'it, such as 192.168.1.20.',
      );
    }
    final code = await context.window.showInputBox(
      title: 'Pair with RR Pocket',
      prompt: 'The pairing code RR Pocket shows',
      placeHolder: '1234-5678',
    );
    if (code == null || code.trim().isEmpty) return;

    final phone = Phone(address.host, address.port, normalizePairingCode(code));
    try {
      final hello = await context.window.withProgress(
        title: 'Pairing with RR Pocket',
        task: (_) async {
          final hello = await phone.hello().timeout(helloTimeout);
          await phone.save(config);
          await registerDevice(_flutter, await _helperCommand());
          return hello;
        },
      );
      final status = Reachable.fromHello(address.toString(), hello);
      await statusBar.update(status);
      await _info(
        'Paired with ${status.name} (Flutter ${status.flutterVersion}). '
        'Pick RR Pocket in the device list, then run.',
      );
    } finally {
      phone.close();
    }
  }

  /// Pins a project's Android plugins to the versions RR Pocket carries.
  Future<void> pin() async {
    final phone = await Phone.tryLoad(config);
    if (phone == null) {
      return _offerPairing(
        'RR Pocket is not paired yet, so its plugin versions are unknown.',
      );
    }
    try {
      final project = await projects.pick();
      if (project == null) return;
      final written = await context.window.withProgress(
        title: 'Matching RR Pocket\'s plugin versions',
        task: (_) async {
          final hello = await phone.hello().timeout(helloTimeout);
          final written = await writePins(hello, Directory(project));
          final got = await _flutter(
            ['pub', 'get'],
            workingDirectory: project,
          );
          if (got.exitCode != 0) {
            throw PocketException(
              'flutter pub get failed in $project:\n${got.stderr}',
            );
          }
          return written;
        },
      );
      await _info(switch (written.pins.length) {
        0 => 'This project uses none of the plugins RR Pocket carries; '
            'nothing to pin.',
        final count =>
          'Pinned $count plugins in ${written.file.path} and ran pub get.',
      });
    } finally {
      phone.close();
    }
  }

  Future<void> showPhone() async {
    final status = await refresh();
    switch (status) {
      case NotPaired():
        return _offerPairing('RR Pocket is not paired yet.');
      case Reachable(:final summary):
        return _info(summary);
      case Unreachable(:final address, :final reason):
        return _offerPairing(
          'RR Pocket at $address did not answer: $reason.',
          again: true,
        );
    }
  }

  Future<void> _offerPairing(String message, {bool again = false}) async {
    final action = switch (again) {
      true => 'Pair again?',
      false => 'Pair with a phone now?',
    };
    final confirmed = await context.window.showConfirmDialog(
      '$message $action',
      title: pluginName,
    );
    if (confirmed) await pair();
  }

  Future<FlutterResult> _flutter(
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    final result = await context.shell.run(
      executableFlutter,
      arguments,
      workingDirectory: workingDirectory,
    );
    return (
      exitCode: result.exitCode,
      stdout: result.stdout,
      stderr: result.stderr,
    );
  }

  Future<void> _info(String message) =>
      context.window.showMessage(message, title: pluginName);

  Future<void> _error(String message) => context.window.showMessage(
        message,
        type: MessageType.error,
        title: pluginName,
      );
}
