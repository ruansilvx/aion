// presentation/cubit/documentation_state.dart — DocumentationState sealed hierarchy (presentation layer).

import 'package:equatable/equatable.dart';

import 'package:aion/features/tickets/domain/entities/ticket.dart';

/// The state emitted by [DocumentationCubit].
sealed class DocumentationState extends Equatable {
  const DocumentationState();

  @override
  List<Object?> get props => [];
}

/// Before [DocumentationCubit.load] has been called. Nothing to render but
/// an empty shell.
class DocumentationInitial extends DocumentationState {
  /// Creates a [DocumentationInitial] state.
  const DocumentationInitial();
}

/// A [DocumentationCubit.load]/[DocumentationCubit.search] call is in
/// flight and nothing is on screen yet. UI should show [AppSpinner].
class DocumentationLoading extends DocumentationState {
  /// Creates a [DocumentationLoading] state.
  const DocumentationLoading();
}

/// The Documentation tree (and, optionally, an active search) loaded
/// successfully.
class DocumentationLoaded extends DocumentationState {
  /// Creates a [DocumentationLoaded] state carrying [rootDocs],
  /// [childrenByParentId], and the optional [searchResults].
  const DocumentationLoaded({
    required this.rootDocs,
    required this.childrenByParentId,
    required this.expandedIds,
    this.searchResults,
  });

  /// Every root-level (no `parentId`) `page`/`resource` ticket.
  final List<Ticket> rootDocs;

  /// Lazily-loaded children, keyed by parent `page` id, populated as
  /// [DocumentationCubit.loadChildren] resolves for each expanded node.
  /// Only `page` ids are ever keys — resources never have children.
  final Map<String, List<Ticket>> childrenByParentId;

  /// Ids of `page` nodes the user has expanded — drives which cached
  /// [childrenByParentId] entries the tree renders under each row.
  final Set<String> expandedIds;

  /// The current search results, ranked by
  /// [TicketDocumentSearchService.search], or `null` when no search is
  /// active (tree mode).
  final List<Ticket>? searchResults;

  @override
  List<Object?> get props => [
    rootDocs,
    childrenByParentId,
    expandedIds,
    searchResults,
  ];
}

/// A [DocumentationCubit.load]/[loadChildren]/[search] call failed.
class DocumentationError extends DocumentationState {
  /// Creates a [DocumentationError] state carrying [message].
  const DocumentationError(this.message);

  /// A raw, unlocalized description of what went wrong.
  final String message;

  @override
  List<Object?> get props => [message];
}
