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
    await Phone('127.0.0.1', phone.port, phone.code).save(config);
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
