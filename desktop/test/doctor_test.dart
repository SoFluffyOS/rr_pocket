import 'dart:io';

import 'package:rr_pocket/rr_pocket.dart';
import 'package:test/test.dart';

import 'support/fake_phone.dart';

void main() {
  late Directory temp;
  late FakePhone phone;
  late PocketConfig config;
  var engine = 'engine-a';
  var customDevices = true;

  Future<FlutterResult> flutter(
    List<String> arguments, {
    String? workingDirectory,
  }) async =>
      switch (arguments) {
        ['--version', '--machine'] => (
            exitCode: 0,
            stdout:
                '{"frameworkVersion": "3.47.7", "engineRevision": "$engine"}',
            stderr: '',
          ),
        ['config', '--list'] => (
            exitCode: 0,
            stdout: 'All Settings:\n  enable-custom-devices: $customDevices\n',
            stderr: '',
          ),
        _ => (exitCode: 1, stdout: '', stderr: 'unexpected'),
      };

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('rr_pocket_doctor');
    phone = await FakePhone.start(
      plugins: {'camera': '0.12.1', 'flutter_secure_storage': '11.2.0'},
    );
    config = PocketConfig('${temp.path}/config');
    engine = 'engine-a';
    customDevices = true;
  });

  tearDown(() async {
    await phone.close();
    await temp.delete(recursive: true);
  });

  Future<void> pairAndRegister() async {
    await Phone('127.0.0.1', phone.port, phone.code).save(config);
    await config.registeredFile.writeAsString('["dart"]');
  }

  List<DoctorState> states(List<DoctorCheck> checks) =>
      [for (final check in checks) check.state];

  test('all good', () async {
    await pairAndRegister();
    final checks = await runDoctor(config: config, flutter: flutter);
    expect(states(checks), everyElement(DoctorState.ok));
    expect(checks.first.found, contains('answers'));
  });

  test('not paired', () async {
    final checks = await runDoctor(config: config, flutter: flutter);
    expect(checks.first.state, DoctorState.problem);
    expect(checks.first.fix, contains('pocket pair'));
  });

  test('the phone does not answer', () async {
    await pairAndRegister();
    await phone.close();
    final checks = await runDoctor(config: config, flutter: flutter);
    expect(checks.first.found, contains('does not answer'));
  });

  test('another Flutter on the PATH', () async {
    await pairAndRegister();
    engine = 'engine-b';
    final checks = await runDoctor(config: config, flutter: flutter);
    final version = checks[1];
    expect(version.state, DoctorState.problem);
    expect(version.fix, contains('fvm use 3.47.7'));
  });

  test('custom devices off, or the device not registered', () async {
    await Phone('127.0.0.1', phone.port, phone.code).save(config);
    var checks = await runDoctor(config: config, flutter: flutter);
    expect(checks[2].state, DoctorState.warning);

    customDevices = false;
    checks = await runDoctor(config: config, flutter: flutter);
    expect(checks[2].state, DoctorState.problem);
    expect(checks[2].fix, contains('pocket pair'));
  });

  test("a project's plugins: to pin, breaking, missing", () async {
    await pairAndRegister();
    final project = Directory('${temp.path}/app')..createSync();
    File('${project.path}/pubspec.yaml').writeAsStringSync('name: app\n');
    File('${project.path}/pubspec.lock').writeAsStringSync(
      'packages:\n'
      '  camera:\n    source: hosted\n    version: "0.12.0"\n'
      '  flutter_secure_storage:\n    source: hosted\n    version: "10.3.1"\n',
    );
    File('${project.path}/.flutter-plugins-dependencies').writeAsStringSync(
      '{"plugins": {"android": [{"name": "ffmpeg_kit_flutter_new"}]}}',
    );

    final checks =
        await runDoctor(config: config, flutter: flutter, project: project);
    final text = describeDoctor(checks);

    expect(text, contains('camera 0.12.0 (RR Pocket has 0.12.1)'));
    expect(text, contains('→ Run `pocket pin` in the project.'));
    expect(text, contains('flutter_secure_storage 10.3.1'));
    expect(text, contains('pocket pin --all'));
    expect(text, contains('! RR Pocket does not carry ffmpeg_kit_flutter_new'));
  });
}
