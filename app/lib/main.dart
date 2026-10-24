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
      builder: (context, _) => FluffyTheme(
        data: rrTheme(MediaQuery.platformBrightnessOf(context)),
        child: const HomePage(),
      ),
    );
  }
}
