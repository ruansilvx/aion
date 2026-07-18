// presentation/cubit/create_project_cubit.dart — CreateProjectCubit business logic (presentation layer).

import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/projects/domain/entities/project.dart';
import 'package:aion/features/projects/domain/repositories/baseline_repository.dart';
import 'package:aion/features/projects/domain/repositories/project_repository.dart';
import 'package:aion/features/projects/presentation/cubit/create_project_state.dart';

/// Owns the invariants a new project must satisfy before it's created —
/// validation lives here, not in [ProjectRepository]'s Drift
/// implementation, per `project.md`'s Cubit-vs-repository split.
/// Validates the name (non-empty, unique) and — desktop only — that the
/// chosen directory isn't already an Aion project (no existing
/// `.aion/manifest.json` marker), then persists via [ProjectRepository]
/// and, on desktop, writes the marker and initializes an empty git
/// repository at `rootPath`.
class CreateProjectCubit extends Cubit<CreateProjectState> {
  /// Creates a [CreateProjectCubit] backed by [_projectRepository] and
  /// [_baselineRepository].
  CreateProjectCubit(this._projectRepository, this._baselineRepository)
    : super(const CreateProjectInitial());

  final ProjectRepository _projectRepository;
  final BaselineRepository _baselineRepository;
  static const _uuid = Uuid();

  /// Marker file written at `<rootPath>/.aion/manifest.json` on project
  /// creation (desktop only), and checked for by [submit] to reject a
  /// directory that's already an Aion project.
  static const _manifestFileName = 'manifest.json';

  /// Validates and, if valid, creates a new project named [name] pinned
  /// to [baselineVersion] (defaults to the latest bundled version when
  /// omitted). [rootPath] is required on desktop and ignored on
  /// mobile/web, where a project is isolated purely by its generated
  /// storage key.
  ///
  /// Emits [CreateProjectValidating], then either [CreateProjectFailure]
  /// (classified via [CreateProjectFailureReason]) or
  /// [CreateProjectReady] followed immediately by
  /// [CreateProjectSubmitting] and finally [CreateProjectSuccess] or a
  /// [CreateProjectFailure] carrying a raw repository/filesystem error.
  Future<void> submit({
    required String name,
    String? rootPath,
    String? baselineVersion,
  }) async {
    emit(const CreateProjectValidating());

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      emit(
        const CreateProjectFailure(
          '',
          reason: CreateProjectFailureReason.emptyName,
        ),
      );
      return;
    }

    final existing = await _projectRepository.getAllProjects();
    final isDuplicateName = existing.any(
      (p) => p.name.trim().toLowerCase() == trimmedName.toLowerCase(),
    );
    if (isDuplicateName) {
      emit(
        const CreateProjectFailure(
          '',
          reason: CreateProjectFailureReason.duplicateName,
        ),
      );
      return;
    }

    if (isDesktop) {
      if (rootPath == null || rootPath.trim().isEmpty) {
        emit(
          const CreateProjectFailure(
            '',
            reason: CreateProjectFailureReason.directoryNotChosen,
          ),
        );
        return;
      }
      if (_manifestFile(rootPath).existsSync()) {
        emit(
          const CreateProjectFailure(
            '',
            reason: CreateProjectFailureReason.directoryAlreadyInUse,
          ),
        );
        return;
      }
    }

    final versions = await _baselineRepository.getAvailableBaselineVersions();
    final resolvedVersion = baselineVersion ?? versions.last;

    emit(
      CreateProjectReady(
        name: trimmedName,
        rootPath: isDesktop ? rootPath : null,
        baselineVersion: resolvedVersion,
      ),
    );

    emit(const CreateProjectSubmitting());
    try {
      final now = DateTime.now();
      final id = _uuid.v4();
      final project = Project(
        id: id,
        name: trimmedName,
        storageKey: id,
        rootPath: isDesktop ? rootPath : null,
        baselineVersion: resolvedVersion,
        createdAt: now,
        lastOpenedAt: now,
      );

      if (isDesktop && rootPath != null) {
        await _initializeDesktopProject(rootPath, resolvedVersion);
      }

      await _projectRepository.createProject(project);
      emit(CreateProjectSuccess(project));
    } catch (e) {
      emit(CreateProjectFailure(e.toString()));
    }
  }

  /// Writes the `.aion/manifest.json` marker and initializes an empty
  /// git repository at [rootPath]. Desktop only — see
  /// `aion-arch/changes/multi-project-hub/proposal.md`'s platform note
  /// for why mobile/web don't get git-backed version history in this
  /// change.
  Future<void> _initializeDesktopProject(
    String rootPath,
    String baselineVersion,
  ) async {
    final aionDir = Directory('$rootPath${Platform.pathSeparator}.aion')
      ..createSync(recursive: true);
    final manifest = File(
      '${aionDir.path}${Platform.pathSeparator}$_manifestFileName',
    );
    manifest.writeAsStringSync('{"baselineVersion": "$baselineVersion"}');

    await Process.run('git', ['init'], workingDirectory: rootPath);
  }

  File _manifestFile(String rootPath) {
    return File(
      '$rootPath${Platform.pathSeparator}.aion${Platform.pathSeparator}$_manifestFileName',
    );
  }
}
