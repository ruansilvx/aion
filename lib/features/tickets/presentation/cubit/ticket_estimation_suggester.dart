// presentation/cubit/ticket_estimation_suggester.dart — TicketEstimationSuggester orchestrator (presentation layer).

import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/core/contracts/agent_model_descriptor.dart';
import 'package:aion/core/contracts/embedding_provider.dart';
import 'package:aion/core/contracts/provider_id.dart';
import 'package:aion/core/contracts/provider_registry.dart';
import 'package:aion/features/providers/domain/enums/model_phase.dart';
import 'package:aion/features/providers/domain/repositories/model_routing_repository.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_complexity.dart';
import 'package:aion/features/tickets/domain/enums/ticket_estimation_source.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';
import 'package:aion/features/tickets/domain/utils/embedding_similarity.dart';

/// Produces AI-suggested `complexity`/`estimate` values for a [Ticket],
/// calibrated against similar already-sized tickets. Placed alongside
/// `TicketRollupRecomputer` rather than in `data/services/`, because it
/// owns the actual judgment logic (is a field locked? how many comparable
/// tickets? what counts as low-confidence?) that `project.md`'s
/// Cubit-owns-domain-logic convention keeps out of the repository/service
/// layer. `TicketsCubit` constructs one instance in its own constructor
/// body, next to `_rollupRecomputer`. See
/// `aion-arch/changes/ai-assisted-complexity-and-estimate-suggestions/design.md`
/// §2.1–§2.2.
class TicketEstimationSuggester {
  /// Creates a [TicketEstimationSuggester] backed by [_repository].
  /// [embeddingProvider]/[providerRegistry]/[modelRoutingRepository] are
  /// optional — when [embeddingProvider] or [providerRegistry] is `null`,
  /// [suggest]/[regenerate] silently no-op (mirrors
  /// `TicketsCubit._triggerEmbeddingRegen`'s/`_runShallowSummarization`'s
  /// own optional-dependency guards); [modelRoutingRepository] being
  /// `null` only narrows [_resolveModel]'s fallback chain.
  TicketEstimationSuggester(
    this._repository, {
    EmbeddingProvider? embeddingProvider,
    ProviderRegistry? providerRegistry,
    ModelRoutingRepository? modelRoutingRepository,
  }) {
    _embeddingProvider = embeddingProvider;
    _providerRegistry = providerRegistry;
    _modelRoutingRepository = modelRoutingRepository;
  }

  final TicketRepository _repository;
  late final EmbeddingProvider? _embeddingProvider;
  late final ProviderRegistry? _providerRegistry;
  late final ModelRoutingRepository? _modelRoutingRepository;

  /// The maximum number of comparable past tickets included as few-shot
  /// calibration examples in the prompt.
  static const _maxComparableTickets = 5;

  /// Background path — fires from `TicketsCubit.createTicket`/
  /// `updateTicket`, always `unawaited`. Silently no-ops (no exception
  /// ever escapes) if:
  /// - constructed without an [EmbeddingProvider]/[ProviderRegistry]
  ///   (mirrors `_triggerEmbeddingRegen`'s/`_runShallowSummarization`'s
  ///   own optional-dependency guards), or
  /// - both `complexity` and `estimate` are already `manual`-locked
  ///   (nothing eligible — skips the model call entirely rather than
  ///   spending one for zero writable output).
  /// Only requests a suggestion for whichever of `complexity`/`estimate`
  /// is *not* currently `manual` (i.e. `null` source or already
  /// `aiSuggested`/`aiSuggestedLowConfidence`).
  Future<void> suggest(Ticket ticket) =>
      _run(ticket, forceComplexity: false, forceEstimate: false);

