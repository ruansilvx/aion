// core/routing/app_router.dart — go_router configuration (core layer).

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/core/contracts/embedding_provider.dart';
import 'package:aion/core/database/app_database.dart';
import 'package:aion/core/git/git_repository_client.dart';
import 'package:aion/core/markdown/ticket_markdown_serializer.dart';
import 'package:aion/core/utils/platform_utils.dart';
import 'package:aion/features/projects/projects.dart';
import 'package:aion/features/tickets/data/repositories/drift_comment_repository.dart';
import 'package:aion/features/tickets/data/repositories/drift_ticket_link_repository.dart';
import 'package:aion/features/tickets/data/repositories/drift_ticket_repository.dart';
import 'package:aion/features/tickets/data/services/active_ticket_view_registry.dart';
import 'package:aion/features/tickets/data/services/document_parent_migration_service.dart';
import 'package:aion/features/tickets/data/services/ticket_document_search_service.dart';
import 'package:aion/features/tickets/data/services/ticket_git_projector.dart';
import 'package:aion/features/tickets/data/services/ticket_markdown_reconciler.dart';
import 'package:aion/features/tickets/data/services/ticket_markdown_watcher_service.dart';
import 'package:aion/features/tickets/data/services/ticket_repair_service.dart';
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
          builder: (context, state) {
            final extra = state.extra;
            return extra is CreateTicketRouteExtra
                ? CreateTicketScreen(
                    initialType: extra.initialType,
                    initialParentId: extra.initialParentId,
                  )
                : const CreateTicketScreen();
          },
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
        GoRoute(
          path: '/workspace/documentation',
          builder: (context, state) => BlocProvider<DocumentationCubit>(
            create: (context) => DocumentationCubit(
              context.read<TicketRepository>(),
              TicketDocumentSearchService(
                context.read<EmbeddingProvider>(),
                context.read<TicketRepository>(),
              ),
            ),
            child: const DocumentationScreen(),
          ),
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

/// Converts every existing resource/page ticket's legacy `parentId` →
/// epic/story/task relationship into a `TicketLink`, every time a
/// project's workspace opens (called from [WorkspaceShell.initState]),
/// via [DocumentParentMigrationService] — which itself gates the actual
/// migration work to a single run per install. Fire-and-forget, same
/// rationale as [_purgeOldTrashOnOpen]: never delays the workspace's
/// first paint, and failures are non-fatal (retried on the next open).
Future<void> _migrateDocumentParentsOnOpen(AppDatabase database) async {
  final prefs = await SharedPreferences.getInstance();
  await DocumentParentMigrationService(
    DriftTicketRepository(database),
    DriftTicketLinkRepository(database),
    prefs,
  ).migrateIfNeeded();
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

class _WorkspaceShellState extends State<WorkspaceShell>
    with WidgetsBindingObserver {
  late final AppDatabase _database = AppDatabase(widget.project);

  /// Non-null only on desktop with a resolved project directory — the
  /// same gate `CreateProjectCubit._initializeDesktopProject` uses for
  /// git-backed version history at all (see proposal.md's Non-goals:
  /// mobile/web project-scoped git history is a separate, unbuilt gap).
  String? get _rootPath => isDesktop ? widget.project.rootPath : null;

  TicketMarkdownWatcherService? _watcherService;

  @override
  void initState() {
    super.initState();
    unawaited(_purgeOldTrashOnOpen(_database));
    unawaited(_migrateDocumentParentsOnOpen(_database));
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watcherService?.stop();
    unawaited(_database.close());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final watcher = _watcherService;
    if (watcher == null) return;
    switch (state) {
      case AppLifecycleState.resumed:
        watcher.start();
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        watcher.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rootPath = _rootPath;

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
        // Desktop-only project-scoped services below — git projection,
        // bidirectional resource/page reconcile, and repair. Absent
        // entirely on mobile/web (no rootPath to address git commands
        // to); `TicketsCubit`'s embeddingProvider/gitProjector/
        // projectRootPath params already no-op when null, and
        // `TicketDetailScreen` gates the sync badge/banner on
        // `isDesktop` rather than reading these providers unguarded.
        if (rootPath != null) ...[
          RepositoryProvider<GitRepositoryClient>(
            create: (_) => GitRepositoryClient(),
          ),
          RepositoryProvider<TicketMarkdownSerializer>(
            create: (_) => TicketMarkdownSerializer(),
          ),
          RepositoryProvider<ActiveTicketViewRegistry>(
            create: (_) => ActiveTicketViewRegistry(),
          ),
          RepositoryProvider<TicketGitProjector>(
            create: (context) => TicketGitProjector(
              context.read<TicketMarkdownSerializer>(),
              context.read<GitRepositoryClient>(),
            ),
          ),
          RepositoryProvider<TicketMarkdownReconciler>(
            create: (context) => TicketMarkdownReconciler(
              context.read<TicketRepository>(),
              context.read<TicketMarkdownSerializer>(),
              context.read<ActiveTicketViewRegistry>(),
              context.read<EmbeddingProvider>(),
            ),
          ),
          RepositoryProvider<TicketRepairService>(
            create: (context) => TicketRepairService(
              context.read<TicketRepository>(),
              context.read<TicketMarkdownSerializer>(),
            ),
          ),
        ],
      ],
      child: Builder(
        builder: (context) {
          if (rootPath != null) {
            // Deferred until the providers above exist — `initState`
            // itself can't `context.read` before `build` runs once.
            _watcherService ??= TicketMarkdownWatcherService(
              context.read<TicketMarkdownReconciler>(),
              rootPath,
            )..start();
          }
          return BlocProvider<TicketsCubit>(
            create: (context) => TicketsCubit(
              context.read<TicketRepository>(),
              embeddingProvider: context.read<EmbeddingProvider>(),
              gitProjector: rootPath != null
                  ? context.read<TicketGitProjector>()
                  : null,
              projectRootPath: rootPath,
              linkRepository: context.read<TicketLinkRepository>(),
            ),
            child: widget.child,
          );
        },
      ),
    );
  }
}
