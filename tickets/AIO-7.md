---
ticketId: AIO-7
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-09-02T00:00:00.000
updatedAt: 2026-09-02T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Aion-native release preparation and tag management

## Propose stage (2026-09-02)

`/explore` (this same day) confirmed the idea's premises against the real
codebase — `ProjectStackDetector` is genuinely guidance-only today,
per-phase model routing is real (not aspirational), and
`TicketLinkRepository`/`GitRepositoryClient` already have everything
needed except tag creation. `/propose` turned that into
`aion-arch/changes/release-preparation-and-tagging/` — see that change's
`proposal.md`/`design.md` for the concrete architecture. One decision
that the brainstorm left open got settled during drafting: auto mode's
entry point is a new "Cut a release" card on the Inbox screen (inside
`features/tickets/`), not a Project Settings entry — a Settings-screen
placement would have needed a cross-feature import into `TicketsCubit`,
which `project.md`'s hard cross-feature-import rule forbids.

## Key questions asked

1. Is this meant to be Aion managing its own releases only (self-hosting,
   replacing `/prepare-release` 1:1), or a generic capability for any
   project Aion manages?
2. Should changelog/version-bump drafting keep `/prepare-release`'s
   AI-drafted quality (via Aion's own model routing), or become fully
   deterministic with no model involved?
3. Should Aion autonomously decide when to cut a release and push the
   tag, or draft everything and wait for explicit confirmation before
   pushing?
4. Should this idea take on extending `ProjectStackDetector` into a
   real, code-consumed signal for stack-aware version-file handling, or
   scope v1 to Flutter/`pubspec.yaml` only (Aion's own dogfood target)?
5. Should this surface as an action on the `release` ticket itself, or
   as a separate standalone flow (e.g. Project Settings)?
6. (Raised by the user, after the conclusion above) A curated `release`
   ticket fits a planned release, but what about a minor/patch release —
   e.g. pushing one bug fix and cutting a new build? Would that require
   creating a new `release` ticket every time, or should there be a
   lighter path?
7. In curated mode, can the `release` ticket be pre-populated with its
   linked work — starting from the existing Release Planning inbox
   chat, or from something on the release ticket itself?

## Summary of answers

1. **Generic for any project, including Aion itself.** Not a
   self-hosting-only feature.
2. **Keep the AI-drafted quality**, using Aion's own already-provider-
   agnostic model routing — not a deterministic algorithm.
3. **Confirm before pushing.** Draft everything (changelog, version
   bump, tag), but the user must explicitly confirm before the tag is
   actually created and pushed — no full automation of the trigger
   itself.
4. **Extend `ProjectStackDetector`.** Take this on as part of the same
   effort rather than deferring to a Flutter-only v1.
5. **On the `release` ticket itself** — not a separate standalone flow.
6. **Auto mode — keep patch releases lightweight.** Rather than forcing
   a hand-curated `release` ticket for every patch, "Prepare Release"
   also supports auto-creating/populating one from everything merged
   since the last tag, no manual curation required.
7. **The existing Release Planning inbox chat already covers this** —
   confirmed no new pre-population mechanism is needed. Curated-mode
   population is what that chat already does today (converse about
   which tickets belong, create the `release` ticket, link each one on
   the terminal marker). No separate release-ticket-screen pre-
   population action was requested once this was pointed out.

## Conclusions reached

- Build a new, generic, Aion-native capability that fully replaces
  reliance on `/prepare-release` for drafting a release, for any
  project Aion manages (Aion included).
- Surfaces as an action on a `release` ticket (e.g. "Prepare Release"),
  in two modes:
  - **Curated** — a manually-built `release` ticket with deliberate
    `relatesTo` links to the `epic`/`story`/`task`/`bug` tickets that
    belong in a planned minor/major release. Closes the existing "no
    dedicated assign-to-release UI" gap and realizes the "future
    `create_release` tool" `aion-arch/specs/tickets.md`'s gap section
    already flagged as inevitable but undone.
  - **Auto** — for a lightweight patch release (e.g. one bug fix), Aion
    auto-creates and populates a `release` ticket from everything
    merged since the last tag, mirroring `/prepare-release`'s existing
    pull-based default (it already looks backward at every archived
    change plus ad hoc `fix:`/`chore:`/`refactor:` commits since the
    last tag, rather than requiring a pre-declared bundle). No manual
    curation required for this path.
- Curated mode's ticket population is the existing Release Planning
  inbox chat (`InboxCubit.startReleasePlanning()`) — no new
  pre-population mechanism is needed. That chat already converses about
  which tickets belong, creates the `release` ticket, and links each
  one on the terminal `RELEASE PLAN: DONE` marker. "Prepare Release" on
  the ticket screen is the next step after that chat has already
  populated it (or after auto mode populated it, or after manual
  `TicketLinkPicker` edits) — not a competing population path.
- Drafts changelog prose and suggests a semver bump using Aion's own
  per-project model routing (`providers.md`) — the same AI-drafted
  quality bar `/prepare-release` has today, not a fixed/deterministic
  algorithm, so the feature stays genuinely useful rather than
  degrading to raw ticket-title concatenation.
- Requires extending `ProjectStackDetector` (today guidance-text-only —
  per `projects.md`, "never a value Aion's own code runs or enforces")
  into a real, programmatically-consumed signal, so the feature knows
  which version file/field to bump per detected stack (`pubspec.yaml`
  `version:`, `package.json` `version`, `Cargo.toml` `[package]
  version`, etc.). A concrete, not-yet-built dependency this idea takes
  on directly rather than deferring.
- Creates and pushes the actual git tag using Aion's existing git/PR
  tooling (already proven via the coding-execution → `git push` → real
  `gh pr create` path), but only after the user explicitly confirms the
  drafted changelog/version — never autonomously, matching
  `/prepare-release`'s existing "skill suggests, developer confirms"
  pattern and Aion's broader gated-confirmation precedent for
  consequential git actions.
- Once built, this lets Aion prepare and tag its own future releases
  too, superseding `/prepare-release` for that purpose — though this
  idea doesn't itself delete that skill; that's a natural follow-on for
  whoever picks this up.

## Open questions

- Whether Aion should also help scaffold a new project's own CI
  reaction to a pushed tag (building/packaging/publishing), or whether
  this idea stops entirely at preparing content and creating/pushing
  the tag itself, leaving "what (if anything) reacts to the tag" out of
  scope. Not discussed this session.
- Whether `/prepare-release` (the Claude Code skill) should be formally
  deprecated/removed once this ships, and how that interacts with
  [[decommission-aion-arch-cli-workflow]]'s already-resolved six-step
  retirement plan for aion-arch's CLI-driven workflow — that plan
  doesn't currently name `/prepare-release` in its scope. Left for
  `/propose` or a follow-up brainstorm.
- Whether extending `ProjectStackDetector` for this purpose should live
  entirely inside this change, or get carved out as its own smaller
  prerequisite idea/change, given
  [[project-type-aware-conventions-and-verification]] already
  established the detector and override mechanism this would build on.

## Architectural implications

- Extends `ProjectStackDetector` (`projects.md`) from a guidance-text-
  only tool into genuine programmatic infrastructure — the first thing
  in Aion's own code that actually reads and acts on detected-stack
  output, not just feeds it into a model prompt.
- Extends the `release` ticket type's UI (`tickets.md`) with a new
  action, closing the existing "no dedicated assign-to-release UI" gap
  and realizing the "future `create_release` tool" the gap section
  already anticipated.
- Reuses Aion's existing git/PR-pushing infrastructure (proven via
  coding execution's `git push` → `gh pr create` path) for a new
  purpose: tag creation and push.
- Reuses Aion's existing per-project, per-phase model routing
  (`providers.md`) rather than introducing any new provider/model-
  selection mechanism.
- Once shipped, positions Aion to prepare and tag its own future
  releases, closing the loop this session's earlier idea
  ([[release-pipeline-dry-run-via-tag-push]]) opened — though that
  idea's own manual dry run remains a valid, much smaller near-term
  action independent of this larger build.
- Bears directly on [[decommission-aion-arch-cli-workflow]]'s broader
  theme of migrating Claude-Code-tied tooling into ticket-native Aion
  mechanisms, even though `/prepare-release` isn't explicitly in that
  idea's current scope.