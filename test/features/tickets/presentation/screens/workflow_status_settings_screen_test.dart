// test/features/tickets/presentation/screens/workflow_status_settings_screen_test.dart — WorkflowStatusSettingsScreen widget tests.

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/tickets.dart';
import 'package:aion/l10n/generated/app_localizations.dart';

class MockWorkflowStatusRepository extends Mock
    implements WorkflowStatusRepository {}

class MockSddStageConfigRepository extends Mock
    implements SddStageConfigRepository {}

class MockTicketRepository extends Mock implements TicketRepository {}

Widget _wrap(WorkflowConfigCubit cubit) {
  return ThemeScope(
    theme: aionThemeArctic,
    child: WidgetsApp(
      color: aionThemeArctic.colors.primary,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, _) => BlocProvider<WorkflowConfigCubit>.value(
        value: cubit,
        child: const WorkflowStatusSettingsScreen(),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(SddStage.exploring);
  });

  late MockWorkflowStatusRepository statusRepository;
  late MockSddStageConfigRepository sddStageConfigRepository;
  late MockTicketRepository ticketRepository;

  final backlog = WorkflowStatus(
    id: 'id-backlog',
    name: 'backlog',
    displayName: 'Backlog',
    sortOrder: 0,
  );
  final inProgress = WorkflowStatus(
    id: 'id-in-progress',
    name: 'inProgress',
    displayName: 'In Progress',
    sortOrder: 1,
    role: WorkflowStatusRole.executionTrigger,
  );
  final done = WorkflowStatus(
    id: 'id-done',
    name: 'done',
    displayName: 'Done',
    sortOrder: 2,
    role: WorkflowStatusRole.done,
  );

  setUp(() {
    // Wide enough that every ScopeSelector pill (Base + all TicketType
    // values) fits without needing to scroll the horizontal strip.
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .implicitView!;
    view.physicalSize = const Size(1400, 900);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);

    statusRepository = MockWorkflowStatusRepository();
    sddStageConfigRepository = MockSddStageConfigRepository();
    ticketRepository = MockTicketRepository();
    when(() => statusRepository.onChanged).thenAnswer((_) => const Stream.empty());
    when(
      () => statusRepository.getAll(),
    ).thenAnswer((_) async => [backlog, inProgress, done]);
    when(
      () => sddStageConfigRepository.getDesignStagesEnabled(),
    ).thenAnswer((_) async => true);
    when(
      () => sddStageConfigRepository.getDisplayNameOverride(any()),
    ).thenAnswer((_) async => null);
    when(() => ticketRepository.getAllTickets()).thenAnswer((_) async => []);
  });

  testWidgets('renders the header and every Base status row', (tester) async {
    final cubit = WorkflowConfigCubit(
      statusRepository,
      sddStageConfigRepository,
      ticketRepository,
    )..load();
    await tester.pumpWidget(_wrap(cubit));
    await tester.pumpAndSettle();

    expect(find.text('Workflow'), findsOneWidget);
    expect(find.text('Backlog'), findsOneWidget);
    expect(find.text('In Progress'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Require design review stages'), findsOneWidget);
  });

  testWidgets('tapping "Add status" expands the inline add form', (tester) async {
    final cubit = WorkflowConfigCubit(
      statusRepository,
      sddStageConfigRepository,
      ticketRepository,
    )..load();
    await tester.pumpWidget(_wrap(cubit));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add status'));
    await tester.pumpAndSettle();

    expect(find.text('Display name'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets(
    'switching to a type scope shows the inherited tag on Base rows',
    (tester) async {
      final cubit = WorkflowConfigCubit(
        statusRepository,
        sddStageConfigRepository,
        ticketRepository,
      )..load();
      await tester.pumpWidget(_wrap(cubit));
      await tester.pumpAndSettle();

      // "Epic" — the first TicketType pill after "Base" in the
      // horizontally-scrolling strip — stays on-screen without needing
      // to scroll the strip first, unlike a later type (e.g. "Bug").
      await tester.tap(find.text('Epic'));
      await tester.pumpAndSettle();

      expect(find.text('INHERITED'), findsWidgets);
    },
  );
}
