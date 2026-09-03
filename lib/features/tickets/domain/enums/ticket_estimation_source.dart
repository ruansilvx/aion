// domain/enums/ticket_estimation_source.dart — TicketEstimationSource enum (domain layer).

/// Where a [Ticket](../entities/ticket.dart)'s [Ticket.complexity]/
/// [Ticket.estimate] value came from — drives whether the automatic
/// background estimator (`TicketEstimationSuggester`) is still allowed to
/// silently replace it, and whether the UI shows an `AiSuggestionBadge` or
/// a Regenerate action next to the field. See
/// `AIO-75`
/// §1.1.
///
/// `complexity == null`/`estimate == null` always implies its companion
/// source is also `null` — there is nothing to source when a field is
/// unset. This is enforced structurally by every write path, not
/// re-validated defensively at read time.
enum TicketEstimationSource {
  /// The current value came from the automatic background estimator or
  /// an explicit "Regenerate" action, and — since it's unlocked — remains
  /// eligible to be silently replaced by a future automatic re-estimate.
  aiSuggested,

  /// Same as [aiSuggested], but produced with zero comparable historical
  /// tickets to calibrate against (a cold-start guess from title/
  /// description content alone). Rendered with an extra low-confidence
  /// caveat; otherwise behaves identically to [aiSuggested] (still
  /// unlocked, still eligible for silent re-estimation).
  aiSuggestedLowConfidence,

  /// The user set this value directly (typed a fresh value, or edited/
  /// confirmed an existing AI suggestion). Locked: the automatic
  /// background estimator skips this field permanently until an explicit
  /// "Regenerate" action overrides the lock.
  manual,
}
