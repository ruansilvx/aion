---
ticketId: AIO-73
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-07-13T00:00:00.000
updatedAt: 2026-07-18T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Use internationalization for the strings

## Key questions asked

1. What's actually driving this — a real need for another language, or code hygiene around hardcoded strings?
2. Given it's hygiene-driven, should this be a full retrofit of every existing string at once, or incremental migration with enforcement only on new code?
3. How should "no loose strings" be enforced going forward — a custom lint/CI rule, or a documented convention?

## Summary of answers

1. Hygiene, not an active multi-language requirement. Wants to get rid of loose/hardcoded strings; `intl` is the chosen mechanism.
2. The app is still small, so retrofit everything at once rather than migrating file-by-file over time.
3. A documented convention (in `flutter-conventions.md`) is enough — no custom lint rule or CI gate.

## Conclusions reached

Adopt the `intl` package (ARB-based) for all app strings. Retrofit every existing hardcoded string across the app in one pass — not incremental. Only an English ARB is needed right now (no live multi-language requirement), but routing everything through `intl` means a second locale later is additive (new ARB file), not a rearchitecture. Enforcement is a convention documented in `flutter-conventions.md` instructing that new UI strings must use the localization lookup rather than string literals — deliberately not a lint rule or CI check, since the user judged that overkill for a solo-dev app at this size.

## Open questions

- Exact ARB key naming scheme (by screen/widget vs. flat namespace) — left for `/propose` to decide.
- Whether generated localization code (`AppLocalizations` via `flutter gen-l10n` or similar) gets committed or gitignored — left for `/propose`.

## Architectural implications

- Touches every widget file under `lib/` that currently has a string literal — this is a wide, mechanical change rather than a narrow one.
- `flutter-conventions.md` needs a new documented rule once this ships (part of the eventual change's scope, not this idea file).
- No conflict with existing `project.md` foundational decisions — this is additive tooling, not a storage/branching/agentic-engine decision.