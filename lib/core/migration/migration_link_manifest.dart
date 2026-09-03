// core/migration/migration_link_manifest.dart — MigrationLinkRow/MigrationLinkManifest (core layer).

import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';

/// One `ticket_links`-shaped row produced by a migrator in
/// `core/migration/`, pending creation via
/// [TicketLinkRepository.createLink](../../features/tickets/domain/repositories/ticket_link_repository.dart).
///
/// [sourceTicketId]/[targetTicketId] are internal [Ticket](../../features/tickets/domain/entities/ticket.dart)
/// `id` values (uuids), matching [TicketLinkRepository.createLink]'s own
/// parameter contract — never a human-readable `ticketId`. A migrator
/// that cannot yet resolve its target's final `id` at the point it builds
/// this row (see `AionArchIdeaMigrator`'s `related_ideas` handling, the
/// only such case in this migration) returns a row whose [targetTicketId]
/// is a symbolic placeholder instead (that idea's own filename slug);
/// resolving every such placeholder into a real `id` is
/// `bin/migrate_aion_arch.dart`'s job, once every source file in the pass
/// has been migrated and every `id` is therefore known. Only fully
/// resolved rows are ever serialized via [MigrationLinkManifest].
class MigrationLinkRow {
  /// Creates a [MigrationLinkRow].
  const MigrationLinkRow({
    required this.sourceTicketId,
    required this.targetTicketId,
    required this.type,
  });

  /// The link's source ticket id.
  final String sourceTicketId;

  /// The link's target ticket id.
  final String targetTicketId;

  /// The relationship type, from the source ticket's perspective.
  final TicketLinkType type;

  /// Builds a [MigrationLinkRow] from its JSON map form, as written by
  /// [toJson]. Throws [FormatException] if [json]'s `type` value doesn't
  /// name a known [TicketLinkType].
  factory MigrationLinkRow.fromJson(Map<String, Object?> json) {
    final typeName = json['type'] as String?;
    TicketLinkType? type;
    for (final t in TicketLinkType.values) {
      if (t.name == typeName) type = t;
    }
    if (type == null) {
      throw FormatException('Unknown TicketLinkType name: $typeName');
    }
    return MigrationLinkRow(
      sourceTicketId: json['sourceTicketId'] as String,
      targetTicketId: json['targetTicketId'] as String,
      type: type,
    );
  }

  /// Renders this row as a JSON-serializable map.
  Map<String, Object?> toJson() => {
    'sourceTicketId': sourceTicketId,
    'targetTicketId': targetTicketId,
    'type': type.name,
  };
}

/// The on-disk contents of `tickets/.migration-links.json`: every
/// [MigrationLinkRow] this migration produced, since
/// [TicketMarkdownTemplate](../markdown/ticket_markdown_template.dart)'s
/// frontmatter schema has no field for non-hierarchical `TicketLink`
/// relationships (see design.md's "Why TicketLinks need a separate
/// manifest"). Not a ticket file itself — never read by
/// [TicketMarkdownSerializer](../markdown/ticket_markdown_serializer.dart)
/// or `TicketDbReconstructionService`, only by
/// `bin/migrate_aion_arch.dart`'s own `--import` link-backfill step.
class MigrationLinkManifest {
  /// Creates a [MigrationLinkManifest] wrapping [rows].
  const MigrationLinkManifest(this.rows);

  /// Every link row this migration produced.
  final List<MigrationLinkRow> rows;

  /// Builds a [MigrationLinkManifest] from its JSON form, as written by
  /// [toJson]: a plain JSON array of [MigrationLinkRow] objects. An empty
  /// or missing [json] list yields an empty manifest.
  factory MigrationLinkManifest.fromJson(Object? json) {
    if (json is! List) return const MigrationLinkManifest([]);
    return MigrationLinkManifest([
      for (final entry in json)
        MigrationLinkRow.fromJson(Map<String, Object?>.from(entry as Map)),
    ]);
  }

  /// Renders this manifest as a JSON-serializable value: a plain list of
  /// [MigrationLinkRow.toJson] maps.
  List<Map<String, Object?>> toJson() => [for (final row in rows) row.toJson()];
}
