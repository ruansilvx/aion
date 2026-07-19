// features/pages/presentation/cubit/pages_state.dart — PagesState sealed hierarchy (presentation layer).

import 'package:equatable/equatable.dart';

import 'package:aion/core/contracts/page_ticket_provider.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';

/// The state emitted by `PagesCubit`.
sealed class PagesState extends Equatable {
  const PagesState();

  @override
  List<Object?> get props => [];
}

/// Before any `PagesCubit` method has been called.
class PagesInitial extends PagesState {
  /// Creates a [PagesInitial] state.
  const PagesInitial();
}

/// A load/create/update/trash call is in flight.
class PagesLoading extends PagesState {
  /// Creates a [PagesLoading] state.
  const PagesLoading();
}

/// A page's detail view loaded successfully: the ticket plus its
/// sub-pages/linked-tickets/backlinks.
class PageDetailLoaded extends PagesState {
  /// Creates a [PageDetailLoaded] state carrying [page] and [relations].
  const PageDetailLoaded(this.page, this.relations);

  /// The loaded `page` ticket.
  final Ticket page;

  /// [page]'s sub-pages, linked tickets, and backlinks.
  final PageRelations relations;

  @override
  List<Object?> get props => [page, relations];
}

/// A new page was created successfully. Carries the created ticket so the
/// screen can navigate straight into its detail view.
class PageCreated extends PagesState {
  /// Creates a [PageCreated] state carrying the created [page].
  const PageCreated(this.page);

  /// The newly created `page` ticket.
  final Ticket page;

  @override
  List<Object?> get props => [page];
}

/// A page was moved to trash successfully.
class PageTrashed extends PagesState {
  /// Creates a [PageTrashed] state.
  const PageTrashed();
}

/// A `PagesCubit` operation failed. Carries a raw, unlocalized [message]
/// describing what went wrong.
class PagesError extends PagesState {
  /// Creates a [PagesError] state carrying [message].
  const PagesError(this.message);

  /// A raw, unlocalized description of what went wrong.
  final String message;

  @override
  List<Object?> get props => [message];
}
