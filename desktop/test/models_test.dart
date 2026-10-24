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

    test('reads the Android plugins Flutter resolved', () {
      const json = '{"plugins": {"android": [{"name": "camera_android"}, '
          '{"name": "url_launcher_android"}], "ios": []}}';
      expect(parseAndroidPlugins(json),
          ['camera_android', 'url_launcher_android']);
      expect(parseAndroidPlugins('{"plugins": {}}'), isEmpty);
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

    test('an installed package is called through pub global run', () {
      final helper = helperCommand(
        dart: '/sdk/bin/dart',
        script: Uri.file(
          '/home/me/.pub-cache/global_packages/rr_pocket/bin/'
          'pocket.dart-3.13.4.snapshot',
        ),
        packageRoot: '/home/me/.pub-cache/git/rr_pocket-abc/desktop',
        separator: '/',
      );
      expect(helper,
          ['/sdk/bin/dart', 'pub', 'global', 'run', 'rr_pocket:pocket']);
    });

    test('a checkout is called through its bin/pocket.dart', () {
      final helper = helperCommand(
        dart: '/sdk/bin/dart',
        script: Uri.file('/src/rr_pocket/desktop/bin/main.dart'),
        packageRoot: '/src/rr_pocket/desktop',
        separator: '/',
      );
      expect(
          helper, ['/sdk/bin/dart', '/src/rr_pocket/desktop/bin/pocket.dart']);
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
