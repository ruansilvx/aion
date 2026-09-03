// core/migration/aion_arch_idea_migrator.dart — AionArchIdeaMigrator (core layer).

import 'package:uuid/uuid.dart';

import 'package:aion/core/migration/migration_link_manifest.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

/// Converts one `aion-arch/ideas/<slug>.md` file (schema:
/// `aion-arch/workflow/shared/idea-format.md`) into an `idea`/`knownGap`/
/// `openQuestion` [Ticket] plus its `relatesTo` link rows, per
/// `changes/decommission-aion-arch-cli-workflow-step-1/design.md`'s
/// "Field mapping: idea file → ticket" table.
///
/// Pure Dart, no Flutter/drift dependency — same constraint as
/// [TicketMarkdownSerializer](../markdown/ticket_markdown_serializer.dart),
/// so `bin/migrate_aion_arch.dart` can run this without pulling in
/// Flutter.
class AionArchIdeaMigrator {
  static const _uuid = Uuid();

  /// Migrates one idea file's raw [fileContent] into a `(Ticket, List of
  /// MigrationLinkRow)` pair.
  ///
  /// [migratedIdeaSlugs] is every idea filename slug (no `.md`
  /// extension) that this migration pass is migrating — the full set,
  /// known upfront by listing `aion-arch/ideas/*.md` before any single
  /// file is parsed. Only `related_ideas` entries present in this set
  /// produce a link row; an entry with no migrated counterpart is
  /// dropped and instead noted as a one-line addition to the returned
  /// ticket's `description`, per design.md — never a dangling-target
  /// link.
  ///
  /// The returned [Ticket.id] is a freshly generated uuid, safe to use
  /// immediately as a link row's `sourceTicketId`. [Ticket.ticketId] is
  /// left as `''` — this migrator has no visibility into the other files
  /// this migration pass will also produce, so it cannot allocate a
  /// collision-free sequential id itself; `bin/migrate_aion_arch.dart`
  /// assigns the real `AIO-<n>` value to every migrated ticket in one
  /// pass after every source file (ideas and archived changes alike) has
  /// been migrated.
  ///
  /// Every returned link row's `targetTicketId` is likewise a
  /// placeholder — the *target idea's own filename slug*, not yet a real
  /// ticket id — since a target idea processed later in the same pass
  /// has no `id` yet at the time this call returns. Resolving every such
  /// placeholder into the target's real generated `id` is
  /// `bin/migrate_aion_arch.dart`'s job, once it has migrated every idea
  /// file and therefore knows every slug's final `id`. See
  /// [MigrationLinkRow]'s own dartdoc for this same contract stated from
  /// the manifest side.
  (Ticket, List<MigrationLinkRow>) migrate(
    String fileContent, {
    required Set<String> migratedIdeaSlugs,
  }) {
    // Source files are read verbatim off disk and may be CRLF-terminated
    // (a plain Windows git checkout) — normalize once so no stray `\r`
    // ends up embedded mid-description.
    fileContent = fileContent.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final frontmatter = _parseFrontmatter(fileContent);
    final id = _uuid.v4();
    final now = DateTime.now();

    final title = _unquote(frontmatter['title']);
    final status = _mapStatus(frontmatter['status']);
    final createdAt = _parseDate(frontmatter['created']) ?? now;
    final updatedAt = _parseDate(frontmatter['last_touched']) ?? createdAt;
    final relatedIdeas = _stringList(frontmatter['related_ideas']);

    final migratedTargets = relatedIdeas
        .where(migratedIdeaSlugs.contains)
        .toList();
    final danglingTargets = relatedIdeas
        .where((slug) => !migratedIdeaSlugs.contains(slug))
        .toList();

    final reclassified = _reclassify(
      title: title,
      migratedTargets: migratedTargets,
    );

    final links = <MigrationLinkRow>[
      for (final target in migratedTargets)
        MigrationLinkRow(
          sourceTicketId: id,
          targetTicketId: target,
          type: TicketLinkType.relatesTo,
        ),
    ];

    var description = _extractBody(fileContent);
    if (danglingTargets.isNotEmpty) {
      description +=
          '\n\n_Related idea${danglingTargets.length > 1 ? 's' : ''} not '
          'migrated (no corresponding ticket): '
          '${danglingTargets.join(', ')}._';
    }

    final ticket = Ticket(
      id: id,
      ticketId: '',
      type: reclassified ?? TicketType.idea,
      title: title.isEmpty ? '(untitled idea)' : title,
      description: description.isEmpty ? null : description,
      status: status,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    return (ticket, links);
  }

  /// Reclassifies an idea to [TicketType.knownGap]/[TicketType.openQuestion]
  /// only when [title] unambiguously carries the literal `"Known gap:"`/
  /// `"Open question:"` marker (case-insensitive) *and* exactly one
  /// `related_ideas` entry was actually migrated — the single target the
  /// mandatory `relatesTo` link (already built into [migratedTargets],
  /// via the caller's `links` list) attaches to. Every other case — no
  /// marker, marker with zero or multiple migrated targets — stays
  /// `null` (meaning: default to [TicketType.idea]), per design.md's
  /// "never guessed" rule: no real `aion-arch/ideas/*.md` title uses this
  /// marker convention today, so this reclassification is a mechanism
  /// this migration keeps available, not one it expects to fire, exactly
  /// as intended.
  TicketType? _reclassify({
    required String title,
    required List<String> migratedTargets,
  }) {
    if (migratedTargets.length != 1) return null;
    final normalized = title.trim().toLowerCase();
    if (normalized.startsWith('known gap:')) return TicketType.knownGap;
    if (normalized.startsWith('open question:')) return TicketType.openQuestion;
    return null;
  }

  /// Maps an idea file's `status` value to this project's open/backlog-
  /// or done-equivalent `WorkflowStatus.name` — `raw`/`resolved`/
  /// `explored` become `'backlog'`, `specced`/`archived` become `'done'`,
  /// per design.md's field-mapping table. An unrecognized or missing
  /// value defaults to `'backlog'`, the least presumptive choice.
  String _mapStatus(String? status) {
    switch (status) {
      case 'specced':
      case 'archived':
        return 'done';
      case 'raw':
      case 'resolved':
      case 'explored':
      default:
        return 'backlog';
    }
  }

  /// Parses a `created`/`last_touched` field's raw `YYYY-MM-DD` [value]
  /// into a [DateTime], or `null` if [value] is missing or unparseable.
  DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  /// Reads a bracketed, comma-separated frontmatter field (e.g.
  /// `related_ideas: [a, b]`) as a plain `List<String>`, or `[]` if
  /// [value] is missing, empty (`[]`), or not bracketed.
  List<String> _stringList(String? value) {
    if (value == null) return const [];
    final trimmed = value.trim();
    if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) return const [];
    final inner = trimmed.substring(1, trimmed.length - 1).trim();
    if (inner.isEmpty) return const [];
    return [
      for (final entry in inner.split(','))
        if (entry.trim().isNotEmpty) entry.trim(),
    ];
  }

