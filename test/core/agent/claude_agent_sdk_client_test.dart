// test/core/agent/claude_agent_sdk_client_test.dart — ClaudeAgentSdkClient tests.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:aion/core/agent/agent_bridge_locator.dart';
import 'package:aion/core/agent/claude_agent_sdk_client.dart';
import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/core/contracts/agent_tool_definition.dart';

/// Points [ClaudeAgentSdkClient] at
/// `test/core/agent/fixtures/fake_tool_call_bridge.mjs` — a minimal
/// stand-in for the real `agent_bridge/index.mjs` that implements just
/// enough of the NDJSON wire protocol (including the tool-call round
/// trip) to exercise `ClaudeAgentSdkClient.run`'s Dart-side handling
/// without depending on the real Claude Agent SDK, its `node_modules`, or
/// network access.
class _FixtureBridgeLocator extends AgentBridgeLocator {
  @override
  String resolve() => p.join(
    Directory.current.path,
    'test',
    'core',
    'agent',
    'fixtures',
    'fake_tool_call_bridge.mjs',
  );
}

void main() {
  group('ClaudeAgentSdkClient tool-call round trip', () {
    test(
      'emits AgentToolCallEvent and feeds onToolCall\'s result back',
      () async {
        final calls = <(String, String, Map<String, dynamic>)>[];
        final client = ClaudeAgentSdkClient(_FixtureBridgeLocator());

        final stream = await client.run(
          AgentRequest(
            prompt: 'irrelevant',
            model: 'irrelevant',
            tools: const [
              AgentToolDefinition(
                name: 'branch_ticket',
                description: 'test tool',
                inputSchema: {'type': 'object', 'properties': {}},
              ),
            ],
            onToolCall: (toolCallId, toolName, arguments) async {
              calls.add((toolCallId, toolName, arguments));
              return {'accepted': true};
            },
          ),
        );
        final events = await stream.toList();

        expect(calls, hasLength(1));
        expect(calls.single.$1, 'test-call-1');
        expect(calls.single.$2, 'branch_ticket');
        expect(calls.single.$3, {'title': 'From fixture'});

        final toolCallEvents = events.whereType<AgentToolCallEvent>();
        expect(toolCallEvents, hasLength(1));
        expect(toolCallEvents.single.toolCallId, 'test-call-1');
        expect(toolCallEvents.single.toolName, 'branch_ticket');

        final textEvents = events.whereType<AgentTextEvent>();
        expect(textEvents, hasLength(1));
        expect(textEvents.single.text, contains('"accepted":true'));

        expect(events.last, isA<AgentDoneEvent>());
        final done = events.last as AgentDoneEvent;
        expect(done.inputTokens, 1);
        expect(done.outputTokens, 2);
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      'a request with no tools never emits AgentToolCallEvent',
      () async {
        final client = ClaudeAgentSdkClient(_FixtureBridgeLocator());

        final stream = await client.run(
          const AgentRequest(prompt: 'irrelevant', model: 'irrelevant'),
        );
        final events = await stream.toList();

        expect(events.whereType<AgentToolCallEvent>(), isEmpty);
        expect(events.last, isA<AgentDoneEvent>());
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );
  });
}
