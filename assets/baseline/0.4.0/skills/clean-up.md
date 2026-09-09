# clean-up

Post-merge housekeeping, run once a change's pull request(s) — opened by
`archive` — have actually been merged upstream. Not part of the SDD
cycle itself (`explore → propose → apply → verify → archive`); it's the
step after the cycle's own record-keeping is done, syncing the local
working copy back up with the now-updated shared history.

What it does: checks out each affected repository's default branch and
pulls the latest changes, so the next cycle starts from a clean,
up-to-date base rather than an ancestor branch that's now behind.

Skipping this doesn't corrupt anything, but starting the next `propose`
from a stale branch risks basing new work on code that's already been
superseded — small friction now versus a messier merge later.
