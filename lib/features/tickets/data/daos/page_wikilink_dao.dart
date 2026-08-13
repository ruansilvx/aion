// data/daos/page_wikilink_dao.dart — PageWikilinkDao Drift accessor (data layer).

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/tickets/data/models/page_wikilink_model.dart';

part 'page_wikilink_dao.g.dart';

/// Drift accessor for [PageWikilinksTable].
@DriftAccessor(tables: [PageWikilinksTable])
class PageWikilinkDao extends DatabaseAccessor<AppDatabase>
    with _$PageWikilinkDaoMixin {
  /// Creates a [PageWikilinkDao] bound to [db].
  PageWikilinkDao(super.db);

  static const _uuid = Uuid();

  /// Returns every row whose [PageWikilinkData.targetPageId] is
  /// [targetPageId] — the raw rows behind a doc's wikilink-origin
  /// backlinks.
  Future<List<PageWikilinkData>> getIncomingLinks(String targetPageId) {
    return (select(
      pageWikilinksTable,
    )..where((t) => t.targetPageId.equals(targetPageId))).get();
  }

  /// Returns every row whose [PageWikilinkData.sourcePageId] is
  /// [sourcePageId] — the ids [sourcePageId] currently links to.
  Future<List<PageWikilinkData>> getOutgoingLinks(String sourcePageId) {
    return (select(
      pageWikilinksTable,
    )..where((t) => t.sourcePageId.equals(sourcePageId))).get();
  }

  /// Atomically replaces every outgoing row for [sourcePageId]: deletes
  /// the existing set, then batch-inserts one fresh row per
  /// [targetPageIds] member. Wrapped in a transaction so a caller never
  /// observes a partially-cleared outgoing set. An empty [targetPageIds]
  /// simply clears every existing row.
  Future<void> replaceOutgoingLinks(
    String sourcePageId,
    Set<String> targetPageIds,
  ) {
    return transaction<void>(() async {
      await (delete(
        pageWikilinksTable,
      )..where((t) => t.sourcePageId.equals(sourcePageId))).go();
      if (targetPageIds.isEmpty) return;
      final now = DateTime.now();
      await batch((b) {
        b.insertAll(pageWikilinksTable, [
          for (final targetId in targetPageIds)
            PageWikilinksTableCompanion.insert(
              id: _uuid.v4(),
              sourcePageId: sourcePageId,
              targetPageId: targetId,
              createdAt: now,
            ),
        ]);
      });
    });
  }

  /// Deletes every row where [PageWikilinkData.sourcePageId] or
  /// [PageWikilinkData.targetPageId] is any id in [ticketIds]. Used by
  /// permanent ticket deletion, mirroring
  /// `TicketLinkDao.deleteLinksForTickets`'s shape.
  Future<void> deleteLinksForTickets(List<String> ticketIds) {
    return (delete(pageWikilinksTable)..where(
          (t) =>
              t.sourcePageId.isIn(ticketIds) | t.targetPageId.isIn(ticketIds),
        ))
        .go();
  }
}
