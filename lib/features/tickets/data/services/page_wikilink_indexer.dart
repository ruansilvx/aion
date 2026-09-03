// data/services/page_wikilink_indexer.dart — PageWikilinkIndexer (data layer).

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:aion/core/markdown/wikilink_extractor.dart';
import 'package:aion/features/tickets/data/services/active_ticket_view_registry.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/repositories/page_wikilink_repository.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';

/// Shared inline-`[[wikilink]]` reindex/rename-cascade logic, used by both
/// `TicketsCubit.updateTicket` (in-app edits) and `TicketMarkdownReconciler`
/// (external file-edit reconciles) — the two content-change surfaces that can
/// change a `page` ticket's Markdown, so neither one duplicates this
/// extraction/resolution logic inline. Per `AIO-963`'s `TicketsCubit`
/// pseudocode, factored out to a shared seam per that change's `tasks.md` T14.
class PageWikilinkIndexer {
  /// Creates a [PageWikilinkIndexer] wired to [_repository] (candidate/
  /// referrer lookups), [_pageWikilinkRepository] (the index itself), and
  /// [_activeTicketViewRegistry] (desktop-only; `null` on mobile/web,
  /// where the rename-rewrite deferral this class performs simply never
  /// triggers — there is no separate file-watcher write path to race
  /// against on those platforms).
  PageWikilinkIndexer(
    this._repository,
    this._pageWikilinkRepository,
    this._activeTicketViewRegistry,
  );

  final TicketRepository _repository;
  final PageWikilinkRepository _pageWikilinkRepository;
  final ActiveTicketViewRegistry? _activeTicketViewRegistry;

  /// Re-parses [newTicket]'s content, resolves and persists its outgoing
  /// wikilinks, and — if its title changed from [oldTicket] — rewrites
  /// every title-anchored `[[...]]` occurrence in every page that links
  /// to it. [applyRewrittenReferrer] is how each call site actually
  /// persists a referrer's rewritten content: `TicketsCubit` recurses
  /// through its own `updateTicket` for the full content-edit side-effect
  /// chain (embedding regen, its own outgoing-link reindex);
  /// `TicketMarkdownReconciler` writes directly through
  /// [TicketRepository] plus its own embedding-regen trigger, since it
  /// has no cubit to recurse through. Swallows any failure (matching
  /// embedding regen's existing non-blocking, best-effort failure
  /// tolerance) so this call never rolls back the primary ticket update
  /// that triggered it — logged via [debugPrint] rather than left
  /// silently opaque.
  Future<void> reindexAndCascade({
    required Ticket oldTicket,
    required Ticket newTicket,
    required Future<void> Function(Ticket referrer, String rewrittenDescription)
    applyRewrittenReferrer,
  }) async {
    try {
      final candidates = await _repository.getAllTicketsByType([
        TicketType.page,
        TicketType.resource,
      ]);
      final matches = WikilinkExtractor.extractReferences(
        newTicket.description ?? '',
      );
      final resolvedIds = <String>{
        for (final match in matches)
          ?resolveWikilinkTarget(match.target, candidates),
      };
      await _pageWikilinkRepository.replaceOutgoingLinks(
        newTicket.id,
        resolvedIds,
      );

      if (oldTicket.title != newTicket.title) {
        // Only title-anchored occurrences can possibly need a rewrite —
        // an id-anchored one's target is never a title.
        final referrers = await _pageWikilinkRepository.getIncomingLinks(
          newTicket.id,
        );
        for (final link in referrers) {
          await _rewriteReferrerOrDefer(
            referrerId: link.sourcePageId,
            oldTitle: oldTicket.title,
            newTitle: newTicket.title,
            applyRewrittenReferrer: applyRewrittenReferrer,
          );
        }
      }
    } catch (e) {
      debugPrint('PageWikilinkIndexer.reindexAndCascade failed: $e');
    }
  }

  /// Resolves a wikilink [target] against [candidates] (every live
  /// page/resource ticket): an exact [Ticket.ticketId] match when
  /// [WikilinkExtractor.looksLikeTicketId] says [target] looks like one,
  /// otherwise a case-insensitive title match (first `createdAt` wins on
  /// a duplicate title). Returns `null` when nothing matches.
  static String? resolveWikilinkTarget(String target, List<Ticket> candidates) {
    if (WikilinkExtractor.looksLikeTicketId(target)) {
      for (final candidate in candidates) {
        if (candidate.ticketId == target) return candidate.id;
      }
      return null;
    }
    Ticket? best;
    final targetLower = target.toLowerCase();
    for (final candidate in candidates) {
      if (candidate.title.toLowerCase() != targetLower) continue;
      if (best == null || candidate.createdAt.isBefore(best.createdAt)) {
        best = candidate;
      }
    }
    return best?.id;
  }

  /// Rewrites [referrerId]'s title-anchored `[[oldTitle...` occurrences
  /// to [newTitle] via [applyRewrittenReferrer], or defers the rewrite
  /// (via a one-shot [ActiveTicketViewRegistry] listener) if the user
  /// currently has [referrerId] open — mirrors
  /// `TicketMarkdownReconciler`'s existing "re-attempt once the active id
  /// changes" pattern for the equivalent external-edit race. No-ops if
  /// [referrerId] no longer exists, or its content has no title-anchored
  /// occurrence to rewrite.
  Future<void> _rewriteReferrerOrDefer({
    required String referrerId,
    required String oldTitle,
    required String newTitle,
    required Future<void> Function(Ticket referrer, String rewrittenDescription)
    applyRewrittenReferrer,
  }) async {
    final referrer = await _repository.getTicketById(referrerId);
    if (referrer == null) return;
    final currentDescription = referrer.description ?? '';
    final rewritten = WikilinkExtractor.rewriteTitle(
      currentDescription,
      oldTitle,
      newTitle,
    );
    if (rewritten == currentDescription) return;

    // [ActiveTicketViewRegistry.activeTicketId] holds a ticket's
    // human-readable `ticketId` (e.g. `AIO-42`, matching
    // `TicketMarkdownReconciler`'s own use of the same registry) — not
    // [referrerId], which is [PageWikilink.sourcePageId]'s internal UUID.
    final registry = _activeTicketViewRegistry;
    if (registry != null &&
        registry.activeTicketId.value == referrer.ticketId) {
      late final VoidCallback listener;
      listener = () {
        if (registry.activeTicketId.value != referrer.ticketId) {
          registry.activeTicketId.removeListener(listener);
          unawaited(
            _rewriteReferrerOrDefer(
              referrerId: referrerId,
              oldTitle: oldTitle,
              newTitle: newTitle,
              applyRewrittenReferrer: applyRewrittenReferrer,
            ),
          );
        }
      };
      registry.activeTicketId.addListener(listener);
      return;
    }

    unawaited(applyRewrittenReferrer(referrer, rewritten));
  }
}
