// domain/entities/backlink_ref.dart — BacklinkRef entity (domain layer).

import 'package:equatable/equatable.dart';

import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/backlink_origin.dart';

/// One row in a doc's Backlinks section: another ticket that references
/// this one, either via an explicit `TicketLink` or an inline
/// `[[wikilink]]`. Replaces the bare `List<Ticket>`/`List<LinkedTicketRef>`
/// `BacklinksSection` previously took — a link's origin never survived
/// past `TicketsCubit.loadDocumentRelations`/`PageTicketProviderImpl
/// .loadPageRelations` before this, so nothing could render it
/// differently. Per
/// `aion-arch/changes/inline-wikilink-backlinks/design.md`.
class BacklinkRef extends Equatable {
  /// Creates a [BacklinkRef] pairing [ticket] with how it was discovered
  /// ([origin]).
  const BacklinkRef({required this.ticket, required this.origin});

  /// The other-side ticket that references the doc this row belongs to.
  final Ticket ticket;

  /// Whether this row was authored explicitly or discovered from content.
  final BacklinkOrigin origin;

  @override
  List<Object?> get props => [ticket, origin];
}
