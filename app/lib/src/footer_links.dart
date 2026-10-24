import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:rr_pocket/src/links.dart';
import 'package:rr_pocket/src/rr_theme.dart';
import 'package:sofluffy_ui/sofluffy_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Help · Privacy · GitHub, under everything, opened in the browser.
class FooterLinks extends StatelessWidget {
  const FooterLinks({super.key});

  @override
  Widget build(BuildContext context) {
    final style = context.fluffyTheme.typography.base2.copyWith(
      color: context.fluffyTheme.muted,
      fontWeight: FontWeight.w700,
    );
    Widget link(String label, String url, String tooltip) => Tappable(
      tooltip: tooltip,
      onTap: () => unawaited(
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: Spacing.d8,
          vertical: Spacing.d4,
        ),
        child: Text(label, style: style),
      ),
    );
    final dot = Text('·', style: style);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        link('Help', RrLinks.help, 'How RR Pocket works'),
        dot,
        link('Privacy', RrLinks.privacy, 'RR Pocket\'s privacy policy'),
        dot,
        link('GitHub', RrLinks.repository, 'RR Pocket\'s source'),
      ],
    );
  }
}
