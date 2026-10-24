import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:rr_pocket/src/build_card.dart';
import 'package:rr_pocket/src/pairing_card.dart';
import 'package:rr_pocket/src/rr_logo.dart';
import 'package:rr_pocket/src/rr_theme.dart';
import 'package:rr_pocket/src/waiting_card.dart';
import 'package:sofluffy_ui/sofluffy_ui.dart';

/// What the phone shows until a project restarts into this engine.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.fluffyTheme;
    final systemBars = switch (theme.isDark) {
      true => SystemUiOverlayStyle.light,
      false => SystemUiOverlayStyle.dark,
    };
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemBars,
      child: ColoredBox(
        color: theme.background,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: Spacing.d440 + Spacing.d40),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  Spacing.d24,
                  Spacing.d48,
                  Spacing.d24,
                  Spacing.d24,
                ),
                children: [
                  const Center(child: RrLogo()),
                  Spacing.v24,
                  Text(
                    'RR Pocket',
                    textAlign: TextAlign.center,
                    style: theme.typography.title1.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Spacing.v4,
                  Text(
                    'Your Flutter app, on this phone.',
                    textAlign: TextAlign.center,
                    style: theme.typography.body2.copyWith(color: theme.muted),
                  ),
                  Spacing.v32,
                  const WaitingCard(),
                  Spacing.v16,
                  const PairingCard(),
                  Spacing.v16,
                  const BuildCard(),
                  Spacing.v24,
                  Text(
                    'No Android SDK. No adb. Just Flutter.',
                    textAlign: TextAlign.center,
                    style: theme.typography.base2.copyWith(color: theme.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
