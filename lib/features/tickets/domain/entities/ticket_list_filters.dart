// domain/entities/ticket_list_filters.dart — TicketListFilters entity (domain layer).

import 'package:equatable/equatable.dart';

import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

/// The multi-select filter selection for the ticket list, one `Set` per
/// field. Values within a field combine as OR (`todo` or `backlog`
/// matches either); the three fields combine with each other as AND —
/// mirrors the semantics of
/// [TicketRepository.searchTickets](../repositories/ticket_repository.dart).
/// An empty set for a field means "no constraint on that field", not
/// "match nothing".
class TicketListFilters extends Equatable {
  /// Creates a [TicketListFilters]. Each field defaults to an empty set,
  /// meaning no constraint on that field.
  const TicketListFilters({
    this.statuses = const {},
    this.types = const {},
    this.priorities = const {},
  });

  /// The selected project-defined status names. Empty means no status
  /// constraint. Was `Set<TicketStatus>` before
  /// `AIO-549`.
  final Set<String> statuses;

  /// The selected [TicketType] values. Empty means no type constraint.
  final Set<TicketType> types;

  /// The selected [TicketPriority] values. Empty means no priority
  /// constraint.
  final Set<TicketPriority> priorities;

  @override
  List<Object?> get props => [statuses, types, priorities];
}
