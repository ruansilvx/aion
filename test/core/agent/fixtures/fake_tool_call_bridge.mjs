// test/core/agent/fixtures/fake_tool_call_bridge.mjs — minimal stand-in
// for agent_bridge/index.mjs, used only by
// claude_agent_sdk_client_test.dart's tool-call round-trip test. Never
// touches the real Claude Agent SDK, node_modules, or network. Reads the
// initial request line and, if it carries a non-empty `tools` array,
// emits one "session" line followed by one "tool_call_request" line and
// awaits the matching {"toolCallId":...,"result":...} reply on stdin
// before finishing — exercising exactly the wire protocol
// ClaudeAgentSdkClient.run implements
// (aion-arch/changes/mid-task-chat-branching/design.md §3 and
// aion-arch/changes/decision-graph-agentjudgment-condition/design.md §3).

import { createInterface } from 'node:readline';

function emit(event) {
  process.stdout.write(`${JSON.stringify(event)}\n`);
}

async function main() {
  const rl = createInterface({ input: process.stdin, terminal: false });
  const iterator = rl[Symbol.asyncIterator]();

  const first = await iterator.next();
  const request = JSON.parse(first.value);

  if (Array.isArray(request.tools) && request.tools.length > 0) {
    emit({ type: 'session', sessionId: 'test-session-1' });
    emit({
      type: 'tool_call_request',
      toolCallId: 'test-call-1',
      name: request.tools[0].name,
      arguments: { title: 'From fixture' },
    });
    const replyLine = await iterator.next();
    const reply = JSON.parse(replyLine.value);
    emit({ type: 'text', text: `got:${JSON.stringify(reply.result)}` });
  }

  emit({ type: 'done', inputTokens: 1, outputTokens: 2 });
  rl.close();
}

main().catch((error) => {
  emit({ type: 'error', message: error?.message ?? String(error) });
  process.exitCode = 1;
});
