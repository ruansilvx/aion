// data/models/project_model.dart — ProjectModel JSON-serializable data model (data layer).

import 'package:drift/drift.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/projects/domain/entities/project.dart';

part 'project_model.g.dart';

/// JSON-serializable data-layer model for [Project], and the mapping
/// to/from the generated [RegistryDatabase] `projects` row
/// ([ProjectRegistryData]). Keeps [Project] itself free of
/// serialization annotations, per `project.md`'s domain/data split.
@JsonSerializable()
class ProjectModel {
  /// Creates a [ProjectModel].
  const ProjectModel({
    required this.id,
    required this.name,
    required this.storageKey,
    this.rootPath,
    required this.baselineVersion,
    required this.createdAtMillis,
    required this.lastOpenedAtMillis,
  });

  /// Internal UUID v4 primary key.
  final String id;

  /// Display name shown on the Hub.
  final String name;

  /// Platform-agnostic storage identifier — see [Project.storageKey].
  final String storageKey;

  /// Real filesystem directory, desktop only. `null` on mobile/web.
  final String? rootPath;

  /// Pinned baseline version string.
  final String baselineVersion;

  /// [Project.createdAt] as Unix milliseconds.
  final int createdAtMillis;

  /// [Project.lastOpenedAt] as Unix milliseconds.
  final int lastOpenedAtMillis;

  /// Deserializes a [ProjectModel] from JSON.
  factory ProjectModel.fromJson(Map<String, dynamic> json) =>
      _$ProjectModelFromJson(json);

  /// Serializes this [ProjectModel] to JSON.
  Map<String, dynamic> toJson() => _$ProjectModelToJson(this);

  /// Builds a [ProjectModel] from a generated [ProjectRegistryData] row.
  factory ProjectModel.fromRow(ProjectRegistryData row) {
    return ProjectModel(
      id: row.id,
      name: row.name,
      storageKey: row.storageKey,
      rootPath: row.rootPath,
      baselineVersion: row.baselineVersion,
      createdAtMillis: row.createdAt,
      lastOpenedAtMillis: row.lastOpenedAt,
    );
  }

  /// Builds a [ProjectModel] from the [Project] domain entity.
  factory ProjectModel.fromEntity(Project project) {
    return ProjectModel(
      id: project.id,
      name: project.name,
      storageKey: project.storageKey,
      rootPath: project.rootPath,
      baselineVersion: project.baselineVersion,
      createdAtMillis: project.createdAt.millisecondsSinceEpoch,
      lastOpenedAtMillis: project.lastOpenedAt.millisecondsSinceEpoch,
    );
  }

  /// Converts this model to the [Project] domain entity.
  Project toEntity() {
    return Project(
      id: id,
      name: name,
      storageKey: storageKey,
      rootPath: rootPath,
      baselineVersion: baselineVersion,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMillis),
      lastOpenedAt: DateTime.fromMillisecondsSinceEpoch(lastOpenedAtMillis),
    );
  }

  /// Converts this model to a [ProjectsTableCompanion] for insert/update.
  ProjectsTableCompanion toCompanion() {
    return ProjectsTableCompanion.insert(
      id: id,
      name: name,
      storageKey: storageKey,
      rootPath: Value(rootPath),
      baselineVersion: baselineVersion,
      createdAt: createdAtMillis,
      lastOpenedAt: lastOpenedAtMillis,
    );
  }
}
