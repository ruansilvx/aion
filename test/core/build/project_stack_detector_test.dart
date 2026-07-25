import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/build/project_stack_detector.dart';

void main() {
  late Directory tempDir;
  late ProjectStackDetector detector;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('stack_detector_test_');
    detector = ProjectStackDetector();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  void createMarker(String fileName) {
    File(
      '${tempDir.path}${Platform.pathSeparator}$fileName',
    ).writeAsStringSync('');
  }

  test('detects Flutter/Dart from pubspec.yaml', () {
    createMarker('pubspec.yaml');
    final detected = detector.detect(tempDir.path);
    expect(detected?.language, 'Flutter/Dart');
    expect(detected?.setupCommand, 'flutter pub get');
    expect(detected?.checkCommand, 'flutter analyze');
  });

  test('detects Node.js from package.json', () {
    createMarker('package.json');
    final detected = detector.detect(tempDir.path);
    expect(detected?.language, 'Node.js');
    expect(detected?.setupCommand, 'npm install');
    expect(detected?.checkCommand, 'npm test');
  });

  test('detects Rust from Cargo.toml with no setup command', () {
    createMarker('Cargo.toml');
    final detected = detector.detect(tempDir.path);
    expect(detected?.language, 'Rust');
    expect(detected?.setupCommand, isNull);
    expect(detected?.checkCommand, 'cargo check');
  });

  test('detects Go from go.mod with no setup command', () {
    createMarker('go.mod');
    final detected = detector.detect(tempDir.path);
    expect(detected?.language, 'Go');
    expect(detected?.setupCommand, isNull);
    expect(detected?.checkCommand, 'go build ./...');
  });

  test('detects Python from pyproject.toml', () {
    createMarker('pyproject.toml');
    final detected = detector.detect(tempDir.path);
    expect(detected?.language, 'Python');
    expect(detected?.setupCommand, 'pip install -e .');
    expect(detected?.checkCommand, 'pytest');
  });

  test('detects Python from requirements.txt', () {
    createMarker('requirements.txt');
    final detected = detector.detect(tempDir.path);
    expect(detected?.language, 'Python');
    expect(detected?.setupCommand, 'pip install -r requirements.txt');
    expect(detected?.checkCommand, 'pytest');
  });

  test('returns null when no known marker file exists', () {
    final detected = detector.detect(tempDir.path);
    expect(detected, isNull);
  });
}
