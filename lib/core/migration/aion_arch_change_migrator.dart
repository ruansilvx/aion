// core/migration/aion_arch_change_migrator.dart — AionArchChangeMigrator (core layer).

import 'package:uuid/uuid.dart';

import 'package:aion/core/migration/migration_link_manifest.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

/// The bundle of tickets and link rows [AionArchChangeMigrator.migrate]
/// produces for one `aion-arch/changes/archive/<name>/` folder.
class AionArchChangeMigration {
  /// Creates an [AionArchChangeMigration].
  const AionArchChangeMigration({
    required this.epic,
    required this.storiesAndTasks,
    required this.page,
    required this.spec,
    required this.links,
  });

  /// The change's `proposal.md`-derived Epic ticket.
  final Ticket epic;

  /// Every `tasks.md`-derived Story and Task ticket, flat (a Task's
  /// [Ticket.parentId] points at its own Story's [Ticket.id] within this
  /// same list; a Story's [Ticket.parentId] points at [epic.id]).
  final List<Ticket> storiesAndTasks;

  /// The `design.md`-derived Documentation `page` ticket.
  final Ticket page;

  /// The `specs/spec.md`-derived `spec` ticket, seeded
  /// `[NEEDS RECONCILIATION]`.
  final Ticket spec;

  /// `relatesTo` rows connecting [page] to [epic] and [spec] — see
  /// design.md's field-mapping table.
  final List<MigrationLinkRow> links;
}

/// Converts one archived `aion-arch/changes/archive/<name>/` folder's four
/// planning artifacts (`proposal.md`, `design.md`, `specs/spec.md`,
/// `tasks.md`) into an Epic/Story/Task/spec/page ticket bundle, per
/// `changes/decommission-aion-arch-cli-workflow-step-1/design.md`'s
/// "Field mapping: archived change → Epic/Story/Task/spec/page" table.
///
/// Pure Dart, no Flutter/drift dependency, same as
/// [AionArchIdeaMigrator](aion_arch_idea_migrator.dart).
class AionArchChangeMigrator {
  static const _uuid = Uuid();

  /// Matches a `tasks.md` level-2 section heading (`## Title`), excluding
  /// `### `-or-deeper subheadings.
  static final RegExp _sectionHeading = RegExp(r'^## (?!#)(.*)$');

  /// Matches a top-level (column-0) Markdown checklist item, e.g.
  /// `- [x] Title...` or `- [ ] Title...`.
  static final RegExp _checklistItem = RegExp(r'^- \[[ xX]\] (.*)$');

  /// Migrates one archived change folder's four file contents into an
  /// [AionArchChangeMigration].
  ///
  /// Every produced [Ticket.id] is a freshly generated uuid; every
  /// [Ticket.ticketId] is left as `''`, assigned for real by
  /// `bin/migrate_aion_arch.dart` in the same pass as every other
  /// migrated ticket — see [AionArchIdeaMigrator.migrate]'s dartdoc for
  /// why. Unlike idea migration, every link and parent/child reference
  /// this migrator produces is fully resolvable within this one call — an
  /// Epic, its Stories/Tasks, its page, and its spec are all generated
  /// together — so, unlike [AionArchIdeaMigrator], no placeholder/
  /// deferred-resolution step is needed here.
  AionArchChangeMigration migrate(
    String changeName, {
    required String proposalMd,
    required String designMd,
    required String specDeltaMd,
    required String tasksMd,
  }) {
    // Source files are read verbatim off disk and may be CRLF-terminated
    // (a plain Windows git checkout, unlike this migration's own LF
    // output). Every line-oriented parse below (`_sectionHeading`/
    // `_checklistItem`) assumes a bare `\n`, so normalize once up front —
    // otherwise a trailing `\r` left on every split line silently defeats
    // `$`-anchored matching (`.` never matches a line terminator).
    proposalMd = _normalizeLineEndings(proposalMd);
    designMd = _normalizeLineEndings(designMd);
    specDeltaMd = _normalizeLineEndings(specDeltaMd);
    tasksMd = _normalizeLineEndings(tasksMd);

    final title = _humanize(changeName);
    final now = DateTime.now();

    final epic = Ticket(
      id: _uuid.v4(),
      ticketId: '',
      type: TicketType.epic,
      title: title,
      description: proposalMd.trim().isEmpty ? null : proposalMd,
      status: 'done',
      createdAt: now,
      updatedAt: now,
    );

    final storiesAndTasks = _buildStoriesAndTasks(
      tasksMd,
      epicId: epic.id,
      now: now,
    );

    final (pageTitle, pageBody) = _extractLeadingHeading(
      designMd,
      fallbackTitle: 'Design: $title',
    );
    final page = Ticket(
      id: _uuid.v4(),
      ticketId: '',
      type: TicketType.page,
      title: pageTitle,
      description: pageBody.isEmpty ? null : pageBody,
      status: 'done',
      createdAt: now,
      updatedAt: now,
    );

    final (specTitle, specBody) = _extractLeadingHeading(
      specDeltaMd,
      fallbackTitle: 'Spec delta: $title',
    );
    final spec = Ticket(
      id: _uuid.v4(),
      ticketId: '',
      type: TicketType.spec,
      title: specTitle,
      description:
          '[NEEDS RECONCILIATION] — seeded from this change\'s delta spec; '
          'not yet reconciled against the current merged '
          'aion-arch/specs/*.md text.\n\n$specBody',
      status: 'done',
      createdAt: now,
      updatedAt: now,
    );

    final links = [
      MigrationLinkRow(
        sourceTicketId: page.id,
        targetTicketId: epic.id,
        type: TicketLinkType.relatesTo,
      ),
      MigrationLinkRow(
        sourceTicketId: page.id,
        targetTicketId: spec.id,
        type: TicketLinkType.relatesTo,
      ),
    ];

    return AionArchChangeMigration(
      epic: epic,
      storiesAndTasks: storiesAndTasks,
      page: page,
      spec: spec,
      links: links,
    );
  }

