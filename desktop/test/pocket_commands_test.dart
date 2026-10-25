import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:lumide_api/lumide_api.dart' show MessageType;
import 'package:rr_pocket/rr_pocket.dart';
import 'package:test/test.dart';

import 'support/fake_host.dart';
import 'support/fake_phone.dart';

void main() {
  late Directory temp;
  late FakePhone phone;
  late FakeHost host;
  late PocketConfig config;
  late PocketCommands commands;
  late List<FoundPhone> found;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('rr_pocket_test');
    phone = await FakePhone.start(plugins: {'camera': '0.12.1'});
    host = FakeHost(workspaceFolder: temp.path);
    config = PocketConfig('${temp.path}/config');
    found = [];
    commands = PocketCommands(
      host,
      config: config,
      statusBar: StatusBarService(host, icon: () async => '/icon.svg'),
      projects: ProjectPicker(host),
      helperCommand: () async => ['dart', '/src/bin/pocket.dart'],
      discover: () async => found,
      addresses: () async => ['127.0.0.1'],
      computer: 'Mac',
      newToken: () => 'the-token',
    );
    // Pairing asks how; typing is what most tests answer.
    host.window.pickPayload = 'type';
  });

  tearDown(() async {
    await phone.close();
    await temp.delete(recursive: true);
  });

  Future<void> savePairing({String? code}) =>
      Phone('127.0.0.1', phone.port, code ?? phone.code,
              fingerprint: phone.fingerprint)
          .save(config);

  /// A resolved Flutter project in the workspace, using camera 0.12.0.
  Future<String> addProject(String name) async {
    final project = Directory('${temp.path}/$name');
    await project.create(recursive: true);
    await File('${project.path}/pubspec.yaml').writeAsString(
      'name: $name\ndependencies:\n  flutter:\n    sdk: flutter\n',
    );
    await File('${project.path}/pubspec.lock').writeAsString(
      'packages:\n  camera:\n    source: hosted\n    version: "0.12.0"\n',
    );
    host.workspace.files
        .add(Uri.file('${project.path}/pubspec.lock').toString());
    return project.path;
  }

  List<String> messages(MessageType type) => [
        for (final (messageType, text) in host.window.messages)
          if (messageType == type) text,
      ];

  group('pair', () {
    test('saves the phone and registers the pocket device', () async {
      host.window.inputs.addAll(['127.0.0.1:${phone.port}', '1234-5678']);

      await commands.pair();

      final saved = jsonDecode(await config.deviceFile.readAsString());
      expect(saved, {
        'host': '127.0.0.1',
        'port': phone.port,
        'code': '12345678',
        'fingerprint': phone.fingerprint,
      });
      final ran = [
        for (final run in host.shell.ran) run.command.take(3).join(' ')
      ];
      expect(ran, [
        'flutter config --enable-custom-devices',
        'flutter custom-devices delete',
        'flutter custom-devices add',
      ]);
      final added = host.shell.ran.last.command.last;
      final device = jsonDecode(added.substring('--json='.length)) as Map;
      expect(device['ping'], ['dart', '/src/bin/pocket.dart', 'ping']);
      expect(host.statusBar.items.values.single.$2, contains('Test Phone'));
      expect(messages(MessageType.info).single,
          startsWith('Paired with Test Phone'));
    });

    test('pairing a registered device runs no flutter and needs no restart',
        () async {
      expect(await commands.ensureRegistered(), isTrue);
      final registrations = host.shell.ran.length;
      host.window.inputs.addAll(['127.0.0.1:${phone.port}', phone.code]);

      await commands.pair();

      expect(host.shell.ran.length, registrations);
      expect(messages(MessageType.info).single, isNot(contains('restart')));
    });

    test('a first pairing that registers says to restart if not listed',
        () async {
      host.window.inputs.addAll(['127.0.0.1:${phone.port}', phone.code]);

      await commands.pair();

      expect(messages(MessageType.info).single, contains('restart Lumide'));
    });

    test('registers again when the command Flutter should run changes',
        () async {
      var helper = ['dart', '/old/pocket.dart'];
      final changing = PocketCommands(
        host,
        config: config,
        statusBar: StatusBarService(host, icon: () async => '/icon.svg'),
        projects: ProjectPicker(host),
        helperCommand: () async => helper,
      );
      expect(await changing.ensureRegistered(), isTrue);
      expect(await changing.ensureRegistered(), isFalse);
      helper = ['dart', '/new/pocket.dart'];
      expect(await changing.ensureRegistered(), isTrue);
    });

    test('offers the phones found, then a QR code, then typing', () async {
      found = [
        FoundPhone(name: 'Pixel 7', host: '127.0.0.1', port: phone.port)
      ];
      await commands.searchNetwork();
      host.window.pickPayload = null;

      await commands.pair();

      expect([
        for (final item in host.window.lastPick) item.payload
      ], [
        'found:0',
        'qr',
        'type',
      ]);
    });

    test('opens at once, without waiting for the network', () async {
      final hanging = Completer<List<FoundPhone>>();
      final waiting = PocketCommands(
        host,
        config: config,
        statusBar: StatusBarService(host, icon: () async => '/icon.svg'),
        projects: ProjectPicker(host),
        discover: () => hanging.future,
      );
      host.window.pickPayload = null;

      await waiting.pair().timeout(const Duration(seconds: 1));

      expect([
        for (final item in host.window.lastPick) item.payload
      ], [
        'qr',
        'type',
        'search',
      ]);
      hanging.complete([]);
    });

    test('searches when asked, then offers what it found', () async {
      found = [
        FoundPhone(name: 'Pixel 7', host: '127.0.0.1', port: phone.port)
      ];
      host.window.pickPayload = 'search';

      await commands.pair();

      expect(
        host.window.progressTitles,
        contains('Looking for RR Pocket on this network'),
      );
      expect(host.window.lastPick.first.payload, 'found:0');
    });

    test('a search that finds nothing offers the other routes', () async {
      host.window.pickPayload = 'search';

      await commands.pair();

      expect([
        for (final item in host.window.lastPick) item.payload
      ], [
        'qr',
        'type',
      ]);
    });

    test('pairs with a found phone once its user allows it', () async {
      found = [
        FoundPhone(name: 'Pixel 7', host: '127.0.0.1', port: phone.port)
      ];
      await commands.searchNetwork();
      host.window.pickPayload = 'found:0';

      await commands.pair();

      expect(phone.pairRequests, ['Mac']);
      expect(host.window.progressTitles, contains('Tap Allow on Pixel 7'));
      final saved = jsonDecode(await config.deviceFile.readAsString());
      expect(saved, {
        'host': '127.0.0.1',
        'port': phone.port,
        'code': phone.code,
        'fingerprint': phone.fingerprint,
      });
      expect(messages(MessageType.info).single, startsWith('Paired with'));
      expect(
        messages(MessageType.info).single,
        contains('shows certificate ${shortFingerprint(phone.fingerprint)}'),
        reason: 'the phone answered first; the user compares',
      );
    });

    test('a found phone whose user refuses keeps no pairing', () async {
      found = [
        FoundPhone(name: 'Pixel 7', host: '127.0.0.1', port: phone.port)
      ];
      await commands.searchNetwork();
      host.window.pickPayload = 'found:0';
      phone.pairAnswer = PairAnswer.refuse;

      await expectLater(commands.pair(), throwsA(isA<PocketException>()));
      expect(config.deviceFile.existsSync(), isFalse);
    });

    test('pairs with the phone that scans the QR code', () async {
      host.window.pickPayload = 'qr';
      phone.offeredToken = 'the-token';

      final pairing = commands.pair();
      final panel = await host.window.panelOpened.future;
      final page = Uri.parse(panel.url);
      final client = HttpClient();
      final request = await client.post('127.0.0.1', page.port, '/pair');
      request.write(jsonEncode({
        'name': 'Pixel 7',
        'address': '127.0.0.1',
        'port': phone.port,
        'fingerprint': phone.fingerprint,
        'proof': pairingProof('the-token', phone.fingerprint),
      }));
      final response = await request.close();
      await response.drain<void>();
      client.close();
      await pairing;

      expect(response.statusCode, 200);
      expect(panel.disposed, isTrue);
      expect(config.deviceFile.existsSync(), isTrue);
      expect(messages(MessageType.info).single, startsWith('Paired with'));
      expect(
        messages(MessageType.info).single,
        isNot(contains('certificate')),
        reason: 'the QR code proved the phone already',
      );
    });

    test('closing the QR code ends pairing quietly', () async {
      host.window.pickPayload = 'qr';

      final pairing = commands.pair();
      final panel = await host.window.panelOpened.future;
      while (!host.window.progressTitles.any((t) => t.startsWith('Waiting'))) {
        await Future<void>.delayed(Duration.zero);
      }
      host.window.lastProgress?.cancel();
      await pairing;

      expect(panel.disposed, isTrue);
      expect(host.window.messages, isEmpty);
      expect(config.deviceFile.existsSync(), isFalse);
    });

    test('stops at an address that is not one', () async {
      host.window.inputs.addAll(['http://phone', '1234']);

      await commands.pair();

      expect(messages(MessageType.error).single, contains('is not an address'));
      expect(host.shell.ran, isEmpty);
      expect(config.deviceFile.existsSync(), isFalse);
    });

    test('does nothing when the user dismisses a box', () async {
      host.window.inputs.addAll(['127.0.0.1:${phone.port}', null]);

      await commands.pair();

      expect(host.window.messages, isEmpty);
      expect(config.deviceFile.existsSync(), isFalse);
    });

    test('keeps no pairing the phone refused', () async {
      host.window.inputs.addAll(['127.0.0.1:${phone.port}', '0000']);

      await expectLater(
        commands.pair(),
        throwsA(isA<PocketException>().having(
          (e) => e.message,
          'message',
          contains('refused the pairing code'),
        )),
      );
      expect(config.deviceFile.existsSync(), isFalse);
      expect(host.shell.ran, isEmpty);
    });
  });

  group('pin', () {
    test('writes the overrides and resolves', () async {
      await savePairing();
      final project = await addProject('app');

      await commands.pin();

      final overrides =
          await File('$project/pubspec_overrides.yaml').readAsString();
      expect(overrides, contains('  camera: 0.12.1  # was 0.12.0\n'));
      expect(host.shell.ran.single.command, ['flutter', 'pub', 'get']);
      expect(host.shell.ran.single.workingDirectory, project);
      expect(
          messages(MessageType.info).single, startsWith('Pinned 1 plugin in'));
    });

    test('asks which project when there are several, the open one first',
        () async {
      await savePairing();
      await addProject('a_app');
      final open = await addProject('b_app');
      host.editor.activeUri = Uri.file('$open/lib/main.dart').toString();
      host.window.pickPayload = open;

      await commands.pin();

      expect([
        for (final item in host.window.lastPick) item.payload
      ], [
        open,
        '${temp.path}/a_app',
      ]);
      expect(File('$open/pubspec_overrides.yaml').existsSync(), isTrue);
      expect(File('${temp.path}/a_app/pubspec_overrides.yaml').existsSync(),
          isFalse);
    });

    test('offers the innermost project holding the open file first', () async {
      await savePairing();
      final plugin = await addProject('plugin');
      final example = await addProject('plugin/example');
      host.editor.activeUri = Uri.file('$example/lib/main.dart').toString();

      await commands.pin();

      expect(
        [for (final item in host.window.lastPick) item.payload],
        [example, plugin],
      );
    });

    test('asks before pinning across a breaking change', () async {
      await Phone('127.0.0.1', phone.port, phone.code,
              fingerprint: phone.fingerprint)
          .save(config);
      final project = await addProject('app');
      await phone.close();
      phone = await FakePhone.start(plugins: {'camera': '1.0.0'});
      await savePairing();

      await commands.pin();
      expect(
          host.window.confirmations.single, contains('camera 0.12.0 -> 1.0.0'));
      final overrides = File('$project/pubspec_overrides.yaml');
      expect(overrides.readAsStringSync(), isNot(contains('camera')));
      expect(messages(MessageType.info).last, contains('Not pinned'));

      host.window.confirm = true;
      await commands.pin();
      expect(overrides.readAsStringSync(), contains('camera: 1.0.0'));
    });

    test('leaves overrides it did not write', () async {
      await savePairing();
      final project = await addProject('app');
      final overrides = File('$project/pubspec_overrides.yaml');
      await overrides.writeAsString('dependency_overrides:\n  path: 1.9.0\n');

      await expectLater(
        commands.pin(),
        throwsA(isA<PocketException>().having(
          (e) => e.message,
          'message',
          allOf(contains('not ours'), contains('camera: 0.12.1')),
        )),
      );
      expect(await overrides.readAsString(),
          'dependency_overrides:\n  path: 1.9.0\n');
      expect(host.shell.ran, isEmpty);
    });

    test('reports a failed pub get', () async {
      await savePairing();
      await addProject('app');
      host.shell.exitCodes['flutter pub get'] = 1;

      await expectLater(commands.pin(), throwsA(isA<PocketException>()));
    });

    test('offers to pair first', () async {
      await addProject('app');

      await commands.pin();

      expect(host.window.confirmations.single, contains('not paired yet'));
      expect(host.shell.ran, isEmpty);
    });

    test('skips build output and projects that are not Flutter', () async {
      await savePairing();
      await addProject('app');
      final copy = Directory('${temp.path}/app/build/copy')
        ..createSync(recursive: true);
      File('${copy.path}/pubspec.lock').writeAsStringSync('packages:\n');
      File('${copy.path}/pubspec.yaml').writeAsStringSync(
        'dependencies:\n  flutter:\n    sdk: flutter\n',
      );
      host.workspace.files
          .add(Uri.file('${copy.path}/pubspec.lock').toString());
      final dartOnly = Directory('${temp.path}/cli')..createSync();
      File('${dartOnly.path}/pubspec.lock').writeAsStringSync('packages:\n');
      File('${dartOnly.path}/pubspec.yaml').writeAsStringSync('name: cli\n');
      host.workspace.files
          .add(Uri.file('${dartOnly.path}/pubspec.lock').toString());

      expect(await ProjectPicker(host).flutterProjects(), ['${temp.path}/app']);
    });
  });

  group('show phone', () {
    test('shows the phone that answers', () async {
      await savePairing();

      await commands.showPhone();

      expect(
        messages(MessageType.info).single,
        'Test Phone at 127.0.0.1:${phone.port}, Flutter 3.47.7.',
      );
    });

    test('offers to pair again when the phone does not answer', () async {
      await savePairing();
      await phone.close();

      await commands.showPhone();

      expect(
          host.window.confirmations.single,
          allOf(
            contains('did not answer'),
            contains('Pair again?'),
          ));
      expect(host.statusBar.items.values.single.$2, contains('did not answer'));
      expect(host.statusBar.looks.values.single.color, colorNotAnswering);
    });

    test('a refresh that started before a pairing leaves the status to it',
        () async {
      // An old pairing whose phone is gone: its refresh waits on the
      // connection while the user pairs the new phone.
      await Phone('10.255.255.1', 9, '0', fingerprint: 'none').save(config);
      final stale = commands.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      host.window.inputs.addAll(['127.0.0.1:${phone.port}', phone.code]);
      await commands.pair();

      await stale;

      expect(host.statusBar.items.values.single.$2, contains('Test Phone'));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('offers to pair before pairing, the status item saying so', () async {
      await commands.showPhone();

      expect(host.window.confirmations.single, contains('not paired yet'));
      expect(host.statusBar.items.values.single.$2, contains('not paired'));
    });
  });

  group('status bar', () {
    test('shows the R² mark alone, the details on hover', () async {
      await savePairing();

      await commands.refresh();

      expect(host.statusBar.items.values.single.$1, isEmpty);
      expect(host.statusBar.items.values.single.$2, contains('Test Phone'));
      expect(host.statusBar.looks.values.single, (
        color: null,
        iconPath: '/icon.svg',
      ));
    });

    test('turns amber when the phone stops answering, and back', () async {
      await savePairing();
      await commands.refresh();
      await phone.close();

      await commands.refresh();
      expect(host.statusBar.looks.values.single.color, colorNotAnswering);

      phone = await FakePhone.start(plugins: {'camera': '0.12.1'});
      await savePairing();
      await commands.refresh();
      expect(host.statusBar.looks.values.single.color, isNull);
    });
  });

  group('check setup', () {
    test('checks without asking, and shows the findings', () async {
      await savePairing();
      await addProject('app');

      await commands.doctor();

      final output = host.window.channels.single;
      expect(output.shown, isTrue);
      expect('${output.text}', contains('RR Pocket answers'));
      expect('${output.text}', contains('${temp.path}/app'));
      // The fake shell's flutter answers nothing, and camera wants a pin.
      expect('${output.text}', contains('No working `flutter`'));
      expect('${output.text}', contains('Run `pocket pin`'));
      expect(messages(MessageType.error).single, startsWith('3 things to fix'));
      expect(host.window.lastPick, isEmpty);
    });
  });

  group('forget', () {
    test('forgets the phone once confirmed', () async {
      await savePairing();
      host.window.confirm = true;

      await commands.forget();

      expect(config.deviceFile.existsSync(), isFalse);
      expect(host.statusBar.items.values.single.$2, contains('not paired'));
      expect(messages(MessageType.info).single, startsWith('Forgot RR Pocket'));
    });

    test('keeps the phone when not confirmed', () async {
      await savePairing();

      await commands.forget();

      expect(config.deviceFile.existsSync(), isTrue);
    });

    test('says so when nothing is paired', () async {
      await commands.forget();

      expect(host.window.confirmations, isEmpty);
      expect(messages(MessageType.info).single, contains('not paired'));
    });
  });

  group('menu', () {
    List<Object?> payloads() => [
          for (final item in host.window.lastPick)
            if (item.enabled && !item.isSeparator) item.payload,
        ];

    test('before pairing offers only pairing', () async {
      host.window.pickPayload = cmdPair;

      await commands.menu();

      expect(host.window.lastPick.first.label, 'Not paired');
      expect(payloads(), [cmdPair, helpUrl, sponsorUrl]);
      expect(host.commands.executed, [cmdPair]);
    });

    test('once paired, shows the phone and what to do with it', () async {
      await savePairing();
      await commands.refresh();
      host.window.pickPayload = cmdForget;

      await commands.menu({
        'position': {'x': 10, 'y': 20},
      });

      expect(host.window.lastPick.first.label, 'Test Phone');
      expect(host.window.lastPick.first.enabled, isFalse);
      expect(payloads(), [
        cmdShowPhone,
        cmdDoctor,
        cmdPin,
        cmdPair,
        cmdForget,
        helpUrl,
        sponsorUrl,
      ]);
      expect(host.commands.executed, [cmdForget]);
    });

    test('the command it runs opens where the menu did', () async {
      await savePairing();
      host.window.pickPayload = cmdPair;
      const click = {'x': 900, 'y': 700};

      await commands.menu({'position': click});

      expect(host.window.lastPosition, click);
      expect(host.commands.executedArgs.single, {'position': click});
    });

    test('pairing and the project picker open at the click', () async {
      const click = {'x': 900, 'y': 700};
      host.window.pickPayload = null;

      await commands.pair({'position': click});
      expect(host.window.lastPosition, click);

      await savePairing();
      await addProject('a_app');
      await addProject('b_app');
      await commands.pin({'position': click});
      expect(host.window.lastPosition, click);
    });

    test('items say more on hover, not in a description', () async {
      found = [
        FoundPhone(name: 'Pixel 7', host: '127.0.0.1', port: phone.port)
      ];
      await commands.searchNetwork();
      host.window.pickPayload = null;

      await commands.pair();
      final pairing = host.window.lastPick;
      await commands.menu();
      final menu = host.window.lastPick;

      for (final item in [...pairing, ...menu]) {
        if (item.isSeparator) continue;
        expect(item.description, isNull, reason: item.label);
        expect(item.detail, isNull, reason: item.label);
        expect(item.tooltip, isNotNull, reason: item.label);
      }
    });

    test('help and sponsoring open in the browser', () async {
      host.window.pickPayload = sponsorUrl;

      await commands.menu();

      expect(host.window.opened, [sponsorUrl]);
      expect(host.commands.executed, isEmpty);
    });

    test('runs nothing when dismissed', () async {
      host.window.pickPayload = null;

      await commands.menu();

      expect(host.commands.executed, isEmpty);
    });
  });
}
