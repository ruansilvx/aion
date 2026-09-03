// features/tickets/data/page_ticket_provider_impl.dart — PageTicketProviderImpl (data layer).

import 'package:aion/core/contracts/page_ticket_provider.dart';
import 'package:aion/features/tickets/domain/entities/backlink_ref.dart';
import 'package:aion/features/tickets/domain/entities/gap_or_question_ref.dart';
import 'package:aion/features/tickets/domain/entities/linked_ticket_ref.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/backlink_origin.dart';
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/repositories/page_wikilink_repository.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_link_repository.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';
import 'package:aion/features/tickets/domain/utils/ticket_link_direction.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_cubit.dart';

/// Drift/[TicketsCubit]-backed implementation of [PageTicketProvider]. Reads
/// go straight to [TicketRepository]/[TicketLinkRepository]/
/// [PageWikilinkRepository] (no business logic there per project.md's
/// Cubit-vs-repository split); writes delegate to [TicketsCubit] so page
/// creation/edit/trash (and, per `AIO-2257`, link
/// [deleteLink]/[updateLinkType]) reuse exactly the same validation/ invariant
/// logic every other ticket type's screens already trigger — no duplicated
/// write path. See `AIO-1350`. [getPage] also accepts [TicketType.spec]
/// tickets (added for `AIO-1998`) — this is the one place that decides "is
/// this ticket a `PagesCubit`/`PageDetailScreen` document."
class PageTicketProviderImpl implements PageTicketProvider {
  /// Creates a [PageTicketProviderImpl] backed by [_ticketsCubit] (writes)
  /// and [_ticketRepository]/[_ticketLinkRepository]/
  /// [_pageWikilinkRepository] (reads).
  const PageTicketProviderImpl(
    this._ticketsCubit,
    this._ticketRepository,
    this._ticketLinkRepository,
    this._pageWikilinkRepository,
  );

  final TicketsCubit _ticketsCubit;
  final TicketRepository _ticketRepository;
  final TicketLinkRepository _ticketLinkRepository;
  final PageWikilinkRepository _pageWikilinkRepository;

  @override
  Future<Ticket?> getPage(String id) async {
    final ticket = await _ticketRepository.getTicketById(id);
    // Widened to also accept TicketType.spec for AIO-1998 — a spec ticket is
    // an ordinary editable document once created (see TicketType.spec's
    // dartdoc), reusing this exact same read/write path a `page` already has.
    if (ticket == null ||
        (ticket.type != TicketType.page && ticket.type != TicketType.spec)) {
      return null;
    }
    return ticket;
  }

