import 'dart:io';

import 'package:rr_pocket/src/models/models.dart';
import 'package:rr_pocket/src/services/phone.dart';

/// The paired phone and its `/hello`. When it doesn't answer where it
/// paired, because the Wi-Fi gave it a new address, looks for it on the
/// network ([discover]): a phone there that shows the pinned certificate is
/// the same phone, so the pairing moves to its address and [moved] hears
/// where. Any other phone fails the certificate check and is left alone.
///
/// Only an error that a new address explains starts a search: a timeout is
/// more likely a phone asleep, and Flutter's ping, which calls this on every
/// poll, would wait out a search each time for nothing.
Future<(Phone, Map<String, Object?>)> reachPhone(
  PocketConfig config, {
  required Future<List<FoundPhone>> Function() discover,
  void Function(PhoneAddress address)? moved,
}) async {
  final phone = await Phone.load(config);
  try {
    return (phone, await phone.hello());
  } on Object catch (error) {
    if (error is! SocketException && error is! TlsException) rethrow;
    final found = await discover();
    for (final candidate in found) {
      if (candidate.host == phone.host && candidate.port == phone.port) {
        continue;
      }
      final there = Phone(
        candidate.host,
        candidate.port,
        phone.code,
        fingerprint: phone.fingerprint,
      );
      try {
        final hello = await there.hello();
        await there.save(config);
        phone.close();
        moved?.call(PhoneAddress(there.host, there.port));
        return (there, hello);
      } on Object {
        there.close();
      }
    }
    rethrow;
  }
}
