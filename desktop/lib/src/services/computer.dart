import 'dart:io';

/// This computer's name, as the phone shows it: "Pair with `name`?".
String computerName() {
  final name = Platform.localHostname;
  for (final suffix in ['.local', '.lan', '.home']) {
    if (name.endsWith(suffix)) {
      return name.substring(0, name.length - suffix.length);
    }
  }
  return name;
}

/// This computer's site-local IPv4 addresses, Wi-Fi and Ethernet first,
/// where a phone on the same network can reach it.
Future<List<String>> localAddresses() async {
  final interfaces =
      await NetworkInterface.list(type: InternetAddressType.IPv4);
  int rank(NetworkInterface network) {
    final name = network.name.toLowerCase();
    final likely = ['en', 'eth', 'wlan', 'wi-fi', 'ethernet']
        .any((prefix) => name.startsWith(prefix));
    return switch (likely) {
      true => 0,
      false => 1,
    };
  }

  final ordered = interfaces.toList()
    ..sort((a, b) => rank(a).compareTo(rank(b)));
  return [
    for (final network in ordered)
      for (final address in network.addresses)
        if (isSiteLocal(address.address)) address.address,
  ];
}

/// 10/8, 172.16/12 and 192.168/16.
bool isSiteLocal(String ipv4) {
  final parts = [for (final part in ipv4.split('.')) int.tryParse(part) ?? -1];
  if (parts.length != 4) return false;
  return switch (parts) {
    [10, _, _, _] => true,
    [172, final second, _, _] when second >= 16 && second <= 31 => true,
    [192, 168, _, _] => true,
    _ => false,
  };
}