  /// Strips one matching pair of leading/trailing double quotes from
  /// [value], if present, and trims whitespace. `null` becomes `''`.
  /// Real `aion-arch/ideas/*.md` titles are never quoted (per
  /// [_parseFrontmatter]'s own dartdoc, quoting is unnecessary with a
  /// line-based parser) — this only guards against a value someone
  /// quoted anyway, defensively.
  String _unquote(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.length >= 2 &&
        trimmed.startsWith('"') &&
        trimmed.endsWith('"')) {
      return trimmed.substring(1, trimmed.length - 1);
    }
    return trimmed;
  }

  /// Matches one frontmatter line's `key: value` pair. Deliberately not a
  /// YAML parser — see [_parseFrontmatter]'s dartdoc for why.
  static final RegExp _frontmatterLine = RegExp(
    r'^([A-Za-z_][A-Za-z0-9_]*):\s?(.*)$',
  );

  /// Parses [content]'s frontmatter block (delimited by `---` lines, same
  /// convention as [TicketMarkdownSerializer]) into a plain
  /// `Map<String, String>` of raw field values, one per line.
  ///
  /// Deliberately a lenient line-based `key: value` scan, not a real YAML
  /// parser — `package:yaml`'s `loadYaml` was tried first and rejected:
  /// a real `aion-arch/ideas/*.md` corpus scan found 29 of 70 files
  /// (41%) fail strict YAML block-mapping parsing, because a free-text
  /// field (`summary`, `next_action`) contains an unquoted `: ` inside
  /// its own prose (e.g. "rather than keeping it alongside: /explore
  /// found..."), which YAML reads as an unexpected nested mapping key.
  /// These files are otherwise well-formed by the idea-format schema's
  /// own convention (`workflow/shared/idea-format.md`): exactly one
  /// `key: value` pair per line, values never wrapping to a second line.
  /// A parser that assumes that convention directly — split on the
  /// *first* colon of each line — reads every one of these files
  /// correctly instead of silently discarding the whole frontmatter (the
  /// prior YAML-based behavior's fallback, per [migrate]'s "never
  /// guessed" contract, on any parse failure) for close to half the
  /// corpus. Returns an empty map only if the file has no `---`-delimited
  /// frontmatter block at all — such a file still migrates as a bare,
  /// mostly-empty `idea` ticket rather than aborting the whole run.
  Map<String, String> _parseFrontmatter(String content) {
    final lines = content.split('\n');
    if (lines.isEmpty || lines.first.trim() != '---') return const {};
    final closingIndex = lines.indexWhere((l) => l.trim() == '---', 1);
    if (closingIndex == -1) return const {};

    final result = <String, String>{};
    for (final line in lines.sublist(1, closingIndex)) {
      final match = _frontmatterLine.firstMatch(line);
      if (match == null) continue;
      result[match.group(1)!] = match.group(2)!.trim();
    }
    return result;
  }

  /// Extracts everything after the closing frontmatter delimiter —
  /// design.md's "Idea body ... verbatim" mapping — trimmed of leading/
  /// trailing blank lines.
  String _extractBody(String content) {
    final lines = content.split('\n');
    if (lines.isEmpty || lines.first.trim() != '---') return content.trim();
    final closingIndex = lines.indexWhere((l) => l.trim() == '---', 1);
    if (closingIndex == -1) return content.trim();
    return lines.sublist(closingIndex + 1).join('\n').trim();
  }
}
