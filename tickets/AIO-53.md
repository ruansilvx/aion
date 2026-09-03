---
ticketId: AIO-53
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-07-24T00:00:00.000
updatedAt: 2026-07-25T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Project-type-aware conventions, verification, and skill tailoring

## Correction (2026-07-25, during `/propose`)

Q1's resolution below ("user-configured command," a generic
`ProcessVerifier`) was built out in this idea's first `/propose` pass,
then reverted during review: it conflicted with Aion's own architecture,
where "verify" already names the `/verify` OpenSpec skill — an agentic
review, not a shell invocation — and that skill is exactly the
`skills/verify` baseline asset this idea's Q4 resolution already commits
to making stack-agnostic. The two gaps in this idea's `summary` are the
same gap: the coding-execution verify step now runs `skills/verify`'s
effective content as a model turn (the model uses its own tool access to
check the codebase, however that codebase is actually built/linted/
tested), instead of Aion's own Dart code running a project-configured
command. `Project` gains no new fields; there is no per-project verify-
command setting. See `aion-arch/changes/project-type-aware-conventions-
and-verification/proposal.md`'s "Revision note" and design.md §2/§5 for
the corrected design — the rest of this file (Q1's "Summary of answers"
and "Architectural implications" mentioning `ProcessVerifier`/
`FlutterVerifier`'s "properties... to relearn per language") is kept
as-is below for the historical record of how the session actually went,
not as a currently-accurate description of the shipped design.

## Key questions asked

1. How should the coding-execution verify gate work for a non-Flutter
   attached project, given `FlutterVerifier` is a hardcoded concrete
   class today, not a baseline asset?
2. When does a project's verify command get set — mandatory at
   creation/attach, or an optional Settings field with the gate skipped
   if unset?
3. Should the verify-command field be pre-filled via lightweight
   marker-file detection, or always start blank?
4. (Raised by the user, redirecting Q3) The bundled `skills/*` assets are
   pointers into `aion-arch/.claude/skills/`, not self-contained content
   — should the generic baseline be a fresh, stack-agnostic skill set, or
   a mechanically-stripped-down version of aion-arch's own skills?
5. Should setup-time tailoring generate real `ProjectOverride` files, and
   should later manual editing reuse that same mechanism — i.e. does this
   idea resolve `projects.md`'s already-known "Override-authoring UI" gap
   rather than needing something new?
6. How does setup-time tailoring actually produce override content —
   template substitution, always agentic, or tied to the codebase-
   summarization depth choice already decided in `new-project-onboarding`?

## Summary of answers

1. **User-configured command** — a project-level setting stores an
   arbitrary verify command (`flutter analyze`, `npm run lint && npm
   test`, `cargo check`, ...) that a generic `ProcessVerifier` runs in the
   worktree. `FlutterVerifier`'s current behavior becomes the pre-filled
   suggestion for a detected Flutter project, not the only supported path
   — no per-language verifier classes to build and maintain.
2. **Set during creation/attach** — both New Project and Attach flows
   require (or auto-suggest) a verify command as part of setup, before
   the project is usable for coding execution. Ensures the verify gate
   from `coding-execution-reliability-and-safety` is never silently
   absent for a project that hasn't gotten around to configuring it.
3. **Superseded by Q4's answer** — the original marker-file-detection
   question got folded into the broader skill-tailoring mechanism (see
   Q6) rather than staying a standalone lookup table.
4. **New generic skill set** — write real, self-contained,
   stack-agnostic SDD skill content (explore/propose/apply/verify/
   archive etc.) bundled directly in the app, with no Flutter/Dart
   references and no pointers to `aion-arch`. This becomes the actual
   default baseline; `aion-arch`'s own skills are untouched, staying
   purpose-built for developing Aion itself. Rejected mechanically
   stripping down `aion-arch`'s actual skill text, since it's shaped by a
   lot of Aion-specific context (ticket system, two-repo layout) beyond
   just Flutter — likely needs heavier rewriting than "strip out Flutter
   parts" implies anyway.
5. **Yes — same mechanism.** Setup-time tailoring writes real
   `ProjectOverride` files into `<rootPath>/.aion/overrides/`; later
   editing (via Settings or Inbox) is an editor over those same override
   files. One mechanism serves both needs, and directly resolves
   `projects.md`'s existing "Override-authoring UI" gap as a side effect
   rather than being new scope.
6. **Tied to summarization depth** — reuses `new-project-onboarding`'s
   already-decided depth choice. A full agentic codebase-summarization
   pass also tailors skill overrides as a byproduct of already reading
   the codebase deeply. A shallow structural pass only fills simple
   template placeholders (detected language, verify command) from
   marker-file detection — consistent with that idea's "shallow
   knowledge, deepen on demand" pattern; a shallow project's overrides
   could later be re-tailored the same on-demand way a shallow summary's
   knowledge gets deepened.

## Conclusions reached

- **Verification** generalizes to a `ProcessVerifier` running a
  project-level, user-set verify command — no per-language verifier
  classes. `FlutterVerifier`'s existing behavior (worktree check,
  `runInShell` handling, `pubspec.yaml` fast-fail) becomes one detected
  default among many, not the only implementation.
