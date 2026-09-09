# ticket-lint

Validates and reformats this project's hand-editable ticket Markdown
files (resource and page tickets stored under `tickets/`). Not part of
the SDD cycle — a mechanical hygiene check, cheap enough to run
liberally.

Use it when:

- A ticket shows a "needs repair" sync status, meaning its on-disk
  Markdown drifted out of the shape the app expects.
- You want to spot-check every hand-editable ticket file at once,
  rather than opening and inspecting each one individually.

This check only concerns Aion's own ticket file format — the front
matter, structure, and conventions that let a ticket round-trip between
the app's database and a plain Markdown file a person can edit directly.
It has nothing to do with the attached project's own codebase or
language, which is why it applies identically no matter what kind of
project Aion is managing.
