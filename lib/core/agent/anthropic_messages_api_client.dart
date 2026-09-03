// core/agent/anthropic_messages_api_client.dart — AnthropicMessagesApiClient (core layer).

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:aion/core/contracts/agent_model_client.dart';

/// The outcome of one HTTP POST + SSE-stream pass inside
/// [AnthropicMessagesApiClient._streamResponse]'s tool-calling loop. Not
/// itself an [AgentEvent] — an internal record consumed by that loop to
/// decide whether to emit a terminal event, a summed [AgentDoneEvent], or
/// re-POST with a `tool_result` continuation. See design.md §4.
typedef _PassResult = ({
  /// `true` once this pass reached a definitive SSE signal
  /// (`message_stop`, an in-stream `error` block, a non-2xx status, or an
  /// empty body) — `false` if the connection stream ended before any of
  /// those, which the caller treats the same as today's "connection
  /// closed before the run finished" case.
  bool completed,

  /// A terminal [AgentEvent] this pass produced directly (error/overage) —
  /// `null` when the pass completed normally (whether or not it needs a
  /// tool-result continuation).
  AgentEvent? terminalEvent,

  /// `tool_use` content blocks (`{'id', 'name', 'input'}`) this pass's
  /// assistant turn made, in order — non-empty only when
  /// `message_delta.delta.stop_reason == 'tool_use'`.
  List<Map<String, dynamic>> toolCalls,

  /// This pass's full assistant-turn content blocks (text and tool_use,
  /// in the order the API streamed them) — appended verbatim to
  /// `messages` for the follow-up POST when [toolCalls] is non-empty.
  List<Map<String, dynamic>> assistantContent,

  /// This pass's own `input_tokens`, or `null` if never reported.
  int? inputTokens,

  /// This pass's own `output_tokens`, or `null` if never reported.
  int? outputTokens,
});

/// Second [AgentModelClient] implementation: calls the Anthropic Messages
/// API (`https://api.anthropic.com/v1/messages`) directly over HTTP,
/// parsing its server-sent-events stream into the same [AgentEvent]
/// shapes `ClaudeAgentSdkClient` produces from the bundled Node.js
/// bridge's NDJSON stdout. Unlike that client, this one never spawns a
/// process — a plain [Dio]-backed HTTP call, authenticated via
/// [_getApiKey] rather than the user's Claude plan. See
/// `AIO-110` §2.
///
/// When [AgentRequest.tools] is non-empty, a run may issue more than one
/// POST: the Messages API's native `tool_use`/`tool_result` loop is
/// implemented as an internal `while` loop inside [_streamResponse]
/// (via [_postOnce]) rather than a single request — each pass ending in
/// `stop_reason: 'tool_use'` awaits [AgentRequest.onToolCall] and re-POSTs
/// with a `tool_result` continuation, repeating until a pass ends some
/// other way. `inputTokens`/`outputTokens` on the final [AgentDoneEvent]
/// are summed across every POST in the loop. See
/// `AIO-1118` §4.
class AnthropicMessagesApiClient implements AgentModelClient {
  /// Creates an [AnthropicMessagesApiClient] using [_dio] for the HTTP
  /// call, resolving the API key on each [run] via [_getApiKey] (so a key
  /// saved after construction is picked up without recreating this
  /// client).
  AnthropicMessagesApiClient(this._dio, this._getApiKey);

  final Dio _dio;
  final Future<String?> Function() _getApiKey;

  /// Runs currently in flight, keyed by [AgentRequest.runId]. Only runs
  /// started with a non-null `runId` are tracked — a run with no `runId`
  /// can't be cancelled, so there is nothing for [cancel] to look up.
  /// One [CancelToken] per run, shared across every POST in that run's
  /// tool-calling re-POST loop, so cancelling mid-loop takes effect on
  /// whichever pass is currently in flight. Added for
  /// `AIO-1400`; see that change's design.md §2.
  final _cancelTokens = <String, CancelToken>{};

