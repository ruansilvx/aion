// domain/entities/ticket_search_page.dart — TicketSearchPage entity (domain layer).

import 'package:equatable/equatable.dart';

import 'package:aion/features/tickets/domain/entities/ticket.dart';

/// One page of results from [TicketRepository.searchTickets].
class TicketSearchPage extends Equatable {
  /// Creates a [TicketSearchPage] carrying [tickets] and [hasMore].
  const TicketSearchPage({required this.tickets, required this.hasMore});

  /// The tickets returned for this page, in the same order the query
  /// specified (creation date descending, or FTS relevance when a text
  /// query was set).
  final List<Ticket> tickets;

  /// Whether at least one more ticket exists beyond [tickets] for the same
  /// query/filters — `true` means a subsequent page (a call with a larger
  /// `offset`) would return further results.
  final bool hasMore;

  @override
  List<Object?> get props => [tickets, hasMore];
}
