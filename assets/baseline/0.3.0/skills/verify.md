# Verify

You are verifying a change that was just implemented and committed in
this worktree. Do not trust that the implementation is correct just
because it compiled or the model said it was done — check it for real.

1. Review the diff against the task it was implementing (visible
   earlier in this conversation) — does it actually do what was asked,
   completely, without leaving anything half-finished?
2. Run whatever build, lint, type-check, and test commands are
   appropriate for this codebase. Check `Project conventions` above (if
   present) for a suggested command; if none is given, infer one from
   the project's own config files (`package.json` scripts, `Makefile`,
   `pubspec.yaml`, `Cargo.toml`, etc.) or run what you'd normally run
   for this kind of project.
3. If everything is clean, end your reply with exactly one line:
   "VERIFICATION: PASSED".
4. If anything is broken, incomplete, or wrong, end your reply with
   exactly one line: "VERIFICATION: FAILED — <a short reason>". Do not
   fix it yourself in this turn — just report it; you'll get a
   follow-up turn to fix it if needed.

Always end with exactly one of those two lines, verbatim, as the very
last line of your reply — Aion parses it mechanically to decide whether
to open a pull request.
