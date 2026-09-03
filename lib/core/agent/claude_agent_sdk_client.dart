// core/agent/claude_agent_sdk_client.dart — ClaudeAgentSdkClient (core layer).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aion/core/agent/agent_bridge_locator.dart';
import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/core/contracts/agent_session_handle.dart';
import 'package:aion/core/contracts/provider_id.dart';

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
/// When [AgentRequest.tools] is non-empty, the spawned process's stdin is kept
/// open for the run's whole duration (rather than closed right after the
/// initial request line) so a `"tool_call_request"` line from the bridge can
/// be answered with a matching reply line — see [_handleToolCallRequest] and
/// `AIO-1118` §3.
///
/// Supports cancellation (see [cancel]): every [AgentRequest] carrying a
/// non-null [AgentRequest.runId] has its spawned [Process] tracked in
/// [_activeRuns] for the run's duration, escalating from `SIGTERM` to
/// `SIGKILL` if the process hasn't exited shortly after the first signal.
/// Added for `AIO-1400`; see its linked Documentation page, §2.
///
/// When [AgentRequest.resumeSessionId] is set, the outgoing request JSON also
/// carries `{'resume': ..., 'forkSession': true}`, resuming and forking that
/// session inside the bridge process rather than starting a fresh
/// conversation. Independently, every bridge process reports its own session
/// id via a `"session"` stdout line the moment the SDK's message stream first
/// carries one — captured per-[run] call so [_handleToolCallRequest] can hand
/// a resumable [AgentSessionHandle] to [AgentRequest.onToolCall]. See
/// `AIO-613` §3.
class ClaudeAgentSdkClient implements AgentModelClient {
  /// Creates a [ClaudeAgentSdkClient] that resolves the bridge script's
  /// path via [bridgeLocator].
  ClaudeAgentSdkClient(this._bridgeLocator);

  final AgentBridgeLocator _bridgeLocator;

  /// How long [cancel] waits after `SIGTERM` before escalating to
  /// `SIGKILL` — long enough for the bridge process to flush and exit
  /// cleanly on its own, short enough that a stuck process doesn't hang
  /// cancellation indefinitely.
  static const _killEscalationDelay = Duration(seconds: 5);

  /// Runs currently in flight, keyed by [AgentRequest.runId]. Only runs
  /// started with a non-null `runId` are tracked — a run with no `runId`
  /// can't be cancelled, so there is nothing for [cancel] to look up.
  final _activeRuns = <String, _ActiveRun>{};

  @override
  void cancel(String runId) {
    final activeRun = _activeRuns[runId];
    if (activeRun == null) return;
    activeRun.cancelled = true;
    activeRun.process.kill(ProcessSignal.sigterm);
    Timer(_killEscalationDelay, () {
      // Only escalate if this exact run is still the one tracked under
      // `runId` — it may have already exited and been replaced by an
      // unrelated later run reusing the same id.
      if (identical(_activeRuns[runId], activeRun)) {
        activeRun.process.kill(ProcessSignal.sigkill);
      }
    });
  }

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

    final runId = request.runId;
    final _ActiveRun? activeRun = runId == null ? null : _ActiveRun(process);
    if (runId != null && activeRun != null) {
      _activeRuns[runId] = activeRun;
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
        if (request.resumeSessionId != null) ...{
          'resume': request.resumeSessionId,
          'forkSession': true,
        },
      }),
    );
    // Stdin stays open for the run's whole duration (rather than closed
    // right after this line) so a `"tool_call_request"` line can be
    // answered with a matching reply — see [_handleToolCallRequest] and
    // design.md §3. Closed once the process exits, below.

    var sawTerminalEvent = false;
    final stderrBuffer = StringBuffer();
    // Captured off a `"session"` stdout line the moment the bridge emits
    // one — scoped to this run(), never exposed as a public [AgentEvent].
    // See [_handleToolCallRequest] and design.md §3.
    String? sessionId;

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

          // `"session"` doesn't go through [_parseLine] either — it's
          // never a public [AgentEvent], just captured for
          // [_handleToolCallRequest] below. See design.md §3.
          if (json != null && json['type'] == 'session') {
            sessionId = json['sessionId'] as String?;
            return;
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
                sessionId,
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
          if (activeRun?.cancelled ?? false) {
            controller.add(const AgentCancelledEvent());
          } else {
            final message = stderrBuffer.length > 0
                ? stderrBuffer.toString().trim()
                : 'agent_bridge exited with code $exitCode and no result.';
            controller.add(AgentErrorEvent(message));
          }
        }
        if (runId != null) _activeRuns.remove(runId);
        await process.stdin.close();
        await controller.close();
      }),
    );

    return controller.stream;
  }

  /// Handles one `"tool_call_request"` line from the bridge (already decoded
  /// as [json]): emits [AgentToolCallEvent] on [controller], awaits
  /// [request]'s [AgentRequest.onToolCall] for the result, then writes the
  /// matching `{"toolCallId":...,"result":...}` reply line to [process]'s
  /// stdin so the bridge — and the model's in-progress turn — can continue.
  /// See `AIO-1118` §3.
  ///
  /// [sessionId] is [run]'s locally-captured session id at the moment this
  /// call fires — `null` if no `"session"` line has arrived yet (defensive;
  /// shouldn't happen in practice, since the bridge always emits it before any
  /// `"tool_call_request"` in the same message batch, but a tool call firing
  /// before it is parsed is not a crash, just a missed opportunity for that
  /// one call). Wrapped into an [AgentSessionHandle] and passed as
  /// [AgentRequest.onToolCall]'s 4th argument. See `AIO-613` §3.
  Future<void> _handleToolCallRequest(
    Map<String, dynamic> json,
    AgentRequest request,
    StreamController<AgentEvent> controller,
    Process process,
    String? sessionId,
  ) async {
    final toolCallId = json['toolCallId'] as String? ?? '';
    final toolName = json['name'] as String? ?? '';
    final arguments = (json['arguments'] as Map<String, dynamic>?) ?? const {};
    controller.add(AgentToolCallEvent(toolCallId, toolName, arguments));
    final session = sessionId == null
        ? null
        : AgentSessionHandle(
            providerId: ProviderId.claudeAgentSdk,
            sessionId: sessionId,
            modelId: request.model,
          );
    final result = await request.onToolCall!(
      toolCallId,
      toolName,
      arguments,
      session,
    );
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
  /// shouldn't crash the run. `{"type":"tool_call_request",...}` and
  /// `{"type":"session",...}` are never passed here — [run]'s listener
  /// intercepts both directly (the former routed to
  /// [_handleToolCallRequest], the latter captured into a local variable)
  /// before either reaches this method.
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

/// One run tracked in [ClaudeAgentSdkClient._activeRuns] — pairs the
/// spawned [process] with whether [ClaudeAgentSdkClient.cancel] has been
/// called for it, so the process-exit handler in
/// [ClaudeAgentSdkClient.run] knows whether to emit [AgentCancelledEvent]
/// instead of [AgentErrorEvent] for an exit with no terminal event seen.
class _ActiveRun {
  /// Creates an [_ActiveRun] tracking [process], not yet cancelled.
  _ActiveRun(this.process);

  /// The spawned bridge process this run's [ClaudeAgentSdkClient.cancel]
  /// call (if any) signals.
  final Process process;

  /// Set by [ClaudeAgentSdkClient.cancel] just before signalling
  /// [process] — read back once [process] exits.
  bool cancelled = false;
}
