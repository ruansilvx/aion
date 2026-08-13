// core/contracts/agent_tool_definition.dart — AgentToolDefinition value type (core layer).

import 'package:equatable/equatable.dart';

/// An app-defined tool the model may call mid-run via
/// `AgentRequest.tools`/`AgentRequest.onToolCall`
/// (`core/contracts/agent_model_client.dart`) — independent of
/// [ToolAccessTier] (which governs the provider's own file/git/bash tool
/// access) and `ModelPhase` (which governs reasoning weight). Added for
/// `aion-arch/changes/mid-task-chat-branching`; see that change's
/// design.md §2.
class AgentToolDefinition extends Equatable {
  /// Creates an [AgentToolDefinition] named [name], described by
  /// [description] for the model, and shaped by [inputSchema].
  const AgentToolDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  /// Stable tool name the model calls by (e.g. `'branch_ticket'`).
  final String name;

  /// Model-facing description of when/why to call this tool.
  final String description;

  /// JSON Schema (draft-07-compatible object schema) describing the
  /// tool's expected arguments — the same shape both Anthropic's Messages
  /// API `tools[].input_schema` and the Agent SDK's custom-tool
  /// definitions already expect, so one schema serves both providers
  /// unchanged.
  final Map<String, dynamic> inputSchema;

  @override
  List<Object?> get props => [name, description, inputSchema];
}
