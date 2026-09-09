# archive (Aion project override)

Aion's own development still has a second, file-based mechanism
alongside its native ticket-driven one: `aion-arch` (a separate,
private companion repository, `aion-workspace/aion-arch/`) — frozen
from further routine use, but still exercised for real ad hoc
investigation/fix work found via `/explore`. This override preserves
that actual mechanics, distinct from the generic ticket-native
`archive` guidance every other project gets.

The final stage of the OpenSpec cycle (`explore → propose → apply →
verify → archive`), run once `/verify` has reported no outstanding
CRITICAL findings. What it does, concretely:

- Merges the change's delta spec (`aion-arch/changes/<name>/specs/spec.md`
  — the ADDED/MODIFIED/REMOVED behaviors) into the matching file(s) under
  `aion-arch/specs/`, precisely rather than overwriting wholesale, so
  unrelated existing facts survive the merge.
- Moves the completed `aion-arch/changes/<name>/` directory to
  `aion-arch/changes/archive/<name>/`.
- Updates the originating idea file under `aion-arch/ideas/` (if one
  exists) to `status: archived`.
- Commits the merged specs/archived-folder move in `aion-arch/` (its own
  git repository, separate from `aion`'s), pushes, and opens a pull
  request in both `aion` and `aion-arch` summarizing what shipped —
  cross-linking each PR to its companion.
- Does not delete the change's branch — that's `/clean-up`'s job, once
  both PRs are merged.

A change is not "done" until archived — an implemented-but-unarchived
change means `aion-arch/specs/` no longer matches reality, which
compounds the next time someone plans against it.
