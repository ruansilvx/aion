// test/features/projects/screens/new_project_screen_test.dart — NewProjectScreen widget tests.

import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:aion/core/git/git_repository_client.dart';
import 'package:aion/core/git/gitignore_editor.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/projects/data/services/baseline_tailoring_service.dart';
import 'package:aion/features/projects/projects.dart';
import 'package:aion/l10n/generated/app_localizations.dart';

class MockProjectRepository extends Mock implements ProjectRepository {}

class MockBaselineRepository extends Mock implements BaselineRepository {}

class MockBaselineTailoringService extends Mock
    implements BaselineTailoringService {}

class MockGitRepositoryClient extends Mock implements GitRepositoryClient {}

class MockGitignoreEditor extends Mock implements GitignoreEditor {}

/// A fake `FileSelectorPlatform` that returns [directoryToReturn] from
/// `getDirectoryPathWithOptions` (what `getDirectoryPath()` calls under
/// the hood) instead of showing a real OS dialog.
class _FakeFileSelectorPlatform extends FileSelectorPlatform
    with MockPlatformInterfaceMixin {
  _FakeFileSelectorPlatform(this.directoryToReturn);

  final String directoryToReturn;

  @override
  Future<String?> getDirectoryPathWithOptions(FileDialogOptions options) =>
      Future.value(directoryToReturn);
}

Widget _wrap({required Widget child, required CreateProjectCubit cubit}) {
  return MediaQuery(
    data: const MediaQueryData(),
    child: Localizations(
      locale: const Locale('en'),
      delegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: ThemeScope(
          theme: aionThemeArctic,
          child: BlocProvider<CreateProjectCubit>.value(
            value: cubit,
            child: Overlay(
              initialEntries: [OverlayEntry(builder: (context) => child)],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  late MockProjectRepository projectRepository;
  late MockBaselineRepository baselineRepository;
  late MockBaselineTailoringService baselineTailoringService;
  late MockGitignoreEditor gitignoreEditor;
  late Directory tempDir;

  final existing = Project(
    id: 'existing',
    name: 'Existing Project',
    storageKey: 'existing',
    baselineVersion: '0.1.0',
    createdAt: DateTime(2026, 1, 1),
    lastOpenedAt: DateTime(2026, 1, 1),
  );

  setUpAll(() {
    registerFallbackValue(existing);
    registerFallbackValue(const BaselineManifest(version: '0.1.0', assets: []));
  });

  setUp(() async {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .implicitView!;
    view.physicalSize = const Size(900, 1400);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);

    projectRepository = MockProjectRepository();
    baselineRepository = MockBaselineRepository();
    baselineTailoringService = MockBaselineTailoringService();
    gitignoreEditor = MockGitignoreEditor();
    tempDir = await Directory.systemTemp.createTemp('new_project_screen_test_');
    when(
      () => projectRepository.getAllProjects(),
    ).thenAnswer((_) async => [existing]);
    when(
      () => projectRepository.createProject(any()),
    ).thenAnswer((_) async {});
    when(
      () => baselineRepository.getAvailableBaselineVersions(),
    ).thenAnswer((_) async => ['0.1.0']);
    when(
      () => baselineRepository.getManifest('0.1.0'),
    ).thenAnswer((_) async => const BaselineManifest(version: '0.1.0', assets: []));
    when(
      () => baselineTailoringService.tailorForDetectedStack(
        projectId: any(named: 'projectId'),
        rootPath: any(named: 'rootPath'),
        manifest: any(named: 'manifest'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => gitignoreEditor.ensureIgnored(any(), any()),
    ).thenAnswer((_) async {});
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  CreateProjectCubit buildCubit() => CreateProjectCubit(
    projectRepository,
    baselineRepository,
    baselineTailoringService,
    GitRepositoryClient(),
    gitignoreEditor,
  );

  group('NewProjectScreen — gitignore-confirmation banner', () {
    testWidgets(
      'does not show the banner for a directory that is not a git repo',
      (tester) async {
        FileSelectorPlatform.instance = _FakeFileSelectorPlatform(
          tempDir.path,
        );

        await tester.pumpWidget(
          _wrap(
            cubit: buildCubit(),
            child: NewProjectScreen(
              onBack: () {},
              onCreated: (_, {required offerCodebaseAnalysis}) {},
            ),
          ),
        );

        await tester.tap(find.text('Browse…'));
        await tester.pumpAndSettle();

        expect(
          find.text('This folder is already a Git repository'),
          findsNothing,
        );
      },
    );

    testWidgets('shows the banner when the chosen directory is a git repo', (
      tester,
    ) async {
      Directory('${tempDir.path}${Platform.pathSeparator}.git').createSync();
      FileSelectorPlatform.instance = _FakeFileSelectorPlatform(tempDir.path);

      await tester.pumpWidget(
        _wrap(
          cubit: buildCubit(),
          child: NewProjectScreen(
            onBack: () {},
            onCreated: (_, {required offerCodebaseAnalysis}) {},
          ),
        ),
      );

      await tester.tap(find.text('Browse…'));
      await tester.pumpAndSettle();

      expect(
        find.text('This folder is already a Git repository'),
        findsOneWidget,
      );
    });

    testWidgets(
      'unchecking the gitignore checkbox flows through to submit(appendGitignore: false)',
      (tester) async {
        Directory(
          '${tempDir.path}${Platform.pathSeparator}.git',
        ).createSync();
        FileSelectorPlatform.instance = _FakeFileSelectorPlatform(
          tempDir.path,
        );
        Project? created;

        await tester.pumpWidget(
          _wrap(
            cubit: buildCubit(),
            child: NewProjectScreen(
              onBack: () {},
              onCreated: (project, {required offerCodebaseAnalysis}) {
                created = project;
              },
            ),
          ),
        );

        await tester.enterText(find.byType(EditableText).first, 'A New Project');
        await tester.tap(find.text('Browse…'));
        await tester.pumpAndSettle();

        // Uncheck the "add to .gitignore" checkbox.
        await tester.tap(find.byType(AppCheckbox));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Create project'));
        await tester.pump();
        // AppToast.show starts a 3s auto-dismiss timer on this same tap
        // (unchecking the box means the decline toast also fires) —
        // advance past it explicitly rather than pumpAndSettle, which
        // won't flush a plain (non-animation) Timer and would leave it
        // pending at test teardown.
        await tester.pump(const Duration(seconds: 4));

        verifyNever(() => gitignoreEditor.ensureIgnored(any(), any()));
        expect(created, isNotNull);
      },
    );

    testWidgets(
      'declining the gitignore checkbox shows the decline-warning toast on success',
      (tester) async {
        Directory(
          '${tempDir.path}${Platform.pathSeparator}.git',
        ).createSync();
        FileSelectorPlatform.instance = _FakeFileSelectorPlatform(
          tempDir.path,
        );

        await tester.pumpWidget(
          _wrap(
            cubit: buildCubit(),
            child: NewProjectScreen(
              onBack: () {},
              onCreated: (_, {required offerCodebaseAnalysis}) {},
            ),
          ),
        );

        await tester.enterText(find.byType(EditableText).first, 'A New Project');
        await tester.tap(find.text('Browse…'));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(AppCheckbox));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Create project'));
        await tester.pump();

        expect(
          find.textContaining("tracked in this repo's history"),
          findsOneWidget,
        );

        // Advance past AppToast.show's 3s auto-dismiss timer so it
        // doesn't leave a pending Timer at test teardown (see the
        // matching comment in the "unchecking..." test above).
        await tester.pump(const Duration(seconds: 4));
      },
    );
  });
}
