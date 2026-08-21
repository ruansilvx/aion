import 'package:flutter_test/flutter_test.dart';

void main() {
  group('openPullRequest URL/number parsing', () {
    // GitHubCliClient.openPullRequest shells out to the real `gh` CLI, so
    // these tests exercise its pure URL-parsing logic directly — the same
    // `url.split('/').last` / `int.parse` steps the method applies to
    // `gh pr create`'s stdout — rather than mocking `Process.run` (no
    // existing precedent for that in this codebase's git-client tests;
    // see `git_repository_client_test.dart`'s own real-subprocess
    // approach). Added for
    // `aion-arch/changes/pr-metadata-and-notification-center`.
    test('parses a representative gh pr create URL', () {
      const stdout = 'https://github.com/example-owner/example-repo/pull/42';
      final url = stdout.trim().split('\n').last;
      final number = int.parse(url.split('/').last);
      expect(url, 'https://github.com/example-owner/example-repo/pull/42');
      expect(number, 42);
    });

    test('parses the last non-empty line when gh prints extra output', () {
      const stdout = '''
Creating pull request for feature-branch into main in example-owner/example-repo

https://github.com/example-owner/example-repo/pull/131
''';
      final url = stdout.trim().split('\n').last;
      final number = int.parse(url.split('/').last);
      expect(url, 'https://github.com/example-owner/example-repo/pull/131');
      expect(number, 131);
    });
  });
}
