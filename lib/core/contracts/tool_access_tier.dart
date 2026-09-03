// core/contracts/tool_access_tier.dart — ToolAccessTier enum (core layer).

/// The tool-access axis a provider declares support for — independent of
/// `ModelPhase`'s reasoning-weight axis
/// (`features/providers/domain/enums/model_phase.dart`). A stage's tool access
/// and its model tier are configured separately. See `AIO-1544` §1.
enum ToolAccessTier {
  /// No tool access — a plain text-only turn.
  noTools,

  /// An allowlisted subset of tools (e.g. read-only file/search access).
  /// Not supported by any provider today — see
  /// `ClaudeAgentSdkProvider.supportedToolAccessTiers`'s dartdoc for why.
  readOnly,

  /// The provider's full default tool set (file edits, git, bash, MCP).
  full,
}
