// core/contracts/agent_model_client.dart — AgentModelClient abstract interface (core layer).

import 'package:equatable/equatable.dart';

import 'agent_session_handle.dart';
import 'agent_tool_definition.dart';

/// Provider-agnostic entry point for every model call in Aion.
///
/// Per `project.md`'s Pattern 1 (dependency inversion via `core`), any
/// feature needing a model call depends only on this interface, never on a
/// concrete provider directly — see `AIO-1699`
/// §1. The sole implementation for this MVP is `ClaudeAgentSdkClient`
/// (`core/agent/claude_agent_sdk_client.dart`).
///
/// A run may emit any number of [AgentToolCallEvent]s before its terminal
/// event — each one non-terminal, reporting an [AgentRequest.tools] call
/// the implementation is awaiting [AgentRequest.onToolCall] for. See
/// `AIO-1118` §2.
abstract interface class AgentModelClient {
  /// Starts a model run for [request], returning a stream of incremental
  /// [AgentEvent]s. The returned stream is finished by exactly one
  /// terminal event ([AgentDoneEvent], [AgentErrorEvent], or
  /// [AgentCancelledEvent]).
  Future<Stream<AgentEvent>> run(AgentRequest request);

  /// Cancels the run identified by [runId] (the [AgentRequest.runId] it
  /// was started with), causing its [run] stream to close with a
  /// terminal [AgentCancelledEvent] instead of whatever it would
  /// otherwise have ended with. A no-op if [runId] doesn't match any
  /// currently active run — already finished, never started, or unknown
  /// to this client instance — so a caller racing a cancel against a
  /// run's own natural completion never needs to guard the call itself.
  /// Added for `AIO-1400`; see that change's
  /// design.md §2.
  void cancel(String runId);
}

/// A single request to an [AgentModelClient].
class AgentRequest extends Equatable {
  /// Creates an [AgentRequest] for [prompt] against [model]. A non-empty
  /// [tools] should always come with an [onToolCall] to resolve its
  /// calls — see [onToolCall]'s dartdoc. Not enforced by an `assert` here:
  /// `List.length`/`isEmpty` aren't constant expressions, and many
  /// existing call sites construct `const AgentRequest(...)`; each
  /// [AgentModelClient] implementation is responsible for treating a
  /// tool call with no [onToolCall] as its own error instead.
  const AgentRequest({
    required this.prompt,
    required this.model,
    this.toolsEnabled = false,
    this.workingDirectory,
    this.tools = const [],
    this.onToolCall,
    this.runId,
    this.resumeSessionId,
  });

  /// The user- or system-authored prompt text.
  final String prompt;

  /// The model identifier to run against — one of an
  /// `AgentModelDescriptor`'s `modelId` values
  /// (`core/contracts/agent_model_descriptor.dart`). Not validated here;
  /// an unrecognized id is a provider-level error surfaced as
  /// [AgentErrorEvent].
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

  /// App-defined tools the model may call mid-run, independent of
  /// [toolsEnabled] (which governs the provider's own file/git/bash tool
  /// set, not app-defined tools). Empty for every call site that predates
  /// this change. Added for `AIO-1118`;
  /// see that change's design.md §2.
  final List<AgentToolDefinition> tools;

  /// Invoked by the [AgentModelClient] implementation when the model calls
  /// one of [tools] mid-run. Must resolve with the tool's result — a
  /// JSON-serializable [Map] fed back to the model so it can keep
  /// reasoning in the same logical turn. Left unresolved for as long as
  /// the caller needs (e.g. an `AutomationConfidence.gated` proposal
  /// awaiting user confirmation) — the underlying run simply stays open
  /// until it resolves. `null` (the default) means [tools] must also be
  /// empty; a non-empty [tools] list with no [onToolCall] is a programmer
  /// error (see the constructor's dartdoc for why this isn't a compile-time
  /// `assert`).
  ///
  /// The 4th parameter, [AgentSessionHandle], is this call's own
  /// resumable session — non-null only when the implementation has
  /// already captured a session id for this run (e.g.
  /// `ClaudeAgentSdkClient` after its bridge process emits a `"session"`
  /// line) and the underlying provider supports resumption
  /// ([AgentProvider.supportsSessionResume]); `null` otherwise, including
  /// for every provider with no session concept at all. See
  /// `AIO-613`
  /// §4.
  final Future<Map<String, dynamic>> Function(
    String toolCallId,
    String toolName,
    Map<String, dynamic> arguments,
    AgentSessionHandle? session,
  )?
  onToolCall;

