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
    // [fe80::1]:8100, or a bare IPv6 address on the control port.
    if (RegExp(r'^\[([^\]]+)\](?::(\d+))?$').firstMatch(trimmed)
        case final match?) {
      return _withPort(match.group(1), match.group(2) ?? '$controlPort');
    }
    if (trimmed.startsWith('[')) return null;
    final parts = trimmed.split(':');
    return switch (parts) {
      [final host] => PhoneAddress(host, controlPort),
      [final host, final port] => _withPort(host, port),
      _ => PhoneAddress(trimmed, controlPort),
    };
  }

  static PhoneAddress? _withPort(String? host, String port) {
    if (host == null || host.isEmpty) return null;
    return switch (int.tryParse(port)) {
      final number? when number > 0 && number < 65536 =>
        PhoneAddress(host, number),
      _ => null,
    };
  }

  @override
  String toString() {
    final shown = switch (host.contains(':')) {
      true => '[$host]',
      false => host,
    };
    return switch (port) {
      controlPort => shown,
      _ => '$shown:$port',
    };
  }
}

/// The pairing code as the phone checks it: digits only, so `1234-5678`
/// and `1234 5678` both work.
String normalizePairingCode(String code) =>
    code.replaceAll(RegExp(r'[\s-]'), '');
