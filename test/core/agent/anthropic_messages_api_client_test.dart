import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/agent/anthropic_messages_api_client.dart';
import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/core/contracts/agent_tool_definition.dart';

class MockDio extends Mock implements Dio {}

Response<ResponseBody> _response(String body, int statusCode) {
  return Response<ResponseBody>(
    requestOptions: RequestOptions(
      path: 'https://api.anthropic.com/v1/messages',
    ),
    statusCode: statusCode,
    data: ResponseBody.fromString(body, statusCode),
  );
}

const _successSse = '''
event: message_start
data: {"type":"message_start","message":{"usage":{"input_tokens":10}}}

event: content_block_delta
data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}

event: content_block_delta
data: {"type":"content_block_delta","delta":{"type":"text_delta","text":" world"}}

event: message_delta
data: {"type":"message_delta","usage":{"output_tokens":5}}

event: message_stop
data: {"type":"message_stop"}

''';

// First-POST SSE for the tool-calling round-trip test: a tool_use content
// block (id-and-name via content_block_start, arguments streamed as
// input_json_delta chunks) ending in stop_reason: 'tool_use'.
const _toolUseSse = '''
event: message_start
data: {"type":"message_start","message":{"usage":{"input_tokens":10}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"branch_ticket"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"title\\":\\"Fix bug\\"}"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":5}}

event: message_stop
data: {"type":"message_stop"}

''';

// Follow-up-POST SSE, once the tool_result continuation has been sent —
// a genuine finish (stop_reason: 'end_turn').
const _followUpSse = '''
event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Done"}}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":3}}

event: message_stop
data: {"type":"message_stop"}

''';

