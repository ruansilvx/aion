import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/git/gitignore_editor.dart';

void main() {
  late Directory tempDir;
  late GitignoreEditor editor;
  late File gitignoreFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gitignore_editor_test_');
    editor = GitignoreEditor();
    gitignoreFile = File(
      '${tempDir.path}${Platform.pathSeparator}.gitignore',
    );
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('creates .gitignore with the given entries when absent', () async {
    await editor.ensureIgnored(tempDir.path, ['.aion/', 'tickets/']);

    expect(gitignoreFile.existsSync(), isTrue);
    final lines = gitignoreFile.readAsStringSync().split('\n');
    expect(lines, containsAll(['.aion/', 'tickets/']));
  });

  test('appends missing entries to an existing .gitignore', () async {
    gitignoreFile.writeAsStringSync('node_modules/\n');

    await editor.ensureIgnored(tempDir.path, ['.aion/', 'tickets/']);

    final lines = gitignoreFile.readAsStringSync().split('\n');
    expect(lines, containsAll(['node_modules/', '.aion/', 'tickets/']));
  });

  test('is idempotent when every entry is already present', () async {
    gitignoreFile.writeAsStringSync('.aion/\ntickets/\n');
    final before = gitignoreFile.readAsStringSync();

    await editor.ensureIgnored(tempDir.path, ['.aion/', 'tickets/']);

    final after = gitignoreFile.readAsStringSync();
    expect(after, before);
  });

  test('only appends entries that are missing from a mixed file', () async {
    gitignoreFile.writeAsStringSync('.aion/\nbuild/\n');

    await editor.ensureIgnored(tempDir.path, ['.aion/', 'tickets/']);

    final lines = gitignoreFile.readAsStringSync().split('\n');
    expect(lines, containsAll(['.aion/', 'build/', 'tickets/']));
    expect('tickets/'.allMatches(gitignoreFile.readAsStringSync()).length, 1);
  });

  test('appends on a new line when the existing file has no trailing newline', () async {
    gitignoreFile.writeAsStringSync('node_modules/');

    await editor.ensureIgnored(tempDir.path, ['.aion/']);

    final lines = gitignoreFile.readAsStringSync().split('\n');
    expect(lines, containsAll(['node_modules/', '.aion/']));
  });
}
