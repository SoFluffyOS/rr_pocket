import 'package:flutter/services.dart';

/// What the phone posts to a computer whose QR code it scanned, in place of
/// its code: its certificate's fingerprint, and proof it saw the QR code
/// (docs/pairing.md).
typedef PairOffer = ({String fingerprint, String proof});

/// Where a computer reaches this phone, and the code it must show.
class Pairing {
  const Pairing({
    required this.address,
    required this.code,
    this.port = 8100,
    this.name = 'Android phone',
  });

  /// The phone's LAN address, null when it has none (no Wi-Fi).
  final String? address;
  final String code;

  /// The control server's port.
  final int port;

  /// The phone's model, such as `Pixel 7`.
  final String name;

  /// RR Pocket's own channel to its Kotlin side: pairing details, the code
  /// scanner, pairing links, and the computer asking to pair.
  static const channel = MethodChannel('rr_pocket/pairing');

  /// Null where nothing answers (tests, a host without RR Pocket's activity).
  static Future<Pairing?> load() async {
    try {
      final info = await channel.invokeMapMethod<String, Object?>('info');
      if (info case {'code': final String code}) {
        return Pairing(
          address: info['address'] as String?,
          code: code,
          port: switch (info['port']) {
            final int port => port,
            _ => 8100,
          },
          name: switch (info['name']) {
            final String name when name.isNotEmpty => name,
            _ => 'Android phone',
          },
        );
      }
    } on MissingPluginException {
      return null;
    }
    return null;
  }

  /// Keeps [token], from a QR code the user allowed, for the computer to
  /// redeem over TLS. Null where nothing answers.
  static Future<PairOffer?> offer(String token) async {
    try {
      final offer = await channel.invokeMapMethod<String, String>(
        'offerPairing',
        {'token': token},
      );
      if (offer case {'fingerprint': final fingerprint, 'proof': final proof}) {
        return (fingerprint: fingerprint, proof: proof);
      }
      return null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// The code in two groups of four, easier to read out.
  String get displayCode => switch (code.length) {
    8 => '${code.substring(0, 4)} ${code.substring(4)}',
    _ => code,
  };
}
