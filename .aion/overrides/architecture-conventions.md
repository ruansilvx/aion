# Architecture conventions

Detected stack: Flutter/Dart.

## Build/verification commands

Run, in order:

1. `flutter pub get`
2. `flutter analyze` — must report 0 issues. Do not open a pull request or
   report success with any outstanding analyzer issue, even one that looks
   pre-existing or unrelated to this task.
3. `flutter test` — the full suite must pass, not just newly-added tests.
   A task is not done if it makes any previously-passing test fail.

## Test coverage

Every task needs real test coverage added alongside its implementation, not
just the implementation itself — a unit test, `blocTest` (for a
Cubit/Bloc), or widget test as appropriate to what changed. Match the
existing test's shape for similar code in this codebase rather than
inventing a new pattern. A task is not complete without its own test(s)
passing as part of the full suite run above.

## Documentation

Every public Dart symbol you add or touch needs a dartdoc (`///`) comment.
Every new file under `lib/` needs a one-line header comment stating its
contents and layer (see existing files for the pattern). This is part of
the task itself, not a follow-up.

## Formatting

Only format the lines you actually changed. Do not run `dart format`
across an entire file or the repository — this codebase's committed
formatting has drifted from canonical `dart_style` output in places, and a
blanket format will rewrite large numbers of unrelated lines, making the
diff impossible to review. If you need to discard a bad edit and restore a
file to its committed state, use `git checkout <branch> -- <file>` — never
`git show <ref>:<file>` piped/redirected to the file, which strips CRLF
line endings on Windows checkouts.

## Design system

Aion's UI is non-Material by design. Do not import
`package:flutter/material.dart` or use Material widgets (`Card`,
`ElevatedButton`, `Scaffold`, `ThemeData`, etc.) in presentation code. Use
this project's own design tokens and widgets instead — check sibling
files in the same feature for the established pattern.

## Layering

Presentation-layer code must not import data-layer classes directly — go
through the domain-layer repository interfaces. Follow this project's
existing Cubit/Bloc state-management pattern rather than introducing a
different one.