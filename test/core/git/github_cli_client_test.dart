// test/core/git/github_cli_client_test.dart — GitHubCliClient tests.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/git/github_cli_client.dart';

void main() {
  group('openPullRequest', () {
    /// The most recent invocation's arguments — captured by the fake
    /// [ProcessRunner], asserted where a test cares about exactly what
    /// was shelled out to `gh`.
    late String capturedExecutable;
    late List<String> capturedArguments;
    late String? capturedWorkingDirectory;

    GitHubCliClient buildClient(String stdout, {int exitCode = 0}) {
      return GitHubCliClient(
        processRunner: (executable, arguments, {workingDirectory}) async {
          capturedExecutable = executable;
          capturedArguments = arguments;
          capturedWorkingDirectory = workingDirectory;
          return ProcessResult(0, exitCode, stdout, '');
        },
      );
    }

    test(
      'shells out to `gh pr create --title ... --body ... --head ...` in '
      'rootPath, and parses the URL/number from stdout',
      () async {
        final client = buildClient(
          'https://github.com/example-owner/example-repo/pull/42',
        );

        final result = await client.openPullRequest(
          rootPath: '/fake/worktree',
          branch: 'aion/task-1',
          title: 'Fix the thing',
          body: 'Implements "Fix the thing" via Aion coding execution.',
        );

        expect(capturedExecutable, 'gh');
        expect(capturedArguments, [
          'pr',
          'create',
          '--title',
          'Fix the thing',
          '--body',
          'Implements "Fix the thing" via Aion coding execution.',
          '--head',
          'aion/task-1',
        ]);
        expect(capturedWorkingDirectory, '/fake/worktree');
        expect(
          result.url,
          'https://github.com/example-owner/example-repo/pull/42',
        );
        expect(result.number, 42);
      },
    );

    test(
      'parses the last non-empty line when gh prints extra output before '
      'the URL',
      () async {
        final client = buildClient('''
Creating pull request for feature-branch into main in example-owner/example-repo

https://github.com/example-owner/example-repo/pull/131
''');

        final result = await client.openPullRequest(
          rootPath: '/fake/worktree',
          branch: 'aion/task-2',
          title: 'Title',
          body: 'Body',
        );

        expect(
          result.url,
          'https://github.com/example-owner/example-repo/pull/131',
        );
        expect(result.number, 131);
      },
    );

    test(
      'throws a ProcessException on a non-zero exit code, with stderr as '
      'the message',
      () async {
        final client = GitHubCliClient(
          processRunner: (executable, arguments, {workingDirectory}) async {
            return ProcessResult(0, 1, '', 'gh: not authenticated');
          },
        );

        await expectLater(
          () => client.openPullRequest(
            rootPath: '/fake/worktree',
            branch: 'aion/task-3',
            title: 'Title',
            body: 'Body',
          ),
          throwsA(
            isA<ProcessException>().having(
              (e) => e.message,
              'message',
              'gh: not authenticated',
            ),
          ),
        );
      },
    );
  });
}
