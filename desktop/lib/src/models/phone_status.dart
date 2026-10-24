import 'package:rr_pocket/src/models/plugin_versions.dart';

/// The paired phone as last seen.
sealed class PhoneStatus {
  const PhoneStatus();
}

class NotPaired extends PhoneStatus {
  const NotPaired();
}

class Reachable extends PhoneStatus {
  const Reachable({
    required this.name,
    required this.address,
    required this.flutterVersion,
    required this.pluginCount,
  });

  factory Reachable.fromHello(String address, Map<String, Object?> hello) {
    return Reachable(
      name: '${hello['name'] ?? 'RR Pocket'}',
      address: address,
      flutterVersion: '${hello['flutterVersion'] ?? 'unknown'}',
      pluginCount: bundledPlugins(hello).length,
    );
  }

  final String name;
  final String address;
  final String flutterVersion;
  final int pluginCount;

  String get summary =>
      '$name at $address: Flutter $flutterVersion, $pluginCount plugins.';
}

class Unreachable extends PhoneStatus {
  const Unreachable({required this.address, required this.reason});

  final String address;
  final String reason;
}
