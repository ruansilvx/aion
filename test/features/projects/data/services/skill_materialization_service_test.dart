import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/features/projects/data/services/skill_materialization_service.dart';
import 'package:aion/features/projects/domain/entities/baseline_asset.dart';
import 'package:aion/features/projects/domain/entities/baseline_manifest.dart';
import 'package:aion/features/projects/domain/entities/project_override.dart';
import 'package:aion/features/projects/domain/repositories/baseline_repository.dart';

class MockBaselineRepository extends Mock implements BaselineRepository {}

void main() {
  late MockBaselineRepository baselineRepository;
  late Directory tempDir;
  late SkillMaterializationService service;

  const archiveAsset = BaselineAsset(
    key: 'skills/archive',
    kind: BaselineAssetKind.skill,
    bundledPath: 'assets/baseline/0.4.0/skills/archive.md',
  );
  const proposeAsset = BaselineAsset(
    key: 'skills/propose',
    kind: BaselineAssetKind.skill,
    bundledPath: 'assets/baseline/0.4.0/skills/propose.md',
  );
  const conventionAsset = BaselineAsset(
    key: 'conventions/architecture-conventions',
    kind: BaselineAssetKind.architectureConvention,
    bundledPath: 'assets/baseline/0.4.0/architecture_convention.md',
  );

  String skillFilePath(String name) {
    final sep = Platform.pathSeparator;
    return '${tempDir.path}$sep.claude${sep}skills$sep$name${sep}SKILL.md';
  }

  setUpAll(() {
    registerFallbackValue(archiveAsset);
  });

  setUp(() async {
    baselineRepository = MockBaselineRepository();
    service = SkillMaterializationService(baselineRepository);
    tempDir = await Directory.systemTemp.createTemp('skill_mat_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('buildSkillDocument', () {
    test(
      'emits frontmatter naming the skill, a description taken from the '
      "body's first paragraph, the managed marker, then the body verbatim",
      () {
        const body =
            '# archive\n'
            '\n'
            'The final stage of the SDD cycle, reached once verify has\n'
            'reported no outstanding critical findings.\n'
            '\n'
            'What it does:\n'
            '\n'
            '- Synthesizes the outcome into a spec ticket.\n';

        final doc = SkillMaterializationService.buildSkillDocument(
          skillName: 'archive',
          body: body,
        );

        expect(
          doc,
          startsWith(
            '---\n'
            'name: archive\n'
            'description: "The final stage of the SDD cycle, reached once '
            'verify has reported no outstanding critical findings."\n'
            '---\n',
          ),
        );
        expect(doc, contains(SkillMaterializationService.managedMarker));
        expect(doc, endsWith(body));
        // The `# archive` title is skipped rather than used as the
        // description — it only repeats `name:`.
        expect(doc, isNot(contains('description: "# archive')));
      },
    );

    test('escapes quotes and backslashes so the YAML scalar stays valid', () {
      final doc = SkillMaterializationService.buildSkillDocument(
        skillName: 'weird',
        body: r'Runs "git log" against C:\repos and reports: findings.',
      );

      expect(
        doc,
        contains(
          r'description: "Runs \"git log\" against C:\\repos and reports: '
          r'findings."',
        ),
      );
    });

    test('truncates an over-long paragraph on a word boundary', () {
      final body = List.filled(200, 'word').join(' ');

      final doc = SkillMaterializationService.buildSkillDocument(
        skillName: 'long',
        body: body,
      );

      final description = RegExp(
        r'description: "(.*)"',
      ).firstMatch(doc)!.group(1)!;
      expect(
        description.length,
        lessThanOrEqualTo(SkillMaterializationService.maxDescriptionLength + 1),
      );
      expect(description, endsWith('…'));
      expect(description, isNot(contains('  ')));
    });

    test('falls back to a generic description for a heading-only body', () {
      final doc = SkillMaterializationService.buildSkillDocument(
        skillName: 'empty',
        body: '# empty\n',
      );

      expect(doc, contains('description: "The empty skill'));
    });
  });

  group('materializeSkill', () {
    test('writes .claude/skills/<name>/SKILL.md, creating parents', () {
      service.materializeSkill(
        rootPath: tempDir.path,
        asset: archiveAsset,
        content: '# archive\n\nDoes the archiving.\n',
      );

      final file = File(skillFilePath('archive'));
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), contains('name: archive'));
      expect(file.readAsStringSync(), contains('Does the archiving.'));
    });

    test('no-ops for a non-skill asset kind', () {
      service.materializeSkill(
        rootPath: tempDir.path,
        asset: conventionAsset,
        content: 'conventions body',
      );

      expect(
        Directory(
          '${tempDir.path}${Platform.pathSeparator}.claude',
        ).existsSync(),
        isFalse,
      );
    });

    test('overwrites a file it previously generated', () {
      service.materializeSkill(
        rootPath: tempDir.path,
        asset: archiveAsset,
        content: 'first body',
      );
      service.materializeSkill(
        rootPath: tempDir.path,
        asset: archiveAsset,
        content: 'second body',
      );

      final content = File(skillFilePath('archive')).readAsStringSync();
      expect(content, contains('second body'));
      expect(content, isNot(contains('first body')));
    });

    test('leaves a hand-authored SKILL.md (no managed marker) untouched', () {
      final file = File(skillFilePath('archive'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('---\nname: archive\n---\n\nMy own skill.\n');

      service.materializeSkill(
        rootPath: tempDir.path,
        asset: archiveAsset,
        content: 'baseline body',
      );

      expect(file.readAsStringSync(), contains('My own skill.'));
      expect(file.readAsStringSync(), isNot(contains('baseline body')));
    });
  });

  group('materializeAll', () {
    test('writes every skill asset, resolving overrides ahead of bundled '
        'defaults and ignoring non-skill kinds', () async {
      when(() => baselineRepository.readOverrides('p1')).thenAnswer(
        (_) async => const [
          ProjectOverride(
            projectId: 'p1',
            assetKey: 'skills/propose',
            overridePath: '/root/.aion/overrides/propose.md',
          ),
        ],
      );
      when(
        () => baselineRepository.readBundledContent(archiveAsset),
      ).thenAnswer((_) async => 'bundled archive body');
      when(
        () => baselineRepository.readOverrideContent(
          '/root/.aion/overrides/propose.md',
        ),
      ).thenAnswer((_) async => 'overridden propose body');

      await service.materializeAll(
        projectId: 'p1',
        rootPath: tempDir.path,
        manifest: const BaselineManifest(
          version: '0.4.0',
          assets: [archiveAsset, proposeAsset, conventionAsset],
        ),
      );

      expect(
        File(skillFilePath('archive')).readAsStringSync(),
        contains('bundled archive body'),
      );
      expect(
        File(skillFilePath('propose')).readAsStringSync(),
        contains('overridden propose body'),
      );
      expect(
        File(skillFilePath('architecture-conventions')).existsSync(),
        isFalse,
      );
      verifyNever(() => baselineRepository.readBundledContent(proposeAsset));
    });

    test('skips an unreadable asset without aborting the rest', () async {
      when(
        () => baselineRepository.readOverrides('p1'),
      ).thenAnswer((_) async => const []);
      when(
        () => baselineRepository.readBundledContent(archiveAsset),
      ).thenThrow(Exception('missing asset'));
      when(
        () => baselineRepository.readBundledContent(proposeAsset),
      ).thenAnswer((_) async => 'propose body');

      await service.materializeAll(
        projectId: 'p1',
        rootPath: tempDir.path,
        manifest: const BaselineManifest(
          version: '0.4.0',
          assets: [archiveAsset, proposeAsset],
        ),
      );

      expect(File(skillFilePath('archive')).existsSync(), isFalse);
      expect(File(skillFilePath('propose')).existsSync(), isTrue);
    });
  });

  group('skillNameOf', () {
    test('returns the asset key\'s last path segment', () {
      expect(SkillMaterializationService.skillNameOf(archiveAsset), 'archive');
      expect(
        SkillMaterializationService.skillNameOf(
          const BaselineAsset(
            key: 'skills/clean-up',
            kind: BaselineAssetKind.skill,
            bundledPath: 'assets/baseline/0.4.0/skills/clean-up.md',
          ),
        ),
        'clean-up',
      );
    });
  });
}
