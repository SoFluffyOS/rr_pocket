const String pluginName = 'RR Pocket';

// the phone
const String deviceId = 'pocket';
const int controlPort = 8100;
const Duration connectionTimeout = Duration(seconds: 5);

// the package, as `dart pub global run` names it
const String packageName = 'rr_pocket';
const String cliExecutable = 'pocket';
const String cliLibrary = 'package:rr_pocket/pocket.dart';

// commands
const String cmdPair = 'rr_pocket.pair';
const String cmdPin = 'rr_pocket.pin';
const String cmdShowPhone = 'rr_pocket.showPhone';
const String cmdForget = 'rr_pocket.forget';
const String cmdMenu = 'rr_pocket.menu';

// executables
const String executableFlutter = 'flutter';

// icons
const String iconPhone = 'smartphone';
const String iconCheck = 'refresh-cw';
const String iconPin = 'package';
const String iconPair = 'link';
const String iconForget = 'unlink';

/// The first line of the pubspec_overrides.yaml that `pocket pin` writes, so
/// it replaces only its own. `tool/pin_plugins.py` writes the same.
const String overridesHeader = '# Written by RR Pocket (pocket pin)';

/// What `dart pocket.dart pin` wrote, before the `pocket` command.
const String oldOverridesHeader =
    '# Written by RR Pocket (dart pocket.dart pin)';