void main() {
  late MockDio dio;

  setUp(() {
    dio = MockDio();
  });

  group('AnthropicMessagesApiClient', () {
    test('run emits an immediate AgentErrorEvent and never calls Dio when no '
        'API key is available', () async {
      final client = AnthropicMessagesApiClient(dio, () async => null);

      final events = await (await client.run(
        const AgentRequest(prompt: 'hi', model: 'claude-sonnet-5'),
      )).toList();

      expect(events, hasLength(1));
      expect(events.single, isA<AgentErrorEvent>());
      verifyNever(
        () => dio.post<ResponseBody>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      );
    });

    test('run emits an immediate AgentErrorEvent and never calls Dio when '
        'toolsEnabled is true', () async {
      final client = AnthropicMessagesApiClient(dio, () async => 'sk-ant-x');

      final events = await (await client.run(
        const AgentRequest(
          prompt: 'hi',
          model: 'claude-sonnet-5',
          toolsEnabled: true,
        ),
      )).toList();

      expect(events, hasLength(1));
      expect(events.single, isA<AgentErrorEvent>());
      verifyNever(
        () => dio.post<ResponseBody>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      );
    });

    test('run parses a successful SSE stream into AgentTextEvents followed by '
        'one AgentDoneEvent carrying the stashed token counts', () async {
      when(
        () => dio.post<ResponseBody>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => _response(_successSse, 200));

      final client = AnthropicMessagesApiClient(dio, () async => 'sk-ant-x');
      final events = await (await client.run(
        const AgentRequest(prompt: 'hi', model: 'claude-sonnet-5'),
      )).toList();

      expect(events, [
        const AgentTextEvent('Hello'),
        const AgentTextEvent(' world'),
        const AgentDoneEvent(inputTokens: 10, outputTokens: 5),
      ]);
    });

    test('run maps a 429 response to AgentOverageDetectedEvent, not '
        'AgentErrorEvent', () async {
      when(
        () => dio.post<ResponseBody>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => _response(
          '{"type":"error","error":{"type":"rate_limit_error",'
          '"message":"Rate limited — too many requests."}}',
          429,
        ),
      );

      final client = AnthropicMessagesApiClient(dio, () async => 'sk-ant-x');
      final events = await (await client.run(
        const AgentRequest(prompt: 'hi', model: 'claude-sonnet-5'),
      )).toList();

      expect(events, hasLength(1));
      expect(
        events.single,
        isA<AgentOverageDetectedEvent>().having(
          (e) => e.message,
          'message',
          'Rate limited — too many requests.',
        ),
      );
    });

    test('run maps a non-429 error status to AgentErrorEvent carrying the '
        "API's own error message", () async {
      when(
        () => dio.post<ResponseBody>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => _response(
          '{"type":"error","error":{"type":"authentication_error",'
          '"message":"Invalid API key."}}',
          401,
        ),
      );

      final client = AnthropicMessagesApiClient(dio, () async => 'sk-ant-x');
      final events = await (await client.run(
        const AgentRequest(prompt: 'hi', model: 'claude-sonnet-5'),
      )).toList();

      expect(events, hasLength(1));
      expect(
        events.single,
        isA<AgentErrorEvent>().having(
          (e) => e.message,
          'message',
          'Invalid API key.',
        ),
      );
    });

    test('run emits AgentToolCallEvent for a tool_use stop_reason, awaits '
        'onToolCall, re-POSTs a tool_result continuation, and sums '
        'inputTokens/outputTokens across both POSTs on the final '
        'AgentDoneEvent', () async {
      final requestBodies = <Map<String, dynamic>>[];
      var callCount = 0;
      when(
        () => dio.post<ResponseBody>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer((invocation) async {
        requestBodies.add(
          invocation.namedArguments[#data] as Map<String, dynamic>,
        );
        callCount += 1;
        return _response(callCount == 1 ? _toolUseSse : _followUpSse, 200);
      });

      final toolCalls = <(String, String, Map<String, dynamic>)>[];
      final client = AnthropicMessagesApiClient(dio, () async => 'sk-ant-x');
      final events = await (await client.run(
        AgentRequest(
          prompt: 'hi',
          model: 'claude-sonnet-5',
          tools: const [
            AgentToolDefinition(
              name: 'branch_ticket',
              description: 'test tool',
              inputSchema: {'type': 'object', 'properties': {}},
            ),
          ],
          onToolCall: (toolCallId, toolName, arguments) async {
            toolCalls.add((toolCallId, toolName, arguments));
            return {'accepted': true};
          },
        ),
      )).toList();

      expect(toolCalls, hasLength(1));
      expect(toolCalls.single.$1, 'toolu_1');
      expect(toolCalls.single.$2, 'branch_ticket');
      expect(toolCalls.single.$3, {'title': 'Fix bug'});

      expect(events, [
        isA<AgentToolCallEvent>()
            .having((e) => e.toolCallId, 'toolCallId', 'toolu_1')
            .having((e) => e.toolName, 'toolName', 'branch_ticket'),
        const AgentTextEvent('Done'),
        const AgentDoneEvent(inputTokens: 10, outputTokens: 8),
      ]);

      // Two POSTs: the first (initial prompt), and the tool_result
      // continuation (design.md §4 step 3) — the second's `messages`
      // carries the original user turn, the assistant's tool_use
      // content, and a new user turn with the tool_result block.
      expect(requestBodies, hasLength(2));
      final continuationMessages =
          requestBodies[1]['messages'] as List<dynamic>;
      expect(continuationMessages, hasLength(3));
      final toolResultMessage = continuationMessages[2] as Map<String, dynamic>;
      expect(toolResultMessage['role'], 'user');
      final toolResultContent = toolResultMessage['content'] as List<dynamic>;
      expect(toolResultContent, hasLength(1));
      final toolResultBlock = toolResultContent.single as Map<String, dynamic>;
      expect(toolResultBlock['type'], 'tool_result');
      expect(toolResultBlock['tool_use_id'], 'toolu_1');
      expect(toolResultBlock['content'], '{"accepted":true}');
    });
  });
}
