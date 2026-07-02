import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:aion/features/tickets/domain/repositories/comment_repository.dart';
import 'package:aion/features/tickets/presentation/cubit/comments_cubit.dart';
import 'package:aion/features/tickets/presentation/screens/create_ticket_screen.dart';
import 'package:aion/features/tickets/presentation/screens/ticket_detail_screen.dart';
import 'package:aion/features/tickets/presentation/screens/tickets_list_screen.dart';

// Clean (path-based, no `#`) URLs are go_router's default. Deploying the web
// build to Firebase Hosting requires a catch-all rewrite rule
// (`"source": "**"`, `"destination": "/index.html"`) in firebase.json so
// deep links and manual URL entry resolve to the Flutter app instead of a
// 404 — see openspec/project.md "Web URL Strategy".
final appRouter = GoRouter(
  initialLocation: '/tickets',
  redirect: (context, state) {
    if (state.uri.path == '/') return '/tickets';
    return null;
  },
  routes: [
    GoRoute(
      path: '/tickets',
      builder: (context, state) => const TicketsListScreen(),
    ),
    GoRoute(
      path: '/tickets/new',
      builder: (context, state) => const CreateTicketScreen(),
    ),
    GoRoute(
      path: '/tickets/:id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return BlocProvider<CommentsCubit>(
          create: (context) => CommentsCubit(context.read<CommentRepository>()),
          child: TicketDetailScreen(ticketId: id),
        );
      },
    ),
  ],
);
