---
ticketId: AIO-64
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-07-17T00:00:00.000
updatedAt: 2026-07-18T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Storage model — per-project scoping and shared baseline

## Key questions asked

1. Is this session meant to resolve implementation readiness of the
   existing three-layer storage model in `project.md`, or reconsider it
   given the just-captured multi-project hub idea?
2. When Aion provides a "common baseline" each project tunes, is that a
   one-time scaffold copy (projects drift independently after) or a
   shared core Aion keeps updating that projects inherit from?
3. (User asked for a recommendation) Pinned shared core with local
   override layer, or always-latest live core?
4. When switching projects in the hub, is that one running instance
   swapping active project context, or a separate instance per project?

## Summary of answers

- Each project gets its own fully isolated environment: own drift DB,
  own git repo (for both the project's ticket data and its
  architecture/spec history), own tuned skills, own model/agent
  configuration.
- Aion provides a common baseline (default skills, agent/model config,
  architecture conventions) that every project starts from and can tune
  away from.
- Baseline distribution model: **pinned + override**, not live-sync.
  Each project's environment references a pinned version of the shared
  baseline; a local override layer can shadow or extend baseline pieces
  by name. Upgrading a project to a newer baseline version is an
  explicit, opt-in action — never silent. This mirrors the pattern
  aion-arch already uses for itself (`aion-arch/.claude` as shared skill
  source, symlinked into `aion-workspace/`).
- Hub/runtime model: **single running Aion instance** with a project
  switcher that swaps the active project context (DB connection, active
  skills, config) — not one process per project.

## Conclusions reached

The three-layer storage model from `project.md` (`drift` live state,
embedding-based semantic memory, git-based event-triggered version
history) stays intact **per project** — it's now explicitly scoped to
each project's own isolated environment rather than a single global
instance. On top of that, a new architectural layer is needed: a pinned
+ override baseline-distribution system, and a single-instance
project-switching runtime. This directly supersedes the ambiguity in
the "Hub and infrastructure to support multiple projects" idea — see
[[hub-and-infrastructure-to-support-multiple-projects]], which this
session resolves jointly.

## Open questions (from initial session)

- How is a new project's environment provisioned (scaffold command,
  UI flow, what gets copied vs. referenced from the pinned baseline)?
- What exactly is allowed in the override layer — full file replacement
  by name only, or partial/merge overrides (e.g. one field of an agent
  config)?
- Where does the pinned baseline version live and get bumped from —
  a manifest file per project, a version pin in project config?
- Does switching active project context require closing/reopening the
  drift DB connection live, or does it require an app restart?

## Architectural implications (from initial session)

- Forces a new concept: a versioned, distributable "baseline" package
  (skills + agent/model config + architecture conventions) distinct
  from any single project's environment.
- Forces the runtime to support hot-swapping active project context
  (DB connection, skill set, config) within one running instance.
- `project.md`'s "Storage Model" foundational decision needs updating to
  reflect per-project scoping once this becomes a change (via
  `/propose`).
- Directly feeds the multi-project hub idea — the two should likely be
  proposed as a single change rather than split, given how tightly
  coupled the runtime and storage decisions are.

---

## Deep dive: drift + embeddings + git relationship (2026-07-18)

Follow-up session on the same idea, going deeper on how the three storage
layers (`drift`, embeddings, git version history) actually work and relate
— confirmed each is scoped **per project**, consistent with the per-project
isolated-environment conclusion above.

### Key questions asked

1. Should embedding regeneration fire on every ticket update, or only when
   the fields that compose the embedding change?
2. Which fields compose the embedding input?
3. Should embedding generation block the ticket save, or run async?
4. Is Ollama the only option for embeddings — can it fit inside the
   Flutter app itself, avoiding an external dependency?
5. (User asked to go deeper on bundling) Is a fully bundled, on-device
   embedding model feasible across desktop, mobile, and web?
6. What actually gets committed to the per-project git repo on a
   version-history trigger event, given drift/SQLite is binary and not
   git-friendly?
7. How should syncing work between the drift DB and the per-ticket
   Markdown files — one-way, or bidirectional?
8. (Resource/page specifically) User wants these hand-editable with
   changes synced back automatically, local-first. What's the conflict
   resolution when both DB and file change in the same window?
9. Should the embedding BLOB (or a hash of it) be referenced in the
   committed Markdown file, or should git stay blind to embeddings
   entirely? What's the impact on installing Aion on a second machine?
10. What happens if a resource/page file is hand-edited outside Aion and
    loses the expected template/frontmatter structure?

### Summary of answers

**Embeddings:**
- Regenerate only when the fields that compose the embedding change, not
  on every ticket mutation.
- Composed from `title` + `description` only for now; more fields
  (comments, tags, type) may be added later.
