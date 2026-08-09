// core/agent/anthropic_messages_api_client.dart — AnthropicMessagesApiClient (core layer).

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:aion/core/contracts/agent_model_client.dart';

/// Second [AgentModelClient] implementation: calls the Anthropic Messages
/// API (`https://api.anthropic.com/v1/messages`) directly over HTTP,
/// parsing its server-sent-events stream into the same [AgentEvent]
/// shapes `ClaudeAgentSdkClient` produces from the bundled Node.js
/// bridge's NDJSON stdout. Unlike that client, this one never spawns a
/// process — a plain [Dio]-backed HTTP call, authenticated via
/// [_getApiKey] rather than the user's Claude plan. See
/// `aion-arch/changes/anthropic-messages-api-provider/design.md` §2.
class AnthropicMessagesApiClient implements AgentModelClient {
  /// Creates an [AnthropicMessagesApiClient] using [_dio] for the HTTP
  /// call, resolving the API key on each [run] via [_getApiKey] (so a key
  /// saved after construction is picked up without recreating this
  /// client).
  AnthropicMessagesApiClient(this._dio, this._getApiKey);

  final Dio _dio;
  final Future<String?> Function() _getApiKey;

  static const _messagesEndpoint = 'https://api.anthropic.com/v1/messages';

  /// Anthropic Messages API version header value — a fixed API version
  /// string, not a model version; stable across model releases.
  static const _anthropicVersion = '2023-06-01';

  /// Conservative fixed output-length cap for every request. Nothing in
  /// [AgentRequest] carries an output-length hint today (design.md §2), so
  /// this is a single constant rather than derived per-call.
  static const _maxTokens = 4096;

  @override
  Future<Stream<AgentEvent>> run(AgentRequest request) async {
    if (request.toolsEnabled) {
      // Defensive, not reachable via normal routing today —
      // `ModelPhaseToolAccess.requiredToolAccessTier` never offers this
      // provider's models to the Execution tier (the only phase that sets
      // `toolsEnabled: true`). Fails loud rather than silently dropping
      // tool intent.
      return Stream.value(
        const AgentErrorEvent(
          'This provider does not support tool-enabled runs.',
        ),
      );
    }
    final apiKey = await _getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return Stream.value(
        const AgentErrorEvent(
          'No API key configured — add one in Settings → Providers.',
        ),
      );
    }

