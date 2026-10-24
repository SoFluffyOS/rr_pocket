import 'dart:io';

import 'package:rr_pocket/rr_pocket.dart';

Future<void> main(List<String> args) async {
  exitCode = await PocketCli()(args);
  // HttpClient keeps the process alive otherwise.
  exit(exitCode);
}
