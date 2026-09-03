---
ticketId: AIO-46
type: idea
status: backlog
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-09-01T00:00:00.000
updatedAt: 2026-09-01T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Parallel Execution PR Merge-Conflict Visibility

Merge-conflict detection/notification for parallel coding-execution PRs. Aion's parallel/hybrid coding-execution scheduling avoids *concurrency* conflicts via a structural heuristic only (blocks/blockedBy hard gate + Hybrid mode's same-ancestor-up-to-Epic sibling serialization in TicketsCubit._nextEligibleForHybrid) — it is not content-aware and does not look at which files a ticket actually touches. Each execution pushes its branch and opens a PR against the default branch via gitHubClient.openPullRequest (tickets_cubit.dart, _runCodingExecution) and stops there; Aion never merges anything itself. So two unrelated tickets (different Epics, no shared ancestor) that happen to edit the same file will run fully in parallel with zero serialization, and if their PRs overlap, nothing detects, surfaces, or resolves that — the second PR just shows as conflicting on GitHub like any normal team's concurrent PRs, with no visibility into that from inside Aion at all.

Idea: detect and surface PR-level merge-conflict risk instead of leaving it silently undiscoverable. Candidate shapes to weigh during /brainstorm or /propose:
- Poll each open coding-execution PR's GitHub "mergeable" status periodically or on a triggering event, and surface a badge/notification on the ticket when it flips to CONFLICTING — natural extension of the existing notification-center groundwork from pr-metadata-and-notification-center (aion-arch/changes/archive/pr-metadata-and-notification-center/), which already tracks PR metadata per ticket.
- Optionally widen the pre-execution scheduling heuristic beyond ancestor-lineage to an actual changed-files check (e.g. diff the PR's file list against other currently-open coding-execution PRs) rather than only Epic/Story structure — more precise but bigger lift, and overlaps dependency-caching-and-ancestor-sibling-conflict's existing sibling-conflict scope.
- Decide whether Aion should ever attempt anything beyond *surfacing* the conflict (e.g. never auto-rebase or auto-resolve — that's explicitly out of scope per the conversation that raised this) versus purely notifying the user so they resolve it themselves via normal GitHub flow.

related_ideas: [pr-metadata-and-notification-center, parallel-work, dependency-caching-and-ancestor-sibling-conflict]