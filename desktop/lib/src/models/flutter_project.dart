import 'package:path/path.dart' as path;

/// The native path of a `file:` URI, or [uriOrPath] itself when it is
/// already a path. Null for other schemes and empty values.
String? filePathOf(String uriOrPath) {
  if (uriOrPath.isEmpty) return null;
  final uri = Uri.tryParse(uriOrPath);
  if (uri == null || !uri.hasScheme || uri.scheme.length == 1) {
    return uriOrPath;
  }
  if (uri.scheme != 'file') return null;
  return uri.toFilePath();
}

/// Whether [filePath] is a copy in build output or tool caches. Only the
/// part inside its workspace folder counts, so a workspace that itself
/// lives under a `build` folder is still scanned.
bool isIgnoredPath(String filePath, List<String> folders) {
  var relative = filePath;
  for (final folder in folders) {
    if (!path.isWithin(folder, filePath)) continue;
    relative = path.relative(filePath, from: folder);
    break;
  }
  return path.split(relative).any(_ignoredSegments.contains);
}

const _ignoredSegments = {'.dart_tool', 'build', '.symlinks', '.pub-cache'};

/// Whether a pubspec.yaml depends on the Flutter SDK.
bool isFlutterPubspec(String pubspec) =>
    RegExp(r'^\s+sdk:\s*flutter\s*$', multiLine: true).hasMatch(pubspec);

/// Whether a pubspec.yaml is a pub workspace's root, which holds the lock
/// and the overrides for its members.
bool isWorkspacePubspec(String pubspec) =>
    RegExp(r'^workspace:', multiLine: true).hasMatch(pubspec);
