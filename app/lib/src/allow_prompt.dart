import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:sofluffy_ui/sofluffy_ui.dart';

/// Asks "Pair with `computer`?"; true when the user allows it.
abstract interface class PairQuestion {
  /// [tag] names the question for [withdraw]; [where] says what address is
  /// involved, so a name alone can't pass for someone's computer.
  Future<bool> ask(String computer, {required Object tag, String? where});

  /// Takes the question [tag] down unanswered, open or still queued.
  void withdraw(Object tag);
}

/// [PairQuestion] as a dialog on RR Pocket's screen, one at a time: a
/// computer's request and a scanned link may arrive together.
class AllowPrompt implements PairQuestion {
  AllowPrompt(this._context);

  /// A context under the app's navigator and theme.
  final BuildContext Function() _context;

  Future<void> _queue = Future.value();
  Object? _open;
  final _withdrawn = <Object>{};

  @override
  Future<bool> ask(String computer, {required Object tag, String? where}) {
    final answer = _queue.then((_) => _show(computer, tag, where));
    _queue = answer.then((_) {}, onError: (Object _) {});
    return answer;
  }

  @override
  void withdraw(Object tag) {
    if (_open == tag) {
      // The dialog is on top: nothing opens over a modal one.
      _context().navigator.pop();
      return;
    }
    _withdrawn.add(tag);
  }

  Future<bool> _show(String computer, Object tag, String? where) async {
    if (_withdrawn.remove(tag)) return false;
    final context = _context();
    if (!context.mounted) return false;
    _open = tag;
    try {
      final action = await ConfirmDialog.show(
        context,
        title: 'Pair with $computer?',
        message: [
          'It will be able to run Flutter projects on this phone. '
              'Allow only a computer you know.',
          ?where,
        ].join('\n\n'),
        negativeText: "Don't allow",
        positiveText: 'Allow',
        barrierDismissible: false,
      );
      return action == ConfirmAction.positive;
    } finally {
      _open = null;
    }
  }
}
