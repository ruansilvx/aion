// test/core/build/mechanical_verification_runner_test.dart — MechanicalVerificationRunner tests.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/build/mechanical_verification_runner.dart';

void main() {
  late Directory tempDir;
  late MechanicalVerificationRunner runner;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mech_verify_test_');
    runner = const MechanicalVerificationRunner();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'every command exiting 0 returns one passing result each, in order',
    () async {
      final results = await runner.run([
        'dart --version',
        'dart --version',
      ], tempDir.path);

      expect(results, hasLength(2));
      expect(results.every((r) => r.passed), isTrue);
      expect(results.map((r) => r.command), [
        'dart --version',
        'dart --version',
      ]);
    },
  );

  test(
    'a failing command stops the chain — later commands never run',
    () async {
      final results = await runner.run([
        'dart pub this-subcommand-does-not-exist',
        'dart --version',
      ], tempDir.path);

      expect(results, hasLength(1));
      expect(results.single.passed, isFalse);
      expect(results.single.command, 'dart pub this-subcommand-does-not-exist');
      expect(results.single.exitCode, isNot(0));
    },
  );

  test('a failing result carries captured output', () async {
    final results = await runner.run([
      'dart pub this-subcommand-does-not-exist',
    ], tempDir.path);

    expect(results.single.output, isNotEmpty);
  });
}
