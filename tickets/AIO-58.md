---
ticketId: AIO-58
type: idea
status: backlog
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
# Release pipeline dry run via real tag push

## Key questions asked

1. What's actually stopping you from just pushing a real `v*.*.*` tag
   right now — a specific concern (e.g. a botched first release being
   hard to clean up), or has it simply not come up as a priority?
2. (Raised by the user, before resolving the fork below) Is release
   *creation* actually built into Aion itself, or is it just a Claude
   Code skill — given Aion's agent-agnostic design, if it were only a
   skill, everything about this pipeline would need rethinking.
3. Given no blocker, should this session conclude with "just do it now"
   or an explicit decision to defer until more changes are batched in?

## Summary of answers

1. **No hidden blocker** — the developer confirmed it just hasn't come
   up as a priority yet, not that something is actively holding it back.
2. **Confirmed agent-agnostic**, by reading
   `aion/.github/workflows/release.yml` directly rather than trusting
   the spec prose alone. The actual release-creation mechanism (builds
   the Windows Inno Setup installer and Linux AppImage, creates the
   GitHub Release) is a plain GitHub Actions workflow committed in the
   `aion` app repo, triggered purely by a `v*.*.*` tag push — no
   Claude Code or model-API dependency anywhere in it. The only
   Claude-specific piece is `/prepare-release`
   (`aion-arch/.claude/skills/prepare-release/`), and it's strictly an
   optional, pre-tagging convenience that drafts `CHANGELOG.md` content
   and bumps `pubspec.yaml` — the workflow doesn't know or care how
   those files got populated, so a human (or any other agent) could
   hand-edit both and the pipeline would behave identically. Nothing
   needed rethinking.
3. **Just do it now** — run `/prepare-release`, then manually tag and
   push, rather than waiting for more archived changes to accumulate
   first.

## Conclusions reached

- The release pipeline is confirmed agent-agnostic at the point that
  actually matters (build/package/publish); no architectural rework is
  needed before exercising it.
- Decision: run `/prepare-release` now to draft the changelog and
  version bump, then manually `git tag`/`git push` a real `v*.*.*`
  release. This is the first real exercise of both CI jobs (Windows
  hard-required, Linux best-effort per `continue-on-error`), the
  changelog-extraction step, and `gh release create` — closing the
  known gap recorded in `aion-arch/specs/release.md`.
- This is an operational action, not a code change — it doesn't need
  its own `/explore` → `/propose` → `/apply` → `/verify` → `/archive`
  cycle. `next_action` points straight at running `/prepare-release`
  and tagging, not at `/explore`.

## Open questions

- No rollback plan was discussed for what happens if the dry run fails
  in an unexpected way (e.g. the Windows build itself fails, rather
  than the already-accepted degraded Linux-only path) — leaving a bad
  tag or a partial GitHub Release to clean up. Not a blocker for
  attempting the dry run, but worth having in mind if it needs cleanup.
- The exact version number for this first real tag was left to
  whatever `/prepare-release` suggests from the current archived-change
  history, rather than decided in this session.

## Architectural implications

- Follow-up in the same session: the confirmation that release-creation
  is agent-agnostic (see above) led directly into a larger idea,
  [[aion-native-release-preparation-and-tag-management]] — building an
  Aion-native equivalent of `/prepare-release`, generic for any managed
  project, so this manual dry run's underlying skill dependency
  eventually goes away entirely. That's a separate, large-complexity
  idea; this dry run remains a valid, much smaller near-term action
  independent of whether/when that larger idea gets built.
- None otherwise — this idea confirms and closes out the existing design from
  [repo-release-setup-and-distribution](repo-release-setup-and-distribution.md)
  rather than changing it. Once the dry run actually happens,
  `aion-arch/specs/release.md`'s "Known gaps" bullet about the pipeline
  never being exercised should be updated with the real result (per
  that file's own precedent for recording a fact that can only become
  true after the tag is pushed).