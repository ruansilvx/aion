// tickets.dart — Public-surface barrel for the tickets feature: domain
// entities/enums/exceptions/repository interfaces plus presentation
// cubits/states/screens/widgets. The data layer (DAOs, Drift table
// models, Drift*Repository implementations) is intentionally not
// exported — see flutter-conventions.md "Barrel files".

export 'domain/entities/ticket.dart';
export 'domain/entities/ticket_comment.dart';
export 'domain/entities/ticket_search_page.dart';
export 'domain/enums/comment_author_type.dart';
export 'domain/enums/ticket_link_type.dart';
export 'domain/enums/ticket_priority.dart';
export 'domain/enums/ticket_status.dart';
export 'domain/enums/ticket_sync_status.dart';
export 'domain/enums/ticket_type.dart';
export 'domain/repositories/comment_repository.dart';
export 'domain/repositories/ticket_link_repository.dart';
export 'domain/repositories/ticket_repository.dart';
export 'presentation/cubit/comments_cubit.dart';
export 'presentation/cubit/comments_state.dart';
export 'presentation/cubit/documentation_cubit.dart';
export 'presentation/cubit/documentation_state.dart';
export 'presentation/cubit/ticket_repair_cubit.dart';
export 'presentation/cubit/ticket_repair_state.dart';
export 'presentation/cubit/ticket_selection_cubit.dart';
export 'presentation/cubit/ticket_selection_state.dart';
export 'presentation/cubit/tickets_cubit.dart';
export 'presentation/cubit/tickets_state.dart';
export 'presentation/cubit/trash_cubit.dart';
export 'presentation/cubit/trash_state.dart';
export 'presentation/screens/create_ticket_screen.dart';
export 'presentation/screens/documentation_screen.dart';
export 'presentation/screens/ticket_detail_screen.dart';
export 'presentation/screens/tickets_board_view.dart';
export 'presentation/screens/tickets_list_screen.dart';
export 'presentation/screens/trash_screen.dart';
export 'presentation/widgets/documentation_tree_item.dart';
export 'presentation/widgets/ticket_needs_repair_banner.dart';
export 'presentation/widgets/ticket_overflow_menu.dart';
export 'presentation/widgets/ticket_selection_bar.dart';
export 'presentation/widgets/trashed_ticket_tile.dart';
