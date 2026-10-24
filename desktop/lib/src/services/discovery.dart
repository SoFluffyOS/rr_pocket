import 'dart:async';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';
import 'package:rr_pocket/src/models/models.dart';

/// The DNS-SD type RR Pocket advertises (docs/pairing.md).
const String pocketServiceType = '_rrpocket._tcp';

/// The phones running RR Pocket on this network, found by mDNS within
/// [timeout]. Empty when multicast is blocked or nothing answers: the
/// caller falls back to a QR code or typing.
Future<List<FoundPhone>> discoverPhones({
  Duration timeout = const Duration(seconds: 3),
  MDnsClient Function()? client,
}) async {
  final mdns = (client ?? MDnsClient.new)();
  try {
    await mdns.start();
  } on SocketException {
    return const [];
  }
  final found = <FoundPhone>{};
  try {
    final pointers = mdns.lookup<PtrResourceRecord>(
      ResourceRecordQuery.serverPointer('$pocketServiceType.local'),
      timeout: timeout,
    );
    final resolving = <Future<void>>[];
    await for (final pointer in pointers) {
      resolving.add(
        _resolve(mdns, pointer.domainName, timeout).then((phones) {
          found.addAll(phones);
        }),
      );
    }
    await Future.wait(resolving);
  } on SocketException {
    // Multicast went away mid-lookup: keep what was found.
  } finally {
    mdns.stop();
  }
  return found.toList()..sort((a, b) => a.name.compareTo(b.name));
}

Future<List<FoundPhone>> _resolve(
  MDnsClient mdns,
  String domain,
  Duration timeout,
) async {
  final phones = <FoundPhone>[];
  final texts = await mdns
      .lookup<TxtResourceRecord>(
        ResourceRecordQuery.text(domain),
        timeout: timeout,
      )
      .toList();
  final txt = {for (final record in texts) ...parseTxt(record.text)};
  await for (final service in mdns.lookup<SrvResourceRecord>(
    ResourceRecordQuery.service(domain),
    timeout: timeout,
  )) {
    await for (final address in mdns.lookup<IPAddressResourceRecord>(
      ResourceRecordQuery.addressIPv4(service.target),
      timeout: timeout,
    )) {
      phones.add(
        FoundPhone(
          name: txt['model'] ?? instanceName(domain, pocketServiceType),
          host: address.address.address,
          port: service.port,
          flutterVersion: txt['flutter'],
        ),
      );
    }
  }
  return phones;
}
