import 'package:flutter/widgets.dart';
import 'package:rr_pocket/src/src.dart';
import 'package:sofluffy_ui/sofluffy_ui.dart';

void main() => runApp(const RrPocketApp());

class RrPocketApp extends StatelessWidget {
  const RrPocketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      title: 'RR Pocket',
      color: RrColors.slate,
      debugShowCheckedModeBanner: false,
      // A navigator for the Allow dialog and the fallback scanner.
      home: const HomePage(),
      pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
        settings: settings,
        pageBuilder: (context, _, _) => builder(context),
      ),
      builder: (context, navigator) => FluffyTheme(
        data: rrTheme(MediaQuery.platformBrightnessOf(context)),
        child: navigator ?? const SizedBox.shrink(),
      ),
    );
  }
}
