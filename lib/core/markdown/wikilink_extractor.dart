// core/markdown/wikilink_extractor.dart — WikilinkMatch + WikilinkExtractor pure parser (core layer).

/// One parsed `[[Target]]`/`[[Target|Alias]]` occurrence in a page's raw
/// Markdown content, as produced by [WikilinkExtractor.extractReferences].
class WikilinkMatch {
  /// Creates a [WikilinkMatch] carrying [raw]/[target]/[alias].
  const WikilinkMatch({required this.raw, required this.target, this.alias});

  /// The full matched text, brackets included (e.g. `[[Auth Notes]]` or
  /// `[[AIO-42|Auth]]`) — used to locate/replace this exact occurrence during
  /// [WikilinkExtractor.rewriteTitle].
  final String raw;

  /// The text before an optional `|`, trimmed — either a page/resource
  /// title or a `Ticket.ticketId` (see [WikilinkExtractor.looksLikeTicketId]).
  final String target;

  /// The text after an optional `|`, trimmed, verbatim, or `null` if this
  /// occurrence has no alias.
  final String? alias;
}

/// Pure parsing/rewriting helpers for `[[Target]]`/`[[Target|Alias]]` inline
/// wikilink references. No Flutter dependency — same precedent as
/// `TicketMarkdownSerializer`, so `bin/ticket_lint.dart`-style tooling could
/// reuse it if ever needed. Resolution itself (matching a
/// [WikilinkMatch.target] against live tickets) is deliberately not this
/// class's job — it has no database access — see `TicketsCubit`/
/// `PageWikilinkIndexer`/`PageTicketProviderImpl` for that. Per `AIO-963`'s
/// "Resolution model".
abstract final class WikilinkExtractor {
  /// Matches `[[Target]]` or `[[Target|Alias]]`. Neither `Target` nor
  /// `Alias` may itself contain `[`/`]`; `Target` additionally may not
  /// contain `|` (that character starts the optional alias segment).
  static final RegExp _pattern = RegExp(r'\[\[([^\[\]|]+)(?:\|([^\[\]]+))?\]\]');

  /// A `Ticket.ticketId`-shaped string: one or more uppercase letters, a
  /// hyphen, then one or more digits (e.g. `AIO-42`).
  static final RegExp _ticketIdPattern = RegExp(r'^[A-Z]+-[0-9]+$');

  /// Every distinct `[[Target]]`/`[[Target|Alias]]` occurrence in
  /// [content], each parsed into a [WikilinkMatch]. Deduplicated by
  /// `(target, alias)` pair, case-insensitively on `target` — the
  /// first-seen casing of a repeated target is preserved in the returned
  /// match, and later occurrences of the exact same `(target, alias)`
  /// pair are dropped rather than producing duplicate rows downstream.
  static List<WikilinkMatch> extractReferences(String content) {
    final seen = <String>{};
    final matches = <WikilinkMatch>[];
    for (final m in _pattern.allMatches(content)) {
      final target = m.group(1)!.trim();
      final aliasRaw = m.group(2);
      final alias = aliasRaw?.trim();
      if (target.isEmpty) continue;
      final dedupeKey = '${target.toLowerCase()}|${alias ?? ''}';
      if (!seen.add(dedupeKey)) continue;
      matches.add(WikilinkMatch(raw: m.group(0)!, target: target, alias: alias));
    }
    return matches;
  }

  /// Whether [target] looks like a `Ticket.ticketId` (e.g. `AIO-42`) — an
  /// uppercase-letter prefix, a hyphen, and a numeric suffix — rather than a
  /// title. A pure syntactic check; the caller still needs a real lookup to
  /// confirm a match actually exists.
  static bool looksLikeTicketId(String target) => _ticketIdPattern.hasMatch(target);

  /// Replaces every case-insensitive occurrence of `[[oldTitle...`
  /// (bare or aliased, i.e. `[[oldTitle]]` or `[[oldTitle|...]]`) in
  /// [content] with the equivalent using [newTitle] in place of
  /// [oldTitle]. Only touches occurrences whose **target** matches
  /// [oldTitle] as literal text — an id-anchored occurrence's target is
  /// never a title, so this can never touch one, even if its alias text
  /// happens to contain the old title. Pure string transform; returns
  /// [content] unchanged if no occurrence matches.
  static String rewriteTitle(String content, String oldTitle, String newTitle) {
    final oldLower = oldTitle.toLowerCase();
    return content.replaceAllMapped(_pattern, (m) {
      final target = m.group(1)!.trim();
      if (target.toLowerCase() != oldLower) return m.group(0)!;
      final alias = m.group(2);
      return alias == null ? '[[$newTitle]]' : '[[$newTitle|${alias.trim()}]]';
    });
  }
}
