import 'package:flutter/widgets.dart';
import 'package:rr_pocket/src/pairing_flow.dart';
import 'package:sofluffy_ui/sofluffy_ui.dart';

/// One line on how the last pairing went: under way, done, or what failed.
class PairingNoteLine extends StatelessWidget {
  const PairingNoteLine(this.note, {super.key});

  final PairingNote note;

  @override
  Widget build(BuildContext context) {
    final theme = context.fluffyTheme;
    Widget icon(String asset, MessageType type) => ImageView(
      asset,
      color: type.color,
      size: Spacing.d16,
      assetPackage: kSofluffyUiPackageName,
    );
    final leading = switch (note.kind) {
      PairingNoteKind.busy => const LoadingSpinner(),
      PairingNoteKind.done => icon(
        FluffyAssets.icons.tick02Solid,
        MessageType.success,
      ),
      PairingNoteKind.failed => icon(
        FluffyAssets.icons.alertCircle,
        MessageType.error,
      ),
    };
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: Spacing.d20,
            width: Spacing.d16,
            child: Center(child: leading),
          ),
          Spacing.h8,
          Expanded(
            child: Text(
              note.text,
              style: theme.typography.base2.copyWith(
                fontWeight: switch (note.kind) {
                  PairingNoteKind.done => FontWeight.w700,
                  _ => FontWeight.w400,
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
