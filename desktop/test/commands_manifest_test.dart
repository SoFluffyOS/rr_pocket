import 'dart:io';

import 'package:lumide_api/lumide_api.dart';
import 'package:rr_pocket/rr_pocket.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  final manifest = LumideManifest.fromYaml(
    File('plugin.yaml').readAsStringSync(),
  );

  test('plugin.yaml lists every command with its runtime title', () {
    final manifestTitles = {
      for (final command in manifest.commands) command.id: command.title,
    };

    expect(manifestTitles, pocketCommandTitles);
  });

  test('command titles are unique', () {
    final titles = pocketCommandTitles.values.toList();
    expect(titles.toSet().length, titles.length);
  });

  test('every command can start the plugin', () {
    expect(
      manifest.activationEvents.where((e) => e.startsWith('onCommand:')),
      unorderedEquals(
          [for (final id in pocketCommandTitles.keys) 'onCommand:$id']),
    );
  });

  test('the shell permission covers what the plugin runs', () {
    expect(
      [
        for (final permission in manifest.permissions)
          if (permission case ShellPermission(:final command)) command,
      ],
      [executableFlutter, executableChmod],
    );
  });

  test('the package installs the pocket command and the plugin', () {
    final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as Map;
    expect(pubspec['name'], packageName);
    expect(pubspec['executables'], {cliExecutable: cliExecutable});
    expect(manifest.entryPoint, 'bin/main.dart');
    expect(manifest.id, packageName);
  });
}
