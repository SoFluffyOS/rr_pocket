import 'dart:convert';
import 'dart:math';

/// What the QR code on the computer holds: where the phone posts its
/// address and code, and the token that proves it saw this code
/// (docs/pairing.md).
class PairLink {
  const PairLink({
    required this.hosts,
    required this.port,
    required this.token,
    required this.name,
  });

  /// The computer's addresses, best first.
  final List<String> hosts;
  final int port;
  final String token;

  /// The computer's name, for the phone to ask "Pair with `name`?".
  final String name;

  Uri toUri() => Uri(
        scheme: 'rrpocket',
        host: 'pair',
        queryParameters: {
          'v': '1',
          'hosts': hosts.join(','),
          'port': '$port',
          'token': token,
          'name': name,
        },
      );

  /// Null when [text] is not a pairing link.
  static PairLink? tryParse(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null || uri.scheme != 'rrpocket' || uri.host != 'pair') {
      return null;
    }
    final query = uri.queryParameters;
    final hosts = [
      for (final host in (query['hosts'] ?? '').split(','))
        if (host.isNotEmpty) host,
    ];
    final port = int.tryParse(query['port'] ?? '');
    final token = query['token'];
    if (hosts.isEmpty || port == null || token == null || token.isEmpty) {
      return null;
    }
    return PairLink(
      hosts: hosts,
      port: port,
      token: token,
      name: query['name'] ?? '',
    );
  }
}

/// 128 random bits, base64url without padding.
String newPairingToken([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = [for (var i = 0; i < 16; i++) source.nextInt(256)];
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// Compares [a] and [b] in constant time for strings of equal length.
bool sameToken(String a, String b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return difference == 0;
}
