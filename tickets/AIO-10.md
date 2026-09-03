---
ticketId: AIO-10
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-07-24T00:00:00.000
updatedAt: 2026-07-28T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Baseline version upgrade flow for an existing project

## Key questions asked

1. What should trigger a baseline upgrade check for an existing project —
   an automatic prompt when a newer bundled version becomes available, or
   a manual "check for updates" action the user has to go find?
2. Given potentially multiple registered projects, how should the prompt
   surface across them — lazily per-project on open, or an upfront scan
   of every registered project at once?
3. What should actually happen when the user accepts — a straight
   version-pin bump trusting existing key-matching, or a diff/review step
   showing what changed first?
4. If the user declines, what happens next — re-prompt later, or go
   silent until a manual trigger?
5. When an upgrade introduces brand-new skill assets that didn't exist in
   the project's old pinned version (no override yet), should it also
   tailor those new assets to the project's stack, reusing
   `project-type-aware-conventions-and-verification`'s setup-time
   tailoring mechanism?
6. What happens to an existing override if the new baseline version
   removes the asset key it was shadowing entirely?

## Summary of answers

1. **Prompt when updating to a newer version** — surfaced when Aion
   itself has shipped a newer bundled baseline, not a background poll or
   a purely manual action.
2. **Lazy, per-project on open** — the prompt appears the first time each
   project is switched into/opened after the app update, one at a time.
   No upfront scan/summary across every registered project.
3. **Straight version bump** — just updates `baselineVersion` in the
   registry DB + `.aion/manifest.json`. Existing `ProjectOverride` files
   keep applying automatically since they shadow by asset key,
   independent of version — no migration or review step, trusting the
   already-shipped key-matching mechanism.
4. **Ask again next time** — declining only dismisses that instance; the
   prompt reappears next time the project is opened while a newer version
   is still available. A manual "Upgrade baseline" action in Settings
   also exists for a user who wants to accept without waiting to be asked.
5. **Yes, tailor new assets** — after the version bump, run the same
   tailoring step (template-fill or agentic, per the project's original
   summarization-depth choice) against just the newly-introduced asset
   keys, writing fresh `ProjectOverride` files for them. Keeps a
   long-lived project from falling behind on stack-awareness for new
   baseline content, without re-tailoring assets that already have an
   override.
6. **Leave the file, ignore it** — an orphaned override just stays in
   `<rootPath>/.aion/overrides/` unused, harmless dead weight. No cleanup
   step, no warning — matches the "trust the mechanism, keep it simple"
   posture of the straight-bump decision.

## Conclusions reached

A complete, resolved flow:

- **Trigger:** lazy, per-project — the first time a project is opened
  after Aion itself has shipped a newer bundled baseline than the
  project's pinned `baselineVersion`.
- **Accept:** a straight version-pin bump (registry DB +
  `.aion/manifest.json`), no diff/review UI. Existing overrides keep
  working via existing per-key matching. Newly-introduced skill assets
  (keys with no existing override) get tailored via
  `project-type-aware-conventions-and-verification`'s setup-time
  mechanism as part of accepting the upgrade.
- **Decline:** re-prompts next time the project is opened while a newer
  version remains available. A manual "Upgrade baseline" Settings action
  is always available regardless of prompt history.
- **Removed asset keys:** any override shadowing a key that no longer
  exists in the new version is left in place, unused — no cleanup, no
  warning.

## Open questions

- Where the manual "Upgrade baseline" Settings action lives in the
  existing Settings screen layout — a UI-placement detail, not
  architectural.
- Whether a project mid-upgrade (tailoring new assets) needs any
  progress/loading UI, given the agentic-tailoring path could take real
  time — not raised this session.

## Follow-up session (2026-07-24) — detection mechanism, resolved

Prompted by the user asking whether Aion has any way of knowing a new
version is available via GitHub. Aion isn't distributed yet — the user
has only run dev builds, no GitHub Release or installer exists — so this
resolves cleanly rather than staying open:

- **Detection is purely local, no network/GitHub involved.** "Is a newer
  baseline available" is just comparing the project's pinned
  `baselineVersion` against
  `BundledBaselineRepository.getAvailableBaselineVersions().last`, which
  reads straight from `assets/baseline/` already compiled into the
  currently-running build. Whoever's running a build already has
  whatever's bundled in it — no polling, no release feed, no version
  check against GitHub needed for this mechanism specifically.
- **Real app-distribution/update-checking (GitHub Releases, installers,
  an actual updater) is deliberately out of scope for now** — explicitly
  deferred, not merely unraised. Reasoning: zero installed users exist to
  distribute to yet; building release infrastructure now would be
  speculative work for a stage where Aion is still dev-build-only. Worth
  its own idea once Aion actually ships something installable.

## Architectural implications

- Confirms `Project.baselineVersion`
  (`aion/lib/features/projects/domain/entities/project.dart`) is
  currently write-once with no mutation path anywhere in the codebase —
  this idea adds the first legitimate way to change it post-creation.
- Directly depends on `project-type-aware-conventions-and-verification`
  for the setup-time tailoring mechanism this idea reuses for
  newly-introduced assets — sequencing these two `/propose` cycles
  matters: the tailoring mechanism should exist first, or this idea's
  "tailor new assets on upgrade" piece has nothing to call.
  `project-type-aware-conventions-and-verification` is more foundational
  and already `next_action: /propose`, so it should ship first.
  This idea's own `/propose` should note that dependency explicitly.
  Alternatively, this idea's upgrade-prompt/version-bump mechanism could
  ship independently first (it doesn't strictly need tailoring to exist —
  new asset tailoring can simply be a no-op until the other idea ships),
  with the tailoring integration added once both exist.
- Reuses `storage-model-per-project-scoping`'s pinned + override baseline
  system exactly as designed — this is the first real "pin changes"
  consumer of that architecture beyond initial creation.
- No changes needed to `BaselineAsset`/`ProjectOverride`/
  `BundledBaselineRepository`'s existing read-side logic — this is purely
  a new write path (updating the pinned version) plus a new UI surface
  (the prompt + Settings action), not a new resolution mechanism.