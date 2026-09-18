// test/core/agent/fixtures/fake_echo_request_bridge.mjs — minimal
// stand-in for agent_bridge/index.mjs, used only by
// claude_agent_sdk_client_test.dart's request-shape tests (AIO-2962).
// Reads the initial request line and emits it straight back as a single
// "text" event, so a Dart test can assert on exactly what
// ClaudeAgentSdkClient wrote to stdin without depending on the real
// Claude Agent SDK, node_modules, or network.

import { createInterface } from 'node:readline';

function emit(event) {
  process.stdout.write(`${JSON.stringify(event)}\n`);
}

async function main() {
  const rl = createInterface({ input: process.stdin, terminal: false });
  const iterator = rl[Symbol.asyncIterator]();

  const first = await iterator.next();
  const request = JSON.parse(first.value);

  emit({ type: 'text', text: JSON.stringify(request) });
  emit({ type: 'done', inputTokens: 0, outputTokens: 0 });
  rl.close();
}

main().catch((error) => {
  emit({ type: 'error', message: error?.message ?? String(error) });
  process.exitCode = 1;
});
