import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show CachingAssetBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/features/projects/data/repositories/bundled_baseline_repository.dart';
import 'package:aion/features/projects/domain/entities/baseline_asset.dart';
import 'package:aion/features/projects/domain/entities/project.dart';
import 'package:aion/features/projects/domain/repositories/project_repository.dart';

class MockProjectRepository extends Mock implements ProjectRepository {}

/// A minimal in-memory [AssetBundle] serving a fixed manifest string at
/// `assets/baseline/0.1.0/manifest.json`, so this test doesn't depend on
/// the real bundled asset or a running Flutter engine's asset resolver.
class _FakeAssetBundle extends CachingAssetBundle {
  _FakeAssetBundle(this._manifestJson);

  final String _manifestJson;

  @override
  Future<ByteData> load(String key) async {
    if (key == 'assets/baseline/0.1.0/manifest.json') {
      final bytes = utf8.encode(_manifestJson);
      return ByteData.view(Uint8List.fromList(bytes).buffer);
    }
    throw FlutterError('Unexpected asset key: $key');
  }
}

void main() {
  late MockProjectRepository projectRepository;
  late Directory tempDir;

  const manifestJson = '''
  {
    "version": "0.1.0",
    "assets": [
      { "key": "skills/propose", "kind": "skill", "bundledPath": "assets/baseline/0.1.0/skills/propose.md" },
      { "key": "config/model-config", "kind": "modelConfig", "bundledPath": "assets/baseline/0.1.0/model_config.json" }
    ]
  }
  ''';

  setUp(() async {
    projectRepository = MockProjectRepository();
    tempDir = await Directory.systemTemp.createTemp('baseline_repo_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('getAvailableBaselineVersions', () {
    test('returns the single bundled version', () async {
      final repository = BundledBaselineRepository(
        projectRepository,
        bundle: _FakeAssetBundle(manifestJson),
      );

      expect(await repository.getAvailableBaselineVersions(), ['0.1.0']);
    });
  });

  group('getManifest', () {
    test('parses the bundled manifest into BaselineAsset entities', () async {
      final repository = BundledBaselineRepository(
        projectRepository,
        bundle: _FakeAssetBundle(manifestJson),
      );

      final manifest = await repository.getManifest('0.1.0');

      expect(manifest.version, '0.1.0');
      expect(manifest.assets, hasLength(2));
      expect(manifest.assets.first.key, 'skills/propose');
      expect(manifest.assets.first.kind, BaselineAssetKind.skill);
      expect(manifest.assets.last.kind, BaselineAssetKind.modelConfig);
    });

    test('throws for a version not bundled in this app build', () async {
      final repository = BundledBaselineRepository(
        projectRepository,
        bundle: _FakeAssetBundle(manifestJson),
      );

      expect(
        () => repository.getManifest('9.9.9'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('readOverrides', () {
    test('returns an empty list when the project has no rootPath '
        '(mobile/web)', () async {
      final project = Project(
        id: '1',
        name: 'Mobile Project',
        storageKey: '1',
        baselineVersion: '0.1.0',
        createdAt: DateTime(2026, 1, 1),
        lastOpenedAt: DateTime(2026, 1, 1),
      );
      when(
        () => projectRepository.getProject('1'),
      ).thenAnswer((_) async => project);
      final repository = BundledBaselineRepository(
        projectRepository,
        bundle: _FakeAssetBundle(manifestJson),
      );

      expect(await repository.readOverrides('1'), isEmpty);
    });

    test('returns an empty list when the overrides directory does not '
        'exist', () async {
      final project = Project(
        id: '1',
        name: 'Desktop Project',
        storageKey: '1',
        rootPath: tempDir.path,
        baselineVersion: '0.1.0',
        createdAt: DateTime(2026, 1, 1),
        lastOpenedAt: DateTime(2026, 1, 1),
      );
      when(
        () => projectRepository.getProject('1'),
      ).thenAnswer((_) async => project);
      final repository = BundledBaselineRepository(
        projectRepository,
        bundle: _FakeAssetBundle(manifestJson),
      );

      expect(await repository.readOverrides('1'), isEmpty);
    });

    test('lists override files under .aion/overrides, keyed by file '
        'name without extension', () async {
      final project = Project(
        id: '1',
        name: 'Desktop Project',
        storageKey: '1',
        rootPath: tempDir.path,
        baselineVersion: '0.1.0',
        createdAt: DateTime(2026, 1, 1),
        lastOpenedAt: DateTime(2026, 1, 1),
      );
      when(
        () => projectRepository.getProject('1'),
      ).thenAnswer((_) async => project);
      final overridesDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}.aion${Platform.pathSeparator}overrides',
      )..createSync(recursive: true);
      File(
        '${overridesDir.path}${Platform.pathSeparator}propose.md',
      ).writeAsStringSync('custom propose skill');

      final repository = BundledBaselineRepository(
        projectRepository,
        bundle: _FakeAssetBundle(manifestJson),
      );
      final overrides = await repository.readOverrides('1');

      expect(overrides, hasLength(1));
      expect(overrides.first.assetKey, 'propose');
      expect(overrides.first.projectId, '1');
    });
  });
}