  /// Caller-supplied identifier for this run, later passed to
  /// [AgentModelClient.cancel] to cancel it mid-flight. `null` (the
  /// default) for every call site that has no cancellation UI wired to
  /// it — a run with no [runId] simply can't be cancelled. Added for
  /// `AIO-1400`; see that change's design.md §2.
  final String? runId;

  /// When set, this run resumes and forks [resumeSessionId] rather than
  /// starting a fresh conversation — see design.md §3. `null` (the
  /// default) for every existing call site, preserving today's behavior.
  /// Only honored by a provider whose [AgentProvider.supportsSessionResume]
  /// is `true`; ignored otherwise.
  final String? resumeSessionId;

  @override
  List<Object?> get props => [
    prompt,
    model,
    toolsEnabled,
    workingDirectory,
    tools,
    runId,
    resumeSessionId,
  ];
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
  /// Creates an [AgentDoneEvent], optionally carrying [inputTokens] and
  /// [outputTokens].
  const AgentDoneEvent({this.inputTokens, this.outputTokens});

  /// Input tokens the SDK reported for this turn, or `null` if the bridge
  /// process didn't report usage (should not happen in practice, but
  /// `ClaudeAgentSdkClient._parseLine` treats a missing field as `null`
  /// rather than throwing).
  final int? inputTokens;

  /// Output tokens the SDK reported for this turn. See [inputTokens].
  final int? outputTokens;

  @override
  List<Object?> get props => [inputTokens, outputTokens];
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
/// `AIO-1699`'s Non-goals for
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

/// A tool call the model made mid-run (file edit, git, bash, MCP). Purely
/// informational — never a terminal event. Added for
/// `AIO-506` to give a
/// long-running coding-execution turn live progress visibility.
class AgentToolUseEvent extends AgentEvent {
  /// Creates an [AgentToolUseEvent] carrying [toolName] and an optional
  /// [summary].
  const AgentToolUseEvent(this.toolName, this.summary);

  /// The SDK's own tool name (`Read`, `Write`, `Bash`, ...).
  final String toolName;

  /// A short, human-readable one-liner derived from the tool's input
  /// (e.g. the file path for `Read`/`Write`, the command for `Bash`) —
  /// `null` if the bridge couldn't derive one for an unrecognized tool.
  final String? summary;

  @override
  List<Object?> get props => [toolName, summary];
}

/// The run was cancelled via [AgentModelClient.cancel]. Terminal, but
/// **not** a failure — distinct from [AgentErrorEvent], which always
/// represents something going wrong. Always the last event on a
/// cancelled stream; no [AgentDoneEvent]/[AgentErrorEvent] follows.
/// Added for `AIO-1400`; see that change's
/// design.md §2.
class AgentCancelledEvent extends AgentEvent {
  /// Creates an [AgentCancelledEvent].
  const AgentCancelledEvent();

  @override
  List<Object?> get props => [];
}

/// An app-defined tool call the model made mid-run — distinct from
/// [AgentToolUseEvent], which reports the *provider's own* file/git/bash
/// tool use. Purely informational, like [AgentToolUseEvent]; the actual
/// execution and result round-trip happens via [AgentRequest.onToolCall],
/// awaited internally by the client implementation before it emits any
/// further events. Never terminal. Added for
/// `AIO-1118`; see that change's
/// design.md §2.
class AgentToolCallEvent extends AgentEvent {
  /// Creates an [AgentToolCallEvent] for a call to [toolName], identified
  /// by [toolCallId], carrying [arguments].
  const AgentToolCallEvent(this.toolCallId, this.toolName, this.arguments);

  /// The provider-assigned identifier for this specific call, used to
  /// match the eventual result back to it.
  final String toolCallId;

  /// The [AgentToolDefinition.name] of the tool being called.
  final String toolName;

  /// The arguments the model supplied, already parsed from JSON.
  final Map<String, dynamic> arguments;

  @override
  List<Object?> get props => [toolCallId, toolName, arguments];
}
