// domain/entities/release_draft.dart — ReleaseDraft entity (domain layer).

import 'package:equatable/equatable.dart';

import 'package:aion/core/build/project_stack_detector.dart';

/// An AI-drafted, editable-before-confirm release proposal for one
/// `release` ticket, returned by `TicketsCubit.prepareReleaseDraft` and
/// consumed by `ReleaseDraftScreen`/`TicketsCubit.confirmRelease`. Plain
/// data — no persistence, no drift table: it lives only in memory between
/// the draft step and confirmation. If [confirmRelease] never runs (the
/// user cancels), the draft is simply discarded — nothing about a
/// rejected draft needs to survive. Added for
/// `aion-arch/changes/release-preparation-and-tagging`; see that change's
/// design.md §3.
class ReleaseDraft extends Equatable {
  /// Creates a [ReleaseDraft].
  const ReleaseDraft({
    required this.releaseTicketId,
    required this.linkedTicketIds,
    required this.changelogMarkdown,
    required this.suggestedVersion,
    this.detectedVersionFile,
  });

  /// Internal id of the `release` ticket this draft is for.
  final String releaseTicketId;

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
    linkedTicketIds,
    changelogMarkdown,
    suggestedVersion,
    detectedVersionFile,
  ];
}
