// core/build/project_manifest_writer.dart — ProjectManifestWriter (core layer).

import 'dart:io';

/// Writes `<rootPath>/.aion/manifest.json`, creating the `.aion/`
/// directory if absent. The sole writer of this project marker file —
/// used both at project creation
/// ([CreateProjectCubit](../../features/projects/presentation/cubit/create_project_cubit.dart))
/// and on a baseline version upgrade
/// ([ActiveProjectCubit.acceptBaselineUpgrade](../../features/projects/presentation/cubit/active_project_cubit.dart)).
class ProjectManifestWriter {
  /// Writes `{"baselineVersion": "$baselineVersion"}` to
  /// `<rootPath>/.aion/manifest.json`. Synchronous I/O internally
  /// (matching the inline write this replaced) — real asynchronous file
  /// I/O does not reliably complete inside `flutter_test`'s fake-async
  /// zone, which every call site touching this method runs under.
  static Future<void> write(String rootPath, String baselineVersion) async {
    final aionDir = Directory('$rootPath${Platform.pathSeparator}.aion')
      ..createSync(recursive: true);
    final manifest = File(
      '${aionDir.path}${Platform.pathSeparator}manifest.json',
    );
    manifest.writeAsStringSync('{"baselineVersion": "$baselineVersion"}');
  }
}
