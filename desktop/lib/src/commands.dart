import 'package:rr_pocket/src/constants.dart';

/// Titles for every command the Lumide plugin registers, keyed by command id.
///
/// `plugin.yaml` must list the same commands with the same titles;
/// `test/commands_manifest_test.dart` enforces it.
const Map<String, String> pocketCommandTitles = {
  cmdPair: 'RR Pocket: Pair with Phone',
  cmdPin: 'RR Pocket: Match Plugin Versions',
  cmdShowPhone: 'RR Pocket: Show Phone',
  cmdForget: 'RR Pocket: Forget Phone',
  cmdMenu: 'RR Pocket: Menu',
};

/// Title of a registered command, falling back to its id.
String pocketCommandTitle(String id) => pocketCommandTitles[id] ?? id;
