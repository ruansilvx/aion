import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/build/project_stack_detector.dart';
import 'package:aion/features/projects/data/services/baseline_tailoring_service.dart';
import 'package:aion/features/projects/domain/entities/baseline_asset.dart';
import 'package:aion/features/projects/domain/repositories/baseline_repository.dart';

class MockBaselineRepository extends Mock implements BaselineRepository {}

void main() {
  late MockBaselineRepository baselineRepository;
  late ProjectStackDetector detector;
  late Directory tempDir;

  setUpAll(() {
    registerFallbackValue(
      const BaselineAsset(
        key: 'conventions/architecture-conventions',
        kind: BaselineAssetKind.architectureConvention,
        bundledPath: 'assets/baseline/0.3.0/architecture_convention.md',
      ),
    );
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

  test('no-ops when no stack is detected', () async {
    final service = BaselineTailoringService(baselineRepository, detector);

    await service.tailorForDetectedStack(
      projectId: '1',
      rootPath: tempDir.path,
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
}
