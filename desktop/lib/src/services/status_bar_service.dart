import 'package:lumide_api/lumide_api.dart';
import 'package:rr_pocket/src/constants.dart';
import 'package:rr_pocket/src/models/models.dart';
import 'package:rr_pocket/src/services/plugin_files.dart';

/// The RR Pocket item in the status bar: the R² mark alone, its tooltip
/// saying which phone and whether it answered. Amber when the paired phone
/// did not answer. Opens RR Pocket's menu on click.
class StatusBarService {
  StatusBarService(this.context, {Future<String?> Function()? icon})
      : _icon = icon ?? (() => pluginFile(assetIconSolid));

  final LumideContext context;
  final Future<String?> Function() _icon;

  static const String _itemId = 'rr_pocket.status';

  bool _created = false;
  bool _disposed = false;

  /// The colour the item was created with, null for the theme's.
  String? _color;

  Future<void> update(PhoneStatus status) async {
    if (_disposed) return;
    final (tooltip, color) = switch (status) {
      NotPaired() => ('RR Pocket: not paired. Click to pair.', null),
      Reachable(:final summary) => ('RR Pocket: $summary', null),
      Unreachable(:final address, :final reason) => (
          'RR Pocket at $address did not answer: $reason',
          colorNotAnswering,
        ),
    };
    // An update can't give an item back the theme's colour, so a change of
    // colour makes the item again.
    if (_created && color != _color) await _hide();
    if (!_created) {
      _created = true;
      try {
        final iconPath = await _icon();
        await context.statusBar.createItem(
          id: _itemId,
          text: '',
          tooltip: tooltip,
          command: cmdMenu,
          color: color,
          iconPath: iconPath,
          iconName: switch (iconPath) {
            null => iconPhone,
            _ => null,
          },
          alignment: 'right',
          priority: 96,
        );
        _color = color;
      } catch (_) {
        _created = false;
        rethrow;
      }
      return;
    }
    await context.statusBar.updateItem(
      _itemId,
      tooltip: tooltip,
      command: cmdMenu,
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
