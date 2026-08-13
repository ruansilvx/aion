// data/models/page_wikilink_model.dart — Drift table definition for page_wikilinks (data layer).

import 'package:drift/drift.dart';

/// Drift table for resolved inline `[[wikilink]]` references between
/// tickets. Row type is generated as `PageWikilinkData`. No FK
/// constraints — integrity is enforced at the repository layer, matching
/// every other table in this schema.
@DataClassName('PageWikilinkData')
class PageWikilinksTable extends Table {
  @override
  String get tableName => 'page_wikilinks';

  /// Internal UUID v4 primary key.
  TextColumn get id => text()();

  /// The `page` ticket whose content contains the `[[...]]` reference.
  TextColumn get sourcePageId => text().named('source_page_id')();

  /// The `page`/`resource` ticket the reference resolved to.
  TextColumn get targetPageId => text().named('target_page_id')();

  /// When this row was (re)created — refreshed on every reindex, not
  /// preserved across a `PageWikilinkDao.replaceOutgoingLinks` call.
  DateTimeColumn get createdAt => dateTime().named('created_at')();

  @override
  Set<Column> get primaryKey => {id};
}