  /// Builds every Story/Task ticket from [tasksMd]. One Story per
  /// clearly-delimited `## ` section if the file has any; a single Story
  /// wrapping the whole checklist otherwise. Every Task within a section
  /// (or, with no sections, within the whole file) becomes a child of
  /// that section's Story.
  List<Ticket> _buildStoriesAndTasks(
    String tasksMd, {
    required String epicId,
    required DateTime now,
  }) {
    final lines = tasksMd.split('\n');
    final sections = <(String title, List<String> lines)>[];

    var currentTitle = '';
    var currentLines = <String>[];
    var sawSection = false;
    for (final line in lines) {
      final match = _sectionHeading.firstMatch(line);
      if (match != null) {
        if (sawSection || currentLines.any((l) => l.trim().isNotEmpty)) {
          sections.add((currentTitle, currentLines));
        }
        currentTitle = match.group(1)!.trim();
        currentLines = [];
        sawSection = true;
      } else {
        currentLines.add(line);
      }
    }
    sections.add((currentTitle, currentLines));

    final result = <Ticket>[];
    if (sawSection) {
      for (final (title, sectionLines) in sections) {
        if (title.isEmpty && !sectionLines.any(_checklistItem.hasMatch)) {
          // Preamble before the first `## ` heading — not a real section.
          continue;
        }
        final story = Ticket(
          id: _uuid.v4(),
          ticketId: '',
          type: TicketType.story,
          title: title.isEmpty ? '(untitled section)' : title,
          description: sectionLines.join('\n').trim().isEmpty
              ? null
              : sectionLines.join('\n').trim(),
          status: 'done',
          parentId: epicId,
          createdAt: now,
          updatedAt: now,
        );
        result.add(story);
        result.addAll(_buildTasks(sectionLines, storyId: story.id, now: now));
      }
    } else {
      final (fallbackTitle, fallbackBody) = _extractLeadingHeading(
        tasksMd,
        fallbackTitle: 'Tasks',
      );
      final story = Ticket(
        id: _uuid.v4(),
        ticketId: '',
        type: TicketType.story,
        title: fallbackTitle,
        description: fallbackBody.isEmpty ? null : fallbackBody,
        status: 'done',
        parentId: epicId,
        createdAt: now,
        updatedAt: now,
      );
      result.add(story);
      result.addAll(_buildTasks(lines, storyId: story.id, now: now));
    }
    return result;
  }

  /// Scans [lines] for top-level checklist items, each becoming one
  /// `task` [Ticket] parented under [storyId]. An item's indented
  /// continuation lines (until the next top-level item or the end of
  /// [lines]) become its `description`.
  List<Ticket> _buildTasks(
    List<String> lines, {
    required String storyId,
    required DateTime now,
  }) {
    final tasks = <Ticket>[];
    String? currentTitle;
    final currentBody = <String>[];

    void flush() {
      if (currentTitle == null) return;
      final body = currentBody.join('\n').trim();
      tasks.add(
        Ticket(
          id: _uuid.v4(),
          ticketId: '',
          type: TicketType.task,
          title: currentTitle,
          description: body.isEmpty ? null : body,
          status: 'done',
          parentId: storyId,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    for (final line in lines) {
      final match = _checklistItem.firstMatch(line);
      if (match != null) {
        flush();
        currentTitle = match.group(1)!.trim();
        currentBody.clear();
      } else if (currentTitle != null && line.trim().isNotEmpty) {
        currentBody.add(line.trim());
      }
    }
    flush();
    return tasks;
  }

  /// If [content]'s first non-blank line is a Markdown heading (`# `,
  /// `## `, ...), returns `(that heading's text, the rest of the content
  /// trimmed)`; otherwise returns `(fallbackTitle, content trimmed)`.
  (String, String) _extractLeadingHeading(
    String content, {
    required String fallbackTitle,
  }) {
    final lines = content.split('\n');
    final firstIndex = lines.indexWhere((l) => l.trim().isNotEmpty);
    if (firstIndex == -1) return (fallbackTitle, '');
    final firstLine = lines[firstIndex].trim();
    if (!firstLine.startsWith('#')) return (fallbackTitle, content.trim());
    final title = firstLine.replaceFirst(RegExp(r'^#+\s*'), '').trim();
    final rest = lines.sublist(firstIndex + 1).join('\n').trim();
    return (title.isEmpty ? fallbackTitle : title, rest);
  }

  /// Normalizes `\r\n`/bare `\r` line endings to `\n`. See [migrate]'s
  /// dartdoc for why this matters for every line-oriented parse below.
  String _normalizeLineEndings(String content) =>
      content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  /// Converts a kebab-case change-folder name into a humanized title,
  /// e.g. `automatic-time-tracking-for-tickets` →
  /// `Automatic Time Tracking For Tickets`.
  String _humanize(String changeName) {
    return changeName
        .split('-')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}
