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
      process = await Process.start(
        'node',
        [scriptPath],
        workingDirectory: request.workingDirectory,
      );
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
      }),
    );
    unawaited(process.stdin.close());

    var sawTerminalEvent = false;
    final stderrBuffer = StringBuffer();

    process.stdout
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
          final event = _parseLine(line);
          if (event == null) return;
          if (event is AgentDoneEvent || event is AgentErrorEvent) {
            sawTerminalEvent = true;
          }
          controller.add(event);
        });

    process.stderr
        .transform(utf8.decoder)
        .listen(stderrBuffer.write);

    unawaited(
      process.exitCode.then((exitCode) async {
        if (!sawTerminalEvent) {
          final message = stderrBuffer.length > 0
              ? stderrBuffer.toString().trim()
              : 'agent_bridge exited with code $exitCode and no result.';
          controller.add(AgentErrorEvent(message));
        }
        await controller.close();
      }),
    );

    return controller.stream;
  }

  /// Parses one NDJSON line from `agent_bridge/index.mjs`'s stdout into an
  /// [AgentEvent], matching the shapes it emits:
  /// `{"type":"text",...}`, `{"type":"tool_use",...}`, `{"type":"done"}`,
  /// `{"type":"error",...}`, `{"type":"overage",...}`. Returns `null` for
  /// a blank or unrecognized line rather than throwing — a malformed line
  /// shouldn't crash the run.
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
      'done' => const AgentDoneEvent(),
      'error' => AgentErrorEvent(
        json['message'] as String? ?? 'Unknown error.',
      ),
      'overage' => AgentOverageDetectedEvent(json['message'] as String? ?? ''),
      _ => null,
    };
  }
}
