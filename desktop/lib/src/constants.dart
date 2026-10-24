const String pluginName = 'RR Pocket';

// the phone
const String deviceId = 'pocket';
const int controlPort = 8100;
const Duration connectionTimeout = Duration(seconds: 5);

// the package, as `dart pub global run` names it
const String packageName = 'rr_pocket';
const String cliExecutable = 'pocket';

// commands
const String cmdPair = 'rr_pocket.pair';
const String cmdPin = 'rr_pocket.pin';
const String cmdShowPhone = 'rr_pocket.showPhone';

// executables
const String executableFlutter = 'flutter';

// icons
const String iconPhone = 'smartphone';

/// The first line of the pubspec_overrides.yaml that `pocket pin` writes, so
/// it replaces only its own. `tool/pin_plugins.py` writes the same.
const String overridesHeader = '# Written by RR Pocket (dart pocket.dart pin)';
