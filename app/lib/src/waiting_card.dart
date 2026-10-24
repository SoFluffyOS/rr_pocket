import 'package:flutter/widgets.dart';
import 'package:rr_pocket/src/rr_theme.dart';
import 'package:sofluffy_ui/sofluffy_ui.dart';

class WaitingCard extends StatelessWidget {
  const WaitingCard({super.key});

  @override
  Widget build(BuildContext context) {
    final typography = context.fluffyTheme.typography;
    final dot = Container(
      width: Spacing.d12,
      height: Spacing.d12,
      decoration: const ShapeDecoration(
        color: RrColors.amber,
        shape: CircleBorder(),
      ),
    );
    return RoundCard(
      borderRadius: Spacing.d24,
      padding: EdgeInsets.all(Spacing.d20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: Spacing.d6),
            child: switch (context.reducesMotion) {
              true => dot,
              false => GentlePulse(child: dot),
            },
          ),
          Spacing.h16,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Waiting for a project',
                  style: typography.base1.copyWith(fontWeight: FontWeight.w800),
                ),
                Spacing.v4,
                Text(
                  'Run it from your computer over Wi-Fi. It opens here, with hot reload.',
                  style: typography.base2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