- Generation is async — ticket save completes immediately, embedding is
  backfilled in the background.
- Ollama is rejected as the mechanism: it's an external local server
  process (`localhost:11434`), not bundled into the app, and `project.md`
  already scopes it desktop-only — no web/mobile story.
- Decision: **fully bundled, on-device embedding model**, no external
  server or cloud dependency. A portable, quantized embedding model
  (MiniLM-class or similar) shipped as native builds (TFLite/ONNX) for
  desktop/mobile and a WASM build for web — same weights across all
  platforms so embedding vectors stay comparable regardless of where a
  ticket was created. iOS can additionally lean on Apple's built-in
  `NLEmbedding` where useful. This supersedes `project.md`'s current
  "local Ollama embedding model" line.
- Storage/retrieval stays as already decided: the existing `embedding`
  BLOB column, brute-force cosine similarity (sufficient at personal
  scale).

**Git version history:**
- One Markdown file per ticket (frontmatter for structured fields, body
  for description/comments), Obsidian-like. Serialization must be
  deterministic so diffs reflect real changes, not incidental
  reordering.
- Trigger events unchanged from `project.md` (create, status change,
  branch merge, explicit spec save, batch review commit); events landing
  together (e.g. a batch review) coalesce into a single commit.
- Sync direction is **type-dependent**:
  - `epic`/`story`/`task`/`chat` — one-way, DB → file. The file is a
    generated, read-only projection (an audit trail), never read back
    into the DB. Hand-editing these files has no effect beyond the next
    overwrite.
  - `resource`/`page` — **bidirectional**. The file is a live, watched
    input: a filesystem watcher detects changes, debounces until edits
    pause, then reconciles the file's content into the DB (local-first,
    background sync after a delay) — matching how these types are
    conceptually documents/notes, not structured work items.
