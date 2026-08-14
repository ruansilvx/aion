// test/core/agent/fixtures/fake_sleep_bridge.mjs — minimal stand-in for
// agent_bridge/index.mjs, used only by claude_agent_sdk_client_test.dart's
// cancellation test. Reads the initial request line, then sleeps far
// longer than any test needs to wait before cancelling — giving
// ClaudeAgentSdkClient.cancel time to signal the process before it would
// ever finish on its own. Never emits a "done"/"error" line, so a
// successful cancellation is the only way this process's stdout ever
// produces a terminal AgentEvent on the Dart side.

import { createInterface } from 'node:readline';

async function main() {
  const rl = createInterface({ input: process.stdin, terminal: false });
  const iterator = rl[Symbol.asyncIterator]();
  await iterator.next(); // Consume the initial request line.

  // Long enough that no test should ever observe this fire — the test
  // cancels well before this elapses and asserts on the process exiting
  // early instead.
  await new Promise((resolve) => setTimeout(resolve, 30000));
}

main();
