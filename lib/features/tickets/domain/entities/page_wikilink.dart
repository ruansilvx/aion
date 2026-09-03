// domain/entities/page_wikilink.dart — PageWikilink entity (domain layer).

import 'package:equatable/equatable.dart';

/// One resolved `[[...]]` reference: [sourcePageId]'s content contains a
/// wikilink that resolved to the live ticket [targetPageId]. One row per
/// (source, target) pair — repeated occurrences of the same target within
/// one page's content collapse to a single row.
///
/// [sourcePageId] is always a `page` ticket's id — only pages produce
/// *outgoing* references (see `MarkdownEditor`'s authoring surface).
/// [targetPageId] may reference a `page` **or** `resource` ticket — see
/// `AIO-963`'s "Resource participation, widened".
class PageWikilink extends Equatable {
  /// Creates a [PageWikilink] row.
  const PageWikilink({
    required this.id,
    required this.sourcePageId,
    required this.targetPageId,
    required this.createdAt,
  });

  /// Internal UUID v4 primary key.
  final String id;

  /// The `page` ticket whose content contains the `[[...]]` reference.
  final String sourcePageId;

  /// The `page`/`resource` ticket the reference resolved to.
  final String targetPageId;

  /// When this row was (re)created — refreshed on every reindex, not
  /// preserved across a `PageWikilinkRepository.replaceOutgoingLinks` call.
  final DateTime createdAt;

  @override
  List<Object?> get props => [id, sourcePageId, targetPageId, createdAt];
}
