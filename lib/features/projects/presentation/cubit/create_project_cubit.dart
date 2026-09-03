// presentation/cubit/create_project_cubit.dart — CreateProjectCubit business logic (presentation layer).

import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import 'package:aion/core/build/project_manifest_writer.dart';
import 'package:aion/core/core.dart';
import 'package:aion/features/projects/data/services/baseline_tailoring_service.dart';
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
/// and, on desktop, writes the marker, initializes an empty git
/// repository at `rootPath` (skipped if one already exists — see
/// [submit]'s `appendGitignore` parameter), and asks
/// [_baselineTailoringService] to tailor a starting
/// `conventions/architecture-conventions` override from the detected
/// stack.
class CreateProjectCubit extends Cubit<CreateProjectState> {
  /// Creates a [CreateProjectCubit] backed by [_projectRepository],
  /// [_baselineRepository], [_baselineTailoringService], [_gitClient],
  /// and [_gitignoreEditor].
  CreateProjectCubit(
    this._projectRepository,
    this._baselineRepository,
    this._baselineTailoringService,
    this._gitClient,
    this._gitignoreEditor,
  ) : super(const CreateProjectInitial());

  final ProjectRepository _projectRepository;
  final BaselineRepository _baselineRepository;
  final BaselineTailoringService _baselineTailoringService;
  final GitRepositoryClient _gitClient;
  final GitignoreEditor _gitignoreEditor;
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
  /// [appendGitignore] (default `true`) is consulted only when
  /// [rootPath] is already a git repository: `true` appends `.aion/`
  /// and `tickets/` to that repo's `.gitignore` (creating one if
  /// absent) before any bookkeeping is written; `false` proceeds
  /// without touching `.gitignore` — declining doesn't block creation,
  /// matching Aion's inform-don't-block posture (see
  /// `AIO-1266`). Ignored
  /// entirely when [rootPath] isn't already a git repository, since
  /// `git init` there needs no gitignore gate.
  ///
  /// Emits [CreateProjectValidating], then either [CreateProjectFailure]
  /// (classified via [CreateProjectFailureReason]) or
  /// [CreateProjectReady] followed immediately by
  /// [CreateProjectSubmitting] and finally [CreateProjectSuccess]
  /// (carrying whether [rootPath] was already a git repository) or a
  /// [CreateProjectFailure] carrying a raw repository/filesystem error.
  Future<void> submit({
    required String name,
    String? rootPath,
    String? baselineVersion,
    bool appendGitignore = true,
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

      var wasExistingGitRepo = false;
      if (isDesktop && rootPath != null) {
        wasExistingGitRepo = await _gitClient.isGitRepository(rootPath);
        await _initializeDesktopProject(
          rootPath,
          resolvedVersion,
          alreadyGitRepo: wasExistingGitRepo,
          appendGitignore: appendGitignore,
        );
        final manifest = await _baselineRepository.getManifest(
          resolvedVersion,
        );
        await _baselineTailoringService.tailorForDetectedStack(
          projectId: id,
          rootPath: rootPath,
          manifest: manifest,
        );
      }

      await _projectRepository.createProject(project);
      emit(
        CreateProjectSuccess(project, wasExistingGitRepo: wasExistingGitRepo),
      );
    } catch (e) {
      emit(CreateProjectFailure(e.toString()));
    }
  }

  /// Writes the `.aion/manifest.json` marker (via [ProjectManifestWriter])
  /// and creates the `tickets/` subdirectory that ticket git-projection
  /// writes into (see
  /// `AIO-2022`). Desktop
  /// only — see `AIO-1174`'s
  /// platform note for why mobile/web don't get git-backed version
  /// history in this change.
  ///
  /// When [alreadyGitRepo] is `false`, initializes a fresh empty git
  /// repository at [rootPath] exactly as before. When `true`, [rootPath]
  /// is left as whatever repository it already was — re-running `git
  /// init` there is redundant — and, if [appendGitignore] is also
  /// `true`, [_gitignoreEditor] excludes `.aion/`/`tickets/` from that
  /// repo's own history before either bookkeeping path is written above.
  /// Added for `AIO-1266`.
  Future<void> _initializeDesktopProject(
    String rootPath,
    String baselineVersion, {
    required bool alreadyGitRepo,
    required bool appendGitignore,
  }) async {
    if (alreadyGitRepo && appendGitignore) {
      await _gitignoreEditor.ensureIgnored(rootPath, [
        '.aion/',
        'tickets/',
      ]);
    }

    await ProjectManifestWriter.write(rootPath, baselineVersion);

    Directory(
      '$rootPath${Platform.pathSeparator}tickets',
    ).createSync(recursive: true);

    if (!alreadyGitRepo) {
      await _gitClient.init(rootPath);
    }
  }

  File _manifestFile(String rootPath) {
    return File(
      '$rootPath${Platform.pathSeparator}.aion${Platform.pathSeparator}$_manifestFileName',
    );
  }
}