  @override
  void cancel(String runId) {
    _cancelTokens[runId]?.cancel();
  }

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
      // tool intent. Independent of `AgentRequest.tools` — see this
      // class's dartdoc.
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
    final runId = request.runId;
    final cancelToken = CancelToken();
    if (runId != null) _cancelTokens[runId] = cancelToken;
    unawaited(_streamResponse(controller, request, apiKey, cancelToken));
    return controller.stream;
  }

  /// Runs the tool-calling loop and feeds [controller] until it resolves,
  /// then closes it. Isolated from [run] so [run] can return its stream to
  /// the caller immediately, matching `ClaudeAgentSdkClient`'s shape
  /// (`run` returns before the process/call has finished). Each iteration
  /// is one [_postOnce] pass; a pass ending in `stop_reason: 'tool_use'`
  /// awaits [AgentRequest.onToolCall] and re-POSTs with a `tool_result`
  /// continuation appended to `messages` (design.md §4) rather than
  /// returning.
  Future<void> _streamResponse(
    StreamController<AgentEvent> controller,
    AgentRequest request,
    String apiKey,
    CancelToken cancelToken,
  ) async {
    // Local, per-call mutable state — this client instance is shared
    // (registered once in `main.dart`), so token counts and conversation
    // history stashed while parsing one run's SSE stream must never leak
    // into a concurrent one.
    int? totalInputTokens;
    int? totalOutputTokens;
    // Gates the `finally` block's synthetic closing error below — distinct
    // from `AgentEvent`'s own "exactly one terminal event" contract
    // (`AgentDoneEvent`/`AgentErrorEvent` only, per its dartdoc): a 429
    // response is handled in one shot with no further stream to read, so
    // it also counts as "handled" here even though
    // `AgentOverageDetectedEvent` isn't itself a terminal event type.
    var responseHandled = false;

    final messages = <Map<String, dynamic>>[
      {'role': 'user', 'content': request.prompt},
    ];

    try {
      while (true) {
        final pass = await _postOnce(
          controller: controller,
          request: request,
          apiKey: apiKey,
          messages: messages,
          cancelToken: cancelToken,
        );
        if (pass.inputTokens != null) {
          totalInputTokens = (totalInputTokens ?? 0) + pass.inputTokens!;
        }
        if (pass.outputTokens != null) {
          totalOutputTokens = (totalOutputTokens ?? 0) + pass.outputTokens!;
        }

        if (!pass.completed) break; // Falls to the `finally` block below.

        if (pass.terminalEvent != null) {
          controller.add(pass.terminalEvent!);
          responseHandled = true;
          break;
        }

        if (pass.toolCalls.isEmpty) {
          // A genuine finish (`end_turn`/`max_tokens`/`stop_sequence`) —
          // the summed AgentDoneEvent covers every POST in the loop, not
          // just this last one.
          controller.add(
            AgentDoneEvent(
              inputTokens: totalInputTokens,
              outputTokens: totalOutputTokens,
            ),
          );
          responseHandled = true;
          break;
        }

        // `stop_reason: 'tool_use'` — resolve every tool call this pass
        // made, then loop again with the continuation appended.
        messages.add({'role': 'assistant', 'content': pass.assistantContent});
        final toolResults = <Map<String, dynamic>>[];
        for (final call in pass.toolCalls) {
          final toolCallId = call['id'] as String;
          final toolName = call['name'] as String;
          final arguments =
              (call['input'] as Map<String, dynamic>?) ?? const {};
          controller.add(AgentToolCallEvent(toolCallId, toolName, arguments));
          // No session concept on this provider (see
          // AnthropicMessagesApiProvider.supportsSessionResume) — always null.
          final result = await request.onToolCall!(
            toolCallId,
            toolName,
            arguments,
            null,
          );
          toolResults.add({
            'type': 'tool_result',
            'tool_use_id': toolCallId,
            'content': jsonEncode(result),
          });
        }
        messages.add({'role': 'user', 'content': toolResults});
      }
    } catch (error) {
      if (!responseHandled) {
        if (error is DioException && error.type == DioExceptionType.cancel) {
          controller.add(const AgentCancelledEvent());
        } else {
          controller.add(AgentErrorEvent(error.toString()));
        }
        responseHandled = true;
      }
    } finally {
      if (!responseHandled) {
        controller.add(
          const AgentErrorEvent('Connection closed before the run finished.'),
        );
      }
      final runId = request.runId;
      if (runId != null) _cancelTokens.remove(runId);
      await controller.close();
    }
  }

  /// Issues one POST against [messages] (the full conversation so far,
  /// including any prior `tool_use`/`tool_result` continuations) and
  /// parses its SSE response into a [_PassResult]. Live [AgentTextEvent]s
  /// are added to [controller] as `text_delta` chunks stream in; every
  /// other outcome (errors, tool calls, token counts) is reported via the
  /// returned record instead, for [_streamResponse]'s loop to act on.
  Future<_PassResult> _postOnce({
    required StreamController<AgentEvent> controller,
    required AgentRequest request,
    required String apiKey,
    required List<Map<String, dynamic>> messages,
    required CancelToken cancelToken,
  }) async {
    int? inputTokens;
    int? outputTokens;
    String? stopReason;
    AgentEvent? terminalEvent;
    var passComplete = false;
    final blockOrder = <int>[];
    final blocks = <int, Map<String, dynamic>>{};
    final jsonBuffers = <int, StringBuffer>{};

    void handleSseJson(Map<String, dynamic> json) {
      switch (json['type'] as String?) {
        case 'message_start':
          final usage = (json['message'] as Map?)?['usage'] as Map?;
          inputTokens = usage?['input_tokens'] as int?;
        case 'content_block_start':
          // `index` defaults to 0 rather than a hard cast — a
          // single-content-block reply (the common case before this
          // change added multi-block/tool_use handling) is still valid
          // SSE without one.
          final index = (json['index'] as int?) ?? 0;
          final block = json['content_block'] as Map? ?? const {};
          blockOrder.add(index);
          if (block['type'] == 'tool_use') {
            blocks[index] = {
              'type': 'tool_use',
              'id': block['id'],
              'name': block['name'],
            };
            jsonBuffers[index] = StringBuffer();
          } else {
            blocks[index] = {'type': 'text', 'text': ''};
          }
        case 'content_block_delta':
          final index = (json['index'] as int?) ?? 0;
          final delta = json['delta'] as Map? ?? const {};
          if (delta['type'] == 'text_delta') {
            final text = delta['text'] as String? ?? '';
            final block = blocks[index];
            if (block != null) block['text'] = '${block['text']}$text';
            if (text.isNotEmpty) controller.add(AgentTextEvent(text));
          } else if (delta['type'] == 'input_json_delta') {
            jsonBuffers[index]?.write(delta['partial_json'] as String? ?? '');
          }
        case 'content_block_stop':
          final index = (json['index'] as int?) ?? 0;
          final buffer = jsonBuffers[index];
          if (buffer != null) {
            final raw = buffer.toString();
            var input = <String, dynamic>{};
            if (raw.trim().isNotEmpty) {
              try {
                input = jsonDecode(raw) as Map<String, dynamic>;
              } catch (_) {
                // Malformed partial JSON — treat as no arguments rather
                // than failing the whole run.
              }
            }
            blocks[index]?['input'] = input;
          }
        case 'message_delta':
          final usage = json['usage'] as Map?;
          outputTokens = usage?['output_tokens'] as int? ?? outputTokens;
          stopReason = (json['delta'] as Map?)?['stop_reason'] as String?;
        case 'message_stop':
          passComplete = true;
        case 'error':
          final message =
              (json['error'] as Map?)?['message'] as String? ??
              'Unknown error.';
          terminalEvent = AgentErrorEvent(message);
          passComplete = true;
      }
    }

    final response = await _dio.post<ResponseBody>(
      _messagesEndpoint,
      data: {
        'model': request.model,
        'max_tokens': _maxTokens,
        'stream': true,
        'messages': messages,
        if (request.tools.isNotEmpty)
          'tools': request.tools
              .map(
                (tool) => {
                  'name': tool.name,
                  'description': tool.description,
                  'input_schema': tool.inputSchema,
                },
              )
              .toList(),
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
      cancelToken: cancelToken,
    );

    final body = response.data;
    final statusCode = response.statusCode ?? 0;
    if (body == null) {
      return (
        completed: true,
        terminalEvent: const AgentErrorEvent('Empty response from Anthropic.'),
        toolCalls: const <Map<String, dynamic>>[],
        assistantContent: const <Map<String, dynamic>>[],
        inputTokens: null,
        outputTokens: null,
      );
    }
    if (statusCode < 200 || statusCode >= 300) {
      final raw = await _readAll(body.stream);
      final message = _extractErrorMessage(raw) ?? 'HTTP $statusCode error.';
      return (
        completed: true,
        terminalEvent: statusCode == 429
            ? AgentOverageDetectedEvent(message)
            : AgentErrorEvent(message),
        toolCalls: const <Map<String, dynamic>>[],
        assistantContent: const <Map<String, dynamic>>[],
        inputTokens: null,
        outputTokens: null,
      );
    }

    var buffer = '';
    await for (final chunk in body.stream) {
      buffer += utf8.decode(chunk, allowMalformed: true);
      var boundary = buffer.indexOf('\n\n');
      while (boundary != -1 && !passComplete) {
        final json = _decodeSseBlock(buffer.substring(0, boundary));
        buffer = buffer.substring(boundary + 2);
        if (json != null) handleSseJson(json);
        boundary = buffer.indexOf('\n\n');
      }
      if (passComplete) break;
    }

    if (!passComplete) {
      return (
        completed: false,
        terminalEvent: null,
        toolCalls: const <Map<String, dynamic>>[],
        assistantContent: const <Map<String, dynamic>>[],
        inputTokens: inputTokens,
        outputTokens: outputTokens,
      );
    }
    if (terminalEvent != null) {
      return (
        completed: true,
        terminalEvent: terminalEvent,
        toolCalls: const <Map<String, dynamic>>[],
        assistantContent: const <Map<String, dynamic>>[],
        inputTokens: inputTokens,
        outputTokens: outputTokens,
      );
    }

    final assistantContent = blockOrder
        .map((index) => blocks[index])
        .whereType<Map<String, dynamic>>()
        .toList();
    final toolCalls = stopReason == 'tool_use'
        ? assistantContent
              .where((block) => block['type'] == 'tool_use')
              .toList()
        : const <Map<String, dynamic>>[];

    return (
      completed: true,
      terminalEvent: null,
      toolCalls: toolCalls,
      assistantContent: assistantContent,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
    );
  }

  /// Extracts one SSE block's `data:` line and JSON-decodes it, or returns
  /// `null` for a block with no `data:` line or malformed JSON — a
  /// malformed block shouldn't crash the run.
  Map<String, dynamic>? _decodeSseBlock(String block) {
    String? dataLine;
    for (final line in block.split('\n')) {
      if (line.startsWith('data:')) {
        dataLine = line.substring(5).trim();
      }
    }
    if (dataLine == null || dataLine.isEmpty) return null;
    try {
      return jsonDecode(dataLine) as Map<String, dynamic>;
    } catch (_) {
      return null;
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
