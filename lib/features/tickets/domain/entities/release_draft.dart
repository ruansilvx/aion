// domain/entities/release_draft.dart — ReleaseDraft entity (domain layer).

import 'package:equatable/equatable.dart';

import 'package:aion/core/build/project_stack_detector.dart';

/// An AI-drafted, editable-before-confirm release proposal for one `release`
/// ticket, returned by `TicketsCubit.prepareReleaseDraft` and consumed by
/// `ReleaseDraftScreen`/`TicketsCubit.confirmRelease`. Plain data — no
/// persistence, no drift table: it lives only in memory between the draft step
/// and confirmation. If [confirmRelease] never runs (the user cancels), the
/// draft is simply discarded — nothing about a rejected draft needs to
/// survive. Added for `AIO-1782`; see its linked Documentation page, §3.
class ReleaseDraft extends Equatable {
  /// Creates a [ReleaseDraft].
  const ReleaseDraft({
    required this.releaseTicketId,
    required this.releaseKey,
    required this.targetBranch,
    required this.linkedTicketIds,
    required this.changelogMarkdown,
    required this.suggestedVersion,
    this.detectedVersionFile,
  });

  /// Internal id of the `release` ticket this draft is for.
  final String releaseTicketId;

  /// The release ticket's display id (e.g. `"AIO-51"`) — shown in
  /// `ReleaseDraftScreen`'s header badge and scope summary strip. Distinct
  /// from [releaseTicketId], which is the internal (non-human-facing) id.
  final String releaseKey;

  /// The branch `TicketsCubit.confirmRelease` will commit, push, and tag
  /// against — resolved via `GitRepositoryClient.defaultBranch` at draft
  /// time, the same call `confirmRelease` itself makes, so the branch
  /// shown to the user during review is guaranteed to match the one
  /// actually written to. Surfaced on the scope summary strip and in the
  /// tag/branch confirmation dialog.
  final String targetBranch;

  /// Internal ids of every `epic`/`story`/`task`/`bug` ticket
  /// `relatesTo`-linked to [releaseTicketId] at draft time — the scope
  /// [changelogMarkdown] was drafted from.
  final List<String> linkedTicketIds;

  /// The AI-drafted changelog body, in Markdown — editable by the user on
  /// `ReleaseDraftScreen` before [TicketsCubit.confirmRelease] writes it.
  final String changelogMarkdown;

  /// The AI-suggested semver bump (e.g. `"1.5.0"`) — editable by the user
  /// before confirmation, same as [changelogMarkdown].
  final String suggestedVersion;

  /// Where the target project's version lives, as resolved by
  /// [ProjectStackDetector.detectVersionFile] at draft time — `null`
  /// means the project's stack has no supported version file this round
  /// (see [VersionFileKind]'s dartdoc), so [TicketsCubit.confirmRelease]
  /// tags and pushes without a version-bump step, and `ReleaseDraftScreen`
  /// shows a "no version file detected" notice instead of an editable
  /// version field.
  final DetectedVersionFile? detectedVersionFile;

  @override
  List<Object?> get props => [
    releaseTicketId,
    releaseKey,
    targetBranch,
    linkedTicketIds,
    changelogMarkdown,
    suggestedVersion,
    detectedVersionFile,
  ];
}
