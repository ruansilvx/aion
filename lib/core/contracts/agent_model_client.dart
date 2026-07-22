// core/contracts/agent_model_client.dart — AgentModelClient abstract interface (core layer).

import 'package:equatable/equatable.dart';

/// Provider-agnostic entry point for every model call in Aion.
///
/// Per `project.md`'s Pattern 1 (dependency inversion via `core`), any
/// feature needing a model call depends only on this interface, never on a
/// concrete provider directly — see `aion-arch/changes/provider-configuration/design.md`
/// §1. The sole implementation for this MVP is `ClaudeAgentSdkClient`
/// (`core/agent/claude_agent_sdk_client.dart`).
abstract interface class AgentModelClient {
  /// Starts a model run for [request], returning a stream of incremental
  /// [AgentEvent]s. The returned stream is finished by exactly one
  /// terminal event ([AgentDoneEvent] or [AgentErrorEvent]).
  Future<Stream<AgentEvent>> run(AgentRequest request);
}

/// A single request to an [AgentModelClient].
class AgentRequest extends Equatable {
  /// Creates an [AgentRequest] for [prompt] against [model].
  const AgentRequest({
    required this.prompt,
    required this.model,
    this.toolsEnabled = false,
    this.workingDirectory,
  });

  /// The user- or system-authored prompt text.
  final String prompt;

  /// The model identifier to run against — one of `AgentModel`'s `id`
  /// values (`features/providers/domain/enums/agent_model.dart`). Not
  /// validated here; an unrecognized id is a provider-level error
  /// surfaced as [AgentErrorEvent].
  final String model;

  /// When `true`, the run may edit files, run git/bash, and use MCP —
  /// only ever set by `TicketsCubit`'s coding-execution path. Every
  /// existing caller (SDD-stage chats, Settings' connection test) leaves
  /// this `false`, preserving today's text-only behavior.
  final bool toolsEnabled;

  /// The directory the agent process should run in — required
  /// (non-null) whenever [toolsEnabled] is `true`, so file edits/git land
  /// in the actual project checkout rather than wherever the Flutter
  /// process happens to be running from. `null` for every text-only call.
  final String? workingDirectory;

  @override
  List<Object?> get props => [prompt, model, toolsEnabled, workingDirectory];
}

/// One incremental event from an [AgentModelClient.run] stream.
sealed class AgentEvent extends Equatable {
  /// Creates an [AgentEvent].
  const AgentEvent();
}

/// A chunk of model-generated text.
class AgentTextEvent extends AgentEvent {
  /// Creates an [AgentTextEvent] carrying [text].
  const AgentTextEvent(this.text);

  /// The generated text chunk.
  final String text;

  @override
  List<Object?> get props => [text];
}

/// The run finished successfully. Always the last event on a successful
/// stream.
class AgentDoneEvent extends AgentEvent {
  /// Creates an [AgentDoneEvent].
  const AgentDoneEvent();

  @override
  List<Object?> get props => [];
}

/// The run failed. Always the last event on a failed stream — no
/// [AgentDoneEvent] follows.
class AgentErrorEvent extends AgentEvent {
  /// Creates an [AgentErrorEvent] carrying a human-readable [message].
  const AgentErrorEvent(this.message);

  /// A human-readable description of the failure.
  final String message;

  @override
  List<Object?> get props => [message];
}

/// The bridge process reported a plan usage-window / rate-limit signal
/// (e.g. Claude Code's opt-in overage prompt). Informational only — see
/// `aion-arch/changes/provider-configuration/proposal.md`'s Non-goals for
/// why this doesn't gate anything yet. May be followed by further
/// [AgentTextEvent]s if the underlying call still completed, or by
/// [AgentErrorEvent] if it didn't.
class AgentOverageDetectedEvent extends AgentEvent {
  /// Creates an [AgentOverageDetectedEvent] carrying a human-readable
  /// [message].
  const AgentOverageDetectedEvent(this.message);

  /// A human-readable description of the overage/rate-limit signal.
  final String message;

  @override
  List<Object?> get props => [message];
}
