// domain/enums/backlink_origin.dart — BacklinkOrigin enum (domain layer).

/// Where a `BacklinkRef` row was derived from.
enum BacklinkOrigin {
  /// An explicit `TicketLink` the user created between two docs.
  explicitLink,

  /// An inline `[[Title]]` reference discovered by parsing a page's
  /// Markdown content — see `PageWikilinkRepository`.
  wikilink,
}
