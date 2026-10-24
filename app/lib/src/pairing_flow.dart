import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:rr_pocket/src/allow_prompt.dart';
import 'package:rr_pocket/src/code_scan.dart';
import 'package:rr_pocket/src/pair_link.dart';
import 'package:rr_pocket/src/pair_sender.dart';
import 'package:rr_pocket/src/pairing.dart';

enum PairingNoteKind { busy, done, failed }

/// What the home screen says about the last pairing.
class PairingNote {
  const PairingNote(this.kind, this.text);

  final PairingNoteKind kind;
  final String text;
}

/// The phone's side of pairing (docs/pairing.md): a computer that found it
/// on the network asks through the Kotlin server (`askPair`), and a QR code
/// the computer shows arrives scanned or as an rrpocket:// link. Either way
/// the user is asked first.
class PairingFlow extends ChangeNotifier {
  PairingFlow({
    required this.question,
    required this.scanInApp,
    this.scanWithPlayServices = scanWithGoogle,
    this.sender = const PairSender(),
    this.loadPairing = Pairing.load,
  });

  final PairQuestion question;

  /// RR Pocket's own scanner, for phones where Google's can't run.
  final Future<ScanOutcome> Function() scanInApp;
  final Future<ScanOutcome> Function() scanWithPlayServices;
  final PairSender sender;
  final Future<Pairing?> Function() loadPairing;

  PairingNote? _note;
  bool _disposed = false;
  PairingNote? get note => _note;

  bool get busy => _note?.kind == PairingNoteKind.busy;

  /// Listens to the Kotlin side and takes a link that opened the app.
  void start() {
    Pairing.channel.setMethodCallHandler(_handle);
    unawaited(_takeLink());
  }

  @override
  void dispose() {
    _disposed = true;
    Pairing.channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<Object?> _handle(MethodCall call) async {
    switch (call.method) {
      case 'askPair':
        return _askForComputer(call.arguments);
      case 'withdrawPair':
        if (call.arguments case {'id': final int id}) question.withdraw(id);
      case 'linkArrived':
        await _takeLink();
      default:
        throw MissingPluginException('no ${call.method} in RR Pocket');
    }
    return null;
  }

  /// A computer's POST /pair, held open by the server until this answers.
  Future<bool> _askForComputer(Object? arguments) async {
    if (arguments case {'id': final int id, 'computer': final String name}) {
      final where = switch (arguments['from']) {
        final String from => 'Asking from $from.',
        _ => null,
      };
      final allowed = await question.ask(name, tag: id, where: where);
      if (!allowed) return false;
      _say(PairingNoteKind.done, 'Sent the pairing code to $name.');
      return true;
    }
    return false;
  }

  Future<void> _takeLink() async {
    final String? link;
    try {
      link = await Pairing.channel.invokeMethod<String>('takeLink');
    } on MissingPluginException {
      return;
    }
    if (link != null) await openLink(link);
  }

  /// Google's scanner first, RR Pocket's own where it can't run.
  Future<void> scan() async {
    if (busy) return;
    final before = _note;
    // Finding out whether Google's scanner is installed took 10 s and more
    // on an emulator without it (2026-10-24).
    _say(PairingNoteKind.busy, 'Opening the scanner…');
    var outcome = await scanWithPlayServices();
    if (outcome is ScanUnavailable) outcome = await scanInApp();
    if (_disposed) return;
    _note = before;
    notifyListeners();
    switch (outcome) {
      case Scanned(:final text):
        await openLink(text);
      case ScanFailed(:final message):
        _say(PairingNoteKind.failed, message);
      case ScanCancelled() || ScanUnavailable():
        break;
    }
  }

  /// Asks, then sends this phone's address and code to the computer.
  Future<void> openLink(String text) async {
    if (busy) return;
    final PairLink link;
    try {
      link = PairLink.parse(text);
    } on FormatException catch (error) {
      return _say(PairingNoteKind.failed, error.message);
    }
    final allowed = await question.ask(
      link.name,
      tag: link,
      where: 'Sends this phone\'s code to ${link.hosts.join(' or ')}.',
    );
    if (!allowed) return;
    final phone = await loadPairing();
    if (phone == null) {
      return _say(
        PairingNoteKind.failed,
        'RR Pocket could not read its own code. Restart it and scan again.',
      );
    }
    _say(PairingNoteKind.busy, 'Pairing with ${link.name}…');
    final result = await sender.send(link, phone);
    switch (result) {
      case Paired(:final computer):
        _say(PairingNoteKind.done, 'Paired with $computer.');
      case PairFailed(:final message):
        _say(PairingNoteKind.failed, message);
    }
  }

  void _say(PairingNoteKind kind, String text) {
    if (_disposed) return;
    _note = PairingNote(kind, text);
    notifyListeners();
  }
}
