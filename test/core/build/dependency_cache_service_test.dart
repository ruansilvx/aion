// test/core/build/dependency_cache_service_test.dart — DependencyCacheService tests.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:aion/core/build/dependency_cache_service.dart';

void main() {
  late Directory tempDir;
  late DependencyCacheService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dep_cache_test_');
    service = const DependencyCacheService();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('seed', () {
    test('no-ops when the cache dir doesn\'t exist', () async {
      final cacheDir = p.join(tempDir.path, 'cache');
      final targetDir = p.join(tempDir.path, 'target');
      await Directory(targetDir).create(recursive: true);

      await service.seed(cacheDir, targetDir);

      expect(Directory(targetDir).listSync(), isEmpty);
    });

    test('copies a populated cache dir\'s contents, nested dirs included', () async {
      final cacheDir = p.join(tempDir.path, 'cache');
      final targetDir = p.join(tempDir.path, 'target');
      await Directory(p.join(cacheDir, 'nested')).create(recursive: true);
      File(p.join(cacheDir, 'top.txt')).writeAsStringSync('top');
      File(p.join(cacheDir, 'nested', 'inner.txt')).writeAsStringSync('inner');

      await service.seed(cacheDir, targetDir);

      expect(File(p.join(targetDir, 'top.txt')).readAsStringSync(), 'top');
      expect(
        File(p.join(targetDir, 'nested', 'inner.txt')).readAsStringSync(),
        'inner',
      );
    });
  });

  group('writeBack', () {
    test('replaces stale cache contents rather than merging with them', () async {
      final sourceDir = p.join(tempDir.path, 'source');
      final cacheDir = p.join(tempDir.path, 'cache');
      await Directory(cacheDir).create(recursive: true);
      File(p.join(cacheDir, 'stale.txt')).writeAsStringSync('stale');
      await Directory(sourceDir).create(recursive: true);
      File(p.join(sourceDir, 'fresh.txt')).writeAsStringSync('fresh');

      await service.writeBack(sourceDir, cacheDir);

      expect(File(p.join(cacheDir, 'fresh.txt')).readAsStringSync(), 'fresh');
      expect(File(p.join(cacheDir, 'stale.txt')).existsSync(), isFalse);
    });
  });

  group('cacheDirFor', () {
    test('produces the expected path shape', () {
      final result = service.cacheDirFor('proj-123', 'node_modules');

      expect(
        result,
        p.join(
          Directory.systemTemp.path,
          'aion_dep_cache',
          'proj-123',
          'node_modules',
        ),
      );
    });
  });
}
