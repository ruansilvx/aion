// tickets.dart — Public-surface barrel for the tickets feature: domain
// entities/enums/exceptions/repository interfaces plus presentation
// cubits/states/screens/widgets. The data layer (DAOs, Drift table
// models, Drift*Repository implementations) is intentionally not
// exported — see flutter-conventions.md "Barrel files".

export 'domain/entities/ticket.dart';
export 'domain/entities/ticket_comment.dart';
export 'domain/enums/comment_author_type.dart';
export 'domain/enums/ticket_link_type.dart';
export 'domain/enums/ticket_priority.dart';
export 'domain/enums/ticket_status.dart';
export 'domain/enums/ticket_type.dart';
export 'domain/exceptions/ticket_has_children_exception.dart';
export 'domain/repositories/comment_repository.dart';
export 'domain/repositories/ticket_link_repository.dart';
export 'domain/repositories/ticket_repository.dart';
export 'presentation/cubit/comments_cubit.dart';
export 'presentation/cubit/comments_state.dart';
export 'presentation/cubit/tickets_cubit.dart';
export 'presentation/cubit/tickets_state.dart';
export 'presentation/screens/create_ticket_screen.dart';
export 'presentation/screens/ticket_detail_screen.dart';
export 'presentation/screens/tickets_board_view.dart';
export 'presentation/screens/tickets_list_screen.dart';
export 'presentation/widgets/inline_editable_field.dart';
export 'presentation/widgets/ticket_overflow_menu.dart';
