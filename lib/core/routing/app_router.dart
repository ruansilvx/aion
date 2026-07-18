// core/routing/app_router.dart — go_router configuration (core layer).

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:aion/core/database/app_database.dart';
import 'package:aion/features/projects/projects.dart';
import 'package:aion/features/tickets/data/repositories/drift_comment_repository.dart';
import 'package:aion/features/tickets/data/repositories/drift_ticket_link_repository.dart';
import 'package:aion/features/tickets/data/repositories/drift_ticket_repository.dart';
import 'package:aion/features/tickets/tickets.dart';

/// The app's route table: `/hub`, `/hub/new` (project switcher, no
/// active project needed), and `/workspace/tickets`,
/// `/workspace/tickets/new`, `/workspace/tickets/trash`,
/// `/workspace/tickets/:id` (gated on an active project — see
/// [_redirect]). See
/// `aion-arch/changes/multi-project-hub/design.md` §9.
///
/// Clean (path-based, no `#`) URLs are go_router's default. Deploying the
/// web build to Firebase Hosting requires a catch-all rewrite rule
/// (`"source": "**"`, `"destination": "/index.html"`) in firebase.json so
/// deep links and manual URL entry resolve to the Flutter app instead of a
/// 404 — see openspec/project.md "Web URL Strategy".
final appRouter = GoRouter(
  initialLocation: '/hub',
  redirect: _redirect,
  routes: [
    GoRoute(
      path: '/hub',
      builder: (context, state) => BlocProvider<ProjectHubCubit>(
        create: (context) => ProjectHubCubit(context.read<ProjectRepository>()),
        child: HubScreen(
          onOpenProject: (project) => _openProject(context, project),
          onNewProject: () => context.go('/hub/new'),
        ),
      ),
    ),
    GoRoute(
      path: '/hub/new',
      builder: (context, state) => BlocProvider<CreateProjectCubit>(
        create: (context) => CreateProjectCubit(
          context.read<ProjectRepository>(),
          context.read<BaselineRepository>(),
        ),
        child: NewProjectScreen(
          onBack: () => context.go('/hub'),
          onCreated: (project) => _openProject(context, project),
        ),
      ),
    ),
    ShellRoute(
      builder: (context, state, child) {
        final activeState = context.watch<ActiveProjectCubit>().state;
        return switch (activeState) {
          ActiveProjectOpen(:final project) => WorkspaceShell(
            key: ValueKey(project.id),
            project: project,
            child: child,
          ),
          _ => const SizedBox.shrink(),
        };
      },
      routes: [
        GoRoute(
          path: '/workspace/tickets',
          builder: (context, state) => BlocProvider<TicketSelectionCubit>(
            create: (_) => TicketSelectionCubit(),
            child: const TicketsListScreen(),
          ),
        ),
        GoRoute(
          path: '/workspace/tickets/new',
          builder: (context, state) => const CreateTicketScreen(),
        ),
        // Registered before `/workspace/tickets/:id` — go_router matches
        // path segments in declaration order, and `:id` would otherwise
        // greedily match the literal `trash` segment.
        GoRoute(
          path: '/workspace/tickets/trash',
          builder: (context, state) => BlocProvider<TrashCubit>(
            create: (context) =>
                TrashCubit(context.read<TicketRepository>())..load(),
            child: const TrashScreen(),
          ),
        ),
        GoRoute(
          path: '/workspace/tickets/:id',
          builder: (context, state) {
            final id = state.pathParameters['id']!;
            return BlocProvider<CommentsCubit>(
              create: (context) =>
                  CommentsCubit(context.read<CommentRepository>()),
              child: TicketDetailScreen(ticketId: id),
            );
          },
        ),
      ],
    ),
  ],
);

/// If no project is active and the requested location is under
/// `/workspace`, redirect to `/hub` — a project must be opened first.
/// `/` redirects to `/hub`, the app's initial route. Visiting `/hub`
/// while a project is already active is explicitly allowed (the user
/// deliberately navigated back to switch projects) — it does not
/// force-redirect into `/workspace`.
String? _redirect(BuildContext context, GoRouterState state) {
  if (state.uri.path == '/') return '/hub';

  final activeState = context.read<ActiveProjectCubit>().state;
  final isWorkspaceRoute = state.uri.path.startsWith('/workspace');
  if (isWorkspaceRoute && activeState is! ActiveProjectOpen) {
    return '/hub';
  }
  return null;
}

/// Switches the active project via [ActiveProjectCubit.switchTo], then
/// navigates into the workspace once the switch completes.
Future<void> _openProject(BuildContext context, Project project) async {
  await context.read<ActiveProjectCubit>().switchTo(project);
  if (context.mounted) context.go('/workspace/tickets');
}

/// Permanently purges trashed tickets older than
/// [TrashCubit.purgeAgeThreshold] every time a project's workspace opens
/// (called from [WorkspaceShell.initState]), so trash is cleaned up even
/// for users who never visit the Trash screen's manual "Purge old"
/// action. Fire-and-forget: callers do not await this, so it never
/// delays the workspace's first paint. Failures are swallowed — a
/// missed purge has no user-visible consequence and simply gets another
/// chance the next time this project is opened.
Future<void> _purgeOldTrashOnOpen(AppDatabase database) async {
  try {
    await DriftTicketRepository(
      database,
    ).purgeTrashOlderThan(TrashCubit.purgeAgeThreshold);
  } catch (_) {
    // Best-effort housekeeping — no user-facing surface for failures,
    // and this codebase has no logging infrastructure to report into.
  }
}

/// Owns the per-project [AppDatabase] connection and the ticket-feature
/// repositories/cubit built on top of it. Constructed with
/// `key: ValueKey(project.id)` in [appRouter]'s `ShellRoute`, so Flutter
/// disposes the old instance (closing its [AppDatabase]) and builds a
/// fresh one — opening a new [AppDatabase] addressed to the newly active
/// project — whenever the active project's id changes, per
/// `aion-arch/changes/multi-project-hub/design.md` §6.
class WorkspaceShell extends StatefulWidget {
  /// Creates a [WorkspaceShell] for [project], wrapping [child] (the
  /// current `/workspace/*` route's content).
  const WorkspaceShell({super.key, required this.project, required this.child});

  /// The active project this shell's [AppDatabase] is addressed to.
  final Project project;

  /// The current `/workspace/*` route's content.
  final Widget child;

  @override
  State<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends State<WorkspaceShell> {
  late final AppDatabase _database = AppDatabase(widget.project);

  @override
  void initState() {
    super.initState();
    unawaited(_purgeOldTrashOnOpen(_database));
  }

  @override
  void dispose() {
    unawaited(_database.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<TicketRepository>(
          create: (_) => DriftTicketRepository(_database),
        ),
        RepositoryProvider<CommentRepository>(
          create: (_) => DriftCommentRepository(_database),
        ),
        RepositoryProvider<TicketLinkRepository>(
          create: (_) => DriftTicketLinkRepository(_database),
        ),
      ],
      child: BlocProvider<TicketsCubit>(
        create: (context) => TicketsCubit(context.read<TicketRepository>()),
        child: widget.child,
      ),
    );
  }
}
