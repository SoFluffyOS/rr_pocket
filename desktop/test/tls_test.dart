import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:rr_pocket/rr_pocket.dart';
import 'package:test/test.dart';

import 'support/fake_phone.dart';

void main() {
  late FakePhone phone;

  setUp(() async => phone = await FakePhone.start());
  tearDown(() => phone.close());

  group('the phone', () {
    test('answers when it shows the certificate pinned', () async {
      final pinned = Phone(
        '127.0.0.1',
        phone.port,
        phone.code,
        fingerprint: phone.fingerprint,
      );
      expect((await pinned.hello())['name'], 'Test Phone');
      pinned.close();
    });

    test('is refused when it shows another certificate', () async {
      final pinned = Phone(
        '127.0.0.1',
        phone.port,
        phone.code,
        fingerprint: FakePhone.fingerprintOf('other'),
      );
      Object? error;
      try {
        await pinned.hello();
      } catch (e) {
        error = e;
      }
      pinned.close();

      expect(error, isA<TlsException>());
      expect(describePhoneError(error ?? ''), contains('pair again'));
      expect(phone.requests, isEmpty, reason: 'the code was never sent');
    });

    test('typed in, is pinned as first seen', () async {
      final config = PocketConfig(
        (await Directory.systemTemp.createTemp('rr_pocket_tls')).path,
      );
      addTearDown(() => Directory(config.directory).delete(recursive: true));
      final typed = Phone('127.0.0.1', phone.port, phone.code);
      expect(typed.fingerprint, isNull);
      await expectLater(typed.save(config), throwsA(isA<PocketException>()));

      await typed.hello();
      await typed.save(config);
      typed.close();

      final saved = jsonDecode(config.deviceFile.readAsStringSync()) as Map;
      expect(saved['fingerprint'], phone.fingerprint);
      expect((await Phone.tryLoad(config))?.fingerprint, phone.fingerprint);
    });

    test('gives up on a phone that takes a request and never answers',
        () async {
      final silent = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        FakePhone.identity(),
      );
      final held = <Socket>[];
      silent.listen(held.add);
      addTearDown(() async {
        for (final socket in held) {
          socket.destroy();
        }
        await silent.close();
      });
      final pinned = Phone(
        '127.0.0.1',
        silent.port,
        phone.code,
        fingerprint: phone.fingerprint,
      );

      await expectLater(
        pinned.call(
          'GET',
          '/hello',
          timeout: const Duration(milliseconds: 300),
        ),
        throwsA(isA<TimeoutException>()),
      );
      pinned.close();
    });

    test('a pairing from before TLS counts as none', () async {
      final config = PocketConfig(
        (await Directory.systemTemp.createTemp('rr_pocket_tls')).path,
      );
      addTearDown(() => Directory(config.directory).delete(recursive: true));
      config.deviceFile.writeAsStringSync(
        jsonEncode({'host': '127.0.0.1', 'port': phone.port, 'code': 'X'}),
      );

      expect(await Phone.tryLoad(config), isNull);
    });
  });

  group('the VM tunnel', () {
    late SecureServerSocket relay;

    setUp(() async {
      relay = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        FakePhone.identity(),
      );
      // An echoing VM service behind the relay.
      relay.listen(
        (socket) => socket.listen(socket.add, onDone: socket.close),
        // A client that refuses the certificate ends the handshake.
        onError: (Object _) {},
      );
    });

    tearDown(() => relay.close());

    Future<String?> through(VmTunnel tunnel) async {
      final local = await Socket.connect('127.0.0.1', tunnel.port);
      local.done.ignore();
      local.add(utf8.encode('ping'));
      try {
        return await local
            .map(utf8.decode)
            .first
            .timeout(const Duration(seconds: 5));
      } on StateError {
        return null; // closed without a word
      } on SocketException {
        return null; // reset
      } finally {
        local.destroy();
      }
    }

    test('carries a local connection to the pinned relay', () async {
      final tunnel = await VmTunnel.start(
        host: '127.0.0.1',
        port: relay.port,
        trusts: (certificate) =>
            certificateFingerprint(certificate) == phone.fingerprint,
      );
      expect(await through(tunnel), 'ping');
      await tunnel.close();
    });

    test('carries a large stream intact, and an end from either side',
        () async {
      final tunnel = await VmTunnel.start(
        host: '127.0.0.1',
        port: relay.port,
        trusts: (certificate) =>
            certificateFingerprint(certificate) == phone.fingerprint,
      );
      final local = await Socket.connect('127.0.0.1', tunnel.port);
      final sent = List<int>.generate(8 << 20, (i) => i * 31 & 0xff);
      final received = BytesBuilder(copy: false);
      final echoed = Completer<void>();
      final ended = Completer<void>();
      local.listen(
        (chunk) {
          received.add(chunk);
          if (received.length == sent.length) echoed.complete();
        },
        onDone: ended.complete,
      );
      local.add(sent);

      await echoed.future.timeout(const Duration(seconds: 20));
      expect(received.takeBytes(), sent);
      await local.close();
      await ended.future.timeout(const Duration(seconds: 5));
      await tunnel.close();
    });

    test('carries nothing to a relay with another certificate', () async {
      final tunnel = await VmTunnel.start(
        host: '127.0.0.1',
        port: relay.port,
        trusts: (certificate) =>
            certificateFingerprint(certificate) ==
            FakePhone.fingerprintOf('other'),
      );
      expect(await through(tunnel), isNull);
      await tunnel.close();
    });
  });

  test('the QR proof is HMAC-SHA256 of the fingerprint, keyed by the token',
      () {
    // RFC 4231, test case 2; RR Pocket's PairOffersTest checks the same.
    expect(
      pairingProof('Jefe', 'what do ya want for nothing?'),
      '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843',
    );
    expect(provesPairing(pairingProof('t', 'f'), 't', 'f'), isTrue);
    expect(provesPairing(pairingProof('t', 'f'), 't', 'g'), isFalse);
  });
}
