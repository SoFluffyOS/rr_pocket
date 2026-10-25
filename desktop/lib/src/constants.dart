const String pluginName = 'RR Pocket';

// the phone
const String deviceId = 'pocket';
const int controlPort = 8100;
const Duration connectionTimeout = Duration(seconds: 5);

/// How long the phone gets to answer a request it took, unless the request
/// says otherwise.
const Duration requestTimeout = Duration(seconds: 30);

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
const String cmdDoctor = 'rr_pocket.doctor';

// executables
const String executableFlutter = 'flutter';

/// Makes the pairing file private on macOS and Linux.
const String executableChmod = 'chmod';

// icons
const String iconPhone = 'smartphone';
const String iconCheck = 'refresh-cw';
const String iconPin = 'package';
const String iconPair = 'link';
const String iconForget = 'unlink';
const String iconHelp = 'book-open';
const String iconDoctor = 'stethoscope';
const String iconSponsor = 'heart';

// assets, made by tool/make_plugin_icons.py
const String assetIconSolid = 'assets/icon_rr_pocket_solid.svg';
const String assetIcon = 'assets/icon_rr_pocket.svg';

// the status bar's colour when the paired phone does not answer: Lumide's
// warning amber
const String colorNotAnswering = '#E6B450';

// links; the repo goes public under SoFluffyOS
const String helpUrl = 'https://github.com/SoFluffyOS/rr_pocket#readme';
const String sponsorUrl = 'https://github.com/sponsors/simonpham';

/// The first line of the pubspec_overrides.yaml that `pocket pin` writes, so
/// it replaces only its own. `tool/pin_plugins.py` writes the same.
const String overridesHeader = '# Written by RR Pocket (pocket pin)';

/// What `dart pocket.dart pin` wrote, before the `pocket` command.
const String oldOverridesHeader =
    '# Written by RR Pocket (dart pocket.dart pin)';
