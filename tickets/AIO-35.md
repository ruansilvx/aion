---
ticketId: AIO-35
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-08-13T00:00:00.000
updatedAt: 2026-08-13T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Inline [[wikilink]] backlinks for the Documentation section

## Key questions asked

1. What's actually motivating this — a real writing habit (typing `[[Page]]` and expecting it to auto-link), or a completeness/parity want since the doc section is explicitly modeled on Notion/Obsidian?
2. Given no felt need yet, work out a concrete direction now, or conclude with an explicit "defer, no clear need" and leave it raw?
3. How should inline-wikilink backlinks be computed: live scan of every page's Markdown on demand, or parsed on save into a persisted index?
4. When a page is renamed, how should existing `[[Old Title]]` references elsewhere be handled?
5. (Follow-up, after clarifying Obsidian's actual default and that Aion always observes renames through its own save/watcher path) Does that change the rename-handling answer?
6. "Show the ticket number, like Jira" — Aion has no `PROJ-123`-style sequential ticket key today. What's actually wanted?
7. "Hold inline linked tickets on the header too" — where specifically should wikilink-derived references surface?
8. Should typing `[[` trigger a live autocomplete popup of existing page titles, or is MVP just parse-and-resolve-on-save with no editor-time assistance?

## Summary of answers

1. Parity/completeness want — no concrete workflow yet, it stands out as "missing" because Obsidian/Notion have it and the doc section took inspiration from them.
2. Work out a direction now, despite no felt need.
3. Persisted index on save (recommended) — parse `[[...]]` refs when a page is saved, resolve each to a target page id, store rows in a lightweight index table.
4. Initially answered "break silently, MVP" but the user asked how Obsidian actually handles it before committing.
5. Obsidian's real default is auto-rewrite-on-rename (only breaks silently on an out-of-band file rename outside its awareness). Since Aion's page rename always flows through its own save/watcher path, the user chose auto-rewrite on rename — not silent breakage.
6. Existing mono type-key styling (type-color dot + monospace type abbreviation + title, same as `LinkedTicketsSection` rows) is enough — no new sequential-ticket-key system needed; that would be separate, bigger scope.
7. Fold into the existing `BacklinksSection` — no new header placement/section.
8. Autocomplete popup (recommended) — typing `[[` opens a searchable suggestion list of existing pages, same overlay mechanics as `TicketLinkPicker`/`TicketParentPicker`.

## Conclusions reached

Build inline `[[wikilink]]`-style backlink scanning for the Documentation section's pages:

- **Resolution model:** parse `[[Title]]` references out of a page's Markdown on save (via the same save/watcher path as `TicketMarkdownWatcherService`), resolving each to a target page id and storing rows in a lightweight persisted index — not a live re-scan of every page on each read.
- **Rename handling:** auto-rewrite, matching Obsidian's actual default. Renaming a page scans the persisted wikilink index for every `[[Old Title]]` occurrence in other pages and rewrites it to `[[New Title]]`. This is viable specifically because Aion always observes a page rename through its own save/watcher flow — the out-of-band file-rename edge case that makes Obsidian sometimes fall back to silent breakage doesn't apply here.
- **Ticket-key display:** reuse the existing monospace type-abbreviation "mono key" styling already used by `LinkedTicketsSection` rows — no new Jira-style sequential ticket-number field. Introducing a real per-project sequential key (e.g. `AION-42`) is explicitly out of scope here and would need its own idea/proposal if ever wanted.
- **UI placement:** no new header section. Inline-wikilink-derived backlinks become additional rows in the existing `BacklinksSection`, distinguishable from explicit `TicketLink`-derived rows (since inline refs are unauthored/derived-from-content, not user-created relationships with remove/retype actions).
- **Authoring UX:** typing `[[` in a page's Markdown editor opens a searchable autocomplete popup of existing page titles, reusing the same `Overlay`/`LayerLink`/`CompositedTransformFollower` overlay mechanics as `TicketLinkPicker`/`TicketParentPicker` rather than a from-scratch editor widget.

## Open questions

- Ambiguous/duplicate title handling — what happens when two pages share the same title and a `[[Title]]` reference is inherently ambiguous? Not discussed; needs resolving at `/propose`.
- Broken/unresolved `[[Title]]` refs that don't match any existing page — visual treatment (e.g. grayed out, distinct color), and whether the autocomplete should offer "create new page with this title" inline (Obsidian does this) or require the page to already exist.
- Exact schema for the persisted wikilink index table, and precisely how its write path interacts with `TicketMarkdownWatcherService`'s existing save/reindex pipeline (ordering, transactionality).
- Whether `resource` tickets (leaf docs) also get outgoing `[[wikilinks]]` in their content, or whether this is `page`-only — resources may not have the same free-form Markdown body pages do; not discussed.
- Rename-rewrite failure/race handling: what happens if the rewrite of referencing pages partially fails, or a referencing page is being edited concurrently when a rename triggers a rewrite of its content.

## Architectural implications

- **New persisted index required:** a lightweight table (e.g. `PageWikilinkRepository`) mapping source page → resolved target page id(s), populated by parsing `[[...]]` syntax out of Markdown content on save — separate from and additional to the existing `TicketLink` table.
- **Rename becomes a multi-page-mutating operation:** unlike a normal title edit, renaming a page with existing inbound wikilinks now needs to look up the index, rewrite raw Markdown in every referencing page, and trigger each of those pages' own save/reindex — real complexity and risk (concurrent-edit races with `TicketMarkdownWatcherService`, partial-failure/rollback story) that a plain field update doesn't have.
- **`BacklinksSection` needs a two-kind row model:** explicit `TicketLink`-derived backlinks (user-authored, removable/retypeable) vs. inline-wikilink-derived backlinks (automatic, derived from content, not directly editable) need to coexist and be visually distinguishable in the same section.
- **New autocomplete overlay component:** a `[[`-triggered searchable page-title popup, likely living in the Pages module's Markdown editor widget, reusing existing overlay mechanics (`TicketLinkPicker`/`TicketParentPicker`) rather than introducing new overlay infrastructure.
- **No ticket-numbering system change:** deliberately does not touch `Ticket` model fields or introduce sequential keys — reuses existing type-abbreviation display only.
- Closes out the "inline `[[wikilink]]`-style content-reference backlinks are out of scope" known gap carried forward from [[notion-obsidian-like-documentation-section]].