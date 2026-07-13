// presentation/cubit/tickets_state.dart — TicketsState sealed hierarchy (presentation layer).

import 'package:equatable/equatable.dart';

import 'package:aion/features/tickets/domain/entities/ticket.dart';

/// The state emitted by [TicketsCubit].
sealed class TicketsState extends Equatable {
  const TicketsState();

  @override
  List<Object?> get props => [];
}

/// Before [TicketsCubit.loadTickets] or [TicketsCubit.getTicketById] has
/// been called. Nothing to render but an empty shell.
class TicketsInitial extends TicketsState {
  /// Creates a [TicketsInitial] state.
  const TicketsInitial();
}

/// A list or detail fetch is in flight. UI should show [AppSpinner].
class TicketsLoading extends TicketsState {
  /// Creates a [TicketsLoading] state.
  const TicketsLoading();
}

/// The ticket list loaded successfully. Carries the full list to render.
class TicketsLoaded extends TicketsState {
  /// Creates a [TicketsLoaded] state carrying [tickets].
  const TicketsLoaded(this.tickets);

  /// All tickets, most recently created first.
  final List<Ticket> tickets;

  @override
  List<Object?> get props => [tickets];
}

/// Categorizes a [TicketsError] so it can be localized at the widget layer
/// (via `ticketsErrorMessage` in `tickets_board_view.dart`) without
/// [TicketsCubit] needing a [BuildContext]. `null` on [TicketsError.reason]
/// means the error carries only a raw, unlocalized [TicketsError.message]
/// (e.g. a forwarded repository exception) — see [TicketsError].
enum TicketsErrorReason {
  /// The requested ticket does not exist.
  notFound,

  /// Deletion was blocked because the ticket has structural children.
  /// The widget layer reads [TicketsError.childCount] to build a
  /// count-aware message.
  hasChildren,
}

/// A list, detail, or create operation failed. Carries either a classified
/// [reason] — resolved to localized text at the widget layer — or a raw,
/// unlocalized [message] (e.g. a forwarded repository exception) when no
/// more specific reason applies. [reason] takes precedence over [message]
/// for display whenever it's non-null.
class TicketsError extends TicketsState {
  /// Creates a [TicketsError] state. Pass [reason] for a classified,
  /// localizable error; otherwise [message] is shown as-is. Pass
  /// [childCount] alongside [TicketsErrorReason.hasChildren] so the widget
  /// layer can build a count-aware message.
  const TicketsError(this.message, {this.reason, this.childCount});

  /// A raw, unlocalized description of what went wrong. Ignored in favor
  /// of [reason] when [reason] is non-null.
  final String message;

  /// A classified error reason, if this error corresponds to a known,
  /// localizable case. `null` for generic/forwarded exceptions.
  final TicketsErrorReason? reason;

  /// How many structural children blocked deletion. Only set when [reason]
  /// is [TicketsErrorReason.hasChildren]; `null` otherwise.
  final int? childCount;

  @override
  List<Object?> get props => [message, reason, childCount];
}

/// A [TicketsCubit.createTicket] call is in flight. Carries the
/// previously-loaded list so the list screen stays visible during creation.
class TicketCreating extends TicketsState {
  /// Creates a [TicketCreating] state carrying the in-flight [tickets] list.
  const TicketCreating(this.tickets);

  /// The list as it was before this creation started.
  final List<Ticket> tickets;

  @override
  List<Object?> get props => [tickets];
}

/// A ticket was created successfully. Carries the refreshed list (including
/// the new ticket) so the UI can navigate back and show it immediately.
class TicketCreated extends TicketsState {
  /// Creates a [TicketCreated] state carrying the refreshed [tickets] list.
  const TicketCreated(this.tickets);

  /// The full list, including the newly created ticket.
  final List<Ticket> tickets;

  @override
  List<Object?> get props => [tickets];
}

/// A [TicketsCubit.updateTicketStatus] call is in flight. Carries the
/// ticket list with the in-flight ticket's status already replaced
/// locally (optimistic), so a board drag/move reflects instantly instead
/// of waiting on the repository round trip.
class TicketStatusUpdating extends TicketsState {
  /// Creates a [TicketStatusUpdating] state carrying the optimistically
  /// updated [tickets] list.
  const TicketStatusUpdating(this.tickets);

  /// The list with the moved ticket's status already changed locally.
  final List<Ticket> tickets;

  @override
  List<Object?> get props => [tickets];
}

/// A ticket's status change persisted successfully. Carries the list
/// re-fetched from the repository, which supersedes the optimistic copy
/// carried by the preceding [TicketStatusUpdating] state.
class TicketStatusUpdated extends TicketsState {
  /// Creates a [TicketStatusUpdated] state carrying the refreshed
  /// [tickets] list.
  const TicketStatusUpdated(this.tickets);

  /// The full list, re-fetched after the status change persisted.
  final List<Ticket> tickets;

  @override
  List<Object?> get props => [tickets];
}

/// A single ticket's detail loaded successfully. Carries that ticket.
class TicketDetailLoaded extends TicketsState {
  /// Creates a [TicketDetailLoaded] state carrying [ticket].
  const TicketDetailLoaded(this.ticket);

  /// The loaded ticket.
  final Ticket ticket;

  @override
  List<Object?> get props => [ticket];
}

/// A [TicketsCubit.deleteTicket] call is in flight for the ticket
/// currently shown on [TicketDetailScreen].
class TicketDeleting extends TicketsState {
  /// Creates a [TicketDeleting] state.
  const TicketDeleting();
}

/// A ticket was deleted successfully. Carries no data — the UI responds
/// by navigating back to `/tickets`, where [TicketsCubit.loadTickets]
/// re-fetches the now-shorter list.
class TicketDeleted extends TicketsState {
  /// Creates a [TicketDeleted] state.
  const TicketDeleted();
}
