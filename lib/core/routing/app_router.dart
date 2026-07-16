// core/routing/app_router.dart — go_router configuration (core layer).

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:aion/features/tickets/tickets.dart';

/// The app's route table: `/tickets`, `/tickets/new`, `/tickets/trash`,
/// `/tickets/:id`.
///
/// Clean (path-based, no `#`) URLs are go_router's default. Deploying the
/// web build to Firebase Hosting requires a catch-all rewrite rule
/// (`"source": "**"`, `"destination": "/index.html"`) in firebase.json so
/// deep links and manual URL entry resolve to the Flutter app instead of a
/// 404 — see openspec/project.md "Web URL Strategy".
final appRouter = GoRouter(
  initialLocation: '/tickets',
  redirect: (context, state) {
    if (state.uri.path == '/') return '/tickets';
    return null;
  },
  routes: [
    GoRoute(
      path: '/tickets',
      builder: (context, state) => BlocProvider<TicketSelectionCubit>(
        create: (_) => TicketSelectionCubit(),
        child: const TicketsListScreen(),
      ),
    ),
    GoRoute(
      path: '/tickets/new',
      builder: (context, state) => const CreateTicketScreen(),
    ),
    // Registered before `/tickets/:id` — go_router matches path segments
    // in declaration order, and `:id` would otherwise greedily match the
    // literal `trash` segment.
    GoRoute(
      path: '/tickets/trash',
      builder: (context, state) => BlocProvider<TrashCubit>(
        create: (context) =>
            TrashCubit(context.read<TicketRepository>())..load(),
        child: const TrashScreen(),
      ),
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
