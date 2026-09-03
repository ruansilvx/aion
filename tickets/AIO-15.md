---
ticketId: AIO-15
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-07-27T00:00:00.000
updatedAt: 2026-08-14T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Cancel an in-flight agent reply in a chat ticket

## Original scope (2026-07-27)

Aion had no way to cancel an in-flight AI reply once a chat message is
sent — `AgentModelClient`/`ClaudeAgentSdkClient` exposed no cancellation
handle, `ChatCubit` had no cancel method, and the chat UI had no stop
button while streaming.

## Superseded (2026-08-13)

During `parallel-work.md`'s brainstorm session (settling coding-
execution's FIFO/no-cancel/no-persistence Known gap), the question of
cancelling an in-flight *coding-execution* run required the exact same
primitives this idea already scoped generically: kill the underlying
process, close the event stream, add `ChatCubit.cancelReply()`, and add a
stop-button affordance in the transcript UI.

Rather than building a narrow, execution-only kill path now and this
idea's general version later — two mechanisms that would need
reconciling — the session concluded the shared plumbing should be built
once, as `parallel-work.md`'s foundation. Coding-execution's cancel button
and a plain chat's stop button both become callers of the same mechanism.

This idea's scope is therefore fully absorbed into `parallel-work.md` and
ships as part of that change, not as separate work. See
[[parallel-work]] for the full resolution.