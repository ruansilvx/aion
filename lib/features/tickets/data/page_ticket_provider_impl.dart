// features/tickets/data/page_ticket_provider_impl.dart — PageTicketProviderImpl (data layer).

import 'package:aion/core/contracts/page_ticket_provider.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_link_repository.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_cubit.dart';

/// Drift/[TicketsCubit]-backed implementation of [PageTicketProvider].
/// Reads go straight to [TicketRepository]/[TicketLinkRepository] (no
/// business logic there per project.md's Cubit-vs-repository split);
/// writes delegate to [TicketsCubit] so page creation/edit/trash reuse
/// exactly the same validation/invariant logic every other ticket type's
/// screens already trigger — no duplicated write path. See
/// `aion-arch/changes/page-content-markdown-editor/design.md`.
class PageTicketProviderImpl implements PageTicketProvider {
  /// Creates a [PageTicketProviderImpl] backed by [_ticketsCubit] (writes)
  /// and [_ticketRepository]/[_ticketLinkRepository] (reads).
  const PageTicketProviderImpl(
    this._ticketsCubit,
    this._ticketRepository,
    this._ticketLinkRepository,
  );

  final TicketsCubit _ticketsCubit;
  final TicketRepository _ticketRepository;
  final TicketLinkRepository _ticketLinkRepository;

  @override
  Future<Ticket?> getPage(String id) async {
    final ticket = await _ticketRepository.getTicketById(id);
    if (ticket == null || ticket.type != TicketType.page) return null;
    return ticket;
  }

  @override
  Future<PageRelations> loadPageRelations(String pageId) async {
    final childDocs = await _ticketRepository.getTicketsByParent(
      pageId,
      types: const [TicketType.page, TicketType.resource],
    );

    final linkedTickets = <Ticket>[];
    final backlinks = <Ticket>[];
    final links = await _ticketLinkRepository.getLinksForTicket(pageId);
    for (final link in links) {
      final otherId = link.sourceTicketId == pageId
          ? link.targetTicketId
          : link.sourceTicketId;
      final other = await _ticketRepository.getTicketById(otherId);
      if (other == null) continue;
      if (other.type == TicketType.page || other.type == TicketType.resource) {
        backlinks.add(other);
      } else {
        linkedTickets.add(other);
      }
    }

    return PageRelations(
      childDocs: childDocs,
      linkedTickets: linkedTickets,
      backlinks: backlinks,
    );
  }

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
