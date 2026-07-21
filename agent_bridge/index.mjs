// agent_bridge/index.mjs — Node.js bridge invoked by ClaudeAgentSdkClient
// (aion/lib/core/agent/claude_agent_sdk_client.dart). Not part of the
// Flutter build — a plain Node/ESM script.
//
// Reads one JSON request line ({prompt, model}) from stdin, runs it through
// the Claude Agent SDK's query() with tool access disabled (this MVP has no
// coding-execution caller — see
// aion-arch/changes/provider-configuration/design.md §3), and writes one
// NDJSON line per resulting event to stdout:
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
  const { prompt, model } = await readRequest();

  for await (const message of query({
    prompt,
    options: {
      model,
      // No file/git/bash/MCP tool access — every call this MVP makes is
      // plain text-in/text-out (Settings' "Test Connection" and any
      // future ticket-estimation/spec-phase caller). A tool-enabled mode
      // for coding execution is a separate future need with no caller
      // yet — see design.md §3.
      allowedTools: [],
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
