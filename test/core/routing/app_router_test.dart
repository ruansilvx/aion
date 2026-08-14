// test/core/routing/app_router_test.dart — appRouter's /workspace/inbox route-wiring integration test.

import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/projects/projects.dart';
import 'package:aion/features/providers/providers.dart';
import 'package:aion/features/tickets/data/repositories/drift_ticket_repository.dart';
import 'package:aion/features/tickets/tickets.dart';
import 'package:aion/l10n/generated/app_localizations.dart';

class MockActiveProjectCubit extends MockCubit<ActiveProjectState>
    implements ActiveProjectCubit {}

class MockProjectRepository extends Mock implements ProjectRepository {}

class MockBaselineRepository extends Mock implements BaselineRepository {}

class MockEmbeddingProvider extends Mock implements EmbeddingProvider {}

class MockAgentModelClient extends Mock implements AgentModelClient {}

class MockAgentProvider extends Mock implements AgentProvider {}

class MockProviderRegistry extends Mock implements ProviderRegistry {}

class MockModelRoutingRepository extends Mock
    implements ModelRoutingRepository {}

class MockAutomationSettingsRepository extends Mock
    implements AutomationSettingsRepository {}

class MockExecutionContextCapRepository extends Mock
    implements ExecutionContextCapRepository {}

class MockExecutionSchedulingRepository extends Mock
    implements ExecutionSchedulingRepository {}

