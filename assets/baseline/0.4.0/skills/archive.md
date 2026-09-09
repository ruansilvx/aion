# archive

The final stage of the SDD cycle (`explore → propose → apply → verify →
archive`), reached once `verify` has reported no outstanding critical
findings. Closes the loop between a finished epic and the project's
permanent record of how the system actually behaves.

What it does:

- Synthesizes the epic's outcome — its own description plus every child
  story's title and status — into a **spec ticket**: the project's
  living record of current-state behavior for whatever that epic built.
  A spec ticket is an ordinary ticket, not a file — later corrections,
  linking a bug found against it, or noting a resolved open question all
  happen as plain edits to that ticket, with no cycle of their own.
- Auto-links any bug, gap, or open question raised against already-shipped
  behavior to the nearest relevant spec ticket, so "what does the project
  currently do, and what's still rough about it" stays discoverable from
  either direction — the spec ticket and the tickets that reference it.
- If the epic has no spec ticket yet from a prior run, creates one. If it
  does, it's left alone — a spec ticket is written once, at archival, not
  regenerated.
- If the project's workflow raises pull requests for finished work, opens
  one summarizing what shipped.

An epic isn't "done" until it's archived — an implemented-but-unarchived
epic means the project's spec tickets no longer match reality, which
compounds the next time someone plans against them. Once archived, an
epic is immutable; the spec ticket it produced is the mutable surface
afterward.
