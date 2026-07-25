// presentation/cubit/override_editor_state.dart — OverrideEditorState sealed hierarchy (presentation layer).

import 'package:equatable/equatable.dart';

/// The state emitted by [OverrideEditorCubit].
sealed class OverrideEditorState extends Equatable {
  const OverrideEditorState();

  @override
  List<Object?> get props => [];
}

/// The asset's content fetch is in flight. UI should show [AppSpinner].
class OverrideEditorLoading extends OverrideEditorState {
  /// Creates an [OverrideEditorLoading] state.
  const OverrideEditorLoading();
}

/// The asset's effective content loaded successfully — a local override's
/// content if one exists, otherwise the bundled default.
class OverrideEditorReady extends OverrideEditorState {
  /// Creates an [OverrideEditorReady] state carrying [content] and
  /// [isOverridden].
  const OverrideEditorReady({required this.content, required this.isOverridden});

  /// The content currently shown in the editor.
  final String content;

  /// Whether [content] came from an existing project override (`true`)
  /// or the bundled default (`false`) — drives the status line's
  /// "editing your local override" vs. "editing the default" copy.
  final bool isOverridden;

  @override
  List<Object?> get props => [content, isOverridden];
}

/// A save is in flight — [content] is what's being written, so the UI can
/// keep showing it (and a "Saving…" state) while the write completes.
class OverrideEditorSaving extends OverrideEditorState {
  /// Creates an [OverrideEditorSaving] state carrying [content].
  const OverrideEditorSaving(this.content);

  /// The content currently being written.
  final String content;

  @override
  List<Object?> get props => [content];
}

/// The save completed successfully. Terminal for this editing session —
/// the screen pops back to `OverridesListScreen` on this state.
class OverrideEditorSaved extends OverrideEditorState {
  /// Creates an [OverrideEditorSaved] state.
  const OverrideEditorSaved();
}

/// The content fetch or save failed. Carries a raw, unlocalized
/// description of what went wrong.
class OverrideEditorError extends OverrideEditorState {
  /// Creates an [OverrideEditorError] state carrying [message].
  const OverrideEditorError(this.message);

  /// A raw, unlocalized description of what went wrong.
  final String message;

  @override
  List<Object?> get props => [message];
}
