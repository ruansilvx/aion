// test/core/agent/agent_bridge_locator_test.dart — AgentBridgeLocator tests.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:aion/core/agent/agent_bridge_locator.dart';

void main() {
  group('AgentBridgeLocator', () {
    late Directory tempRoot;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync(
        'agent_bridge_locator_test_',
      );
    });

    tearDown(() {
      tempRoot.deleteSync(recursive: true);
    });

    /// Builds `<tempRoot>/<subdirs...>` and returns its path — mirrors a
    /// real project checkout's directory nesting for each test case
    /// below.
    String makeDir(List<String> subdirs) {
      final dir = Directory(p.joinAll([tempRoot.path, ...subdirs]));
      dir.createSync(recursive: true);
      return dir.path;
    }

    void writeBridgeScript(String projectDir) {
      File(
        p.join(projectDir, 'agent_bridge', 'index.mjs'),
      ).createSync(recursive: true);
    }

    test(
      'resolves via Directory.current when it is the project root '
      '(the flutter run case) even if the executable lives elsewhere',
      () {
        final projectDir = makeDir(['aion']);
        writeBridgeScript(projectDir);
        final elsewhereExe = p.join(makeDir(['elsewhere']), 'aion.exe');

        final locator = AgentBridgeLocator(
          currentDirectory: projectDir,
          executablePath: elsewhereExe,
        );

        expect(
          locator.resolve(),
          p.join(projectDir, 'agent_bridge', 'index.mjs'),
        );
      },
    );

    test(
      'resolves by walking up from the executable directory when '
      'Directory.current is NOT the project root (a desktop shortcut, '
      "Start Menu entry, or any launch method that doesn't happen to "
      'match flutter run\'s cwd)',
      () {
        final projectDir = makeDir(['aion']);
        writeBridgeScript(projectDir);
        // Mirrors Windows' build/windows/x64/runner/Release/ nesting:
        // 4 levels below the project root.
        final exeDir = makeDir([
          'aion',
          'build',
          'windows',
          'x64',
          'runner',
          'Release',
        ]);
        final exePath = p.join(exeDir, 'aion.exe');
        // Simulates a launch from an unrelated working directory, e.g.
        // a shell sitting in the parent workspace folder.
        final unrelatedCwd = makeDir(['unrelated_launch_cwd']);

        final locator = AgentBridgeLocator(
          currentDirectory: unrelatedCwd,
          executablePath: exePath,
        );

        expect(
          locator.resolve(),
          p.join(projectDir, 'agent_bridge', 'index.mjs'),
        );
      },
    );

    test(
      'reproduces the exact bug found live: launched from the parent '
      "workspace folder (one level above the project root) — cwd's own "
      'agent_bridge/ does not exist, only the ancestor walk finds the '
      'real one',
      () {
        // <tempRoot>/aion-workspace/aion/agent_bridge/index.mjs
        final projectDir = makeDir(['aion-workspace', 'aion']);
        writeBridgeScript(projectDir);
        final workspaceRoot = p.dirname(projectDir);
        final exeDir = makeDir([
          'aion-workspace',
          'aion',
          'build',
          'windows',
          'x64',
          'runner',
          'Release',
        ]);
        final exePath = p.join(exeDir, 'aion.exe');

        final locator = AgentBridgeLocator(
          // cwd = the workspace root, one level too high — exactly the
          // launch that produced "Cannot find module
          // '...\aion-workspace\agent_bridge\index.mjs'" live.
          currentDirectory: workspaceRoot,
          executablePath: exePath,
        );

        expect(
          locator.resolve(),
          p.join(projectDir, 'agent_bridge', 'index.mjs'),
        );
      },
    );

    test(
      'falls back to the Directory.current candidate when no real '
      'agent_bridge/index.mjs exists anywhere on the walk, rather than '
      'throwing — so the caller still gets a nameable path to report',
      () {
        final cwd = makeDir(['nowhere_near_a_checkout']);
        final exePath = p.join(makeDir(['also_nowhere']), 'aion.exe');

        final locator = AgentBridgeLocator(
          currentDirectory: cwd,
          executablePath: exePath,
        );

        expect(locator.resolve(), p.join(cwd, 'agent_bridge', 'index.mjs'));
      },
    );
  });
}
