import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:multicast_dns/multicast_dns.dart';
import 'package:rr_pocket/rr_pocket.dart';
import 'package:test/test.dart';

import 'support/fake_phone.dart';

void main() {
  group('the pairing link', () {
    const link = PairLink(
      hosts: ['192.168.1.5', '10.0.0.3'],
      port: 53123,
      token: 'abc_DEF-123',
      name: "Simon's MacBook Pro",
    );

    test('round-trips through its URI', () {
      final uri = link.toUri();
      expect(uri.scheme, 'rrpocket');
      expect(uri.host, 'pair');
      expect(uri.queryParameters['v'], '1');
      final parsed = PairLink.tryParse('$uri');
      expect(parsed?.hosts, link.hosts);
      expect(parsed?.port, link.port);
      expect(parsed?.token, link.token);
      expect(parsed?.name, link.name);
    });

    test('refuses what is not one', () {
      for (final text in [
        'https://example.com/pair?hosts=1.2.3.4&port=1&token=t',
        'rrpocket://other?hosts=1.2.3.4&port=1&token=t',
        'rrpocket://pair?port=1&token=t',
        'rrpocket://pair?hosts=1.2.3.4&token=t',
        'rrpocket://pair?hosts=1.2.3.4&port=1',
      ]) {
        expect(PairLink.tryParse(text), isNull, reason: text);
      }
    });

    test('tokens are 128 bits, base64url, no padding', () {
      final token = newPairingToken(Random(1));
      expect(token, hasLength(22));
      expect(token, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      expect(newPairingToken(), isNot(newPairingToken()));
      expect(sameToken(token, token), isTrue);
      expect(sameToken(token, newPairingToken(Random(2))), isFalse);
      expect(sameToken(token, '$token!'), isFalse);
    });
  });

  group('QR codes', () {
    const data = 'rrpocket://pair?v=1&hosts=192.168.1.5&port=53123&token=abc';

    test('are square, with finder patterns inside the quiet zone', () {
      final modules = qrModules(data);
      expect(modules.every((row) => row.length == modules.length), isTrue);
      expect(modules.first.every((dark) => !dark), isTrue);
      // The top-left finder pattern's corner, after 4 quiet modules.
      expect(modules[4][4], isTrue);
      expect(modules[3][3], isFalse);
    });

    test('draw in a terminal two rows per line, black on white with ANSI', () {
      final modules = qrModules(data);
      final plain = qrTerminal(data, ansi: false).split('\n');
      expect(plain, hasLength((modules.length + 1) ~/ 2));
      expect(plain.first, hasLength(modules.length));
      final ansi = qrTerminal(data, ansi: true).split('\n').first;
      expect(ansi, startsWith('\x1B[30;47m'));
      expect(ansi, endsWith('\x1B[0m'));
    });

    test('draw as SVG', () {
      final svg = qrSvg(data, pixels: 200);
      expect(svg, startsWith('<svg'));
      expect(svg, contains('width="200"'));
      expect(svg, contains('fill="#000"'));
    });
  });

  group('the network', () {
    test('site-local addresses', () {
      expect(isSiteLocal('192.168.110.185'), isTrue);
      expect(isSiteLocal('10.0.2.16'), isTrue);
      expect(isSiteLocal('172.20.1.1'), isTrue);
      expect(isSiteLocal('172.32.1.1'), isFalse);
      expect(isSiteLocal('8.8.8.8'), isFalse);
      expect(isSiteLocal('127.0.0.1'), isFalse);
    });

    test('TXT records and instance names', () {
      expect(parseTxt('v=1\nmodel=Pixel 7\nflutter=3.47.7'), {
        'v': '1',
        'model': 'Pixel 7',
        'flutter': '3.47.7',
      });
      expect(parseTxt('junk\n=x'), isEmpty);
      expect(
        instanceName('Pixel 7 (2)._rrpocket._tcp.local', pocketServiceType),
        'Pixel 7 (2)',
      );
    });

    test('discovery resolves what mDNS answers', () async {
      final phones = await discoverPhones(client: FakeMdns.new);
      expect(phones, hasLength(1));
      expect(phones.single.name, 'Pixel 7');
      expect(phones.single.host, '192.168.1.20');
      expect(phones.single.port, 8100);
      expect(phones.single.flutterVersion, '3.47.7');
    });

    test('discovery returns as soon as the phone answers', () async {
      final watch = Stopwatch()..start();
      final phones = await discoverPhones(
        client: LingeringMdns.new,
        browse: const Duration(milliseconds: 300),
        resolve: const Duration(seconds: 5),
      );
      expect(phones.single.name, 'Pixel 7');
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('discovery finds nothing when multicast is blocked', () async {
      expect(await discoverPhones(client: BlockedMdns.new), isEmpty);
    });
  });

  group('asking a found phone', () {
    late FakePhone phone;

    setUp(() async => phone = await FakePhone.start());
    tearDown(() => phone.close());

    test('gets the code when the user allows it, and the certificate',
        () async {
      final given = await requestPairing('127.0.0.1', phone.port, 'Mac');
      expect(given.code, phone.code);
      expect(given.fingerprint, phone.fingerprint);
      expect(phone.pairRequests, ['Mac']);
    });

    test('says why when it does not', () async {
      for (final (answer, words) in [
        (PairAnswer.refuse, 'refused'),
        (PairAnswer.noAnswer, 'no answer'),
        (PairAnswer.busy, 'another computer'),
      ]) {
        phone.pairAnswer = answer;
        await expectLater(
          requestPairing('127.0.0.1', phone.port, 'Mac'),
          throwsA(isA<PocketException>()
              .having((e) => e.message, 'message', contains(words))),
        );
      }
    });

    test('gives up after its timeout', () async {
      final silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      silent.listen((_) {});
      await expectLater(
        requestPairing(
          '127.0.0.1',
          silent.port,
          'Mac',
          timeout: const Duration(milliseconds: 300),
        ),
        throwsA(isA<PocketException>()
            .having((e) => e.message, 'message', 'no answer on the phone')),
      );
      await silent.close();
    });
  });

  group('the QR listener', () {
    late FakePhone phone;
    late PairListener listener;

    setUp(() async {
      phone = await FakePhone.start()
        ..offeredToken = 'the-token';
      listener = await PairListener.start(
        computer: 'Mac',
        hosts: const ['127.0.0.1'],
        verify: (phone) => phone.hello(),
        token: 'the-token',
      );
    });

    tearDown(() async {
      await listener.close();
      await phone.close();
    });

    Future<(int, Map<String, Object?>)> post(Map<String, Object?> body) async {
      final client = HttpClient();
      try {
        final request =
            await client.post('127.0.0.1', listener.link.port, '/pair');
        request.write(jsonEncode(body));
        final response = await request.close();
        final json = jsonDecode(await utf8.decodeStream(response));
        return (response.statusCode, json as Map<String, Object?>);
      } finally {
        client.close();
      }
    }

    Map<String, Object?> fromPhone({
      String token = 'the-token',
      int? port,
      String? fingerprint,
    }) {
      final certificate = fingerprint ?? phone.fingerprint;
      return {
        'name': 'Pixel 7',
        'address': '127.0.0.1',
        'port': port ?? phone.port,
        'fingerprint': certificate,
        'proof': pairingProof(token, certificate),
      };
    }

    test('pairs the phone that scanned its code, once', () async {
      final (status, body) = await post(fromPhone());
      expect(status, 200);
      expect(body, {'computer': 'Mac'});
      final paired = await listener.paired;
      expect(paired.phone.code, phone.code);
      expect(paired.phone.fingerprint, phone.fingerprint);
      expect(paired.hello['name'], 'Test Phone');
      expect(phone.offeredToken, isNull, reason: 'the token was redeemed');
      paired.phone.close();
    });

    test('refuses a proof made without its token', () async {
      final (status, _) = await post(fromPhone(token: 'not-it'));
      expect(status, 403);
      expect(phone.offeredToken, 'the-token');
    });

    test('talks only to the certificate the proof was for', () async {
      final (status, body) = await post(
        fromPhone(fingerprint: FakePhone.fingerprintOf('other')),
      );
      expect(status, 502);
      expect('${body['error']}', contains('not the RR Pocket'));
      expect(phone.offeredToken, 'the-token', reason: 'nothing was sent');
    });

    test('says when it cannot reach the phone, and keeps waiting', () async {
      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close();

      final (status, body) = await post(fromPhone(port: port));
      expect(status, 502);
      expect('${body['error']}', contains('could not reach the phone'));

      final (retried, _) = await post(fromPhone());
      expect(retried, 200);
      (await listener.paired).phone.close();
    });

    test('refuses a body too large to be a pairing, and keeps waiting',
        () async {
      final (status, _) = await post({...fromPhone(), 'pad': 'x' * 10000});
      expect(status, 413);

      final (retried, _) = await post(fromPhone());
      expect(retried, 200);
      (await listener.paired).phone.close();
    });

    test('serves the QR page to this computer', () async {
      final client = HttpClient();
      final request = await client.getUrl(listener.pageUri);
      final response = await request.close();
      final page = await utf8.decodeStream(response);
      client.close();
      expect(response.statusCode, 200);
      expect(page, contains('<svg'));
      expect(page, contains('Scan with RR Pocket'));
    });

    test('closing it cancels the wait', () async {
      final waiting = listener.paired;
      await listener.close();
      await expectLater(waiting, throwsA(isA<PairingCancelled>()));
    });

    test('expires', () async {
      final short = await PairListener.start(
        computer: 'Mac',
        hosts: const ['127.0.0.1'],
        verify: (phone) => phone.hello(),
        lifetime: const Duration(milliseconds: 100),
      );
      await expectLater(
        short.paired,
        throwsA(isA<PocketException>().having(
          (e) => e.message,
          'message',
          contains('no phone scanned'),
        )),
      );
    });

    test('needs an address on a local network', () async {
      await expectLater(
        PairListener.start(
          computer: 'Mac',
          hosts: const [],
          verify: (phone) => phone.hello(),
        ),
        throwsA(isA<PocketException>()),
      );
    });
  });
}

/// An mDNS client that finds one phone.
class FakeMdns extends MDnsClient {
  @override
  Future<void> start({
    InternetAddress? listenAddress,
    NetworkInterfacesFactory? interfacesFactory,
    int mDnsPort = 5353,
    InternetAddress? mDnsAddress,
    Function? onError,
  }) async {}

  @override
  void stop() {}

  @override
  Stream<T> lookup<T extends ResourceRecord>(
    ResourceRecordQuery query, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    const domain = 'Pixel 7._rrpocket._tcp.local';
    final until = DateTime.now().millisecondsSinceEpoch + 60000;
    final records = <ResourceRecord>[
      if (query.resourceRecordType == ResourceRecordType.serverPointer)
        PtrResourceRecord('_rrpocket._tcp.local', until, domainName: domain),
      if (query.resourceRecordType == ResourceRecordType.text)
        TxtResourceRecord(domain, until,
            text: 'v=1\nmodel=Pixel 7\nflutter=3.47.7'),
      if (query.resourceRecordType == ResourceRecordType.service)
        SrvResourceRecord(domain, until,
            target: 'pixel.local', port: 8100, priority: 0, weight: 0),
      if (query.resourceRecordType == ResourceRecordType.addressIPv4)
        IPAddressResourceRecord('pixel.local', until,
            address: InternetAddress('192.168.1.20')),
    ];
    return Stream.fromIterable(records.whereType<T>());
  }
}

/// An mDNS client whose answers come at once but whose lookups stay open
/// until their timeout, as on a real network.
class LingeringMdns extends FakeMdns {
  @override
  Stream<T> lookup<T extends ResourceRecord>(
    ResourceRecordQuery query, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    final controller = StreamController<T>();
    super.lookup<T>(query).forEach(controller.add);
    Timer(timeout, controller.close);
    return controller.stream;
  }
}

/// An mDNS client on a network that blocks multicast.
class BlockedMdns extends MDnsClient {
  @override
  Future<void> start({
    InternetAddress? listenAddress,
    NetworkInterfacesFactory? interfacesFactory,
    int mDnsPort = 5353,
    InternetAddress? mDnsAddress,
    Function? onError,
  }) async =>
      throw const SocketException('multicast blocked');

  @override
  void stop() {}
}
