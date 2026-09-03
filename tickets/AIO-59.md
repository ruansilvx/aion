---
ticketId: AIO-59
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
# Repo release setup and distribution (Windows + Linux)

## Key questions asked

1. What's actually motivating this now, given it was explicitly deferred
   in the previous session (`baseline-version-upgrade-flow-for-an-
   existing-project`)?
2. Which platform(s) should the first real release build target?
3. What installer format for each platform, favoring simplicity given no
   CI/signing infra exists yet?
4. Should building/packaging be automated via GitHub Actions on tag
   push, or done manually?
5. Should the app's release version and the baseline version be kept in
   lockstep, or are they independent numbering schemes?
6. Should release notes/changelog be maintained formally, or kept
   lightweight?
7. (Raised mid-session) Can an agentic step handle changelog drafting,
   and if so, where should it run — locally before tagging, or inside
   the CI workflow itself?
8. Should `/prepare-release` also decide the next version number, or
   should the developer always specify it explicitly?
9. (Raised by the user) Should `/prepare-release` read from
   `aion-arch/changes/archive/` — using each archived change's own
   `proposal.md` — as its primary changelog/version-bump source instead
   of raw commit messages, and should each archived change record which
   release it shipped in?
10. Should ad hoc (non-OpenSpec-cycle) fix/chore/refactor commits also be
    scanned and included in the changelog alongside archive-driven
    entries?

## Summary of answers

1. **Want real installable builds for myself/testers** — not preparing
   for public distribution yet, just tired of `flutter run` from source
   being the only way to actually use Aion.
2. **Windows and Linux only**, not macOS (no Mac hardware to build/sign
   on) — the coding-execution differentiator is desktop-only anyway.
3. **Windows: Inno Setup installer** (Start Menu shortcut, uninstaller
   entry — a real installer, not a bare zip). **Linux: AppImage**
   (single portable file, no distro-specific packaging).
4. **GitHub Actions on tag push** — a workflow builds + packages both
   platforms and attaches artifacts to a GitHub Release automatically.
   This also solves cross-building Linux from a Windows dev machine
   (GitHub-hosted `ubuntu-latest` runners build it natively).
5. **Independent** — "usual practice" for a content/config-bundle version
   separate from the app binary's own version (comparable to a mobile
   app's remote-config version vs. its release version): they change at
   different cadences and shouldn't be coupled. Matches how
   `baseline-version-upgrade-flow-for-an-existing-project` already treats
   baseline detection as purely local/independent of any app-version
   concept.
6. **Neither raw GitHub auto-generated notes nor fully hand-written** —
   redirected into an agentic approach (see Q7-10).
7. **Yes, agentic changelog drafting is a good fit — run locally, before
   tagging.** A new skill (e.g. `/prepare-release`) reads history since
   the last tag, drafts the changelog, the developer reviews/edits
   before it's committed and tagged. Rejected running it inside the CI
   workflow itself — that would need model-API credentials in CI and
   would let unreviewed agentic output become a public release's
   permanent notes.
8. **Skill suggests, developer confirms** — not fully manual, not fully
   automatic. Reduces typing without removing the human judgment call
   entirely.
9. **Yes — archive-driven, with explicit release tagging.**
   `/prepare-release` finds every `changes/archive/<name>/` folder
   archived since the last release tag, uses each one's `proposal.md`
   "What"/"Why" as the changelog entry's source (richer than a commit
   message), and suggests a version bump from what kind of changes they
   were (new ticket type/architecture-level change → minor; a
   fix-scoped change → patch). Each archived change's `proposal.md` gets
   a "Shipped in: vX.Y.Z" note added once tagged, so the mapping is
   explicit and never needs to be re-derived from dates.
10. **Yes** — also scans `fix:`/`chore:`/`refactor:` commits since the
    last tag not already covered by an archived change, added as a
    lightweight "Fixes & chores" changelog section, so ad hoc work
    shipped in a release isn't invisible just because it wasn't a full
    OpenSpec cycle.

## Conclusions reached

A complete release pipeline:

- **Scope:** Windows + Linux desktop builds only, for
  developer/tester use — not yet a public-distribution or
  auto-update-checking effort (that remains explicitly deferred, per the
  prior session, until Aion has real installed users).
- **Packaging:** Windows via Inno Setup (a real installer with Start
  Menu/uninstaller entries); Linux via AppImage.
- **CI:** a GitHub Actions workflow triggered on a version-tag push
  builds both platforms and attaches the packaged artifacts to a GitHub
  Release.
- **Versioning:** the app's own release version (git tag / `pubspec.
  yaml`) and the baseline version (`assets/baseline/<version>/`) are
  independent — no coupling, no forced lockstep bump.
- **`/prepare-release` skill (new, local, human-reviewed):**
  1. Finds every `aion-arch/changes/archive/<name>/` folder archived
     since the last release tag.
  2. Drafts a changelog entry per change from its `proposal.md`
     "What"/"Why," plus a "Fixes & chores" section from any
     `fix:`/`chore:`/`refactor:` commits since the last tag not already
     covered by one of those archived changes.
  3. Suggests a semver bump (patch/minor/major) based on what kind of
     changes shipped; the developer confirms or overrides.
  4. On confirmation: bumps `pubspec.yaml`, writes the changelog (file
     format TBD — `CHANGELOG.md` vs. directly as the GitHub Release
     body — left for `/propose`), and adds a "Shipped in: vX.Y.Z" note
     to each archived change's `proposal.md`.
  5. The developer then tags and pushes, triggering the CI build/package
     workflow.

## Open questions

- Exact changelog artifact format — a committed `CHANGELOG.md` (Keep-a-
  Changelog style) vs. only ever the GitHub Release body text, vs. both
  — not decided, left for `/propose`'s design.md.
- Where `/prepare-release` lives — likely `aion-arch/.claude/skills/`
  alongside every other skill (per `CLAUDE.md`'s "the Aion app repository
  root intentionally carries no Claude Code configuration of its own"),
  even though it operates on the `aion` repo's own release process
  rather than the OpenSpec SDD cycle — worth confirming explicitly during
  `/propose` since it's a new kind of skill (release tooling, not an SDD
  stage or orientation skill).
- Exact heuristic `/prepare-release` uses to map an archived change's
  content to a suggested semver bump level (e.g. does adding a new
  `TicketType` always count as "minor," does a UI-only change count as
  "patch") — not walked through this session.
- Code-signing/SmartScreen handling for the unsigned Windows Inno Setup
  installer (testers will see a SmartScreen warning) — acceptable for
  now given the "myself/testers" scope, but worth flagging as a known
  rough edge rather than silently ignoring it.
- Whether Linux packaging needs any distro-specific runtime dependency
  bundling beyond what AppImage's `linuxdeploy`-style tooling handles by
  default — not investigated this session.

## Architectural implications

- First real CI/CD surface for the `aion` repo — nothing today
  automates a build/package/publish step; this idea introduces the
  first GitHub Actions workflow with that responsibility.
- `/prepare-release` becomes a new kind of skill distinct from every
  existing one: it operates on release/versioning concerns for the
  `aion` repo itself, not the `aion-arch` OpenSpec SDD cycle it reads
  from — a new category alongside "SDD-stage skills" and "orientation
  skills" in `CLAUDE.md`'s taxonomy.
- Establishes "Shipped in: vX.Y.Z" as a new convention on archived
  changes' `proposal.md` files — `/archive` itself doesn't write this
  (it doesn't know the eventual release version at archive time);
  `/prepare-release` writes it retroactively once a release is actually
  cut. Worth noting in `aion-arch-workflow.md` once built, so future
  agents don't mistake it for something `/archive` should have done.
- Confirms and reinforces `baseline-version-upgrade-flow-for-an-existing-
  project`'s existing assumption that baseline-version detection stays
  purely local and independent of the app's own version scheme — this
  idea makes that independence an explicit, intentional decision rather
  than one just implied by the baseline idea's own resolution.
- Explicitly does not build any GitHub-Releases-polling/auto-update-
  checking mechanism — that remains deferred per the prior session;
  this idea only produces the releases, it doesn't make Aion aware of
  them.