    final controller = StreamController<AgentEvent>();
    unawaited(_streamResponse(controller, request, apiKey));
    return controller.stream;
  }

  /// Runs the actual HTTP call and feeds [controller] until the stream
  /// resolves, then closes it. Isolated from [run] so [run] can return its
  /// stream to the caller immediately, matching `ClaudeAgentSdkClient`'s
  /// shape (`run` returns before the process/call has finished).
  Future<void> _streamResponse(
    StreamController<AgentEvent> controller,
    AgentRequest request,
    String apiKey,
  ) async {
    // Local, per-call mutable state — this client instance is shared
    // (registered once in `main.dart`), so token counts stashed while
    // parsing one run's SSE stream must never leak into a concurrent one.
    int? inputTokens;
    int? outputTokens;
    // Gates the `finally` block's synthetic closing error below — distinct
    // from `AgentEvent`'s own "exactly one terminal event" contract
    // (`AgentDoneEvent`/`AgentErrorEvent` only, per its dartdoc): a 429
    // response is handled in one shot with no further stream to read, so
    // it also counts as "handled" here even though
    // `AgentOverageDetectedEvent` isn't itself a terminal event type.
    var responseHandled = false;

    AgentEvent? parseSseBlock(String block) {
      String? dataLine;
      for (final line in block.split('\n')) {
        if (line.startsWith('data:')) {
          dataLine = line.substring(5).trim();
        }
      }
      if (dataLine == null || dataLine.isEmpty) return null;
      final Map<String, dynamic> json;
      try {
        json = jsonDecode(dataLine) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
      switch (json['type'] as String?) {
        case 'message_start':
          final usage = (json['message'] as Map?)?['usage'] as Map?;
          inputTokens = usage?['input_tokens'] as int?;
          return null;
        case 'content_block_delta':
          final delta = json['delta'] as Map?;
          return delta?['type'] == 'text_delta'
              ? AgentTextEvent(delta?['text'] as String? ?? '')
              : null;
        case 'message_delta':
          final usage = json['usage'] as Map?;
          outputTokens = usage?['output_tokens'] as int? ?? outputTokens;
          return null;
        case 'message_stop':
          return AgentDoneEvent(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
          );
        case 'error':
          final message =
              (json['error'] as Map?)?['message'] as String? ??
              'Unknown error.';
          return AgentErrorEvent(message);
        default:
          return null;
      }
    }

    try {
      final response = await _dio.post<ResponseBody>(
        _messagesEndpoint,
        data: {
          'model': request.model,
          'max_tokens': _maxTokens,
          'stream': true,
          'messages': [
            {'role': 'user', 'content': request.prompt},
          ],
        },
        options: Options(
          headers: {
            'x-api-key': apiKey,
            'anthropic-version': _anthropicVersion,
            'content-type': 'application/json',
          },
          responseType: ResponseType.stream,
          // Handled manually below (429 vs. every other non-2xx status
          // map to different AgentEvent variants) rather than letting Dio
          // throw a DioException for any non-2xx response.
          validateStatus: (_) => true,
        ),
      );

      final body = response.data;
      final statusCode = response.statusCode ?? 0;
      if (body == null) {
        controller.add(
          const AgentErrorEvent('Empty response from Anthropic.'),
        );
        responseHandled = true;
      } else if (statusCode < 200 || statusCode >= 300) {
        final raw = await _readAll(body.stream);
        final message = _extractErrorMessage(raw) ?? 'HTTP $statusCode error.';
        controller.add(
          statusCode == 429
              ? AgentOverageDetectedEvent(message)
              : AgentErrorEvent(message),
        );
        responseHandled = true;
      } else {
        var buffer = '';
        await for (final chunk in body.stream) {
          buffer += utf8.decode(chunk, allowMalformed: true);
          var boundary = buffer.indexOf('\n\n');
          while (boundary != -1 && !responseHandled) {
            final event = parseSseBlock(buffer.substring(0, boundary));
            buffer = buffer.substring(boundary + 2);
            if (event != null) {
              controller.add(event);
              if (event is AgentDoneEvent || event is AgentErrorEvent) {
                responseHandled = true;
              }
            }
            boundary = buffer.indexOf('\n\n');
          }
          if (responseHandled) break;
        }
      }
    } catch (error) {
      if (!responseHandled) {
        controller.add(AgentErrorEvent(error.toString()));
        responseHandled = true;
      }
    } finally {
      if (!responseHandled) {
        controller.add(
          const AgentErrorEvent(
            'Connection closed before the run finished.',
          ),
        );
      }
      await controller.close();
    }
  }

  /// Reads [stream] to completion and decodes it as UTF-8 — used only for
  /// a non-2xx response's body, which is small (a JSON error object), not
  /// a real content stream.
  Future<String> _readAll(Stream<Uint8List> stream) async {
    final buffer = StringBuffer();
    await for (final chunk in stream) {
      buffer.write(utf8.decode(chunk, allowMalformed: true));
    }
    return buffer.toString();
  }

  /// Pulls a human-readable message out of a non-2xx response body, which
  /// the Messages API shapes as `{"type":"error","error":{"type":"...",
  /// "message":"..."}}`. Returns `null` (letting the caller fall back to a
  /// generic "HTTP `<code>` error." message) if [raw] isn't that shape.
  String? _extractErrorMessage(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) {
        final error = json['error'];
        if (error is Map<String, dynamic>) {
          final message = error['message'];
          if (message is String && message.isNotEmpty) return message;
        }
      }
    } catch (_) {
      // Not JSON — fall through to null.
    }
    return null;
  }
}
