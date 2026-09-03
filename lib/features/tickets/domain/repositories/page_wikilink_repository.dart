// domain/repositories/page_wikilink_repository.dart — PageWikilinkRepository interface (domain layer).

import 'package:aion/features/tickets/domain/entities/page_wikilink.dart';

/// Persists resolved inline `[[wikilink]]` references between tickets.
/// Parallel to `TicketLinkRepository`, not built on it — a wikilink is
/// derived from content, never user-authored, so it has no remove/retype
/// affordance and no link type. Per
/// `AIO-963`.
abstract interface class PageWikilinkRepository {
  /// Every page that links to [targetPageId] — the raw rows behind a
  /// doc's wikilink-origin backlinks. [targetPageId] may be a `page` or a
  /// `resource` ticket's id, now that wikilink targets are widened beyond
  /// `page`-only (see design.md's "Resource participation, widened") —
  /// only pages ever appear as [PageWikilink.sourcePageId] though, since
  /// only pages produce outgoing references.
  Future<List<PageWikilink>> getIncomingLinks(String targetPageId);

  /// Every page [sourcePageId] currently links to — each id may be a
  /// `page` or a `resource` ticket.
  Future<List<PageWikilink>> getOutgoingLinks(String sourcePageId);

  /// Atomically replaces every outgoing row for [sourcePageId] with one
  /// row per id in [targetPageIds] (each a `page` or `resource` ticket
  /// id). The sole write path — called after every `page` save with the
  /// freshly re-parsed, freshly resolved set. An empty [targetPageIds]
  /// clears all of [sourcePageId]'s outgoing rows, correctly reflecting a
  /// page that removed its last reference.
  Future<void> replaceOutgoingLinks(String sourcePageId, Set<String> targetPageIds);

  /// Batch cleanup for permanent delete — removes every row where any id
  /// in [ticketIds] is source or target. Mirrors
  /// `TicketLinkRepository.deleteLinksForTickets`'s shape.
  Future<void> deleteLinksForTickets(List<String> ticketIds);
}
