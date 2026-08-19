// test/features/tickets/presentation/screens/workflow_status_settings_screen_test.dart — WorkflowStatusSettingsScreen widget tests.

import 'package:flutter/material.dart' show TextField;
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/core.dart';
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
        // An explicit Overlay ancestor — this bare WidgetsApp (no
        // home/routes) doesn't provide one on its own, but AppTextField's
        // underlying TextField needs one once actually focused/edited
        // (the text-selection overlay), which none of this file's tests
        // did before workflow-skill-attachments' delegated-skill-name
        // field test. Added for
        // `aion-arch/changes/workflow-skill-attachments`.
        child: Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (context) => const WorkflowStatusSettingsScreen(),
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
      const SkillAttachment(
        id: 'fallback',
        workflowStatusId: 'fallback-status',
        kind: SkillAttachmentKind.delegatedSkill,
        skillName: 'fallback',
        confidence: AutomationConfidence.gated,
      ),
    );
  });

  late MockWorkflowStatusRepository statusRepository;
  late MockSddStageConfigRepository sddStageConfigRepository;
  late MockTicketRepository ticketRepository;
  late MockWorkflowSkillAttachmentRepository attachmentRepository;
  late MockWorkflowPromptTemplateRepository templateRepository;

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
    attachmentRepository = MockWorkflowSkillAttachmentRepository();
    templateRepository = MockWorkflowPromptTemplateRepository();
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
    when(() => attachmentRepository.onChanged).thenAnswer((_) => const Stream.empty());
    when(() => attachmentRepository.getAll()).thenAnswer((_) async => []);
    when(() => templateRepository.getAll()).thenAnswer((_) async => []);
  });

  WorkflowConfigCubit buildCubit() => WorkflowConfigCubit(
    statusRepository,
    sddStageConfigRepository,
    ticketRepository,
    attachmentRepository,
    templateRepository,
  );

  testWidgets('renders the header and every Base status row', (tester) async {
    final cubit = buildCubit()..load();
    await tester.pumpWidget(_wrap(cubit));
    await tester.pumpAndSettle();

    expect(find.text('Workflow'), findsOneWidget);
    expect(find.text('Backlog'), findsOneWidget);
    expect(find.text('In Progress'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Require design review stages'), findsOneWidget);
  });

  testWidgets('tapping "Add status" expands the inline add form', (tester) async {
    final cubit = buildCubit()..load();
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
      final cubit = buildCubit()..load();
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

  // Skill attachments (Phase 2) — `_AttachmentBadge`/`_AttachmentForm`.
  // Only the `delegatedSkill` kind is exercised here (a plain text
  // field) — the `aionNativeTemplate` kind's `SelectionMenu`-backed
  // picker is left to manual/exploratory verification, matching this
  // file's own file-level scope (no existing test here drives a
  // `SelectionMenu` overlay either — see `_RoleDropdown`).
  testWidgets(
    'tapping "Attach skill" expands the form; saving a delegated skill '
    'attachment persists it via the repository',
    (tester) async {
      final attachmentRepository = MockWorkflowSkillAttachmentRepository();
      when(
        () => attachmentRepository.onChanged,
      ).thenAnswer((_) => const Stream.empty());
      when(() => attachmentRepository.getAll()).thenAnswer((_) async => []);
      when(
        () => attachmentRepository.create(any()),
      ).thenAnswer((_) async {});

      final cubit = WorkflowConfigCubit(
        statusRepository,
        sddStageConfigRepository,
        ticketRepository,
        attachmentRepository,
        templateRepository,
      )..load();
      await tester.pumpWidget(_wrap(cubit));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Attach skill').first);
      await tester.pumpAndSettle();

      // Switch kind to "Delegated skill" (the form opens defaulted to
      // "Template", whose picker isn't exercised here).
      await tester.tap(find.text('Delegated skill'));
      await tester.pumpAndSettle();

      final nameField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'e.g. code-review',
      );
      expect(nameField, findsOneWidget);
      await tester.enterText(nameField, 'code-review');
      await tester.pumpAndSettle();

      // The form's Save button can land below the fold once expanded —
      // scroll it into view before tapping.
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final captured = verify(
        () => attachmentRepository.create(captureAny()),
      ).captured;
      expect(captured, hasLength(1));
      final saved = captured.single as SkillAttachment;
      expect(saved.kind, SkillAttachmentKind.delegatedSkill);
      expect(saved.skillName, 'code-review');
      expect(saved.confidence, AutomationConfidence.gated);
    },
  );

  testWidgets(
    'Save stays disabled while the delegated-skill name is empty',
    (tester) async {
      final attachmentRepository = MockWorkflowSkillAttachmentRepository();
      when(
        () => attachmentRepository.onChanged,
      ).thenAnswer((_) => const Stream.empty());
      when(() => attachmentRepository.getAll()).thenAnswer((_) async => []);

      final cubit = WorkflowConfigCubit(
        statusRepository,
        sddStageConfigRepository,
        ticketRepository,
        attachmentRepository,
        templateRepository,
      )..load();
      await tester.pumpWidget(_wrap(cubit));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Attach skill').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delegated skill'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a skill name.'), findsOneWidget);
      verifyNever(() => attachmentRepository.create(any()));
    },
  );

  testWidgets(
    'tapping an existing attachment badge reopens the form pre-filled, '
    'with a Remove action that deletes it',
    (tester) async {
      final attachmentRepository = MockWorkflowSkillAttachmentRepository();
      final existing = SkillAttachment(
        id: 'attach-1',
        workflowStatusId: backlog.id,
        kind: SkillAttachmentKind.delegatedSkill,
        skillName: 'code-review',
        confidence: AutomationConfidence.auto,
      );
      when(
        () => attachmentRepository.onChanged,
      ).thenAnswer((_) => const Stream.empty());
      when(
        () => attachmentRepository.getAll(),
      ).thenAnswer((_) async => [existing]);
      when(
        () => attachmentRepository.delete(existing.id),
      ).thenAnswer((_) async {});

      final cubit = WorkflowConfigCubit(
        statusRepository,
        sddStageConfigRepository,
        ticketRepository,
        attachmentRepository,
        templateRepository,
      )..load();
      await tester.pumpWidget(_wrap(cubit));
      await tester.pumpAndSettle();

      // The attached-state chip label — "SKILL · AUTO".
      expect(find.textContaining('SKILL'), findsWidgets);

      await tester.tap(find.textContaining('SKILL').first);
      await tester.pumpAndSettle();

      expect(find.text('Remove'), findsOneWidget);

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      verify(() => attachmentRepository.delete(existing.id)).called(1);
    },
  );

  testWidgets(
    'tapping an existing attachment badge, changing its confidence, and '
    'saving persists the update via the repository — added for '
    'aion-arch/changes/workflow-skill-attachments (post-/verify fix: T30 '
    'previously covered create/delete only, never edit)',
    (tester) async {
      final attachmentRepository = MockWorkflowSkillAttachmentRepository();
      final existing = SkillAttachment(
        id: 'attach-1',
        workflowStatusId: backlog.id,
        kind: SkillAttachmentKind.delegatedSkill,
        skillName: 'code-review',
        confidence: AutomationConfidence.auto,
      );
      when(
        () => attachmentRepository.onChanged,
      ).thenAnswer((_) => const Stream.empty());
      when(
        () => attachmentRepository.getAll(),
      ).thenAnswer((_) async => [existing]);
      when(
        () => attachmentRepository.update(any()),
      ).thenAnswer((_) async {});

      final cubit = WorkflowConfigCubit(
        statusRepository,
        sddStageConfigRepository,
        ticketRepository,
        attachmentRepository,
        templateRepository,
      )..load();
      await tester.pumpWidget(_wrap(cubit));
      await tester.pumpAndSettle();

      // The attached-state chip label — "SKILL · AUTO".
      await tester.tap(find.textContaining('SKILL').first);
      await tester.pumpAndSettle();

      // Reopened pre-filled with the existing skill name.
      final nameField = find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == 'code-review',
      );
      expect(nameField, findsOneWidget);

      // Change confidence from Auto to Manual, then Save.
      await tester.tap(find.text('Manual'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final captured = verify(
        () => attachmentRepository.update(captureAny()),
      ).captured;
      expect(captured, hasLength(1));
      final saved = captured.single as SkillAttachment;
      expect(saved.id, existing.id);
      expect(saved.skillName, 'code-review');
      expect(saved.confidence, AutomationConfidence.manual);
      verifyNever(() => attachmentRepository.create(any()));
    },
  );
}
