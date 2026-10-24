import 'dart:io';

/// What the QR code on a computer holds (docs/pairing.md):
/// `rrpocket://pair?v=1&hosts=<a>,<b>&port=<port>&token=<token>&name=<name>`.
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

  /// Proves the phone saw the code the computer is showing.
  final String token;

  /// The computer's name, for "Pair with `name`?".
  final String name;

  /// Throws a [FormatException] whose message the user can act on.
  static PairLink parse(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null || uri.scheme != 'rrpocket' || uri.host != 'pair') {
      throw const FormatException(
        'That QR code is not for pairing RR Pocket. '
        'Scan the one your computer shows.',
      );
    }
    final query = uri.queryParameters;
    if (query['v'] != '1') {
      throw const FormatException(
        'This pairing code is newer than RR Pocket. '
        'Update RR Pocket, then scan it again.',
      );
    }
    final listed = [
      for (final host in (query['hosts'] ?? '').split(','))
        if (host.trim() case final address when address.isNotEmpty) address,
    ];
    // Any page or app can open an rrpocket:// link, so the phone sends its
    // code only to an address on its own network: never the internet, nor
    // this phone itself, where another app could be listening.
    final hosts = [
      for (final host in listed)
        if (isLocalNetworkAddress(host)) host,
    ];
    final port = int.tryParse(query['port'] ?? '') ?? 0;
    final token = query['token'] ?? '';
    if (listed.isNotEmpty && hosts.isEmpty) {
      throw const FormatException(
        'This pairing code points outside your Wi-Fi, so RR Pocket won\'t '
        'send its code there. Scan the code your own computer shows.',
      );
    }
    if (hosts.isEmpty || port < 1 || port > 65535 || token.isEmpty) {
      throw const FormatException(
        'This pairing code is incomplete. '
        'Show a new one on your computer and scan it again.',
      );
    }
    return PairLink(
      hosts: hosts,
      port: port,
      token: token,
      name: switch (query['name']?.trim()) {
        // Cut as /pair cuts a computer's name.
        final name? when name.isNotEmpty => String.fromCharCodes(
          name.runes.take(maxName),
        ),
        _ => 'your computer',
      },
    );
  }

  static const maxName = 64;

  /// Whether [host] is an IPv4 address on a local network: private
  /// (10/8, 172.16/12, 192.168/16) or link-local (169.254/16).
  static bool isLocalNetworkAddress(String host) {
    final address = InternetAddress.tryParse(host);
    if (address == null || address.type != InternetAddressType.IPv4) {
      return false;
    }
    return switch (address.rawAddress) {
      [10, _, _, _] => true,
      [172, final second, _, _] when second >= 16 && second <= 31 => true,
      [192, 168, _, _] => true,
      [169, 254, _, _] => true,
      _ => false,
    };
  }

  /// Where the phone posts its address and code on [host].
  Uri pairUri(String host) =>
      Uri(scheme: 'http', host: host, port: port, path: '/pair');
}
