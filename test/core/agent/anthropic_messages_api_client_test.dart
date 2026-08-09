import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/agent/anthropic_messages_api_client.dart';
import 'package:aion/core/contracts/agent_model_client.dart';

class MockDio extends Mock implements Dio {}

Response<ResponseBody> _response(String body, int statusCode) {
  return Response<ResponseBody>(
    requestOptions: RequestOptions(path: 'https://api.anthropic.com/v1/messages'),
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

void main() {
  late MockDio dio;

  setUp(() {
    dio = MockDio();
  });

  group('AnthropicMessagesApiClient', () {
    test(
      'run emits an immediate AgentErrorEvent and never calls Dio when no '
      'API key is available',
      () async {
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
      },
    );

    test(
      'run emits an immediate AgentErrorEvent and never calls Dio when '
      'toolsEnabled is true',
      () async {
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
      },
    );

    test(
      'run parses a successful SSE stream into AgentTextEvents followed by '
      'one AgentDoneEvent carrying the stashed token counts',
      () async {
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
      },
    );

    test(
      'run maps a 429 response to AgentOverageDetectedEvent, not '
      'AgentErrorEvent',
      () async {
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
      },
    );

    test(
      'run maps a non-429 error status to AgentErrorEvent carrying the '
      "API's own error message",
      () async {
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
      },
    );
  });
}
