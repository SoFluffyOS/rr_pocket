import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rr_pocket/main.dart';
import 'package:rr_pocket/src/build_info.dart';
import 'package:yaml/yaml.dart';

void main() {
  testWidgets('shows the waiting screen and what the build carries', (
    tester,
  ) async {
    await tester.pumpWidget(const RrPocketApp());

    expect(find.text('Waiting for a project'), findsOneWidget);
    expect(find.text('In this build'), findsOneWidget);
    for (final plugin in BuildInfo.plugins) {
      expect(find.text(plugin), findsOneWidget);
    }
  });

  test('lists every plugin in pubspec.yaml', () {
    final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as Map;
    final dependencies = (pubspec['dependencies'] as Map).keys.toSet()
      ..remove('flutter');

    expect(BuildInfo.plugins.toSet(), dependencies);
  });
}
