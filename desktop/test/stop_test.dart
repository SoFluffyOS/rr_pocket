@TestOn('posix')
library;

import 'dart:async';
import 'dart:io';

import 'package:rr_pocket/rr_pocket.dart';
import 'package:test/test.dart';

import 'support/fake_phone.dart';

/// Flutter stops a run by sending SIGTERM to the process it started, and
/// to nothing else. The command it saved must hear it, so RR Pocket stops
/// the app and goes back to its own screen.
void main() {
  late Directory temp;
  late FakePhone phone;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('rr_pocket_stop_test');
    phone = await FakePhone.start();
  });

  tearDown(() async {
    await phone.close();
    await temp.delete(recursive: true);
  });

  test('the device command stops the app on SIGTERM', () async {
    final config = PocketConfig('${temp.path}/.config/rr_pocket');
    await Phone('127.0.0.1', phone.port, phone.code).save(config);
    final helper = await currentHelperCommand();
    expect(helper, isNot(contains('global')));

    final process = await Process.start(
      helper.first,
      [...helper.skip(1), 'run', 'app'],
      environment: {'HOME': temp.path},
    );
    // Read all of it, as Flutter does: a closed pipe would end the command.
    final listening = Completer<void>();
    process.stdout.transform(const SystemEncoding().decoder).listen((text) {
      if (text.contains('VM service is listening') && !listening.isCompleted) {
        listening.complete();
      }
    });
    unawaited(process.stderr.drain<void>());
    await listening.future;
    process.kill(ProcessSignal.sigterm);

    expect(await process.exitCode.timeout(const Duration(seconds: 10)), 0);
    expect(phone.requests, contains('POST /stop'));
  });
}
