// core/contracts/page_ticket_provider.dart — PageTicketProvider abstract interface + PageRelations DTO (core layer).

import 'package:equatable/equatable.dart';

import 'package:aion/features/tickets/domain/entities/ticket.dart';

/// Cross-feature contract exposing the `page`-ticket data and mutations
/// `features/pages/` needs. Implemented by `PageTicketProviderImpl`
/// (`features/tickets/data/page_ticket_provider_impl.dart`) and provided
/// once per workspace, alongside `TicketsCubit`.
///
/// Per `project.md`'s Pattern 1 (dependency inversion via `core`),
/// `features/pages/` depends only on this interface — never on
/// `features/tickets/` directly. See
/// `aion-arch/changes/page-content-markdown-editor/design.md`.
abstract interface class PageTicketProvider {
  /// Fetches a single `page` ticket by id, or `null` if not found/not a page.
  Future<Ticket?> getPage(String id);

  /// Loads a page's sub-pages, linked tickets, and backlinks in one call —
  /// the same three collections `TicketsCubit.loadDocumentRelations`
  /// already computes for the shared `TicketDetailScreen`.
  Future<PageRelations> loadPageRelations(String pageId);

  /// Creates a new `page` ticket. Delegates to `TicketsCubit.createTicket`
  /// for the same validation/invariant logic every other creation path
  /// uses — no duplicated business logic in `features/pages/`.
  Future<Ticket> createPage({
    required String title,
    String? description,
    String? parentId,
  });

  /// Persists an edited `page` ticket (title/content/parent changes).
  /// Delegates to `TicketsCubit.updateTicket`.
  Future<Ticket> updatePage(Ticket page);

  /// Moves a `page` ticket to trash. Delegates to `TicketsCubit.trashTicket`.
  Future<void> trashPage(String id);

  /// Candidate parents for a page (self/descendants/type-incompatible
  /// candidates already excluded), for `PageCreateScreen`'s/
  /// `PageDetailScreen`'s parent picker.
  Future<List<Ticket>> getValidParentCandidatesForPage({String? excludeId});
}

/// A page's sub-pages, linked tickets, and backlinks — the same three
/// collections `TicketDetailScreen` already renders for `page` tickets,
/// carried across the `core/contracts/` boundary as plain domain entities.
class PageRelations extends Equatable {
  /// Creates a [PageRelations] carrying [childDocs]/[linkedTickets]/
  /// [backlinks].
  const PageRelations({
    required this.childDocs,
    required this.linkedTickets,
    required this.backlinks,
  });

  /// This page's direct `page`/`resource` children.
  final List<Ticket> childDocs;

  /// Board tickets (epic/story/task/chat) linked to this page via
  /// `TicketLink`.
  final List<Ticket> linkedTickets;

  /// Other `page`/`resource` tickets linked to this page via `TicketLink`.
  final List<Ticket> backlinks;

  @override
  List<Object?> get props => [childDocs, linkedTickets, backlinks];
}
