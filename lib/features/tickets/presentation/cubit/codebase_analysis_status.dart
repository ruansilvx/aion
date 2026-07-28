// presentation/cubit/codebase_analysis_status.dart — CodebaseAnalysisStatus sealed hierarchy (presentation layer).

import 'package:equatable/equatable.dart';

/// The state emitted on `TicketsCubit.codebaseAnalysisStatus` as
/// `TicketsCubit.runCodebaseSummarization` progresses. Deliberately kept
/// separate from `TicketsState` — this is a transient, first-open-only
/// concern unrelated to the ticket list's own filter/sort/pagination
/// state. `CodebaseAnalysisBanner` subscribes to this stream directly.
/// Added for `aion-arch/changes/new-project-onboarding`.
sealed class CodebaseAnalysisStatus extends Equatable {
  const CodebaseAnalysisStatus();

  @override
  List<Object?> get props => [];
}

/// No codebase-summarization run has started yet.
class CodebaseAnalysisIdle extends CodebaseAnalysisStatus {
  /// Creates a [CodebaseAnalysisIdle] state.
  const CodebaseAnalysisIdle();
}

/// A codebase-summarization run is in progress.
class CodebaseAnalysisRunning extends CodebaseAnalysisStatus {
  /// Creates a [CodebaseAnalysisRunning] state, optionally carrying a
  /// live [statusText] snippet (the most recent non-empty line of the
  /// model's streamed reply, or a tool-use summary) for the banner to
  /// display.
  const CodebaseAnalysisRunning({this.statusText});

  /// A short, human-readable live status snippet, or `null` before the
  /// first chunk/tool-use event arrives.
  final String? statusText;

  @override
  List<Object?> get props => [statusText];
}

/// A codebase-summarization run finished successfully, creating [count]
/// `signal` tickets (0 if the model reported no findings).
class CodebaseAnalysisDone extends CodebaseAnalysisStatus {
  /// Creates a [CodebaseAnalysisDone] state carrying [count].
  const CodebaseAnalysisDone(this.count);

  /// How many `signal` tickets the run created.
  final int count;

  @override
  List<Object?> get props => [count];
}

/// A codebase-summarization run failed before creating any tickets.
class CodebaseAnalysisFailed extends CodebaseAnalysisStatus {
  /// Creates a [CodebaseAnalysisFailed] state carrying a human-readable
  /// [message].
  const CodebaseAnalysisFailed(this.message);

  /// A human-readable description of what went wrong.
  final String message;

  @override
  List<Object?> get props => [message];
}
