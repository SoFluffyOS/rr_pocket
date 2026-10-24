import 'package:flutter/material.dart';

import 'src/home_page.dart';
import 'src/theme.dart';

void main() => runApp(const RrPocketApp());

class RrPocketApp extends StatelessWidget {
  const RrPocketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RR Pocket',
      debugShowCheckedModeBanner: false,
      theme: rrTheme(Brightness.light),
      darkTheme: rrTheme(Brightness.dark),
      home: const HomePage(),
    );
  }
}
