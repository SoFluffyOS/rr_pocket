import 'dart:async';
import 'dart:io';

import 'package:lumide_api/lumide_api.dart';
import 'package:rr_pocket/rr_pocket.dart';

/// Errors nobody awaited would end the plugin process, so they are logged
/// instead.
void main() => runZonedGuarded(
      () => RrPocketPlugin().run(),
      (error, stackTrace) =>
          stderr.writeln('[ERROR] Uncaught: $error\n$stackTrace'),
    );

class RrPocketPlugin extends LumidePlugin {
  late LumideContext _context;
  late LogService logService;
  late StatusBarService statusBarService;
  late PocketCommands commands;
  bool _initialized = false;

  @override
  Future<void> onActivate(LumideContext context) async {
    _context = context;
    logService = LogService(log);
    statusBarService = StatusBarService(context);
    commands = PocketCommands(
      context,
      config: PocketConfig(),
      statusBar: statusBarService,
      projects: ProjectPicker(context),
    );
    _initialized = true;

    await _registerCommands(context);
    unawaited(_refreshQuietly());
    logService.info('RR Pocket plugin ready.');
  }

  Future<void> _registerCommands(LumideContext context) async {
    final callbacks = <String, Future<void> Function()>{
      cmdPair: commands.pair,
      cmdPin: commands.pin,
      cmdShowPhone: commands.showPhone,
    };
    await Future.wait([
      for (final MapEntry(key: id, value: callback) in callbacks.entries)
        context.commands
            .registerCommand(
              id: id,
              title: pocketCommandTitle(id),
              category: pluginName,
              callback: ([_]) => _guard(id, callback),
            )
            .catchError(
              (Object error, StackTrace stackTrace) =>
                  logService.error('Could not register $id', error, stackTrace),
            ),
    ]);
  }

  /// The status bar shows the phone from the start, without a message when
  /// it is off or elsewhere.
  Future<void> _refreshQuietly() async {
    try {
      final status = await commands.refresh();
      if (status case Unreachable(:final address, :final reason)) {
        logService.info('RR Pocket at $address did not answer: $reason');
      }
    } catch (error, stackTrace) {
      logService.error('Could not check the phone', error, stackTrace);
    }
  }

  Future<void> _guard(String command, Future<void> Function() action) async {
    try {
      await action();
    } catch (error, stackTrace) {
      logService.error('$command failed', error, stackTrace);
      await _context.window.showMessage(
        '${pocketCommandTitle(command)} failed: ${describePhoneError(error)}',
        type: MessageType.error,
        title: pluginName,
      );
    }
  }

  @override
  Future<void> onDeactivate() async {
    if (!_initialized) return;
    try {
      await statusBarService.dispose();
    } catch (error, stackTrace) {
      logService.error(
          'Could not remove the status bar item', error, stackTrace);
    }
  }
}
