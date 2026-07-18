// domain/entities/project.dart — Project entity (domain layer).

import 'package:equatable/equatable.dart';

/// A single isolated Aion project — the unit of isolation the Hub
/// switches between. Each project has its own drift database and
/// (desktop only) its own git repository, addressed by [storageKey]/
/// [rootPath] rather than one global path. See
/// `aion-arch/changes/multi-project-hub/design.md` §2 for the full
/// per-project storage model this entity backs.
class Project extends Equatable {
  /// Internal UUID v4 primary key.
  final String id;

  /// Display name shown on the Hub's [ProjectCard].
  final String name;

  /// Platform-agnostic identifier used to derive this project's
  /// per-project drift database name/path — a real subdirectory name on
  /// desktop/mobile, or a WASM database-name suffix on web. Always
  /// present, unlike [rootPath].
  final String storageKey;

  /// Real filesystem directory for this project's data (drift DB file,
  /// `.aion/` marker, and — desktop only — its git repository). `null`
  /// on mobile/web, where a project has no user-chosen directory and is
  /// isolated purely by [storageKey].
  final String? rootPath;

  /// The pinned baseline version this project was created against (e.g.
  /// `"0.1.0"`). Immutable through this change's UI — upgrading a
  /// project's pin is a future change.
  final String baselineVersion;

  /// When this project was created.
  final DateTime createdAt;

  /// When this project was last opened from the Hub. Updated by
  /// [ActiveProjectCubit](../../presentation/cubit/active_project_cubit.dart)
  /// on every switch; drives the Hub's most-recently-opened-first
  /// ordering.
  final DateTime lastOpenedAt;

  /// Creates a [Project].
  const Project({
    required this.id,
    required this.name,
    required this.storageKey,
    this.rootPath,
    required this.baselineVersion,
    required this.createdAt,
    required this.lastOpenedAt,
  });

  @override
  List<Object?> get props => [
    id,
    name,
    storageKey,
    rootPath,
    baselineVersion,
    createdAt,
    lastOpenedAt,
  ];
}
