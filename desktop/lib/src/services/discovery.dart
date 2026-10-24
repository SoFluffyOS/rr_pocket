import 'dart:async';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';
import 'package:rr_pocket/src/models/models.dart';

/// The DNS-SD type RR Pocket advertises (docs/pairing.md).
const String pocketServiceType = '_rrpocket._tcp';

/// The phones running RR Pocket on this network, found by mDNS: those that
/// answer within [browse], each resolved within [resolve] of answering.
/// Empty when multicast is blocked or nothing answers: the caller falls back
/// to a QR code or typing.
Future<List<FoundPhone>> discoverPhones({
  Duration browse = const Duration(milliseconds: 1500),
  Duration resolve = const Duration(milliseconds: 1500),
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
      timeout: browse,
    );
    final resolving = <Future<void>>[];
    await for (final pointer in pointers) {
      resolving.add(
        _resolve(mdns, pointer.domainName, resolve).then((phone) {
          if (phone != null) found.add(phone);
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

/// The phone behind a service [domain], from the first answer to each
/// lookup rather than waiting out [timeout]; null when one never comes.
Future<FoundPhone?> _resolve(
  MDnsClient mdns,
  String domain,
  Duration timeout,
) async {
  Future<T?> first<T extends ResourceRecord>(ResourceRecordQuery query) async {
    try {
      return await mdns.lookup<T>(query, timeout: timeout).first;
    } on StateError {
      return null;
    }
  }

  final (service, text) = await (
    first<SrvResourceRecord>(ResourceRecordQuery.service(domain)),
    first<TxtResourceRecord>(ResourceRecordQuery.text(domain)),
  ).wait;
  if (service == null) return null;
  final address = await first<IPAddressResourceRecord>(
    ResourceRecordQuery.addressIPv4(service.target),
  );
  if (address == null) return null;
  final txt = switch (text) {
    final record? => parseTxt(record.text),
    null => const <String, String>{},
  };
  return FoundPhone(
    name: txt['model'] ?? instanceName(domain, pocketServiceType),
    host: address.address.address,
    port: service.port,
    flutterVersion: txt['flutter'],
  );
}
