import 'package:flutter/widgets.dart';
import 'package:rr_pocket/src/rr_theme.dart';
import 'package:sofluffy_ui/sofluffy_ui.dart';

/// The R² mark: a white R with an amber superscript 2, as in the icon.
class RrLogo extends StatelessWidget {
  const RrLogo({super.key});

  @override
  Widget build(BuildContext context) {
    final typography = context.fluffyTheme.typography;
    final edge = switch (context.isDark) {
      true => const BorderSide(color: Color(0x3DFFFFFF)),
      false => BorderSide.none,
    };
    return Container(
      width: Spacing.d96 + Spacing.d20,
      height: Spacing.d96 + Spacing.d20,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: RrColors.slate,
        shape: RoundedSuperellipseBorder(borderRadius: Spacing.r24, side: edge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'R',
            style: typography.headline2.copyWith(
              fontSize: Spacing.d72,
              fontWeight: FontWeight.w800,
              color: FluffyColors.white,
              height: 1,
            ),
          ),
          Text(
            '2',
            style: typography.headline4.copyWith(
              fontSize: Spacing.d32,
              fontWeight: FontWeight.w800,
              color: RrColors.amber,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
