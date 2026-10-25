import 'dart:convert';
import 'dart:io';

import 'package:rr_pocket/rr_pocket.dart';
import 'package:test/test.dart';

import 'support/fake_phone.dart';

void main() {
  late Directory temp;
  late FakePhone phone;
  late PocketConfig config;
  late PocketCli cli;
  late Directory bundle;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('rr_pocket_cli_test');
    phone = await FakePhone.start(plugins: {'camera': '0.12.1'});
    config = PocketConfig('${temp.path}/config');
    await Phone('127.0.0.1', phone.port, phone.code,
            fingerprint: phone.fingerprint)
        .save(config);
    cli = PocketCli(config: config, environment: const {});

    // A project and the bundle Flutter builds for it.
    final project = temp.path;
    File('$project/pubspec.lock').writeAsStringSync(
      'packages:\n  camera:\n    source: hosted\n    version: "0.12.1"\n',
    );
    bundle = Directory('$project/build/flutter_assets')
      ..createSync(recursive: true);
    File('${bundle.path}/kernel_blob.bin').writeAsStringSync('kernel');
    File('${bundle.path}/vm_snapshot_data').writeAsStringSync('engine');
    Directory('${bundle.path}/fonts').createSync();
    File('${bundle.path}/fonts/a.ttf').writeAsStringSync('font');
  });

  tearDown(() async {
    await phone.close();
    await temp.delete(recursive: true);
  });

  test('install sends the bundle without the engine snapshots', () async {
    expect(await cli(['install', bundle.path, 'app']), 0);

    expect(
        phone.bundle.keys, unorderedEquals(['kernel_blob.bin', 'fonts/a.ttf']));
    expect(String.fromCharCodes(phone.bundle['fonts/a.ttf'] ?? []), 'font');
    expect(phone.requests.first, 'GET /hello');
    expect(phone.requests.last, 'POST /bundle/commit');
    expect(config.installFailedFile.existsSync(), isFalse);
  });

  test('a failed install stops the run that follows', () async {
    File('${temp.path}/pubspec.lock').writeAsStringSync(
      'packages:\n  camera:\n    source: hosted\n    version: "0.12.0"\n',
    );

    expect(await cli(['install', bundle.path, 'app']), 1);
    expect(config.installFailedFile.readAsStringSync(), contains('pocket pin'));
    expect(phone.requests, isNot(contains('POST /bundle/begin')));

    expect(await cli(['run', 'app']), 1);
    expect(phone.requests, isNot(contains('POST /run')));
  });

  test('an install the network cut short stops the run too', () async {
    await phone.close();

    expect(await cli(['install', bundle.path, 'app']), 1);
    expect(config.installFailedFile.readAsStringSync(), contains('reach'));
    expect(await cli(['run', 'app']), 1);
  });

  test('an unreadable pairing counts as none', () async {
    config.deviceFile.writeAsStringSync('{"host": "127.0.0.1", "po');

    expect(await Phone.tryLoad(config), isNull);
    expect(await cli(['ping']), 1);
  });

  group('pair', () {
    late List<FoundPhone> found;
    late List<List<String>> ranFlutter;
    late int pairPort;
    late PocketCli pairing;

    setUp(() async {
      config.deviceFile.deleteSync();
      found = [];
      ranFlutter = [];
      final free = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      pairPort = free.port;
      await free.close();
      pairing = PocketCli(
        config: config,
        environment: const {},
        discover: () async => found,
        addresses: () async => ['127.0.0.1'],
        flutter: (arguments, {workingDirectory}) async {
          ranFlutter.add(arguments);
          return (exitCode: 0, stdout: '', stderr: '');
        },
        helperCommand: () async => ['dart', 'pocket.dart'],
        computer: 'Mac',
        newToken: () => 'the-token',
        pairPort: pairPort,
      );
    });

    test('asks the phone it finds, and registers the device', () async {
      found = [
        FoundPhone(name: 'Pixel 7', host: '127.0.0.1', port: phone.port)
      ];

      expect(await pairing(['pair']), 0);

      expect(phone.pairRequests, ['Mac']);
      expect(config.deviceFile.existsSync(), isTrue);
      expect(ranFlutter.last.take(2), ['custom-devices', 'add']);
      expect(config.registeredFile.existsSync(), isTrue);
    });

    test('keeps the code readable by this account only', () async {
      // An old pairing file, readable by everyone.
      config.deviceFile.writeAsStringSync('{}');
      await Process.run('chmod', ['644', config.deviceFile.path]);

      expect(await pairing(['pair', '127.0.0.1:${phone.port}', phone.code]), 0);

      expect(config.deviceFile.statSync().modeString(), 'rw-------');
      expect(File('${config.deviceFile.path}.tmp').existsSync(), isFalse);
    }, testOn: '!windows');

    test('shows a QR code when no phone is found, and pairs who scans it',
        () async {
      phone.offeredToken = 'the-token';
      final paired = pairing(['pair']);
      // The phone, once it scanned the code.
      HttpClientResponse? response;
      for (var attempt = 0; response == null && attempt < 50; attempt++) {
        try {
          final client = HttpClient();
          final request = await client.post('127.0.0.1', pairPort, '/pair');
          request.write(jsonEncode({
            'name': 'Pixel 7',
            'address': '127.0.0.1',
            'port': phone.port,
            'fingerprint': phone.fingerprint,
            'proof': pairingProof('the-token', phone.fingerprint),
          }));
          response = await request.close();
          await response.drain<void>();
          client.close();
        } on SocketException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }

      expect(response?.statusCode, 200);
      expect(await paired, 0);
      expect(config.deviceFile.existsSync(), isTrue);
    });

    test('says why a found phone did not pair', () async {
      found = [
        FoundPhone(name: 'Pixel 7', host: '127.0.0.1', port: phone.port)
      ];
      phone.pairAnswer = PairAnswer.refuse;

      expect(await pairing(['pair']), 1);
      expect(config.deviceFile.existsSync(), isFalse);
    });
  });

  test('forget unpairs this computer', () async {
    expect(await cli(['forget']), 0);
    expect(config.deviceFile.existsSync(), isFalse);
    expect(await cli(['ping']), 1);
    expect(await cli(['forget']), 0);
  });

  group('a pub workspace', () {
    late Directory root;
    late Directory app;
    late FakePhone isarPhone;
    late PocketCli workspaceCli;

    const lock = '''packages:
  isar_community:
    source: hosted
    version: "3.3.2"
  isar_community_flutter_libs:
    source: hosted
    version: "3.3.2"
  isar_community_generator:
    source: hosted
    version: "3.3.2"
''';

    setUp(() async {
      isarPhone = await FakePhone.start(
        plugins: {'isar_community_flutter_libs': '3.4.1'},
      );
      await Phone('127.0.0.1', isarPhone.port, isarPhone.code,
              fingerprint: isarPhone.fingerprint)
          .save(config);
      workspaceCli = PocketCli(config: config, environment: const {});
      root = Directory('${temp.path}/converter')..createSync();
      File('${root.path}/pubspec.yaml')
          .writeAsStringSync('name: root\nworkspace:\n  - apps/mcu\n');
      File('${root.path}/pubspec.lock').writeAsStringSync(lock);
      app = Directory('${root.path}/apps/mcu')..createSync(recursive: true);
      File('${app.path}/pubspec.yaml').writeAsStringSync(
        'name: mcu\nresolution: workspace\n'
        'dependencies:\n  flutter:\n    sdk: flutter\n',
      );
      Directory('${app.path}/build/flutter_assets').createSync(recursive: true);
      File('${app.path}/build/flutter_assets/kernel_blob.bin')
          .writeAsStringSync('kernel');
    });

    tearDown(() => isarPhone.close());

    test('install reads the root lock and stops on a version mismatch',
        () async {
      expect(
        await workspaceCli(
            ['install', '${app.path}/build/flutter_assets', 'mcu']),
        1,
      );
      expect(
        config.installFailedFile.readAsStringSync(),
        contains('isar_community_flutter_libs 3.3.2 (RR Pocket has 3.4.1)'),
      );
      expect(isarPhone.bundle, isEmpty);
    });

    test('install leaves out plugins only another member uses', () async {
      File('${app.path}/.flutter-plugins-dependencies').writeAsStringSync(
        '{"plugins": {"android": [], "ios": []}}',
      );

      expect(
        await workspaceCli(
            ['install', '${app.path}/build/flutter_assets', 'mcu']),
        0,
      );
      expect(isarPhone.bundle.keys, contains('kernel_blob.bin'));
    });

    test('pin writes the overrides at the root, the family included', () async {
      final hello = await Phone('127.0.0.1', isarPhone.port, isarPhone.code,
              fingerprint: isarPhone.fingerprint)
          .hello();
      final written = await writePins(hello, app);

      expect(written.file.path, '${root.path}/pubspec_overrides.yaml');
      expect(written.pins, {
        'isar_community': '3.4.1',
        'isar_community_flutter_libs': '3.4.1',
        'isar_community_generator': '3.4.1',
      });
      expect(File('${app.path}/pubspec_overrides.yaml').existsSync(), isFalse);
    });

    test('a project outside any workspace never reads a lock above it', () {
      final loose = Directory('${root.path}/tools/loose')
        ..createSync(recursive: true);
      File('${loose.path}/pubspec.yaml').writeAsStringSync('name: loose\n');

      expect(lockedVersions(loose), isNull);
      expect(lockedVersions(app), containsPair('isar_community', '3.3.2'));
    });
  });

  group('a breaking change', () {
    late FakePhone storagePhone;
    late PocketCli storageCli;

    setUp(() async {
      storagePhone = await FakePhone.start(
        plugins: {'flutter_secure_storage': '11.2.0', 'share_plus': '13.3.1'},
      );
      await Phone('127.0.0.1', storagePhone.port, storagePhone.code,
              fingerprint: storagePhone.fingerprint)
          .save(config);
      storageCli = PocketCli(config: config, environment: const {});
      File('${temp.path}/pubspec.lock').writeAsStringSync(
        'packages:\n'
        '  flutter_secure_storage:\n    source: hosted\n    version: "10.3.1"\n'
        '  share_plus:\n    source: hosted\n    version: "13.3.0"\n',
      );
    });

    tearDown(() => storagePhone.close());

    test('install says which differences are breaking', () async {
      expect(await storageCli(['install', bundle.path, 'app']), 1);
      final why = config.installFailedFile.readAsStringSync();
      expect(
          why,
          contains(
              'flutter_secure_storage 10.3.1 (RR Pocket has 11.2.0, a breaking change)'));
      expect(why, contains('share_plus 13.3.0 (RR Pocket has 13.3.1)\n'));
      expect(why, contains('pocket pin --all'));
    });

    test('pin leaves the breaking one, --all pins it too', () async {
      final hello = await Phone(
              '127.0.0.1', storagePhone.port, storagePhone.code,
              fingerprint: storagePhone.fingerprint)
          .hello();

      final safe = await writePins(hello, temp);
      expect(safe.pins, {'share_plus': '13.3.1'});
      expect(safe.breaking.single.name, 'flutter_secure_storage');

      final all = await writePins(hello, temp, all: true);
      expect(all.pins, containsPair('flutter_secure_storage', '11.2.0'));

      // pub get then locks the pin; pinning again still sees 10.3.1.
      File('${temp.path}/pubspec.lock').writeAsStringSync(
        'packages:\n'
        '  flutter_secure_storage:\n    source: hosted\n    version: "11.2.0"\n'
        '  share_plus:\n    source: hosted\n    version: "13.3.1"\n',
      );
      final again = await writePins(hello, temp);
      expect(again.breaking.single.theirs, '10.3.1');
      expect(again.pins, isNot(contains('flutter_secure_storage')));
    });
  });

  test('ping fails before pairing', () async {
    final unpaired = PocketCli(config: PocketConfig('${temp.path}/none'));
    expect(await unpaired(['ping']), 1);
    expect(await cli(['ping']), 0);
  });

  test('unknown arguments print the usage', () async {
    expect(await cli(['frobnicate']), 64);
  });

  test('the device runs on the Dart of the Flutter SDK that registered it',
      () async {
    final dart = File('${temp.path}/sdk/bin/cache/dart-sdk/bin/dart')
      ..createSync(recursive: true);
    Future<FlutterResult> flutter(
      List<String> arguments, {
      String? workingDirectory,
    }) async =>
        (
          exitCode: 0,
          stdout: '{"flutterRoot": "${temp.path}/sdk"}',
          stderr: '',
        );
    Future<FlutterResult> missing(
      List<String> arguments, {
      String? workingDirectory,
    }) async =>
        (exitCode: 1, stdout: '', stderr: 'not found');

    expect(await findFlutterDart(flutter), dart.path);
    expect(await findFlutterDart(missing), isNull);
    dart.deleteSync();
    expect(await findFlutterDart(flutter), isNull);
  });

  test('the engine must match the SDK the project builds with', () {
    expect(
      () => checkEngine(
        {'engineRevision': 'a', 'flutterVersion': '3.47.7'},
        {'engineRevision': 'b', 'frameworkVersion': '3.48.0'},
      ),
      throwsA(isA<PocketException>().having(
        (e) => e.message,
        'message',
        contains('RR Pocket runs Flutter 3.47.7'),
      )),
    );
    checkEngine({'engineRevision': 'a'}, {'engineRevision': 'a'});
    checkEngine({'engineRevision': 'a'}, null);
  });
}
