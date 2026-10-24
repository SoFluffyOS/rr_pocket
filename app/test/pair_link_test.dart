import 'package:flutter_test/flutter_test.dart';
import 'package:rr_pocket/src/src.dart';

void main() {
  test('reads the link a computer shows', () {
    final link = PairLink.parse(
      'rrpocket://pair?v=1&hosts=192.168.1.5,10.0.0.3&port=53123'
      '&token=abc_-123&name=Simon%27s+MacBook+Pro',
    );

    expect(link.hosts, ['192.168.1.5', '10.0.0.3']);
    expect(link.port, 53123);
    expect(link.token, 'abc_-123');
    expect(link.name, "Simon's MacBook Pro");
    expect(link.pairUri('10.0.0.3').toString(), 'http://10.0.0.3:53123/pair');
  });

  test('reads the link the computer side builds', () {
    final uri = Uri(
      scheme: 'rrpocket',
      host: 'pair',
      queryParameters: {
        'v': '1',
        'hosts': '192.168.1.5',
        'port': '4000',
        'token': 't',
        'name': 'A & B = C',
      },
    );

    expect(PairLink.parse(uri.toString()).name, 'A & B = C');
  });

  test('cuts a long name to 64 characters', () {
    final name = '${'M' * 63}😀tail';
    final link = PairLink.parse(
      'rrpocket://pair?v=1&hosts=10.0.0.3&port=1&token=t'
      '&name=${Uri.encodeQueryComponent(name)}',
    );

    expect(link.name, '${'M' * 63}😀');
  });

  test('calls a computer without a name "your computer"', () {
    final link = PairLink.parse(
      'rrpocket://pair?v=1&hosts=10.0.0.3&port=1&token=t',
    );

    expect(link.name, 'your computer');
  });

  test('says when a code is not a pairing link', () {
    for (final text in [
      'https://flutter.dev',
      'rrpocket://other?v=1&hosts=10.0.0.3&port=1&token=t',
      'just text',
      '',
    ]) {
      expect(
        () => PairLink.parse(text),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('not for pairing'),
          ),
        ),
        reason: text,
      );
    }
  });

  test('says when the link is newer than this app', () {
    expect(
      () => PairLink.parse(
        'rrpocket://pair?v=2&hosts=10.0.0.3&port=1&token=t&name=Mac',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Update RR Pocket'),
        ),
      ),
    );
  });

  test('sends its code only to an address on the local network', () {
    for (final host in [
      '203.0.113.9',
      '8.8.8.8',
      '127.0.0.1',
      'evil.example.com',
      '172.32.0.1',
      'fe80::1',
    ]) {
      expect(
        () => PairLink.parse(
          'rrpocket://pair?v=1&hosts=$host&port=1&token=t&name=Mac',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('outside your Wi-Fi'),
          ),
        ),
        reason: host,
      );
    }
    final mixed = PairLink.parse(
      'rrpocket://pair?v=1&hosts=203.0.113.9,192.168.1.5,169.254.3.4'
      '&port=1&token=t',
    );
    expect(mixed.hosts, ['192.168.1.5', '169.254.3.4']);
  });

  test('refuses a link with parts missing', () {
    for (final query in [
      'v=1&port=1&token=t',
      'v=1&hosts=10.0.0.3&token=t',
      'v=1&hosts=10.0.0.3&port=70000&token=t',
      'v=1&hosts=10.0.0.3&port=1',
    ]) {
      expect(
        () => PairLink.parse('rrpocket://pair?$query'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('incomplete'),
          ),
        ),
        reason: query,
      );
    }
  });
}