  /// User-invoked path — fires from `TicketsCubit.regenerateComplexitySuggestion`/
  /// `regenerateEstimateSuggestion`, always awaited by the caller so it
  /// can re-emit `TicketDetailLoaded` once this resolves. Bypasses the
  /// lock for exactly the one field the caller names ([forceComplexity]/
  /// [forceEstimate]) — the other field is left completely untouched
  /// regardless of its own lock state, even if this call also happens to
  /// produce a value for it (per design §2.1's per-field independence).
  Future<void> regenerate(
    Ticket ticket, {
    bool forceComplexity = false,
    bool forceEstimate = false,
  }) => _run(
    ticket,
    forceComplexity: forceComplexity,
    forceEstimate: forceEstimate,
  );

  /// Shared implementation for [suggest]/[regenerate]. Embeds [ticket]'s
  /// title/description, scans every other live ticket with a `complexity`/
  /// `estimate` already set for the top [_maxComparableTickets] by cosine
  /// similarity (empty when none exist — the cold-start case), prompts the
  /// resolved [ModelPhase.capable] model for a suggestion, parses the
  /// response, and persists whichever fields were requested via
  /// [TicketRepository.applyEstimationSuggestion]. Every failure mode
  /// (missing dependency, network/parse error, [AgentErrorEvent]) is
  /// swallowed — this is a background nicety, never allowed to surface as
  /// `TicketsError` or interrupt the caller's own save flow.
  Future<void> _run(
    Ticket ticket, {
    required bool forceComplexity,
    required bool forceEstimate,
  }) async {
    final embeddingProvider = _embeddingProvider;
    final providerRegistry = _providerRegistry;
    if (embeddingProvider == null || providerRegistry == null) return;

    final wantComplexity =
        forceComplexity ||
        ticket.complexitySource != TicketEstimationSource.manual;
    final wantEstimate =
        forceEstimate || ticket.estimateSource != TicketEstimationSource.manual;
    if (!wantComplexity && !wantEstimate) return;

    try {
      final queryVector = await embeddingProvider.embed(
        '${ticket.title}\n\n${ticket.description ?? ''}',
      );
      final all = await _repository.getAllTickets();
      final comparable = <(Ticket, double)>[
        for (final other in all)
          if (other.id != ticket.id &&
              other.embedding != null &&
              (other.complexity != null || other.estimate != null))
            (other, cosineSimilarity(queryVector, other.embedding!)),
      ]..sort((a, b) => b.$2.compareTo(a.$2));
      final topComparable = comparable
          .take(_maxComparableTickets)
          .map((e) => e.$1)
          .toList();
      final lowConfidence = topComparable.isEmpty;

      final model = await _resolveModel();
      if (model == null) return;
      final provider = providerRegistry.providerById(model.providerId);
      final prompt = _buildPrompt(
        ticket,
        topComparable,
        wantComplexity: wantComplexity,
        wantEstimate: wantEstimate,
      );

      final buffer = StringBuffer();
      final events = await provider.client.run(
        AgentRequest(prompt: prompt, model: model.modelId),
      );
      await for (final event in events) {
        switch (event) {
          case AgentTextEvent(:final text):
            buffer.write(text);
          case AgentDoneEvent():
          case AgentOverageDetectedEvent():
          case AgentToolUseEvent():
          case AgentToolCallEvent(): // never emitted — this call sends no tools
            break;
          case AgentErrorEvent():
            return; // background nicety — swallow, never surface TicketsError
        }
      }

      final parsed = _parseSuggestion(buffer.toString());
      if (parsed == null) return;

      await _repository.applyEstimationSuggestion(
        ticket.id,
        complexity: wantComplexity && parsed.complexity != null
            ? (value: parsed.complexity!, lowConfidence: lowConfidence)
            : null,
        estimate: wantEstimate && parsed.estimateMinutes != null
            ? (value: parsed.estimateMinutes!, lowConfidence: lowConfidence)
            : null,
      );
    } catch (_) {
      // Background nicety — never let a network/parse failure surface as
      // TicketsError or interrupt the caller's own save flow.
    }
  }

