import 'package:flutter/material.dart';

void main() => runApp(const RrPocketApp());

/// What the phone shows until a project restarts into this engine.
class RrPocketApp extends StatelessWidget {
  const RrPocketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'RR Pocket',
      home: Scaffold(
        body: Center(child: Text('RR Pocket\nWaiting for a project')),
      ),
    );
  }
}
