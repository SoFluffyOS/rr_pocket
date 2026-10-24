import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as path;

/// The absolute path of [relativePath] in the plugin's folder, or null when
/// it cannot be found.
///
/// Lumide runs the plugin with its package config, so the package's own
/// folder is found from it; the script's folder and the working directory,
/// which Lumide sets to the plugin's folder, are the fallbacks.
Future<String?> pluginFile(String relativePath) async {
  final candidates = <String>[];
  try {
    final library = await Isolate.resolvePackageUri(
      Uri.parse('package:rr_pocket/rr_pocket.dart'),
    );
    if (library != null && library.isScheme('file')) {
      final packageRoot = path.dirname(path.dirname(library.toFilePath()));
      candidates.add(path.join(packageRoot, relativePath));
    }
  } catch (_) {
    // Running without a package config.
  }
  final scriptDirectory = path.dirname(Platform.script.toFilePath());
  candidates.addAll([
    path.join(scriptDirectory, '..', relativePath),
    path.join(Directory.current.path, relativePath),
  ]);

  for (final candidate in candidates) {
    final normalized = path.normalize(candidate);
    if (await File(normalized).exists()) return normalized;
  }
  return null;
}
