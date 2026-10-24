import 'package:rr_pocket/rr_pocket.dart';
import 'package:test/test.dart';

void main() {
  group('PhoneAddress', () {
    test('takes a host, with the control port by default', () {
      final address = PhoneAddress.tryParse(' 192.168.1.20 ');
      expect((address?.host, address?.port), ('192.168.1.20', controlPort));
      expect('$address', '192.168.1.20');
    });

    test('takes host:port', () {
      final address = PhoneAddress.tryParse('10.0.2.2:9100');
      expect((address?.host, address?.port), ('10.0.2.2', 9100));
      expect('$address', '10.0.2.2:9100');
    });

    test('takes IPv6 addresses, bare or bracketed', () {
      final bare = PhoneAddress.tryParse('fe80::1');
      expect((bare?.host, bare?.port), ('fe80::1', controlPort));
      expect('$bare', '[fe80::1]');
      final bracketed = PhoneAddress.tryParse('[::1]:9100');
      expect((bracketed?.host, bracketed?.port), ('::1', 9100));
      expect('$bracketed', '[::1]:9100');
      expect(PhoneAddress.tryParse('[::1]:x'), isNull);
    });

    test('refuses what is not an address', () {
      for (final text in ['', ' ', 'a b', 'http://x', ':80', 'x:0', 'x:y']) {
        expect(PhoneAddress.tryParse(text), isNull, reason: text);
      }
    });

    test('pairing codes lose spaces and dashes', () {
      expect(normalizePairingCode('1234-5678'), '12345678');
      expect(normalizePairingCode(' 1234 5678 '), '12345678');
    });
  });

  group('plugin versions', () {
    const lock = '''
packages:
  camera:
    dependency: "direct main"
    description:
      name: camera
      url: "https://pub.dev"
    source: hosted
    version: "0.12.1"
  path:
    dependency: transitive
    source: hosted
    version: "1.9.1"
sdks:
  dart: ">=3.0.0 <4.0.0"
''';

    test('reads a pubspec.lock', () {
      expect(parseLockedVersions(lock), {'camera': '0.12.1', 'path': '1.9.1'});
    });

    test('reads a pubspec.lock with Windows line endings', () {
      expect(
        parseLockedVersions(lock.replaceAll('\n', '\r\n')),
        {'camera': '0.12.1', 'path': '1.9.1'},
      );
    });

    test('reads the Android plugins Flutter resolved', () {
      const json = '{"plugins": {"android": [{"name": "camera_android"}, '
          '{"name": "url_launcher_android"}], "ios": []}}';
      expect(parseAndroidPlugins(json),
          ['camera_android', 'url_launcher_android']);
      expect(parseAndroidPlugins('{"plugins": {}}'), isEmpty);
      expect(
        parseAndroidPlugins(
            '{"plugins": {"android": [{"name": "camera_android"}, '
            '{"name": "integration_test", "dev_dependency": true}]}}'),
        ['camera_android'],
      );
      expect(parseAndroidPlugins('[]'), isEmpty);
    });

    test('reads the plugins from /hello', () {
      expect(
        bundledPlugins({
          'plugins': {'camera': '0.12.1'},
        }),
        {'camera': '0.12.1'},
      );
      expect(bundledPlugins({}), isEmpty);
    });

    test('finds versions that differ and plugins RR Pocket lacks', () {
      final check = PluginCheck.compare(
        carried: {'camera': '0.12.1', 'camera_android': '0.11.0'},
        used: {'camera': '0.12.0', 'camera_android': '0.11.0', 'path': '1.9.1'},
        android: ['camera_android', 'ble_android'],
      );
      expect(check.differ, ['camera 0.12.0 (RR Pocket has 0.12.1)']);
      expect(check.missing, ['ble_android']);
    });
  });

  group('overrides', () {
    test('pins only the carried plugins the project uses', () {
      expect(
        pinsFor(
          carried: {'camera': '0.12.1', 'sqflite': '2.4.5'},
          used: {'camera': '0.12.0', 'path': '1.9.1'},
        ),
        {'camera': '0.12.1'},
      );
    });

    test('a flutter_libs plugin moves its lockstep family with it', () {
      expect(
        pinsFor(
          carried: {'isar_community_flutter_libs': '3.4.1'},
          used: {
            'isar_community_flutter_libs': '3.3.2',
            'isar_community': '3.3.2',
            'isar_community_generator': '3.3.2',
            'isar_community_extra': '1.0.0',
            'isar_other': '3.3.2',
          },
        ),
        {
          'isar_community_flutter_libs': '3.4.1',
          'isar_community': '3.4.1',
          'isar_community_generator': '3.4.1',
        },
      );
    });

    test('renders sorted pins under our header', () {
      final text = renderOverrides({'sqflite': '2.4.5', 'camera': '0.12.1'});
      expect(
        text,
        '$overridesHeader: the Android plugin versions RR Pocket carries.\n'
        'dependency_overrides:\n'
        '  camera: 0.12.1\n'
        '  sqflite: 2.4.5\n',
      );
      expect(isOurOverrides(text), isTrue);
      expect(isOurOverrides('dependency_overrides:\n'), isFalse);
      expect(
        isOurOverrides(
          '# Written by RR Pocket (dart pocket.dart pin): the Android ...\n',
        ),
        isTrue,
      );
    });
  });

  group('the pocket device', () {
    test('calls the helper for each step', () {
      final config = deviceConfig(['dart', 'pocket.dart']);
      expect(config['id'], deviceId);
      expect(config['ping'], ['dart', 'pocket.dart', 'ping']);
      expect(config['install'], [
        'dart',
        'pocket.dart',
        'install',
        r'${localPath}',
        r'${appName}',
      ]);
      expect(config['runDebug'], ['dart', 'pocket.dart', 'run', r'${appName}']);
      expect(config['uninstall'], [
        'dart',
        'pocket.dart',
        'uninstall',
        r'${appName}',
      ]);
    });

    test('runs the pocket library with the package config of this copy', () {
      const config = '/home/me/.pub-cache/global_packages/rr_pocket/.dart_tool/'
          'package_config.json';
      final helper = helperCommand(
        dart: '/sdk/bin/dart',
        packageConfig: config,
        script: '/home/me/.pub-cache/global_packages/rr_pocket/bin/'
            'pocket.dart-3.13.4.snapshot',
      );
      expect(helper, [
        '/sdk/bin/dart',
        '--packages=$config',
        'package:rr_pocket/pocket.dart',
      ]);
    });

    test('without a package config, runs the script', () {
      final helper = helperCommand(
        dart: '/sdk/bin/dart',
        packageConfig: null,
        script: '/src/pocket.dart',
      );
      expect(helper, ['/sdk/bin/dart', '/src/pocket.dart']);
    });
  });

  group('the Flutter SDK', () {
    test('finds its folder in flutter --version --machine', () {
      expect(
        parseFlutterRoot(
          'Waiting for another flutter command to release the startup '
          'lock...\n{"frameworkVersion": "3.47.7", "flutterRoot": "/sdk"}\n',
        ),
        '/sdk',
      );
      expect(parseFlutterRoot('{"frameworkVersion": "3.47.7"}'), isNull);
      expect(parseFlutterRoot('flutter: command not found'), isNull);
      expect(parseFlutterRoot('{not json}'), isNull);
    });

    test('its dart is in bin/cache/dart-sdk', () {
      expect(
        flutterDart('/sdk', windows: false),
        '/sdk/bin/cache/dart-sdk/bin/dart',
      );
      expect(
        flutterDart(r'C:\flutter', windows: true),
        r'C:\flutter\bin\cache\dart-sdk\bin\dart.exe',
      );
    });
  });

  group('Flutter projects', () {
    test('build output and caches inside the workspace are ignored', () {
      const folders = ['/work'];
      expect(isIgnoredPath('/work/app/pubspec.lock', folders), isFalse);
      expect(isIgnoredPath('/work/app/build/x/pubspec.lock', folders), isTrue);
      expect(isIgnoredPath('/work/.dart_tool/a/pubspec.lock', folders), isTrue);
      expect(isIgnoredPath('/build/work/app/pubspec.lock', ['/build/work']),
          isFalse);
    });

    test('a Flutter pubspec depends on the SDK', () {
      expect(
        isFlutterPubspec('dependencies:\n  flutter:\n    sdk: flutter\n'),
        isTrue,
      );
      expect(isFlutterPubspec('dependencies:\n  path: ^1.9.0\n'), isFalse);
    });

    test('file URIs become paths', () {
      expect(filePathOf('file:///work/app/pubspec.lock'),
          '/work/app/pubspec.lock');
      expect(filePathOf('/work/app'), '/work/app');
      expect(filePathOf('https://example.com'), isNull);
      expect(filePathOf(''), isNull);
    });
  });
}
