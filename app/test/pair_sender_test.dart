import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rr_pocket/src/src.dart';

// Plain tests, no testWidgets: flutter_test's widget binding answers every
// HttpClient request with 400, and these need real sockets.
void main() {
  const phone = Pairing(
    address: '192.168.1.20',
    code: 'H79GN4XS',
    name: 'Pixel 7',
  );
  late HttpServer computer;
  late List<Map<String, Object?>> posts;
  late Future<void> Function(HttpRequest request) answer;

  setUp(() async {
    posts = [];
    answer = (request) => _reply(request, 200, {'computer': "Simon's Mac"});
    computer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    computer.listen((request) async {
      final body = await utf8.decodeStream(request);
      posts.add({
        'length': request.contentLength,
        'method': request.method,
        'path': request.uri.path,
        ...jsonDecode(body) as Map<String, Object?>,
      });
      await answer(request);
    });
  });

  tearDown(() => computer.close(force: true));

  PairLink link({List<String> hosts = const ['127.0.0.1']}) => PairLink(
    hosts: hosts,
    port: computer.port,
    token: 'token-1',
    name: "Simon's Mac",
  );

  test("posts the phone's name, address, port and code", () async {
    final result = await const PairSender().send(link(), phone);

    expect(
      result,
      isA<Paired>().having((r) => r.computer, 'computer', "Simon's Mac"),
    );
    expect(posts, [
      {
        'length': isPositive,
        'method': 'POST',
        'path': '/pair',
        'token': 'token-1',
        'name': 'Pixel 7',
        'address': '192.168.1.20',
        'port': 8100,
        'code': 'H79GN4XS',
      },
    ]);
  });

  test('tries the next address when one does not answer', () async {
    // Nothing listens on IPv6 loopback at this port.
    final result = await const PairSender().send(
      link(hosts: ['::1', '127.0.0.1']),
      phone,
    );

    expect(result, isA<Paired>());
    expect(posts, hasLength(1));
  });

  test(
    'moves on from an address that takes the connection but never answers',
    () async {
      final stalled = await ServerSocket.bind(
        InternetAddress.loopbackIPv6,
        computer.port,
      );
      addTearDown(stalled.close);
      final held = <Socket>[];
      stalled.listen(held.add);
      addTearDown(() {
        for (final socket in held) {
          socket.destroy();
        }
      });

      final result = await const PairSender(
        answerTimeout: Duration(milliseconds: 300),
      ).send(link(hosts: ['::1', '127.0.0.1']), phone);

      expect(result, isA<Paired>());
    },
  );

  test("shows the computer's reason when it refuses", () async {
    answer = (request) => _reply(request, 403, {
      'error': 'this code is not the one showing; scan it again',
    });

    final result = await const PairSender().send(link(), phone);

    expect(
      result,
      isA<PairFailed>().having(
        (r) => r.message,
        'message',
        'Not paired: this code is not the one showing; scan it again',
      ),
    );
  });

  test('says when the computer could not reach the phone', () async {
    answer = (request) => _reply(request, 502, {
      'error': 'the computer could not reach the phone at 192.168.1.20:8100',
    });

    final result = await const PairSender().send(
      link(hosts: ['127.0.0.1', '::1']),
      phone,
    );

    expect(
      result,
      isA<PairFailed>().having(
        (r) => r.message,
        'message',
        contains('could not reach the phone'),
      ),
    );
    expect(posts, hasLength(1), reason: 'a computer that answered is the one');
  });

  test('says when no address answers', () async {
    final closed = link();
    await computer.close(force: true);

    final result = await const PairSender().send(closed, phone);

    expect(
      result,
      isA<PairFailed>().having(
        (r) => r.message,
        'message',
        contains('Could not reach'),
      ),
    );
  });

  test('sends nothing without a Wi-Fi address', () async {
    final result = await const PairSender().send(
      link(),
      const Pairing(address: null, code: 'H79GN4XS'),
    );

    expect(
      result,
      isA<PairFailed>().having((r) => r.message, 'message', contains('Wi-Fi')),
    );
    expect(posts, isEmpty);
  });
}

Future<void> _reply(
  HttpRequest request,
  int status,
  Map<String, Object?> body,
) async {
  request.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  await request.response.close();
}
