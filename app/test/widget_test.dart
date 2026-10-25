import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rr_pocket/main.dart';
import 'package:rr_pocket/src/src.dart';
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

  testWidgets('shows the address, the code and the certificate to compare', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      Pairing.channel,
      (call) async => switch (call.method) {
        'info' => {
          'address': '192.168.0.159',
          'port': 8100,
          'code': 'H79GN4XS',
          'name': 'Pixel 7',
          'fingerprint': '2dc91e21557912f4c249c4592684a8cca77e630b',
        },
        _ => null,
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        Pairing.channel,
        null,
      ),
    );

    await tester.pumpWidget(const RrPocketApp());
    // The waiting card animates for good: no pumpAndSettle.
    await tester.pump();
    await tester.pump();

    expect(find.text('H79G N4XS'), findsOneWidget);
    expect(find.text('Certificate'), findsOneWidget);
    expect(find.text('2DC9 1E21'), findsOneWidget);
  });

  test('lists every Flutter plugin in pubspec.yaml', () {
    expect(BuildInfo.plugins.toSet(), _directPlugins());
  });
}

/// The direct dependencies whose own pubspec declares a Flutter plugin.
Set<String> _directPlugins() {
  final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as Map;
  final dependencies = (pubspec['dependencies'] as Map).keys.toSet();
  final config = jsonDecode(
    File('.dart_tool/package_config.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final configDir = Directory('.dart_tool').absolute.uri;
  return {
    for (final package in config['packages'] as List)
      if (package case {'name': final String name, 'rootUri': final String root}
          when dependencies.contains(name) && _isPlugin(configDir, root))
        name,
  };
}

bool _isPlugin(Uri configDir, String rootUri) {
  final root = configDir.resolve(switch (rootUri.endsWith('/')) {
    true => rootUri,
    false => '$rootUri/',
  });
  final pubspec = File.fromUri(root.resolve('pubspec.yaml'));
  if (!pubspec.existsSync()) return false;
  final yaml = loadYaml(pubspec.readAsStringSync());
  return switch (yaml) {
    {'flutter': {'plugin': _?}} => true,
    _ => false,
  };
}