/// Exercises the real `appRouter` singleton (not a stand-in `GoRouter`,
/// unlike `workspace_nav_shell_test.dart`'s own routing test) to prove the
/// `/workspace/inbox` `GoRoute` added by
/// `aion-arch/changes/new-project-onboarding-inbox` is wired correctly end
/// to end: it resolves to `InboxScreen`, and the route-scoped
/// `BlocProvider<InboxCubit>` it constructs is handed a real
/// `TicketRepository` backed by a real (temp-directory-addressed)
/// `AppDatabase` — not a mock — so `InboxCubit.load()` genuinely round-trips
/// through drift. Every other cross-feature dependency `WorkspaceShell`
/// needs to build at all (`ProviderRegistry`, `ModelRoutingRepository`,
/// `EmbeddingProvider`, `AutomationSettingsRepository`,
/// `ExecutionContextCapRepository`, `BaselineRepository`,
/// `ProjectRepository`) is mocked, since none of the four Inbox launch
/// methods are invoked here — that behavior is already covered by
/// `inbox_cubit_test.dart`/`inbox_screen_test.dart` against a mocked
/// `InboxCubit`. This file is the one place that previously had no
/// coverage at all: `appRouter`'s own route table.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerFallbackValue(const ActiveProjectNone());

  late Directory tempDir;
  late Project project;

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('aion_app_router_test_');
    project = Project(
      id: 'test-project',
      name: 'Test Project',
      storageKey: 'test-project',
      rootPath: tempDir.path,
      baselineVersion: '0.1.0',
      createdAt: DateTime(2024, 1, 1),
      lastOpenedAt: DateTime(2024, 1, 1),
    );

    // `project.rootPath` being non-null means `AppDatabase`'s own
    // `databasePath` lookup never calls path_provider — but drift_flutter's
    // `driftDatabase` unconditionally calls `getTemporaryDirectory` once,
    // globally, to point sqlite3 at a writable scratch directory (see
    // `drift_flutter`'s `native.dart`), regardless of `databasePath`. No
    // real platform plugin is registered in a widget test, so that channel
    // call needs a mock handler or it throws `MissingPluginException`.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProviderChannel,
          (call) async => tempDir.path,
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    // `WorkspaceShell`'s own internally-opened `AppDatabase` (its
    // isolate-backed sqlite connection) only releases its file lock once
    // the widget is disposed, which each test triggers itself by pumping
    // an empty tree before returning — but the isolate's close message is
    // still asynchronous, so deletion gets a few retries rather than
    // assuming the lock is already gone by the time tearDown runs.
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
        break;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
  });

  /// Pumps the real `appRouter` wrapped in every provider `WorkspaceShell`
  /// needs above it (mirroring `AionApp`'s own provider stack in
  /// `main.dart`, minus the parts `/workspace/inbox` never reaches — the
  /// `/hub`/`/hub/new` routes' own cubits), with [activeProjectCubit]
  /// standing in for the real `ActiveProjectCubit` so the test controls
  /// which project is "open" without touching the registry database.
  Widget wrap(MockActiveProjectCubit activeProjectCubit) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<ProjectRepository>(
          create: (_) => MockProjectRepository(),
        ),
        RepositoryProvider<BaselineRepository>(
          create: (_) => MockBaselineRepository(),
        ),
        RepositoryProvider<EmbeddingProvider>(
          create: (_) => MockEmbeddingProvider(),
        ),
        RepositoryProvider<ProviderRegistry>(
          create: (_) {
            final client = MockAgentModelClient();
            final provider = MockAgentProvider();
            final registry = MockProviderRegistry();
            when(() => provider.client).thenReturn(client);
            when(
              () => registry.providerById(ProviderId.claudeAgentSdk),
            ).thenReturn(provider);
            return registry;
          },
        ),
        RepositoryProvider<ModelRoutingRepository>(
          create: (_) => MockModelRoutingRepository(),
        ),
        RepositoryProvider<ExecutionContextCapRepository>(
          create: (_) => MockExecutionContextCapRepository(),
        ),
        RepositoryProvider<AutomationSettingsRepository>(
          create: (_) => MockAutomationSettingsRepository(),
        ),
        // Added for `aion-arch/changes/parallel-work` — `TicketsCubit`
        // (constructed inside `WorkspaceShell`) reads this unconditionally
        // now, mirroring `main.dart`'s own app-level registration.
        RepositoryProvider<ExecutionSchedulingRepository>(
          create: (_) {
            final repo = MockExecutionSchedulingRepository();
            when(
              () => repo.getMode(),
            ).thenAnswer((_) async => ExecutionSchedulingMode.strictFifo);
            when(() => repo.getConcurrencyCeiling()).thenAnswer((_) async => 2);
            return repo;
          },
        ),
      ],
      child: BlocProvider<ActiveProjectCubit>.value(
        value: activeProjectCubit,
        child: RepositoryProvider<ActiveProjectProvider>(
          create: (context) => context.read<ActiveProjectCubit>(),
          child: ThemeScope(
            theme: aionThemeArctic,
            child: WidgetsApp.router(
              routerConfig: appRouter,
              color: aionThemeArctic.colors.primary,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    '/workspace/inbox resolves to InboxScreen with a working, '
    'real-repository-backed InboxCubit — empty history renders '
    'InboxEmptyState',
    (tester) async {
      final activeProjectCubit = MockActiveProjectCubit();
      when(() => activeProjectCubit.state).thenReturn(
        ActiveProjectOpen(project),
      );
      when(
        () => activeProjectCubit.stream,
      ).thenAnswer((_) => const Stream<ActiveProjectState>.empty());

      // `AppDatabase`'s no-executor constructor opens a real,
      // isolate-backed drift connection (see `_openConnection`) — genuine
      // cross-isolate async work that Flutter test's fake-async zone
      // can't resolve on its own (`pumpAndSettle` hangs waiting on frames
      // that never get scheduled because the isolate reply arrives on a
      // real timer, not a fake one). `runAsync` steps outside that zone
      // so the reply actually arrives.
      await tester.runAsync(() async {
        appRouter.go('/workspace/inbox');
        await tester.pumpWidget(wrap(activeProjectCubit));
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
        }
      });

      expect(find.byType(InboxScreen), findsOneWidget);
      expect(find.text('Inbox'), findsWidgets);
      expect(find.byType(InboxEmptyState), findsOneWidget);

      // Disposes `WorkspaceShell`, closing its internal `AppDatabase`
      // (and releasing the temp-directory sqlite file lock) before
      // `tearDown` tries to delete that directory.
      await tester.pumpWidget(const SizedBox());
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    '/workspace/inbox\'s InboxCubit genuinely round-trips through drift: a '
    'ticket seeded directly via DriftTicketRepository, against the same '
    'project rootPath, appears in the rendered history list',
    (tester) async {
      final activeProjectCubit = MockActiveProjectCubit();
      when(() => activeProjectCubit.state).thenReturn(
        ActiveProjectOpen(project),
      );
      when(
        () => activeProjectCubit.stream,
      ).thenAnswer((_) => const Stream<ActiveProjectState>.empty());

      await tester.runAsync(() async {
        final seedDatabase = AppDatabase(project);
        final now = DateTime.now();
        await DriftTicketRepository(seedDatabase).createTicket(
          Ticket(
            id: 'seeded-inbox-chat',
            ticketId: '',
            type: TicketType.chat,
            title: 'Seeded Q&A chat from app_router_test',
            status: TicketStatus.backlog,
            inboxPurpose: InboxPurpose.qa,
            createdAt: now,
            updatedAt: now,
          ),
        );
        await seedDatabase.close();

        appRouter.go('/workspace/inbox');
        await tester.pumpWidget(wrap(activeProjectCubit));
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
        }
      });

      expect(find.byType(InboxHistoryItem), findsOneWidget);
      expect(
        find.text('Seeded Q&A chat from app_router_test'),
        findsOneWidget,
      );
      expect(find.byType(InboxEmptyState), findsNothing);

      await tester.pumpWidget(const SizedBox());
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
