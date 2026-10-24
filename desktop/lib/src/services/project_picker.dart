import 'package:lumide_api/lumide_api.dart';
import 'package:path/path.dart' as path;
import 'package:rr_pocket/src/models/models.dart';

/// Finds the workspace's Flutter projects that have resolved (a
/// pubspec.lock), and asks which one when there are several.
class ProjectPicker {
  ProjectPicker(this.context);

  final LumideContext context;

  /// The project folder to act on, or null when there is none or the user
  /// dismissed the choice.
  Future<String?> pick({Map<String, int>? position}) async {
    final projects = await flutterProjects();
    if (projects.isEmpty) {
      await context.window.showMessage(
        'No Flutter project with a pubspec.lock in this workspace. Run '
        'flutter pub get first.',
        type: MessageType.warning,
        title: 'RR Pocket',
      );
      return null;
    }
    if (projects case [final only]) return only;
    final active = await _activeDocumentPath();
    // The innermost project holding the open file first: an example/ app
    // before the plugin package around it.
    final holding = [
      for (final project in projects)
        if (_holds(project, active)) project,
    ]..sort((a, b) => b.length.compareTo(a.length));
    final ordered = [
      ...holding,
      ...projects.where((project) => !_holds(project, active)),
    ];
    final picked = await context.window.showQuickPick(
      [
        for (final project in ordered)
          QuickPickItem(
            label: path.basename(project),
            tooltip: project,
            payload: project,
          ),
      ],
      placeholder: 'Which project should match RR Pocket?',
      position: position,
    );
    if (picked?.payload case final String project) return project;
    return null;
  }

  /// Flutter project folders, sorted by path.
  Future<List<String>> flutterProjects() async {
    final folders = await _workspaceFolderPaths();
    final locks = await context.workspace.findFiles(
      '**/pubspec.lock',
      maxResults: 100,
    );
    final projects = <String>[];
    for (final uri in locks) {
      final lockPath = filePathOf(uri);
      if (lockPath == null || isIgnoredPath(lockPath, folders)) continue;
      final project = path.dirname(lockPath);
      final pubspec = await _read(path.join(project, 'pubspec.yaml'));
      if (pubspec == null) continue;
      if (!isFlutterPubspec(pubspec) && !isWorkspacePubspec(pubspec)) continue;
      projects.add(project);
    }
    return projects..sort();
  }

  bool _holds(String project, String? filePath) =>
      filePath != null && path.isWithin(project, filePath);

  Future<String?> _read(String filePath) async {
    try {
      return await context.fs.readString(filePath);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _activeDocumentPath() async {
    try {
      final uri = await context.editor.getActiveDocumentUri();
      if (uri == null) return null;
      return filePathOf(uri);
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> _workspaceFolderPaths() async {
    try {
      final folders = await context.workspace.getWorkspaceFolders();
      return [
        for (final folder in folders)
          if (filePathOf(folder.uri) case final folderPath?) folderPath,
      ];
    } catch (_) {
      return const [];
    }
  }
}
