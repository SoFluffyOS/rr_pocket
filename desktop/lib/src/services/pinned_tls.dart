import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:rr_pocket/src/models/models.dart';

/// SHA-256 of [certificate], lowercase hex: what the computer pins when it
/// pairs, and what RR Pocket's Kotlin side reports (docs/pairing.md).
String certificateFingerprint(X509Certificate certificate) =>
    sha256.convert(certificate.der).toString();

/// What the phone sends with a QR pairing to prove it saw the QR code:
/// HMAC-SHA256 of its certificate's [fingerprint], keyed with the QR code's
/// [token], lowercase hex.
String pairingProof(String token, String fingerprint) =>
    Hmac(sha256, utf8.encode(token))
        .convert(utf8.encode(fingerprint))
        .toString();

/// Whether [proof] is [pairingProof] of [token] and [fingerprint].
bool provesPairing(String proof, String token, String fingerprint) =>
    sameToken(proof, pairingProof(token, fingerprint));

/// The phone's certificate signs itself, so no certificate authority can
/// vouch for it: with no trusted roots, every certificate goes to [trusts],
/// which compares it with the pinned one.
SecurityContext pinnedContext() => SecurityContext(withTrustedRoots: false);

/// A certificate check that pins the first certificate it sees, for
/// pairing typed in or found on the network, where the computer has no
/// fingerprint yet: what it first trusts, it then trusts alone.
class FirstSeen {
  String? fingerprint;

  bool trusts(X509Certificate certificate) {
    final presented = certificateFingerprint(certificate);
    return presented == (fingerprint ??= presented);
  }
}
