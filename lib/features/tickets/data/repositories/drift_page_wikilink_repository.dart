// data/repositories/drift_page_wikilink_repository.dart — Drift implementation of PageWikilinkRepository (data layer).

import 'package:aion/core/core.dart';
import 'package:aion/features/tickets/domain/entities/page_wikilink.dart';
import 'package:aion/features/tickets/domain/repositories/page_wikilink_repository.dart';

/// Drift-backed implementation of [PageWikilinkRepository]. No business
/// logic here — maps [PageWikilinkData] rows to [PageWikilink] entities
/// and delegates every method straight to [PageWikilinkDao], matching
/// every other `Drift*Repository` in this codebase.
class DriftPageWikilinkRepository implements PageWikilinkRepository {
  /// Creates a [DriftPageWikilinkRepository] backed by [_db].
  DriftPageWikilinkRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<PageWikilink>> getIncomingLinks(String targetPageId) async {
    final rows = await _db.pageWikilinkDao.getIncomingLinks(targetPageId);
    return rows.map(_toEntity).toList();
  }

  @override
  Future<List<PageWikilink>> getOutgoingLinks(String sourcePageId) async {
    final rows = await _db.pageWikilinkDao.getOutgoingLinks(sourcePageId);
    return rows.map(_toEntity).toList();
  }

  @override
  Future<void> replaceOutgoingLinks(
    String sourcePageId,
    Set<String> targetPageIds,
  ) {
    return _db.pageWikilinkDao.replaceOutgoingLinks(sourcePageId, targetPageIds);
  }

  @override
  Future<void> deleteLinksForTickets(List<String> ticketIds) {
    return _db.pageWikilinkDao.deleteLinksForTickets(ticketIds);
  }

  /// Maps a raw [PageWikilinkData] row to its domain [PageWikilink] entity.
  PageWikilink _toEntity(PageWikilinkData row) => PageWikilink(
    id: row.id,
    sourcePageId: row.sourcePageId,
    targetPageId: row.targetPageId,
    createdAt: row.createdAt,
  );
}