  /// Mirrors `TicketsCubit._resolveModel(ModelPhase.capable)`'s exact
  /// fallback chain (routing repository → first registered provider's
  /// first model → hardcoded default) — duplicated rather than shared
  /// because `TicketsCubit._resolveModel` is private; both copies must be
  /// kept in sync if that fallback chain ever changes. Returns `null`
  /// only when even the hardcoded default can't be constructed, which
  /// doesn't happen in practice — kept nullable defensively.
  Future<AgentModelDescriptor?> _resolveModel() async {
    final repo = _modelRoutingRepository;
    if (repo != null) return repo.getModelForPhase(ModelPhase.capable);
    final registry = _providerRegistry;
    if (registry != null && registry.availableProviders.isNotEmpty) {
      return registry.availableProviders.first.availableModels.first;
    }
    return const AgentModelDescriptor(
      providerId: ProviderId.claudeAgentSdk,
      modelId: 'claude-sonnet-5',
      label: 'Sonnet 5',
      contextWindowTokens: 200000,
    );
  }

  /// Builds the estimation prompt for [ticket], asking only for whichever
  /// of `COMPLEXITY`/`ESTIMATE_MINUTES` [wantComplexity]/[wantEstimate]
  /// request, with [comparable]'s title/complexity/estimate included as
  /// few-shot calibration examples (the section is omitted entirely when
  /// [comparable] is empty). See design.md §2.2 for the exact format.
  String _buildPrompt(
    Ticket ticket,
    List<Ticket> comparable, {
    required bool wantComplexity,
    required bool wantEstimate,
  }) {
    final lines = <String>[
      "You are estimating a work ticket's size. Respond with exactly "
          'these line(s) and nothing else:',
      if (wantComplexity) 'COMPLEXITY: small, medium, or large',
      if (wantEstimate) 'ESTIMATE_MINUTES: a positive integer',
      '',
      'Ticket to estimate:',
      'Title: ${ticket.title}',
      'Description: ${ticket.description ?? "(none)"}',
    ];

    if (comparable.isNotEmpty) {
      lines
        ..add('')
        ..add('Comparable past tickets, for calibration:');
      for (final other in comparable) {
        final complexityLabel = other.complexity?.name ?? 'unset';
        final estimateLabel = other.estimate != null
            ? '${other.estimate} min'
            : 'unset';
        lines.add(
          '- "${other.title}" — complexity: $complexityLabel, '
          'estimate: $estimateLabel',
        );
      }
    }

    return lines.join('\n');
  }

  /// Line-anchored, case-insensitive parse of `COMPLEXITY`/
  /// `ESTIMATE_MINUTES` out of [text]. A missing or malformed line for a
  /// field means the model declined/failed to produce that value —
  /// reflected as `null` on that field, never an error. An
  /// `ESTIMATE_MINUTES` of `0` or a non-positive parse is treated the same
  /// as missing. Returns `null` only if neither field parsed at all.
  ({TicketComplexity? complexity, int? estimateMinutes})? _parseSuggestion(
    String text,
  ) {
    final complexityMatch = RegExp(
      r'^COMPLEXITY:\s*(small|medium|large)',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(text);
    final complexity = complexityMatch == null
        ? null
        : TicketComplexity.values.firstWhere(
            (c) =>
                c.name.toLowerCase() == complexityMatch.group(1)!.toLowerCase(),
          );

    final estimateMatch = RegExp(
      r'^ESTIMATE_MINUTES:\s*(\d+)',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(text);
    final parsedEstimate = estimateMatch == null
        ? null
        : int.tryParse(estimateMatch.group(1)!);
    final estimateMinutes = (parsedEstimate != null && parsedEstimate > 0)
        ? parsedEstimate
        : null;

    if (complexity == null && estimateMinutes == null) return null;
    return (complexity: complexity, estimateMinutes: estimateMinutes);
  }
}