- The verify command is **set mandatorily at project creation/attach**,
  never left silently unset.
- **Skill content** gets a real, self-contained, stack-agnostic default
  bundle, replacing today's `aion-arch`-pointer assets — the actual
  generic OpenSpec/SDD skill set Aion ships to every project, independent
  of `aion-arch`'s own Aion-specific skills.
- **Tailoring** writes real `ProjectOverride` files at setup time — full
  agentic tailoring when the user opts into deep codebase summarization,
  template-substitution-only when they opt for the shallow pass — and
  **later editing reuses the same override mechanism**, closing
  `projects.md`'s known "Override-authoring UI" gap as part of this work
  rather than as separate scope.
- This idea absorbs what `new-project-onboarding` had originally left as
  an open-ended "other useful project-management skills" catch-all — the
  real underlying issue was Aion's own Flutter-centric bootstrapping
  leaking into every future attached project, not an unnamed fifth Inbox
  purpose.

## Open questions

- Whether `BaselineAssetKind.modelConfig` (model/provider tier config)
  needs any stack-aware tailoring at all, or is genuinely orthogonal to
  project type (a model-routing decision, not a code-convention one) —
  leaning orthogonal, not raised for deeper discussion this session.
- Exact marker-file detection table for the shallow/template-only
  tailoring path (which files map to which language/verify-command
  defaults) — implementation detail for `/propose`'s design.md.
- Whether the generic skill set's content should itself be versioned
  under the existing `assets/baseline/<version>/` scheme (a new baseline
  version bump) or introduced as a parallel set of assets — left for
  `/propose` to resolve against `BaselineManifest`'s existing versioning
  model.
- What "editable via Inbox" looks like concretely (a fifth Inbox chat
  purpose, conversational override authoring?) versus a plain Settings
  text editor over the same override files — not walked through this
  session; both consume the same override mechanism either way, so this
  is a UI-shape decision rather than an architectural one.

## Architectural implications

- Confirms two concrete, code-level blockers to attaching Aion to any
  non-Flutter project: `FlutterVerifier`
  (`aion/lib/core/build/flutter_verifier.dart`) is a hardcoded concrete
  class with no abstraction, and the baseline manifest's `skills/*` /
  `conventions/flutter-conventions` assets
  (`aion/assets/baseline/0.2.0/manifest.json`) are pointers into
  `aion-arch/.claude/skills/` and `aion-arch/flutter-conventions.md`
  respectively — meaningless outside Aion's own self-hosting context.
- Reuses the already-shipped `ProjectOverride`/`BaselineAsset` pinned +
  override system (`storage-model-per-project-scoping`,
  `hub-and-infrastructure-to-support-multiple-projects`) as the
  mechanism for both setup-time tailoring and later manual editing — no
  new persistence or resolution layer needed, just new writers/editors
  over the existing one.
- Directly resolves `projects.md`'s pre-existing "Override-authoring UI"
  known gap as a byproduct of building the "user can edit skills later"
  requirement, rather than as independent scope.
- Ties into `new-project-onboarding`'s codebase-summarization depth
  choice (shallow vs. full agentic) as the deciding factor for how
  setup-time tailoring is produced — these two ideas' attach-flow steps
  are sequenced together in practice even though they're separate
  `/propose` cycles: summarization depth is chosen once and drives both
  the resulting signal tickets and the skill-tailoring approach.
- `ProcessVerifier` generalizing `FlutterVerifier` needs to preserve the
  reliability fixes `coding-execution-reliability-and-safety` already
  shipped (worktree-scoped execution, `runInShell` on Windows, fast-fail
  on a missing project marker file) — these become properties of the
  generic verifier, not Flutter-specific incidental behavior to relearn
  per language.