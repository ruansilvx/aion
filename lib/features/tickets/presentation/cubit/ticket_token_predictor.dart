// presentation/cubit/ticket_token_predictor.dart — TicketTokenPredictor orchestrator (presentation layer).

import 'package:aion/core/contracts/embedding_provider.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';
import 'package:aion/features/tickets/domain/utils/embedding_similarity.dart';

/// Produces a pre-execution token-cost estimate range for a `task`/`bug`
/// [Ticket], calibrated against similar past `task`/`bug` tickets' own
/// recorded execution token spend. The direct sibling of
/// `TicketEstimationSuggester` — same constructor shape, same
/// `TicketsCubit`-constructed-alongside placement, same fire-and-forget
/// `suggest` call from `createTicket`/`updateTicket` — and deliberately
/// mirrors its no-op-guard-chain-then-candidate-walk structure. The one
/// concrete way this diverges: this predictor is fully deterministic and
/// makes no model call at all. It never prompts anything — it ranks
/// candidates by embedding cosine similarity, then deterministically sums
/// each comparable candidate's own historical execution-chat token totals
/// (via [TicketRepository.getExecutionTokenTotals]) and persists the
/// resulting min/max range. See
/// `AIO-2455` §2.
class TicketTokenPredictor {
  /// Creates a [TicketTokenPredictor] backed by [_repository].
  /// [embeddingProvider] is optional — when `null`, [suggest] silently
  /// no-ops, mirroring `TicketEstimationSuggester`'s own optional-
  /// dependency guard: this predictor never actually calls
  /// [EmbeddingProvider.embed] itself (it consumes [Ticket.embedding],
  /// already populated asynchronously elsewhere by
  /// `TicketsCubit._triggerEmbeddingRegen`), but still gates on the same
  /// dependency so embedding-based features are disabled uniformly on any
  /// platform/build that has none configured.
  TicketTokenPredictor(this._repository, {EmbeddingProvider? embeddingProvider}) {
    _embeddingProvider = embeddingProvider;
  }

  final TicketRepository _repository;
  late final EmbeddingProvider? _embeddingProvider;

  /// The maximum number of comparable candidates (ranked by similarity)
  /// this predictor will actually use once found — once this many
  /// candidates with recorded execution history are found, the scan
  /// stops early even if [_maxCandidatesScanned] hasn't been reached.
  static const _maxCandidatesFound = 5;

  /// The maximum number of top-ranked candidates this predictor will
  /// scan for execution history before giving up, even if fewer than
  /// [_maxCandidatesFound] were found. Bounds the batched
  /// [TicketRepository.getExecutionTokenTotals] call's size.
  static const _maxCandidatesScanned = 20;

  /// Background path — fires from `TicketsCubit.createTicket`/
  /// `updateTicket`, always `unawaited`, alongside
  /// `TicketEstimationSuggester.suggest`. Silently no-ops (no exception
  /// ever escapes) if:
  /// - constructed without an [EmbeddingProvider],
  /// - [ticket.type] is not [TicketType.task] or [TicketType.bug],
  /// - [ticket.embedding] is `null` (regen hasn't landed yet — a later
  ///   call, once it has, will succeed),
  /// - [ticket] already has a `"Coding Execution — "`-prefixed `chat`
  ///   child (it has already started executing — a prediction is
  ///   meaningless once real execution data exists; see
  ///   `TicketsCubit`'s running-total display precedence), or
  /// - zero of the top [_maxCandidatesScanned] most-similar other
  ///   `task`/`bug` tickets have any recorded execution-token history
  ///   (the cold-start case — "no estimate available").
  ///
  /// Otherwise: ranks every other live `task`/`bug` ticket with a
  /// non-null [Ticket.embedding] by cosine similarity to [ticket]'s own
  /// embedding, takes the top [_maxCandidatesScanned], resolves all of
  /// their execution-token totals in one batched
  /// [TicketRepository.getExecutionTokenTotals] call, walks the
  /// similarity-ranked list collecting totals until
  /// [_maxCandidatesFound] are found, and persists the resulting
  /// min/max range via [TicketRepository.applyTokenPrediction].
  Future<void> suggest(Ticket ticket) async {
    final embeddingProvider = _embeddingProvider;
    if (embeddingProvider == null) return;
    if (ticket.type != TicketType.task && ticket.type != TicketType.bug) {
      return;
    }
    final queryEmbedding = ticket.embedding;
    if (queryEmbedding == null) return;

    try {
      final existingChats = await _repository.getTicketsByParent(
        ticket.id,
        types: const [TicketType.chat],
      );
      final alreadyExecuted = existingChats.any(
        (chat) => chat.title.startsWith('Coding Execution — '),
      );
      if (alreadyExecuted) return;

      final pool = await _repository.getAllTicketsByType(const [
        TicketType.task,
        TicketType.bug,
      ]);
      final ranked = <(Ticket, double)>[
        for (final other in pool)
          if (other.id != ticket.id && other.embedding != null)
            (other, cosineSimilarity(queryEmbedding, other.embedding!)),
      ]..sort((a, b) => b.$2.compareTo(a.$2));
      final scanned = ranked
          .take(_maxCandidatesScanned)
          .map((entry) => entry.$1)
          .toList();
      if (scanned.isEmpty) return;

      final totals = await _repository.getExecutionTokenTotals(
        scanned.map((candidate) => candidate.id).toList(),
      );

      final found = <int>[];
      for (final candidate in scanned) {
        final total = totals[candidate.id];
        if (total == null) continue;
        found.add(total);
        if (found.length >= _maxCandidatesFound) break;
      }
      if (found.isEmpty) return;

      final low = found.reduce((a, b) => a < b ? a : b);
      final high = found.reduce((a, b) => a > b ? a : b);
      await _repository.applyTokenPrediction(ticket.id, low: low, high: high);
    } catch (_) {
      // Background nicety — never let a failure surface as TicketsError
      // or interrupt the caller's own save flow.
    }
  }
}
