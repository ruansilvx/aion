// core/migration/aion_arch_project_spec_migrator.dart — AionArchProjectSpecMigrator (core layer).

import 'package:uuid/uuid.dart';

import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

/// Wraps `aion-arch/project.md`'s full content into the one hand-
/// bootstrapped architecture `spec` ticket the `spec-ticket-type` idea
/// anticipated, per
/// `changes/decommission-aion-arch-cli-workflow-step-1/design.md`'s
/// "Field mapping: archived change → Epic/Story/Task/spec/page" table's
/// `aion-arch/project.md` row.
///
/// Pure Dart, no Flutter/drift dependency, same as
/// [AionArchIdeaMigrator](aion_arch_idea_migrator.dart)/
/// [AionArchChangeMigrator](aion_arch_change_migrator.dart).
class AionArchProjectSpecMigrator {
  static const _uuid = Uuid();

  /// Migrates [projectMdContent] (the full raw content of
  /// `aion-arch/project.md`) into one parentless `spec` [Ticket].
  ///
  /// Its `description` opens with the same `[NEEDS RECONCILIATION]`
  /// marker [AionArchChangeMigrator] seeds every archived change's spec
  /// ticket with, plus a note that this ticket's own keep-updated
  /// mechanism is a separate, still-unresolved open question per
  /// `spec-ticket-type` — not something this migration resolves.
  ///
  /// [Ticket.id] is a freshly generated uuid; [Ticket.ticketId] is left
  /// as `''`, assigned for real by `bin/migrate_aion_arch.dart` in the
  /// same pass as every other migrated ticket — see
  /// [AionArchIdeaMigrator.migrate]'s dartdoc for why.
  Ticket migrate(String projectMdContent) {
    // Source file is read verbatim off disk and may be CRLF-terminated
    // (a plain Windows git checkout) — normalize once so no stray `\r`
    // ends up embedded mid-description.
    projectMdContent = projectMdContent
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final now = DateTime.now();
    final lines = projectMdContent.split('\n');
    final firstIndex = lines.indexWhere((l) => l.trim().isNotEmpty);
    var title = 'Project Context — Aion';
    var body = projectMdContent.trim();
    if (firstIndex != -1) {
      final firstLine = lines[firstIndex].trim();
      if (firstLine.startsWith('#')) {
        final heading = firstLine.replaceFirst(RegExp(r'^#+\s*'), '').trim();
        if (heading.isNotEmpty) title = heading;
        body = lines.sublist(firstIndex + 1).join('\n').trim();
      }
    }

    return Ticket(
      id: _uuid.v4(),
      ticketId: '',
      type: TicketType.spec,
      title: title,
      description:
          '[NEEDS RECONCILIATION] — seeded verbatim from '
          'aion-arch/project.md; not yet reconciled against that file\'s '
          'current content. This ticket\'s own ongoing keep-updated '
          'mechanism is a separate open question (see the '
          'spec-ticket-type idea) — not resolved by this migration.'
          '\n\n$body',
      status: 'done',
      createdAt: now,
      updatedAt: now,
    );
  }
}
