// domain/enums/summarization_depth.dart — SummarizationDepth enum (domain layer).

/// How thoroughly `TicketsCubit.runCodebaseSummarization` reads an
/// attached, already-git-tracked codebase before drafting starting
/// `signal` tickets. UI-facing, user-selected — not persisted anywhere,
/// and not a structural property of any `Ticket`. Added for
/// `aion-arch/changes/new-project-onboarding`.
enum SummarizationDepth {
  /// A single non-tool-enabled model turn given the detected stack
  /// (`ProjectStackDetector`) and a depth-limited directory listing
  /// (filenames only, no file content). Cheap and bounded in token
  /// cost — no agentic tool loop.
  shallow,

  /// A tool-enabled agentic turn, isolated in a fresh `git worktree`
  /// (never the developer's real checkout), free to read the project's
  /// actual files. Mirrors `TicketsCubit._runCodingExecution`'s
  /// worktree-isolation pattern.
  full,
}
