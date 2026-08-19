// test/features/tickets/presentation/screens/workflow_prompt_templates_screen_test.dart — WorkflowPromptTemplatesScreen widget tests.

import 'package:flutter/material.dart' show TextField;
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

class MockWorkflowSkillAttachmentRepository extends Mock
    implements WorkflowSkillAttachmentRepository {}

class MockWorkflowPromptTemplateRepository extends Mock
    implements WorkflowPromptTemplateRepository {}

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
        // See workflow_status_settings_screen_test.dart's _wrap for why
        // this Overlay is needed once a TextField is actually focused.
        child: Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (context) => const WorkflowPromptTemplatesScreen(),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(SddStage.exploring);
    registerFallbackValue(
      const WorkflowPromptTemplate(id: 'fallback', name: 'fallback', body: 'fallback'),
    );
  });

  late MockWorkflowStatusRepository statusRepository;
  late MockSddStageConfigRepository sddStageConfigRepository;
  late MockTicketRepository ticketRepository;
  late MockWorkflowSkillAttachmentRepository attachmentRepository;
  late MockWorkflowPromptTemplateRepository templateRepository;

  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .implicitView!;
    view.physicalSize = const Size(1000, 1200);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);

    statusRepository = MockWorkflowStatusRepository();
    sddStageConfigRepository = MockSddStageConfigRepository();
    ticketRepository = MockTicketRepository();
    attachmentRepository = MockWorkflowSkillAttachmentRepository();
    templateRepository = MockWorkflowPromptTemplateRepository();
    when(() => statusRepository.onChanged).thenAnswer((_) => const Stream.empty());
    when(() => statusRepository.getAll()).thenAnswer((_) async => []);
    when(
      () => sddStageConfigRepository.getDesignStagesEnabled(),
    ).thenAnswer((_) async => true);
    when(
      () => sddStageConfigRepository.getDisplayNameOverride(any()),
    ).thenAnswer((_) async => null);
    when(() => ticketRepository.getAllTickets()).thenAnswer((_) async => []);
    when(
      () => attachmentRepository.onChanged,
    ).thenAnswer((_) => const Stream.empty());
    when(() => attachmentRepository.getAll()).thenAnswer((_) async => []);
  });

  WorkflowConfigCubit buildCubit() => WorkflowConfigCubit(
    statusRepository,
    sddStageConfigRepository,
    ticketRepository,
    attachmentRepository,
    templateRepository,
  );

  testWidgets('shows the empty state when there are no templates', (
    tester,
  ) async {
    when(() => templateRepository.getAll()).thenAnswer((_) async => []);
    final cubit = buildCubit()..load();

    await tester.pumpWidget(_wrap(cubit));
    await tester.pumpAndSettle();

    expect(find.text('Prompt Templates'), findsOneWidget);
    expect(find.text('No templates yet'), findsOneWidget);
  });

  testWidgets(
    'creating a template via the inline editor persists it via the repository',
    (tester) async {
      when(() => templateRepository.getAll()).thenAnswer((_) async => []);
      when(
        () => templateRepository.create(any()),
      ).thenAnswer((_) async {});
      final cubit = buildCubit()..load();

      await tester.pumpWidget(_wrap(cubit));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New template'));
      await tester.pumpAndSettle();

      final nameField = find.byWidgetPredicate(
        (w) => w is TextField && w.maxLines == 1,
      );
      expect(nameField, findsOneWidget);
      await tester.enterText(nameField, 'Repro Steps Request');
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Save template'));
      await tester.tap(find.text('Save template'));
      await tester.pumpAndSettle();

      final captured = verify(
        () => templateRepository.create(captureAny()),
      ).captured;
      expect(captured, hasLength(1));
      expect(
        (captured.single as WorkflowPromptTemplate).name,
        'Repro Steps Request',
      );
    },
  );

  testWidgets('Save template stays disabled while the name is empty', (
    tester,
  ) async {
    when(() => templateRepository.getAll()).thenAnswer((_) async => []);
    final cubit = buildCubit()..load();

    await tester.pumpWidget(_wrap(cubit));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New template'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Save template'));
    await tester.tap(find.text('Save template'));
    await tester.pumpAndSettle();

    expect(find.text('Name this template.'), findsOneWidget);
    verifyNever(() => templateRepository.create(any()));
  });

  testWidgets(
    'tapping a template row\'s Delete action removes it via the repository',
    (tester) async {
      const template = WorkflowPromptTemplate(
        id: 'template-1',
        name: 'Repro Steps Request',
        body: 'Please provide steps to reproduce.',
      );
      when(
        () => templateRepository.getAll(),
      ).thenAnswer((_) async => [template]);
      when(
        () => templateRepository.delete(template.id),
      ).thenAnswer((_) async {});
      final cubit = buildCubit()..load();

      await tester.pumpWidget(_wrap(cubit));
      await tester.pumpAndSettle();

      expect(find.text('Repro Steps Request'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Delete template'));
      await tester.pumpAndSettle();

      verify(() => templateRepository.delete(template.id)).called(1);
    },
  );

  testWidgets(
    'tapping a template row\'s Edit action opens the editor pre-filled; '
    'saving persists the update via the repository — added for '
    'aion-arch/changes/workflow-skill-attachments (post-/verify fix: T30 '
    'previously covered create/delete only, never edit)',
    (tester) async {
      const template = WorkflowPromptTemplate(
        id: 'template-1',
        name: 'Repro Steps Request',
        body: 'Please provide steps to reproduce.',
      );
      when(
        () => templateRepository.getAll(),
      ).thenAnswer((_) async => [template]);
      when(
        () => templateRepository.update(any()),
      ).thenAnswer((_) async {});
      final cubit = buildCubit()..load();

      await tester.pumpWidget(_wrap(cubit));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Edit template'));
      await tester.pumpAndSettle();

      expect(find.text('EDIT TEMPLATE'), findsOneWidget);
      final nameField = find.byWidgetPredicate(
        (w) => w is TextField && w.maxLines == 1,
      );
      expect(
        tester.widget<TextField>(nameField).controller?.text,
        'Repro Steps Request',
      );

      await tester.enterText(nameField, 'Repro Steps Request v2');
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Save template'));
      await tester.tap(find.text('Save template'));
      await tester.pumpAndSettle();

      final captured = verify(
        () => templateRepository.update(captureAny()),
      ).captured;
      expect(captured, hasLength(1));
      final saved = captured.single as WorkflowPromptTemplate;
      expect(saved.id, template.id);
      expect(saved.name, 'Repro Steps Request v2');
      expect(saved.body, template.body);
      verifyNever(() => templateRepository.create(any()));
    },
  );
}
