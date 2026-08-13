// core/agent/claude_agent_sdk_client.dart — ClaudeAgentSdkClient (core layer).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aion/core/agent/agent_bridge_locator.dart';
import 'package:aion/core/contracts/agent_model_client.dart';

/// Sole [AgentModelClient] implementation for this MVP: spawns a bundled
/// Node.js bridge process (`agent_bridge/index.mjs`) per [run] call and
/// parses its NDJSON stdout into [AgentEvent]s. Authenticates via the
/// user's existing Claude plan (Pro/Max) — no API key handled by Aion.
/// Desktop-only, same `isDesktop`-style gate as `GitRepositoryClient`'s
/// callers — construction is safe on any platform, but [run] surfaces a
/// readable [AgentErrorEvent] rather than working if `dart:io Process`
/// can't actually spawn `node` (e.g. web). When [AgentRequest.toolsEnabled]
/// is set, [AgentRequest.workingDirectory] is passed through to the
/// spawned process's cwd and `toolsEnabled` is forwarded to the bridge, so
/// file edits/git/bash land in the actual project checkout.
///
/// When [AgentRequest.tools] is non-empty, the spawned process's stdin is
/// kept open for the run's whole duration (rather than closed right after
/// the initial request line) so a `"tool_call_request"` line from the
/// bridge can be answered with a matching reply line — see
/// [_handleToolCallRequest] and
/// `aion-arch/changes/mid-task-chat-branching/design.md` §3.
class ClaudeAgentSdkClient implements AgentModelClient {
  /// Creates a [ClaudeAgentSdkClient] that resolves the bridge script's
  /// path via [bridgeLocator].
  ClaudeAgentSdkClient(this._bridgeLocator);

  final AgentBridgeLocator _bridgeLocator;

  @override
  Future<Stream<AgentEvent>> run(AgentRequest request) async {
    final controller = StreamController<AgentEvent>();
    final scriptPath = _bridgeLocator.resolve();

    final Process process;
    try {
      process = await Process.start('node', [
        scriptPath,
      ], workingDirectory: request.workingDirectory);
    } catch (error) {
      controller.add(
        AgentErrorEvent(
          'Node.js not found — install Node.js and ensure `node` is on '
          'your PATH. ($error)',
        ),
      );
      unawaited(controller.close());
      return controller.stream;
    }

    process.stdin.writeln(
      jsonEncode({
        'prompt': request.prompt,
        'model': request.model,
        'toolsEnabled': request.toolsEnabled,
        'tools': request.tools
            .map(
              (tool) => {
                'name': tool.name,
                'description': tool.description,
                'inputSchema': tool.inputSchema,
              },
            )
            .toList(),
      }),
    );
    // Stdin stays open for the run's whole duration (rather than closed
    // right after this line) so a `"tool_call_request"` line can be
    // answered with a matching reply — see [_handleToolCallRequest] and
    // design.md §3. Closed once the process exits, below.

    var sawTerminalEvent = false;
    final stderrBuffer = StringBuffer();

    late final StreamSubscription<String> stdoutSubscription;
    stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          // Ignore everything once a terminal event has been seen —
          // [AgentEvent]'s contract promises exactly one. Empirically,
          // the bridge's underlying SDK can still emit a misleading
          // trailing message after a real failure (e.g. a `result`
          // reporting `subtype: 'success'` moments after an
          // authentication failure already ended the run) — the first
          // terminal event is authoritative, not the last.
          if (sawTerminalEvent) return;

          Map<String, dynamic>? json;
          if (line.trim().isNotEmpty) {
            try {
              json = jsonDecode(line) as Map<String, dynamic>;
            } catch (_) {
              json = null;
            }
          }

          // `"tool_call_request"` doesn't go through [_parseLine]'s
          // normal return-an-[AgentEvent] path: it needs to pause the
          // subscription, await [AgentRequest.onToolCall], and write a
          // reply line before any further stdout is processed, so two
          // concurrent tool calls can never interleave their replies.
          if (json != null && json['type'] == 'tool_call_request') {
            stdoutSubscription.pause();
            unawaited(
              _handleToolCallRequest(
                json,
                request,
                controller,
                process,
              ).whenComplete(stdoutSubscription.resume),
            );
            return;
          }

          final event = _parseLine(line);
          if (event == null) return;
          if (event is AgentDoneEvent || event is AgentErrorEvent) {
            sawTerminalEvent = true;
          }
          controller.add(event);
        });

    process.stderr.transform(utf8.decoder).listen(stderrBuffer.write);

    unawaited(
      process.exitCode.then((exitCode) async {
        if (!sawTerminalEvent) {
          final message = stderrBuffer.length > 0
              ? stderrBuffer.toString().trim()
              : 'agent_bridge exited with code $exitCode and no result.';
          controller.add(AgentErrorEvent(message));
        }
        await process.stdin.close();
        await controller.close();
      }),
    );

    return controller.stream;
  }

  /// Handles one `"tool_call_request"` line from the bridge (already
  /// decoded as [json]): emits [AgentToolCallEvent] on [controller],
  /// awaits [request]'s [AgentRequest.onToolCall] for the result, then
  /// writes the matching `{"toolCallId":...,"result":...}` reply line to
  /// [process]'s stdin so the bridge — and the model's in-progress turn —
  /// can continue. See
  /// `aion-arch/changes/mid-task-chat-branching/design.md` §3.
  Future<void> _handleToolCallRequest(
    Map<String, dynamic> json,
    AgentRequest request,
    StreamController<AgentEvent> controller,
    Process process,
  ) async {
    final toolCallId = json['toolCallId'] as String? ?? '';
    final toolName = json['name'] as String? ?? '';
    final arguments = (json['arguments'] as Map<String, dynamic>?) ?? const {};
    controller.add(AgentToolCallEvent(toolCallId, toolName, arguments));
    final result = await request.onToolCall!(toolCallId, toolName, arguments);
    process.stdin.writeln(
      jsonEncode({'toolCallId': toolCallId, 'result': result}),
    );
  }

  /// Parses one NDJSON line from `agent_bridge/index.mjs`'s stdout into an
  /// [AgentEvent], matching the shapes it emits:
  /// `{"type":"text",...}`, `{"type":"tool_use",...}`,
  /// `{"type":"done","inputTokens":123,"outputTokens":456}`,
  /// `{"type":"error",...}`, `{"type":"overage",...}`. Returns `null` for
  /// a blank or unrecognized line rather than throwing — a malformed line
  /// shouldn't crash the run. `{"type":"tool_call_request",...}` is never
  /// passed here — [run]'s listener intercepts and routes it to
  /// [_handleToolCallRequest] instead.
  AgentEvent? _parseLine(String line) {
    if (line.trim().isEmpty) return null;
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    return switch (json['type']) {
      'text' => AgentTextEvent(json['text'] as String? ?? ''),
      'tool_use' => AgentToolUseEvent(
        json['name'] as String? ?? 'tool',
        json['summary'] as String?,
      ),
      'done' => AgentDoneEvent(
        inputTokens: json['inputTokens'] as int?,
        outputTokens: json['outputTokens'] as int?,
      ),
      'error' => AgentErrorEvent(
        json['message'] as String? ?? 'Unknown error.',
      ),
      'overage' => AgentOverageDetectedEvent(json['message'] as String? ?? ''),
      _ => null,
    };
  }
}
