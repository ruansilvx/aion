// data/services/document_parent_migration_service.dart — DocumentParentMigrationService (data layer).

import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_link_repository.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';

/// One-time, idempotent startup migration that converts a resource/page
/// ticket's old `parentId` → epic/story/task relationship into a
/// `TicketLink` (see [TicketLinkType.relatesTo]), now that the
/// Documentation section owns resource/page structural parenting (only
/// `page` may parent `resource`/`page` — see
/// `TicketTypeHierarchy.canParent`) and work items can no longer parent
/// either. Nothing is left orphaned: the old parent relationship survives
/// as an explicit link instead of silently disappearing.
///
/// Runs once per install, gated by a persisted flag in
/// [SharedPreferences], so it is safe to call [migrateIfNeeded] on every
/// app start (e.g. from `WorkspaceShell.initState`, alongside the existing
/// trash-purge call) without redoing the work or re-creating duplicate
/// links.
class DocumentParentMigrationService {
  /// Creates a [DocumentParentMigrationService] backed by [_ticketRepository]
  /// (to read/clear the legacy `parentId`), [_linkRepository] (to create
  /// the replacement link), and [_prefs] (to persist the one-time-run
  /// flag).
  DocumentParentMigrationService(
    this._ticketRepository,
    this._linkRepository,
    this._prefs,
  );

  final TicketRepository _ticketRepository;
  final TicketLinkRepository _linkRepository;
  final SharedPreferences _prefs;

  /// SharedPreferences key gating this migration to a single run.
  static const _migratedFlagKey = 'hasMigratedDocumentParentsToLinks';

  /// Work-item types a resource/page's `parentId` might have pointed at
  /// before this migration.
  static const _workItemTypes = {
    TicketType.epic,
    TicketType.story,
    TicketType.task,
  };

  /// Performs the migration if it has not already run on this install.
  /// No-ops (and returns immediately) on a second call. Failures are
  /// logged and swallowed — this runs fire-and-forget at startup and must
  /// never block app launch or crash it.
  Future<void> migrateIfNeeded() async {
    if (_prefs.getBool(_migratedFlagKey) ?? false) return;

    try {
      final allTickets = await _ticketRepository.getAllTickets();
      final ticketsById = {for (final t in allTickets) t.id: t};

      for (final ticket in allTickets) {
        if (ticket.type != TicketType.resource &&
            ticket.type != TicketType.page) {
          continue;
        }
        final parentId = ticket.parentId;
        if (parentId == null) continue;
        final parent = ticketsById[parentId];
        if (parent == null || !_workItemTypes.contains(parent.type)) continue;

        await _linkRepository.createLink(
          sourceTicketId: ticket.id,
          targetTicketId: parentId,
          linkType: TicketLinkType.relatesTo,
        );
        await _ticketRepository.updateTicketParent(ticket.id, null);
      }

      await _prefs.setBool(_migratedFlagKey, true);
    } catch (_) {
      // Non-blocking by design — a failed migration is retried on the
      // next app start rather than surfaced as a startup error, matching
      // the focus-only/non-blocking pattern used elsewhere in the app's
      // background reconciliation services.
    }
  }
}
