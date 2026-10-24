import 'dart:io' as io;

import 'package:lumide_api/lumide_api.dart';

/// A Lumide host for the plugin's services: answers from fields, records
/// what the plugin asked for. Files are read from disk.
class FakeHost implements LumideContext {
  FakeHost({this.workspaceFolder = '/work'});

  final String workspaceFolder;

  @override
  late final FakeShell shell = FakeShell();
  @override
  late final FakeWindow window = FakeWindow();
  @override
  late final FakeWorkspace workspace = FakeWorkspace(this);
  @override
  late final FakeFileSystem fs = FakeFileSystem();
  @override
  late final FakeEditor editor = FakeEditor();
  @override
  late final FakeStatusBar statusBar = FakeStatusBar();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeShell implements LumideShell {
  final ran = <({List<String> command, String? workingDirectory})>[];

  /// The exit code for a command line starting with a key, such as
  /// `flutter pub get`.
  final exitCodes = <String, int>{};

  @override
  Future<ProcessResult> run(
    String command,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdin,
  }) async {
    final line = [command, ...arguments];
    ran.add((command: line, workingDirectory: workingDirectory));
    final joined = line.join(' ');
    for (final MapEntry(key: prefix, value: code) in exitCodes.entries) {
      if (joined.startsWith(prefix)) {
        return ProcessResult(exitCode: code, stdout: '', stderr: 'failed');
      }
    }
    return const ProcessResult(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeWindow implements LumideWindow {
  final messages = <(MessageType, String)>[];
  final confirmations = <String>[];
  final progressTitles = <String>[];

  /// Answers to input boxes, in order; null dismisses one.
  final inputs = <String?>[];
  bool confirm = false;

  /// The payload of the quick pick item to choose; null dismisses it.
  Object? pickPayload;
  List<QuickPickItem> lastPick = const [];

  @override
  Future<void> showMessage(
    String message, {
    MessageType type = MessageType.info,
    String? title,
  }) async =>
      messages.add((type, message));

  @override
  Future<bool> showConfirmDialog(String message, {String? title}) async {
    confirmations.add(message);
    return confirm;
  }

  @override
  Future<String?> showInputBox({
    String? prompt,
    String? value,
    String? placeHolder,
    bool password = false,
    String? title,
  }) async =>
      switch (inputs) {
        [] => null,
        _ => inputs.removeAt(0),
      };

  @override
  Future<QuickPickItem?> showQuickPick(
    List<QuickPickItem> items, {
    String? placeholder,
    bool matchOnDescription = true,
    bool matchOnDetail = true,
    Map<String, int>? position,
  }) async {
    lastPick = items;
    for (final item in items) {
      if (item.payload == pickPayload) return item;
    }
    return null;
  }

  @override
  Future<T> withProgress<T>({
    required String title,
    String? message,
    bool cancellable = false,
    required Future<T> Function(LumideProgress progress) task,
  }) {
    progressTitles.add(title);
    return task(FakeProgress());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeProgress implements LumideProgress {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeWorkspace implements LumideWorkspace {
  FakeWorkspace(this._host);

  final FakeHost _host;

  /// What findFiles returns, as `file:` URIs.
  final files = <String>[];

  @override
  Future<List<String>> findFiles(
    String glob, {
    int? maxResults,
    String? folder,
  }) async =>
      files;

  @override
  Future<List<LumideWorkspaceFolder>> getWorkspaceFolders() async => [
        LumideWorkspaceFolder.fromUri(
          Uri.directory(_host.workspaceFolder).toString(),
        ),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFileSystem implements LumideFileSystem {
  @override
  Future<String> readString(String path) => io.File(path).readAsString();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeEditor implements LumideEditor {
  String? activeUri;

  @override
  Future<String?> getActiveDocumentUri() async => activeUri;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeStatusBar implements LumideStatusBar {
  /// The item's text and tooltip by id.
  final items = <String, (String, String?)>{};

  @override
  Future<void> createItem({
    required String id,
    required String text,
    String? tooltip,
    String? command,
    String? color,
    String? iconName,
    String? iconPath,
    String alignment = 'right',
    int priority = 0,
  }) async =>
      items[id] = (text, tooltip);

  @override
  Future<void> updateItem(
    String id, {
    String? text,
    String? tooltip,
    String? command,
    String? color,
    String? iconName,
    String? iconPath,
  }) async =>
      items[id] = (text ?? '', tooltip);

  @override
  Future<void> disposeItem(String id) async => items.remove(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
