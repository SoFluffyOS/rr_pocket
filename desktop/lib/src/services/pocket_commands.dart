import 'dart:async';
import 'dart:io' show Directory;

import 'package:lumide_api/lumide_api.dart';
import 'package:rr_pocket/src/constants.dart';
import 'package:rr_pocket/src/models/models.dart';
import 'package:rr_pocket/src/services/computer.dart';
import 'package:rr_pocket/src/services/discovery.dart';
import 'package:rr_pocket/src/services/doctor.dart';
import 'package:rr_pocket/src/services/flutter_device.dart';
import 'package:rr_pocket/src/services/pair_listener.dart';
import 'package:rr_pocket/src/services/pair_request.dart';
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
    Future<List<FoundPhone>> Function()? discover,
    Future<List<String>> Function()? addresses,
    String? computer,
    String Function()? newToken,
  })  : _helperCommand = helperCommand,
        _newToken = newToken ?? newPairingToken,
        _discover = discover ?? discoverPhones,
        _addresses = addresses ?? localAddresses,
        _computer = computer ?? computerName();

  final LumideContext context;
  final PocketConfig config;
  final StatusBarService statusBar;
  final ProjectPicker projects;
  final Future<List<String>> Function()? _helperCommand;
  final Future<List<FoundPhone>> Function() _discover;
  final Future<List<String>> Function() _addresses;
  final String _computer;
  final String Function() _newToken;

  static const Duration helloTimeout = Duration(seconds: 10);

  /// Counts pairings, so a refresh that started before one leaves the
  /// status bar to it.
  int _pairings = 0;

  /// The phone as last seen, for the menu; null before the first look.
  PhoneStatus? _status;

  Future<void> _show(PhoneStatus status) async {
    _status = status;
    await statusBar.update(status);
  }

  /// Asks the phone how it is, and shows the answer in the status bar.
  Future<PhoneStatus> refresh() async {
    final pairings = _pairings;
    final phone = await Phone.tryLoad(config);
    if (phone == null) {
      await _show(const NotPaired());
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
    if (pairings == _pairings) await _show(status);
    return status;
  }

  /// The phones the last search found, for pairing to offer at once.
  List<FoundPhone> _found = const [];
  Future<List<FoundPhone>>? _searching;

  /// Looks for RR Pocket on the network, one search at a time; what it
  /// finds is offered the next time pairing opens. The plugin searches when
  /// it starts and whenever the menu or pairing opens, so nobody waits.
  Future<List<FoundPhone>> searchNetwork() {
    if (_searching case final running?) return running;
    final search = _discover().then(
      (phones) => _found = phones,
      onError: (Object _) => _found,
    );
    _searching = search;
    return search.whenComplete(() {
      if (identical(_searching, search)) _searching = null;
    });
  }

  /// Pairs by the best route that works (docs/pairing.md): a phone found on
  /// the network, which asks its user; a QR code the phone scans; or the
  /// address and code typed in. Never waits for the network: it offers the
  /// phones found so far, and searches again in the background.
  Future<void> pair([Map<String, dynamic>? args]) async {
    final position = positionOf(args);
    final phones = _found;
    unawaited(searchNetwork());
    final picked = await context.window.showQuickPick(
      [
        for (final (index, phone) in phones.indexed)
          QuickPickItem(
            label: phone.name,
            tooltip: '${phone.host}: found on this network. Tap Allow on '
                'the phone.',
            icon: iconPhone,
            payload: 'found:$index',
          ),
        ..._otherRoutes,
        if (phones.isEmpty)
          const QuickPickItem(
            label: 'Search the network again',
            tooltip: 'For RR Pocket open on the same Wi-Fi as this computer.',
            icon: iconCheck,
            payload: 'search',
          ),
      ],
      placeholder: switch (phones.isEmpty) {
        true => 'No phone found on this network yet',
        false => 'Pair with',
      },
      position: position,
    );
    final payload = picked?.payload;
    if (payload == 'search') return _searchThenPair(position);
    if (payload == 'qr') return _pairByQr();
    if (payload == 'type') return _pairTyped();
    if (payload is! String || !payload.startsWith('found:')) return;
    final index = int.tryParse(payload.substring('found:'.length)) ?? -1;
    if (index < 0 || index >= phones.length) return;
    return _pairFound(phones[index]);
  }

  /// The one place pairing waits for the network: the user asked to.
  Future<void> _searchThenPair(Map<String, int>? position) async {
    final phones = await context.window.withProgress(
      title: 'Looking for RR Pocket on this network',
      task: (_) => searchNetwork(),
    );
    if (phones.isEmpty) {
      return _offerOtherRoutes('No RR Pocket found on this network', position);
    }
    return pair({if (position != null) 'position': position});
  }

  /// Pairing when the network can't find the phone, each with what it
  /// takes on hover.
  static const _otherRoutes = [
    QuickPickItem(
      label: 'Show a QR code',
      tooltip: 'Scan it with RR Pocket (Scan QR code) or the phone\'s '
          'camera, then tap Allow.',
      icon: 'qr-code',
      payload: 'qr',
    ),
    QuickPickItem(
      label: 'Type the address and code',
      tooltip: 'The address and pairing code RR Pocket shows on its home '
          'screen.',
      icon: 'keyboard',
      payload: 'type',
    ),
  ];

  Future<void> _offerOtherRoutes(
    String message,
    Map<String, int>? position,
  ) async {
    final picked = await context.window.showQuickPick(
      _otherRoutes,
      placeholder: message,
      position: position,
    );
    return switch (picked?.payload) {
      'qr' => _pairByQr(),
      'type' => _pairTyped(),
      _ => null,
    };
  }

  Future<void> _pairFound(FoundPhone found) async {
    final given = await context.window.withProgress(
      title: 'Tap Allow on ${found.name}',
      task: (_) => requestPairing(found.host, found.port, _computer),
    );
    final phone = Phone(
      found.host,
      found.port,
      given.code,
      fingerprint: given.fingerprint,
    );
    await _finish(
      phone,
      () => phone.hello().timeout(helloTimeout),
      firstSeen: true,
    );
  }

  Future<void> _pairByQr() async {
    final listener = await PairListener.start(
      computer: _computer,
      hosts: await _addresses(),
      verify: (phone) => phone.hello().timeout(helloTimeout),
      token: _newToken(),
    );
    LumideWebviewPanel? panel;
    try {
      panel = await context.window.createWebviewPanel(
        'rr_pocket.pair',
        'Pair with RR Pocket',
        options: {'url': '${listener.pageUri}'},
      );
      final PairedPhone paired;
      try {
        paired = await context.window.withProgress(
          title: 'Waiting for RR Pocket to scan the code',
          cancellable: true,
          task: (progress) {
            progress.onCancel(() => unawaited(listener.close()));
            return listener.paired;
          },
        );
      } on PairingCancelled {
        return;
      }
      await panel.dispose();
      panel = null;
      await _finish(paired.phone, () async => paired.hello);
    } finally {
      await listener.close();
      await panel?.dispose().catchError((Object _) {});
    }
  }

  Future<void> _pairTyped() async {
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
    await _finish(
      phone,
      () => phone.hello().timeout(helloTimeout),
      firstSeen: true,
    );
  }

  /// Checks the phone with its code ([hello]), keeps the pairing and makes
  /// sure Flutter knows the device. [firstSeen]: the route trusted the
  /// first certificate that answered, so the user compares it with the
  /// phone's (docs/pairing.md).
  Future<void> _finish(
    Phone phone,
    Future<Map<String, Object?>> Function() hello, {
    bool firstSeen = false,
  }) async {
    final address = PhoneAddress(phone.host, phone.port).toString();
    try {
      final result = await context.window.withProgress(
        title: 'Pairing with RR Pocket',
        task: (_) async {
          final answer = await hello();
          await phone.save(config);
          _pairings++;
          final registered = await ensureRegistered();
          return (hello: answer, registered: registered);
        },
      );
      final status = Reachable.fromHello(address, result.hello);
      await _show(status);
      // Registered only now: Lumide's running Flutter daemon never read it.
      final restart = switch (result.registered) {
        true => ' If RR Pocket is not in the device list, restart Lumide: '
            'Flutter reads new devices when it starts.',
        false => '',
      };
      final check = switch (phone.fingerprint) {
        final fingerprint? when firstSeen =>
          ' ${checkCertificate(fingerprint, cli: false)}',
        _ => '',
      };
      await _info(
        'Paired with ${status.name} (Flutter ${status.flutterVersion}). '
        'Pick RR Pocket in the device list, then run.$check$restart',
      );
    } finally {
      phone.close();
    }
  }

  /// Pins a project's Android plugins to the versions RR Pocket carries.
  Future<void> pin([Map<String, dynamic>? args]) async {
    final phone = await Phone.tryLoad(config);
    if (phone == null) {
      return _offerPairing(
        'RR Pocket is not paired yet, so its plugin versions are unknown.',
      );
    }
    try {
      final project = await projects.pick(position: positionOf(args));
      if (project == null) return;
      final hello = await context.window.withProgress(
        title: 'Asking RR Pocket for its plugin versions',
        task: (_) => phone.hello().timeout(helloTimeout),
      );
      // A breaking change may not compile: ask before pinning across one.
      final planned = planPins(
        carried: bundledPlugins(hello),
        used: usedVersions(Directory(project)) ?? const {},
      );
      var all = false;
      if (planned.breaking.isNotEmpty) {
        all = await context.window.showConfirmDialog(
          'These are a breaking change from what the project uses:\n'
          '${describeBreaking(planned.breaking)}\n\n'
          'Pin them too? The project may not compile until its code, or a '
          'package that uses them, is updated. If not, upgrade the project '
          'to these versions instead.',
          title: 'Pin across a breaking change?',
        );
      }
      final written = await context.window.withProgress(
        title: 'Matching RR Pocket\'s plugin versions',
        task: (_) async {
          final written = await writePins(hello, Directory(project), all: all);
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
      final skipped = switch (written.breaking.isEmpty) {
        true => '',
        false => ' Not pinned, a breaking change: '
            '${[for (final pin in written.breaking) pin.name].join(', ')}.',
      };
      await _info(switch (written.pins.length) {
        0 => 'Nothing pinned.$skipped',
        final count =>
          'Pinned ${plugins(count)} in ${written.file.path} and ran '
              'pub get.$skipped',
      });
    } finally {
      phone.close();
    }
  }

  /// Forgets the paired phone: Lumide and the `pocket` command stop using
  /// it, and Flutter drops the device when its ping next fails. The phone
  /// keeps its code, so pairing again works.
  Future<void> forget() async {
    final phone = await Phone.tryLoad(config);
    if (phone == null) {
      return _info('RR Pocket is not paired with a phone.');
    }
    phone.close();
    final address = PhoneAddress(phone.host, phone.port);
    final confirmed = await context.window.showConfirmDialog(
      'Forget RR Pocket at $address? Lumide and the pocket command stop '
      'using it. Pair again any time.',
      title: pluginName,
    );
    if (!confirmed) return;
    for (final file in [config.deviceFile, config.installFailedFile]) {
      if (await file.exists()) await file.delete();
    }
    _pairings++;
    await _show(const NotPaired());
    await _info('Forgot RR Pocket at $address.');
  }

  /// RR Pocket's menu, from the status bar: the phone, then what can be
  /// done with it. [args] carries where the item was clicked.
  Future<void> menu([Map<String, dynamic>? args]) async {
    final position = positionOf(args);
    unawaited(searchNetwork());
    final status = _status ?? await _statusFromFile();
    QuickPickItem action(
      String command,
      String label,
      String icon,
      String tooltip,
    ) =>
        QuickPickItem(
          label: label,
          payload: command,
          icon: icon,
          tooltip: tooltip,
        );
    final selected = await context.window.showQuickPick(
      [
        QuickPickItem(
          label: switch (status) {
            Reachable(:final name) => name,
            Unreachable() => 'Not answering',
            NotPaired() => 'Not paired',
          },
          tooltip: switch (status) {
            Reachable(:final address, :final flutterVersion) =>
              '$address, Flutter $flutterVersion',
            Unreachable(:final address, :final reason) =>
              '$address did not answer: $reason',
            NotPaired() => 'Pair once, then run on it from the device list.',
          },
          iconPath: assetIcon,
          noTint: true,
          enabled: false,
        ),
        const QuickPickItem(label: '', isSeparator: true),
        ...switch (status) {
          NotPaired() => [
              action(cmdPair, 'Pair with Phone', iconPair,
                  'Find RR Pocket on this network, or scan or type its code.'),
            ],
          _ => [
              action(cmdShowPhone, 'Check Phone Again', iconCheck,
                  'Ask the phone for its Flutter version and plugins.'),
              action(cmdDoctor, 'Check Setup', iconDoctor,
                  'Check the phone, Flutter and this project, and say what to fix.'),
              action(cmdPin, 'Match Plugin Versions', iconPin,
                  'Pin a project\'s plugins to the versions RR Pocket carries.'),
              action(cmdPair, 'Pair with Another Phone', iconPair,
                  'This computer uses one phone at a time.'),
              action(cmdForget, 'Forget This Phone', iconForget,
                  'Unpair. The phone keeps its code, so pairing again works.'),
            ],
        },
        const QuickPickItem(label: '', isSeparator: true),
        const QuickPickItem(
          label: 'Help',
          payload: helpUrl,
          icon: iconHelp,
          tooltip: 'How RR Pocket works, in its docs.',
        ),
        const QuickPickItem(
          label: 'Sponsor RR Pocket',
          payload: sponsorUrl,
          icon: iconSponsor,
          tooltip: 'Support RR Pocket on GitHub Sponsors.',
        ),
      ],
      placeholder: pluginName,
      position: position,
    );
    final command = selected?.payload;
    if (command is! String) return;
    if (command.startsWith('https://')) {
      await context.window.openUrl(command);
      return;
    }
    // The next picker opens where this one did.
    await context.commands.executeCommand(command, {
      if (position != null) 'position': position,
    });
  }

  /// Before the phone was asked: paired or not, from the pairing file.
  Future<PhoneStatus> _statusFromFile() async {
    final phone = await Phone.tryLoad(config);
    if (phone == null) return const NotPaired();
    phone.close();
    return Unreachable(
      address: PhoneAddress(phone.host, phone.port).toString(),
      reason: 'not checked yet',
    );
  }

  LumideOutputChannel? _output;

  /// `pocket doctor` in Lumide: the setup, and the project holding the open
  /// file, checked without asking anything; the findings in an output
  /// panel.
  Future<void> doctor() async {
    final project = await projects.current();
    final checks = await context.window.withProgress(
      title: 'Checking RR Pocket\'s setup',
      task: (_) => runDoctor(
        config: config,
        flutter: _flutter,
        project: switch (project) {
          final path? => Directory(path),
          null => null,
        },
      ),
    );
    final output = _output ??= await context.window.createOutputChannel(
      pluginName,
    );
    await output.clear();
    await output.appendLine(switch (project) {
      final path? => 'RR Pocket: the setup, and $path',
      null => 'RR Pocket: the setup',
    });
    await output.appendLine(describeDoctor(checks));
    await output.show();
    final problems = [
      for (final check in checks)
        if (check.state == DoctorState.problem) check,
    ].length;
    await switch (problems) {
      0 => _info('All good: run on RR Pocket from the device list.'),
      1 => _error('1 thing to fix. What and how are in the RR Pocket output.'),
      final count => _error(
          '$count things to fix. What and how are in the RR Pocket output.'),
    };
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

  /// Registers the `pocket` device with Flutter unless it already is;
  /// returns whether it had to. The plugin does this when it starts, so
  /// pairing later needs no restart.
  Future<bool> ensureRegistered() async =>
      ensureDeviceRegistered(_flutter, await _deviceHelper(), config);

  /// Lumide may run this plugin on a Dart SDK of its own, so Flutter calls
  /// the tool back with the Dart of the Flutter SDK it registered with.
  Future<List<String>> _deviceHelper() async {
    if (_helperCommand case final helper?) return helper();
    return currentHelperCommand(dart: await findFlutterDart(_flutter));
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

/// Where a status bar click happened, from a command's arguments, so the
/// quick picks it leads to open there too.
Map<String, int>? positionOf(Map<String, dynamic>? args) =>
    switch (args?['position']) {
      {'x': final int x, 'y': final int y} => {'x': x, 'y': y},
      _ => null,
    };
