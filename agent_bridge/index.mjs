// agent_bridge/index.mjs — Node.js bridge invoked by ClaudeAgentSdkClient
// (aion/lib/core/agent/claude_agent_sdk_client.dart). Not part of the
// Flutter build — a plain Node/ESM script.
//
// Reads one JSON request line ({prompt, model, toolsEnabled}) from stdin and
// runs it through the Claude Agent SDK's query(). Tool access (file edits,
// git, bash, MCP) is disabled unless the request sets toolsEnabled: true —
// set only by TicketsCubit's coding-execution path
// (aion-arch/changes/task-to-coding-execution-trigger/design.md §1.3); every
// other caller keeps today's text-only behavior. Writes one NDJSON line per
// resulting event to stdout:
//   {"type":"text","text":"..."}
//   {"type":"done"}
//   {"type":"error","message":"..."}
//   {"type":"overage","message":"..."}
// Exactly one request per process invocation — ClaudeAgentSdkClient spawns a
// fresh process per AgentModelClient.run() call.

import { query } from '@anthropic-ai/claude-agent-sdk';
import { createInterface } from 'node:readline';

function emit(event) {
  process.stdout.write(`${JSON.stringify(event)}\n`);
}

async function readRequest() {
  const rl = createInterface({ input: process.stdin, terminal: false });
  for await (const line of rl) {
    if (line.trim().length === 0) continue;
    rl.close();
    return JSON.parse(line);
  }
  throw new Error('No request line received on stdin.');
}

async function main() {
  const { prompt, model, toolsEnabled } = await readRequest();

  for await (const message of query({
    prompt,
    options: {
      model,
      // Tool-enabled runs (Task coding-execution) get the SDK's default
      // tool set; every other caller (Settings' "Test Connection",
      // SDD-stage chats) keeps today's text-only behavior.
      ...(toolsEnabled
        ? {
            // This process has no TTY (spawned via dart:io Process with
            // piped stdio, no interactive terminal), so the SDK's default
            // 'default' permissionMode — which prompts for dangerous
            // operations like file writes — has no one to answer its
            // prompts. Confirmed empirically: without this, a tool-enabled
            // run can Read but every Edit/Write/git-write attempt is
            // denied, and the model burns its run narrating workarounds
            // instead of ever touching a file. bypassPermissions requires
            // allowDangerouslySkipPermissions: true as a companion flag.
            permissionMode: 'bypassPermissions',
            allowDangerouslySkipPermissions: true,
          }
        : { allowedTools: [] }),
    },
  })) {
    if (message.type === 'assistant') {
      const text = (message.message?.content ?? [])
        .filter((block) => block.type === 'text')
        .map((block) => block.text)
        .join('');
      if (message.error) {
        // A real failure — `authentication_failed`, `rate_limit`,
        // `billing_error`, `invalid_request`, `server_error`, or
        // `unknown` (SDKAssistantMessageError). Observed empirically: the
        // `result` message that follows can still report
        // `subtype: 'success'` with this same text as its `result` field
        // (an undocumented SDK quirk, confirmed while wiring this up) —
        // ClaudeAgentSdkClient only honors the first terminal event in a
        // stream, so emitting this error now takes precedence over that
        // misleading later "success".
        emit({
          type: 'error',
          message: text || `Claude Agent SDK reported: ${message.error}.`,
        });
      } else if (text.length > 0) {
        emit({ type: 'text', text });
      }
    } else if (message.type === 'result') {
      if (message.subtype === 'success') {
        emit({ type: 'done' });
      } else {
        const errorMessage =
          (message.errors ?? []).join('; ') ||
          `Agent run failed: ${message.subtype}`;
        // `error_max_budget_usd` is the SDK's own structured signal for
        // Claude Code's usage-window/overage limit — the one case this
        // MVP can actually detect reliably (see proposal.md's Non-goals:
        // there's no way to check remaining budget *before* hitting it).
        if (message.subtype === 'error_max_budget_usd') {
          emit({ type: 'overage', message: errorMessage });
        }
        emit({ type: 'error', message: errorMessage });
      }
    }
  }
}

main().catch((error) => {
  emit({ type: 'error', message: error?.message ?? String(error) });
  process.exitCode = 1;
});
