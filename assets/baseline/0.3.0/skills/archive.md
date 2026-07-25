# archive

The final stage of the SDD cycle (`explore → propose → apply → verify →
archive`), run once `verify` has reported no outstanding critical
findings. Closes the loop between a change and the project's permanent
record of how the system actually behaves.

What it does:

- Merges the change's delta spec (the ADDED/MODIFIED/REMOVED behaviors
  from `spec.md`) into the project's current-state specification, so
  that document stays an accurate description of the system as it
  exists today — not just a historical log of proposals.
- Moves the completed change's folder into an `archive/` location,
  keeping it for history without leaving it mixed in with active work.
- If the project's workflow uses pull requests, opens one (or more, if
  the change spans multiple repositories) summarizing what shipped.

A change is not "done" until it's archived — an implemented-but-
unarchived change means the project's spec no longer matches reality,
which compounds the next time someone tries to plan against it.
