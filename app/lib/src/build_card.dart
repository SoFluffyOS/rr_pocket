import 'package:flutter/widgets.dart';
import 'package:rr_pocket/src/build_info.dart';
import 'package:rr_pocket/src/rr_theme.dart';
import 'package:sofluffy_ui/sofluffy_ui.dart';

/// The Flutter version and plugins a project must match to run here.
class BuildCard extends StatelessWidget {
  const BuildCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.fluffyTheme;
    final labelStyle = theme.typography.base1.copyWith(color: theme.muted);
    final tagColor = switch (theme.isDark) {
      true => RrColors.amber,
      false => RrColors.slate,
    };
    Widget row(String label, String value) => Padding(
      padding: EdgeInsets.symmetric(vertical: Spacing.d4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: labelStyle)),
          Text(
            value,
            style: theme.typography.base1.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
    return RoundCard(
      borderRadius: Spacing.d24,
      padding: EdgeInsets.all(Spacing.d20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'In this build',
            style: theme.typography.base1.copyWith(fontWeight: FontWeight.w800),
          ),
          Spacing.v8,
          row('Flutter', BuildInfo.flutterVersion),
          row('Dart', BuildInfo.dartVersion),
          Spacing.v12,
          Text('Plugins', style: labelStyle),
          Spacing.v8,
          Wrap(
            spacing: Spacing.d8,
            runSpacing: Spacing.d8,
            children: [
              for (final plugin in BuildInfo.plugins)
                Tag(
                  plugin,
                  color: tagColor,
                  padding: EdgeInsets.symmetric(
                    horizontal: Spacing.d12,
                    vertical: Spacing.d6,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
