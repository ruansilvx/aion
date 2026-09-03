// domain/entities/ticket_list_sort.dart — TicketListSort entity (domain layer).

import 'package:equatable/equatable.dart';

import 'package:aion/features/tickets/domain/enums/ticket_sort_direction.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sort_field.dart';

/// The ticket list's single-active-key sort selection: exactly one
/// [field] with one [direction] — mirrors [TicketListFilters]' shape,
/// but a single value rather than a `Set` per field, since sort has no
/// multi-select/OR semantics. See
/// `AIO-2371`.
class TicketListSort extends Equatable {
  /// Creates a [TicketListSort] with [field] ordered by [direction].
  const TicketListSort({required this.field, required this.direction});

  /// The field currently being sorted by.
  final TicketSortField field;

  /// The direction [field] is sorted in. Ignored when [field] is
  /// [TicketSortField.relevance].
  final TicketSortDirection direction;

  @override
  List<Object?> get props => [field, direction];
}
