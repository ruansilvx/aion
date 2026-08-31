// core/contracts/agent_provider.dart — AgentProvider abstract interface (core layer).

import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/core/contracts/agent_model_descriptor.dart';
import 'package:aion/core/contracts/consumption_signal.dart';
import 'package:aion/core/contracts/provider_id.dart';
import 'package:aion/core/contracts/tool_access_tier.dart';

/// A configured, usable model provider. [AgentModelClient] stays the
/// low-level "run a request" contract (unchanged); [AgentProvider] is one
/// level up — identity, capability declaration, model list, and the two
/// pure text-mapping functions that keep vendor-specific detail out of
/// [AgentModelClient]'s already-shipped, unchanged event shapes. Looked
/// up by [ProviderId] via a `ProviderRegistry`. See
/// `aion-arch/changes/pluggable-provider-abstraction/design.md` §1.
abstract interface class AgentProvider {
  /// This provider's identity.
  ProviderId get id;

  /// Human-readable name shown in Settings (e.g. `'Claude Agent SDK'`).
  String get displayName;

  /// Which [ToolAccessTier] values this provider can actually run —
  /// checked against `ModelPhase.requiredToolAccessTier` when filtering
  /// which models a Settings dropdown may offer for a given phase.
  Set<ToolAccessTier> get supportedToolAccessTiers;

  /// Every model this provider offers.
  List<AgentModelDescriptor> get availableModels;

  /// The low-level client this provider runs requests through.
  AgentModelClient get client;

  /// Maps a raw `AgentOverageDetectedEvent.message` into this provider's
  /// [ConsumptionSignal] variant. Pure — no I/O.
  ConsumptionSignal describeOverage(String rawMessage);

  /// Maps a raw `AgentErrorEvent.message` (which may contain vendor/CLI-
  /// specific text) into a vendor-neutral, user-facing message. Pure —
  /// no I/O.
  String normalizeErrorMessage(String rawMessage);

  /// Whether this provider's [client] can resume/fork an existing
  /// session cheaply enough for a mid-turn side-question (see
  /// `aion-arch/changes/decision-graph-agentjudgment-condition/design.md`
  /// §1). `false` means an `agentJudgment` decision-graph condition
  /// always resolves to its unmatched branch when evaluated under this
  /// provider — never a crash, never a block.
  bool get supportsSessionResume;
}
