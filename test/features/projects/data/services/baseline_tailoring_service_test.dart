import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/build/project_stack_detector.dart';
import 'package:aion/features/projects/data/services/baseline_tailoring_service.dart';
import 'package:aion/features/projects/domain/entities/baseline_asset.dart';
import 'package:aion/features/projects/domain/entities/baseline_manifest.dart';
import 'package:aion/features/projects/domain/entities/project_override.dart';
import 'package:aion/features/projects/domain/repositories/baseline_repository.dart';

class MockBaselineRepository extends Mock implements BaselineRepository {}

void main() {
  late MockBaselineRepository baselineRepository;
  late ProjectStackDetector detector;
  late Directory tempDir;

  const conventionAsset = BaselineAsset(
    key: 'conventions/architecture-conventions',
    kind: BaselineAssetKind.architectureConvention,
    bundledPath: 'assets/baseline/0.3.0/architecture_convention.md',
  );

  const otherManifestVersion = '0.4.0';
  const otherConventionAsset = BaselineAsset(
    key: 'conventions/architecture-conventions',
    kind: BaselineAssetKind.architectureConvention,
    bundledPath: 'assets/baseline/0.4.0/architecture_convention.md',
  );

  BaselineManifest manifestWith(List<BaselineAsset> assets, {String version = '0.3.0'}) {
    return BaselineManifest(version: version, assets: assets);
  }

  setUpAll(() {
    registerFallbackValue(conventionAsset);
  });

  setUp(() async {
    baselineRepository = MockBaselineRepository();
    detector = ProjectStackDetector();
    tempDir = await Directory.systemTemp.createTemp('tailoring_test_');
    when(
      () => baselineRepository.writeOverride(
        projectId: any(named: 'projectId'),
        asset: any(named: 'asset'),
        content: any(named: 'content'),
      ),
    ).thenAnswer((_) async {});
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('tailorForDetectedStack', () {
    test('no-ops when no stack is detected', () async {
      final service = BaselineTailoringService(baselineRepository, detector);

      await service.tailorForDetectedStack(
        projectId: '1',
        rootPath: tempDir.path,
        manifest: manifestWith([conventionAsset]),
      );

      verifyNever(
        () => baselineRepository.writeOverride(
          projectId: any(named: 'projectId'),
          asset: any(named: 'asset'),
          content: any(named: 'content'),
        ),
      );
    });

    test(
      'writes the architecture-conventions override with the detected '
      'language and suggested command when a stack is detected',
      () async {
        File(
          '${tempDir.path}${Platform.pathSeparator}pubspec.yaml',
        ).writeAsStringSync('');
        final service = BaselineTailoringService(baselineRepository, detector);

        await service.tailorForDetectedStack(
          projectId: '1',
          rootPath: tempDir.path,
          manifest: manifestWith([conventionAsset]),
        );

        final captured = verify(
          () => baselineRepository.writeOverride(
            projectId: '1',
            asset: any(named: 'asset', that: isA<BaselineAsset>()),
            content: captureAny(named: 'content'),
          ),
        ).captured;

        expect(captured, hasLength(1));
        final content = captured.first as String;
        expect(content, contains('Detected stack: Flutter/Dart.'));
        expect(content, contains('`flutter analyze`'));
        expect(content, contains('`flutter pub get`'));
      },
    );

    test(
      'resolves the convention asset from an arbitrary passed-in manifest, '
      'not hardcoded to 0.3.0',
      () async {
        File(
          '${tempDir.path}${Platform.pathSeparator}pubspec.yaml',
        ).writeAsStringSync('');
        final service = BaselineTailoringService(baselineRepository, detector);

        await service.tailorForDetectedStack(
          projectId: '1',
          rootPath: tempDir.path,
          manifest: manifestWith(
            [otherConventionAsset],
            version: otherManifestVersion,
          ),
        );

        final captured = verify(
          () => baselineRepository.writeOverride(
            projectId: '1',
            asset: captureAny(named: 'asset'),
            content: any(named: 'content'),
          ),
        ).captured;

        expect(captured, hasLength(1));
        expect(captured.first, equals(otherConventionAsset));
      },
    );

    test(
      'no-ops if the manifest has no architectureConvention-kind asset',
      () async {
        File(
          '${tempDir.path}${Platform.pathSeparator}pubspec.yaml',
        ).writeAsStringSync('');
        final service = BaselineTailoringService(baselineRepository, detector);

        await service.tailorForDetectedStack(
          projectId: '1',
          rootPath: tempDir.path,
          manifest: manifestWith(const [
            BaselineAsset(
              key: 'skills/verify',
              kind: BaselineAssetKind.skill,
              bundledPath: 'assets/baseline/0.3.0/skills/verify.md',
            ),
          ]),
        );

        verifyNever(
          () => baselineRepository.writeOverride(
            projectId: any(named: 'projectId'),
            asset: any(named: 'asset'),
            content: any(named: 'content'),
          ),
        );
      },
    );
  });

  group('tailorNewlyIntroducedAssets', () {
    test(
      'writes an override when the convention asset key is absent from '
      'the old manifest and no existing override shadows it',
      () async {
        File(
          '${tempDir.path}${Platform.pathSeparator}pubspec.yaml',
        ).writeAsStringSync('');
        when(
          () => baselineRepository.readOverrides('1'),
        ).thenAnswer((_) async => const []);
        final service = BaselineTailoringService(baselineRepository, detector);

        await service.tailorNewlyIntroducedAssets(
          projectId: '1',
          rootPath: tempDir.path,
          oldManifest: manifestWith(const [], version: '0.2.0'),
          newManifest: manifestWith(
            [conventionAsset],
            version: '0.3.0',
          ),
        );

        verify(
          () => baselineRepository.writeOverride(
            projectId: '1',
            asset: conventionAsset,
            content: any(named: 'content'),
          ),
        ).called(1);
      },
    );

    test(
      'no-ops when the convention asset key already existed in the old '
      'manifest',
      () async {
        final service = BaselineTailoringService(baselineRepository, detector);

        await service.tailorNewlyIntroducedAssets(
          projectId: '1',
          rootPath: tempDir.path,
          oldManifest: manifestWith([conventionAsset], version: '0.2.0'),
          newManifest: manifestWith([conventionAsset], version: '0.3.0'),
        );

        verifyNever(
          () => baselineRepository.writeOverride(
            projectId: any(named: 'projectId'),
            asset: any(named: 'asset'),
            content: any(named: 'content'),
          ),
        );
      },
    );

    test('no-ops when the new asset key is already overridden', () async {
      when(() => baselineRepository.readOverrides('1')).thenAnswer(
        (_) async => const [
          ProjectOverride(
            projectId: '1',
            assetKey: 'conventions/architecture-conventions',
            overridePath: '/tmp/override.md',
          ),
        ],
      );
      final service = BaselineTailoringService(baselineRepository, detector);

      await service.tailorNewlyIntroducedAssets(
        projectId: '1',
        rootPath: tempDir.path,
        oldManifest: manifestWith(const [], version: '0.2.0'),
        newManifest: manifestWith([conventionAsset], version: '0.3.0'),
      );

      verifyNever(
        () => baselineRepository.writeOverride(
          projectId: any(named: 'projectId'),
          asset: any(named: 'asset'),
          content: any(named: 'content'),
        ),
      );
    });

    test(
      'no-ops when no architectureConvention-kind asset was newly '
      'introduced at all',
      () async {
        final service = BaselineTailoringService(baselineRepository, detector);

        await service.tailorNewlyIntroducedAssets(
          projectId: '1',
          rootPath: tempDir.path,
          oldManifest: manifestWith(const [], version: '0.2.0'),
          newManifest: manifestWith(const [
            BaselineAsset(
              key: 'skills/verify',
              kind: BaselineAssetKind.skill,
              bundledPath: 'assets/baseline/0.3.0/skills/verify.md',
            ),
          ], version: '0.3.0'),
        );

        verifyNever(
          () => baselineRepository.writeOverride(
            projectId: any(named: 'projectId'),
            asset: any(named: 'asset'),
            content: any(named: 'content'),
          ),
        );
      },
    );
  });
}
