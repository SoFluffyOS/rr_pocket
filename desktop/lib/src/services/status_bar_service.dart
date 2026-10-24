import 'package:lumide_api/lumide_api.dart';
import 'package:rr_pocket/src/constants.dart';
import 'package:rr_pocket/src/models/models.dart';

/// The RR Pocket item in the status bar: the paired phone, and whether it
/// answered. Shows the phone on click. Hidden until a phone is paired.
class StatusBarService {
  StatusBarService(this.context);

  final LumideContext context;

  static const String _itemId = 'rr_pocket.status';

  bool _created = false;
  bool _disposed = false;

  Future<void> update(PhoneStatus status) async {
    if (_disposed) return;
    final (String, String)? content = switch (status) {
      NotPaired() => null,
      Reachable(:final name, :final summary) => (name, summary),
      Unreachable(:final address, :final reason) => (
          pluginName,
          'RR Pocket at $address did not answer: $reason',
        ),
    };
    if (content == null) return _hide();
    final (text, tooltip) = content;
    if (!_created) {
      _created = true;
      try {
        await context.statusBar.createItem(
          id: _itemId,
          text: text,
          tooltip: tooltip,
          command: cmdShowPhone,
          iconName: iconPhone,
          alignment: 'right',
          priority: 96,
        );
      } catch (_) {
        _created = false;
        rethrow;
      }
      return;
    }
    await context.statusBar.updateItem(
      _itemId,
      text: text,
      tooltip: tooltip,
      command: cmdShowPhone,
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    await _hide();
  }

  Future<void> _hide() async {
    if (!_created) return;
    _created = false;
    await context.statusBar.disposeItem(_itemId);
  }
}
