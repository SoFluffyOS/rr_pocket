import 'package:rr_pocket/src/constants.dart';

/// Where the phone listens, as typed from its home screen: `host` or
/// `host:port`.
class PhoneAddress {
  const PhoneAddress(this.host, this.port);

  final String host;
  final int port;

  /// Null when [text] is not an address.
  static PhoneAddress? tryParse(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.contains(RegExp(r'[\s/]'))) return null;
    final parts = trimmed.split(':');
    if (parts case [final host]) return PhoneAddress(host, controlPort);
    if (parts case [final host, final port] when host.isNotEmpty) {
      return switch (int.tryParse(port)) {
        final number? when number > 0 && number < 65536 =>
          PhoneAddress(host, number),
        _ => null,
      };
    }
    return null;
  }

  @override
  String toString() => switch (port) {
        controlPort => host,
        _ => '$host:$port',
      };
}

/// The pairing code as the phone checks it: digits only, so `1234-5678`
/// and `1234 5678` both work.
String normalizePairingCode(String code) =>
    code.replaceAll(RegExp(r'[\s-]'), '');
