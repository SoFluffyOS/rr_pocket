/// The `pocket` command. Flutter runs this library itself (see
/// `helperCommand`), so it imports only what the command needs: it starts on
/// every ping, install and run.
library;

import 'dart:io';

import 'package:rr_pocket/src/services/pocket_cli.dart';

Future<void> main(List<String> args) async {
  exitCode = await PocketCli()(args);
  // HttpClient keeps the process alive otherwise.
  exit(exitCode);
}