  @override
  Future<PageRelations> loadPageRelations(String pageId) async {
    final childDocs = await _ticketRepository.getTicketsByParent(
      pageId,
      types: const [TicketType.page, TicketType.resource],
    );

    final linkedTickets = <LinkedTicketRef>[];
    final backlinks = <BacklinkRef>[];
    final links = await _ticketLinkRepository.getLinksForTicket(pageId);
    for (final link in links) {
      final otherId = link.sourceTicketId == pageId
          ? link.targetTicketId
          : link.sourceTicketId;
      final other = await _ticketRepository.getTicketById(otherId);
      if (other == null) continue;
      if (other.type == TicketType.page || other.type == TicketType.resource) {
        backlinks.add(
          BacklinkRef(ticket: other, origin: BacklinkOrigin.explicitLink),
        );
      } else {
        linkedTickets.add((
          ticket: other,
          relativeType: relativeLinkType(link, pageId),
          linkId: link.id,
        ));
      }
    }
    // `pageId` is always a `page` or `spec` ticket here (see [getPage]'s
    // type gate), so no `resource`-gating check is needed — unlike
    // `TicketsCubit.loadDocumentRelations`'s widened merge, which also
    // serves `resource` tickets via `TicketDetailScreen`.
    final incoming = await _pageWikilinkRepository.getIncomingLinks(pageId);
    for (final link in incoming) {
      final source = await _ticketRepository.getTicketById(link.sourcePageId);
      if (source == null) continue;
      backlinks.add(BacklinkRef(ticket: source, origin: BacklinkOrigin.wikilink));
    }

    final gapsAndOpenQuestions = <GapOrQuestionRef>[];
    final all = await _ticketRepository.getAllTickets();
    final byId = {for (final t in all) t.id: t};
    final subtreeIds = {pageId, ..._descendantIds(pageId, all)};
    final relatesToLinks = await _ticketLinkRepository.getLinksByTypes([
      TicketLinkType.relatesTo,
    ]);
    for (final link in relatesToLinks) {
      final source = byId[link.sourceTicketId];
      final target = byId[link.targetTicketId];
      if (source == null || target == null) continue;
      // The gap/question ticket is always the `relatesTo` link's
      // *source* — createGapOrQuestion/reclassifyIdea always create it
      // that way — so only that direction is checked. Mirrors
      // `TicketsCubit.loadDocumentRelations`'s identical aggregation.
      if ((source.type == TicketType.knownGap ||
              source.type == TicketType.openQuestion) &&
          subtreeIds.contains(target.id)) {
        gapsAndOpenQuestions.add((
          ticket: source,
          raisedOn: target,
          linkId: link.id,
        ));
      }
    }
    // Component Spec §2.4: directly-raised entries (raised on `pageId`
    // itself) sort before rolled-up ones (raised on a descendant), each
    // group ordered by descending `createdAt` of the gap/question ticket
    // itself. Mirrors `TicketsCubit.loadDocumentRelations`'s identical sort.
    gapsAndOpenQuestions.sort((a, b) {
      final aDirect = a.raisedOn.id == pageId;
      final bDirect = b.raisedOn.id == pageId;
      if (aDirect != bDirect) return aDirect ? -1 : 1;
      return b.ticket.createdAt.compareTo(a.ticket.createdAt);
    });

    return PageRelations(
      childDocs: childDocs,
      linkedTickets: linkedTickets,
      backlinks: backlinks,
      gapsAndOpenQuestions: gapsAndOpenQuestions,
    );
  }

  @override
  Future<bool> createGapOrQuestion(
    TicketType type, {
    required String title,
    String? description,
    required String targetTicketId,
  }) => _ticketsCubit.createGapOrQuestion(
    type,
    title: title,
    description: description,
    targetTicketId: targetTicketId,
  );

  @override
  Future<Ticket> createPage({
    required String title,
    String? description,
    String? parentId,
  }) {
    return _ticketsCubit.createTicket(
      type: TicketType.page,
      title: title,
      description: description,
      parentId: parentId,
    );
  }

  @override
  Future<Ticket> updatePage(Ticket page) => _ticketsCubit.updateTicket(page);

  @override
  Future<void> trashPage(String id) => _ticketsCubit.trashTicket(id);

  @override
  Future<List<Ticket>> getValidParentCandidatesForPage({
    String? excludeId,
  }) async {
    final all = await _ticketRepository.getAllTickets();
    final descendantIds = excludeId != null
        ? _descendantIds(excludeId, all)
        : const <String>{};
    return all
        .where(
          (t) =>
              t.type == TicketType.page &&
              t.id != excludeId &&
              !descendantIds.contains(t.id),
        )
        .toList();
  }

  @override
  Future<void> deleteLink(String pageId, String linkId) =>
      _ticketsCubit.deleteTicketLink(pageId, linkId);

  @override
  Future<void> updateLinkType(
    String pageId,
    String linkId,
    TicketLinkType newRelativeType,
  ) => _ticketsCubit.updateTicketLinkType(pageId, linkId, newRelativeType);

  @override
  Future<List<Ticket>> getWikilinkCandidates() {
    return _ticketRepository.getAllTicketsByType([
      TicketType.page,
      TicketType.resource,
    ]);
  }

  /// Builds the full descendant-id set of [rootId] by walking `parentId`
  /// forward through [all] — same cycle definition as
  /// [TicketsCubit.getValidParentCandidates].
  Set<String> _descendantIds(String rootId, List<Ticket> all) {
    final childrenByParent = <String, List<Ticket>>{};
    for (final t in all) {
      final p = t.parentId;
      if (p != null) {
        childrenByParent.putIfAbsent(p, () => []).add(t);
      }
    }
    final result = <String>{};
    void walk(String id) {
      for (final child in childrenByParent[id] ?? const []) {
        if (result.add(child.id)) walk(child.id);
      }
    }

    walk(rootId);
    return result;
  }
}
