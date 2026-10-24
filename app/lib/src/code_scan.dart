import 'package:flutter/services.dart';
import 'package:rr_pocket/src/pairing.dart';

/// How a scan ended.
sealed class ScanOutcome {
  const ScanOutcome();
}

class Scanned extends ScanOutcome {
  const Scanned(this.text);

  final String text;
}

/// The user backed out; nothing to say.
class ScanCancelled extends ScanOutcome {
  const ScanCancelled();
}

/// Google's scanner can't run here: no Play services, or no scanner module.
class ScanUnavailable extends ScanOutcome {
  const ScanUnavailable();
}

class ScanFailed extends ScanOutcome {
  const ScanFailed(this.message);

  final String message;
}

/// Google's code scanner, through RR Pocket's Kotlin side (CodeScanner.kt).
Future<ScanOutcome> scanWithGoogle() async {
  try {
    final answer = await Pairing.channel.invokeMapMethod<String, Object?>(
      'scan',
    );
    return switch (answer) {
      {'status': 'scanned', 'text': final String text} => Scanned(text),
      {'status': 'scanned'} => const ScanFailed(
        'That code holds no text. Scan the QR code your computer shows.',
      ),
      {'status': 'cancelled'} => const ScanCancelled(),
      _ => const ScanUnavailable(),
    };
  } on MissingPluginException {
    return const ScanUnavailable();
  } on PlatformException catch (error) {
    return ScanFailed(
      'The scanner stopped: ${error.message ?? error.code}. Try again.',
    );
  }
}