- Conflict resolution: for `resource`/`page`, **the file wins** when both
  the DB (via Aion's UI) and the file (via external edit) change in the
  same window — Aion's own UI is effectively a write-through client of
  the file for these two types. DB stays authoritative everywhere else,
  where no conflict is possible since the file is never an input.
- Malformed-file handling (relevant only to the bidirectional
  `resource`/`page` path): validate strictly on reconcile.
  - Unparseable frontmatter → do **not** write to DB (avoids corrupting
    the structured row) and do **not** auto-overwrite the file (avoids
    destroying the user's edit, which would violate "file wins"). Flag
    the ticket as **needs repair** in the UI, with a manual
    "restore from last known good" action.
  - Individually invalid fields (e.g. a bad `status` value) degrade
    per-field: reject just that field, keep its last DB value, accept
    the rest of the update.
  - A specific Markdown template/frontmatter schema is planned, serving
    three purposes: reliable identification, future in-app rendering of
    the file, and cheap agentic/CLI access (pre-gathering structured
    data without burning tokens re-deriving it). A manual "lint/repair"
    command should exist to reformat a file back to canonical structure
    while preserving recognizable freeform content — invoked explicitly,
    never automatically (auto-repair would fight the "flag, don't
    silently fix" rule above).

**Relationship between the three layers:**
- The drift DB is treated as **fully disposable and reconstructable**
  from the git-tracked `.md` files. Installing Aion on a second machine
  and cloning a project's repo yields every ticket's structured fields
  (frontmatter) and content (body) — enough to rebuild the DB from
  scratch.
- Embeddings are **never committed to git**, not even as a hash. A hash
  would only help avoid recompute on an *already-populated* local DB
  (a same-machine staleness check), which is better served by a
  local-only DB column — it wouldn't save any work on a fresh machine,
  since a rebuilt DB has no cached embedding to compare a hash against
  regardless. After DB reconstruction, Aion runs the same async
  embedding-backfill mechanism used for normal edits, just applied in
  bulk across every ticket that lacks a local embedding.
- A `resource`/`page` file-driven reconcile that changes description
  content feeds into the **same** embedding-regen trigger as any other
  DB-side edit — one unified trigger path regardless of which surface
  (UI or external file edit) changed the content.

### Conclusions reached

The three-layer storage model is now fully specified at the design
level, per project:
- **Drift** — live state, source of truth for structured fields; fully
  reconstructable from git history.
- **Embeddings** — bundled, on-device, no external dependency; async,
  content-triggered (title/description only for now); never enters git.
- **Git** — one Markdown file per ticket, event-triggered commits,
  direction depends on ticket type (one-way for structured work items,
  bidirectional file-wins for resource/page), with strict-validate/
  never-silently-overwrite handling for malformed hand edits.

This is ready to move into `/propose` — likely as part of the same
`multi-project-hub` change already planned, since per-project storage
scoping and the hub/switcher runtime are tightly coupled.

### Open questions (from this session)

- Exact embedding model choice (which MiniLM-class model/weights,
  quantization level) — an implementation detail for `/propose`.
- Exact Markdown template/frontmatter schema for tickets — not yet
  designed, needed before `/propose` can spec the git layer concretely.
- Does the filesystem watcher for `resource`/`page` files run
  continuously in the background, or only while Aion is open/focused?
- What's the debounce window duration for reconciling file edits?
- Where does the "lint/repair" command live — CLI, an Aion UI action, a
  skill, or several of those?

### Architectural implications (from this session)

- Adds a new bundled-model dependency (native + WASM builds of one
  portable embedding model) to the app across every platform, distinct
  from the existing cloud/local-server `AgentModelClient` provider
  system — embeddings don't go through `ModelRouter` at all, since
  they're not user-configurable per phase.
- Requires a filesystem watcher + debounce + reconcile pipeline scoped
  specifically to `resource`/`page` tickets, separate from the one-way
  git-projection path used by other types.
- Requires a deterministic Markdown serializer/parser pair (and a
  template schema) shared by the git-projection writer, the
  `resource`/`page` reconciler, and any future CLI/agentic pre-gathering
  tooling — one format, three consumers.
- Establishes DB-reconstruction-from-git as the standard recovery/
  multi-machine-install story; no separate backup mechanism needed for
  ticket data itself.

---

## Implementation-readiness follow-up (2026-07-18)

Third session, closing out the four open questions left after the deep
dive, to make this fully ready for `/propose`.

### Key questions asked

1. Should the `resource`/`page` filesystem watcher run continuously in
   the background, or only while Aion is open/focused?
2. On focus-regain after external file edits, should reconciliation fire
   immediately, or wait for the user to open that specific page?
3. What's the right debounce window for reconciling file edits — a
   specific value, or left as an implementation detail for `/propose`?
4. Where should the "lint/repair" command for malformed files live —
   UI, CLI, skill, or a combination?
5. Should a specific embedding model/quantization be locked in now, or
   left for `/propose` (with a suggested default)?

### Summary of answers

- **Watcher lifecycle:** focus-only, not a continuous background daemon
  — avoids eating resources for a solo-dev desktop app when nothing is
  actively being edited.
- **Reconciliation timing:** fires immediately in the background on
  focus-regain, non-blocking, surfaced only via a subtle sync
  indicator. The one exception: if the user is actively viewing the
  specific page being reconciled, that reconcile blocks (prevents the
  file-wins update from landing invisibly under an in-progress local
  edit, which is the actual conflict-risk window).
- **Debounce window:** left as an implementation detail; suggested
  default ~1.5s of inactivity after the last detected write, long
  enough to absorb autosave + explicit-save bursts from most editors
  without feeling laggy.
- **Lint/repair tool:** combined UI action + Claude Code skill + CLI.
  The UI action lives inside the future pages/documentation screen (see
  [[notion-obsidian-like-documentation-section]]) for interactive,
  human-driven repair; the CLI is the same underlying logic exposed as
  a standalone command so agentic/scripted repair calls avoid the
  token cost of routing through a skill invocation for something purely
  mechanical (parse, validate, reformat).
- **Embedding model:** left as an implementation detail for `/propose`
  to finalize; suggested default all-MiniLM-L6-v2, int8-quantized,
  exported to ONNX (desktop/mobile) and WASM (web) — compact (~22MB
  quantized), well-established, and satisfies the "one set of weights
  across all platforms" requirement from the deep-dive session.

### Conclusions reached

All four blocking open questions from the deep-dive session are now
resolved (two locked decisions, two suggested-but-deferred defaults).
The embedding/git-sync half of the storage model is fully specified at
the design level and ready to move into `/propose`. Since the
project-isolation half already shipped separately as `multi-project-hub`,
this is now its own standalone change rather than bundled with that one.

### Open questions

None blocking `/propose`. Remaining decisions (exact debounce value,
exact embedding model/quantization) are intentionally deferred as
implementation details to be finalized during `/propose`/`/apply`, not
architectural unknowns.

### Architectural implications

- Confirms the reconcile pipeline needs a focus-lifecycle hook (start
  watcher on app focus, stop/pause on background) rather than a
  persistent OS-level watcher or background service.
- Confirms the reconcile pipeline needs page-level "is this currently
  being viewed" awareness to decide blocking vs. background-with-indicator
  behavior — ties into whatever screen/navigation state tracks the
  active page.
- Establishes the lint/repair tool's UI surface as a feature of the
  future Notion/Obsidian-like documentation section
  ([[notion-obsidian-like-documentation-section]]) — that idea should
  account for this when it's next brainstormed or proposed. The
  underlying parse/validate/reformat logic must be factored so it's
  callable from three surfaces (UI action, skill, CLI) without
  duplication — one core implementation, three thin entry points.