import 'package:flutter/services.dart';

/// Where a computer reaches this phone, and the code it must show.
class Pairing {
  const Pairing({required this.address, required this.code});

  /// The phone's LAN address, null when it has none (no Wi-Fi).
  final String? address;
  final String code;

  static const _channel = MethodChannel('rr_pocket/pairing');

  /// Null where nothing answers (tests, a host without RR Pocket's activity).
  static Future<Pairing?> load() async {
    try {
      final info = await _channel.invokeMapMethod<String, Object?>('info');
      if (info case {'code': final String code}) {
        return Pairing(address: info['address'] as String?, code: code);
      }
    } on MissingPluginException {
      return null;
    }
    return null;
  }

  /// The code in two groups of four, easier to read out.
  String get displayCode => switch (code.length) {
    8 => '${code.substring(0, 4)} ${code.substring(4)}',
    _ => code,
  };
}
