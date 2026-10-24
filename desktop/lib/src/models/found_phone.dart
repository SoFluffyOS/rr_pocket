/// A phone running RR Pocket, found on the network by mDNS.
class FoundPhone {
  const FoundPhone({
    required this.name,
    required this.host,
    required this.port,
    this.flutterVersion,
  });

  /// The phone's model, as it advertises itself.
  final String name;
  final String host;
  final int port;
  final String? flutterVersion;

  @override
  bool operator ==(Object other) =>
      other is FoundPhone &&
      other.name == name &&
      other.host == host &&
      other.port == port;

  @override
  int get hashCode => Object.hash(name, host, port);

  @override
  String toString() => '$name ($host)';
}

/// The key=value pairs of a DNS-SD TXT record, one per line as
/// package:multicast_dns gives them.
Map<String, String> parseTxt(String text) => {
      for (final entry in text.split('\n'))
        if (entry.indexOf('=') case final at when at > 0)
          entry.substring(0, at): entry.substring(at + 1),
    };

/// The instance name of a service domain such as
/// `Pixel 7._rrpocket._tcp.local`.
String instanceName(String domain, String serviceType) {
  final suffix = '.$serviceType.local';
  if (!domain.endsWith(suffix)) return domain;
  return domain.substring(0, domain.length - suffix.length);
}
