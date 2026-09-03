// core/contracts/page_ticket_provider.dart — PageTicketProvider abstract interface + PageRelations DTO (core layer).

import 'package:equatable/equatable.dart';

import 'package:aion/features/tickets/domain/entities/backlink_ref.dart';
import 'package:aion/features/tickets/domain/entities/gap_or_question_ref.dart';
import 'package:aion/features/tickets/domain/entities/linked_ticket_ref.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

/// Cross-feature contract exposing the `page`-ticket data and mutations
/// `features/pages/` needs. Implemented by `PageTicketProviderImpl`
/// (`features/tickets/data/page_ticket_provider_impl.dart`) and provided
/// once per workspace, alongside `TicketsCubit`.
///
/// Per `project.md`'s Pattern 1 (dependency inversion via `core`),
/// `features/pages/` depends only on this interface — never on
/// `features/tickets/` directly. See `AIO-1350`.
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

  /// Deletes the `TicketLink` row with id [linkId], then refreshes
  /// [pageId]'s relations. Implemented by delegating to
  /// `TicketsCubit.deleteTicketLink` for the same write/refresh logic
  /// every other link mutation uses.
  Future<void> deleteLink(String pageId, String linkId);

  /// Updates the `TicketLink` row with id [linkId]'s stored type to
  /// [newRelativeType] — the type as picked in `LinkedTicketsSection`'s
  /// `_LinkTypeEditor`, i.e. as it reads from [pageId]'s own side, not
  /// the row's raw source-to-target reading. The relative-to-canonical
  /// translation (`ticket_link_direction.dart`'s `toCanonical`) happens
  /// inside `TicketsCubit.updateTicketLinkType` itself, which this
  /// method delegates to — that translation needs the row's actual
  /// source/target ids, data this call site doesn't otherwise carry.
  Future<void> updateLinkType(
    String pageId,
    String linkId,
    TicketLinkType newRelativeType,
  );

  /// Creates a [type] (`knownGap`/`openQuestion` only) ticket titled [title]
  /// with optional [description], linked to [targetTicketId] — delegates to
  /// `TicketsCubit.createGapOrQuestion` for the same hard-rule
  /// validation/atomic-creation logic every other creation path uses. Returns
  /// `true` on success, `false` if rejected/failed — the creation popover's
  /// caller awaits this to decide whether to close or show its inline error
  /// state. Added for `AIO-934`.
  Future<bool> createGapOrQuestion(
    TicketType type, {
    required String title,
    String? description,
    required String targetTicketId,
  });

  /// Every live `page`/`resource` ticket, for wikilink-autocomplete/
  /// resolution — widened beyond `page`-only since a wikilink can now target a
  /// resource too (see design.md's "Resource participation, widened"). No
  /// self/descendant exclusion — unlike parent-candidate queries, a wikilink
  /// reference has no cycle constraint. Added for `AIO-963`.
  Future<List<Ticket>> getWikilinkCandidates();
}

/// A page's sub-pages, linked tickets, and backlinks — the same three
/// collections `TicketDetailScreen` already renders for `page` tickets,
/// carried across the `core/contracts/` boundary as plain domain entities.
class PageRelations extends Equatable {
  /// Creates a [PageRelations] carrying [childDocs]/[linkedTickets]/
  /// [backlinks]/[gapsAndOpenQuestions].
  const PageRelations({
    required this.childDocs,
    required this.linkedTickets,
    required this.backlinks,
    this.gapsAndOpenQuestions = const [],
  });

  /// This page's direct `page`/`resource` children.
  final List<Ticket> childDocs;

  /// Board tickets (epic/story/task/chat) linked to this page via
  /// `TicketLink`. Each entry pairs the other-side [Ticket] with the
  /// link's type as it reads from this page's own side and the
  /// underlying link row's id — see [LinkedTicketRef].
  final List<LinkedTicketRef> linkedTickets;

  /// Other `page`/`resource` tickets that reference this page, either via an
  /// explicit `TicketLink` or an inline `[[wikilink]]` — see
  /// [BacklinkRef.origin]. Was `List<LinkedTicketRef>` (`TicketLink`-only)
  /// before `AIO-963`.
  final List<BacklinkRef> backlinks;

  /// Every `knownGap`/`openQuestion` ticket `relatesTo`-linked to this page
  /// itself or to any descendant of it, recursively rolled up — see
  /// [GapOrQuestionRef]. Mirrors `TicketsCubit.loadDocumentRelations`'s same
  /// aggregation for the shared `TicketDetailScreen`. Added for `AIO-934`.
  final List<GapOrQuestionRef> gapsAndOpenQuestions;

  @override
  List<Object?> get props => [
    childDocs,
    linkedTickets,
    backlinks,
    gapsAndOpenQuestions,
  ];
}
