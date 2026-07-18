// presentation/screens/new_project_screen.dart — NewProjectScreen create-project form (presentation layer).

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/projects/domain/entities/project.dart';
import 'package:aion/features/projects/presentation/cubit/create_project_cubit.dart';
import 'package:aion/features/projects/presentation/cubit/create_project_state.dart';

/// The `/hub/new` route: name, a desktop-only directory picker, and a
/// (currently read-only) baseline-version selector, followed by a
/// submit button. On mobile/web the directory field is omitted from the
/// tree entirely (not merely hidden) and replaced by an informational
/// notice. See
/// `aion-arch/changes/multi-project-hub/design.md` §4.
class NewProjectScreen extends StatefulWidget {
  /// Creates a [NewProjectScreen]. [onBack] returns to the Hub without
  /// creating; [onCreated] is called with the newly created project.
  const NewProjectScreen({
    super.key,
    required this.onBack,
    required this.onCreated,
  });

  /// Called when the back button is activated, or after a successful
  /// create.
  final VoidCallback onBack;

  /// Called with the newly created project on success.
  final ValueChanged<Project> onCreated;

  @override
  State<NewProjectScreen> createState() => _NewProjectScreenState();
}

class _NewProjectScreenState extends State<NewProjectScreen> {
  final _nameController = TextEditingController();
  final _nameFocus = FocusNode();
  String? _chosenDirectory;

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _browseDirectory() async {
    final result = await getDirectoryPath();
    if (result != null) {
      setState(() => _chosenDirectory = result);
    }
  }

  void _submit() {
    context.read<CreateProjectCubit>().submit(
      name: _nameController.text,
      rootPath: _chosenDirectory,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return BlocListener<CreateProjectCubit, CreateProjectState>(
      listener: (context, state) {
        if (state is CreateProjectSuccess) {
          widget.onCreated(state.project);
        }
      },
      child: ColoredBox(
        color: c.background,
        child: SafeArea(
          child: Column(
            children: [
              AppHeader(
                title: context.l10n.newProjectTitle,
                showBack: true,
                onBack: widget.onBack,
                padding: const EdgeInsets.fromLTRB(32, 22, 32, 18),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 28,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: BlocBuilder<CreateProjectCubit, CreateProjectState>(
                      builder: (context, state) => _Form(
                        colors: c,
                        state: state,
                        nameController: _nameController,
                        nameFocus: _nameFocus,
                        chosenDirectory: _chosenDirectory,
                        onBrowseDirectory: _browseDirectory,
                        onSubmit: _submit,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The create-project form body: name field, directory picker/notice,
/// baseline version field, and submit footer.
class _Form extends StatelessWidget {
  const _Form({
    required this.colors,
    required this.state,
    required this.nameController,
    required this.nameFocus,
    required this.chosenDirectory,
    required this.onBrowseDirectory,
    required this.onSubmit,
  });

  final AionColors colors;
  final CreateProjectState state;
  final TextEditingController nameController;
  final FocusNode nameFocus;
  final String? chosenDirectory;
  final VoidCallback onBrowseDirectory;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final failure = state is CreateProjectFailure
        ? state as CreateProjectFailure
        : null;
    final isSubmitting =
        state is CreateProjectValidating || state is CreateProjectSubmitting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          labelText: context.l10n.newProjectNameLabel,
          isRequired: true,
          hintText: context.l10n.newProjectNameHint,
          controller: nameController,
          focusNode: nameFocus,
          textInputAction: TextInputAction.next,
        ),
        if (failure?.reason == CreateProjectFailureReason.duplicateName) ...[
          const SizedBox(height: AionSpacing.sp4),
          _InlineError(
            colors: c,
            message: context.l10n.newProjectDuplicateNameError,
          ),
        ],
        const SizedBox(height: AionSpacing.sp20),
        if (isDesktop)
          _DirectoryPicker(
            colors: c,
            failure: failure,
            chosenDirectory: chosenDirectory,
            onBrowseDirectory: onBrowseDirectory,
          ),
        if (!isDesktop) _NoDirectoryNotice(colors: c),
        const SizedBox(height: AionSpacing.sp20),
        _BaselineVersionField(colors: c),
        const SizedBox(height: AionSpacing.sp24),
        _Footer(isSubmitting: isSubmitting, onSubmit: onSubmit),
      ],
    );
  }
}

/// The desktop-only directory picker field (path display + Browse
/// button).
class _DirectoryPicker extends StatelessWidget {
  const _DirectoryPicker({
    required this.colors,
    required this.failure,
    required this.chosenDirectory,
    required this.onBrowseDirectory,
  });

  final AionColors colors;
  final CreateProjectFailure? failure;
  final String? chosenDirectory;
  final VoidCallback onBrowseDirectory;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final hasDirectoryError =
        failure?.reason == CreateProjectFailureReason.directoryAlreadyInUse ||
        failure?.reason == CreateProjectFailureReason.directoryNotChosen;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              context.l10n.newProjectLocationLabel,
              style: AionText.label.copyWith(color: c.textSecondary),
            ),
            const SizedBox(width: 6),
            Text(
              context.l10n.newProjectLocationDesktopQualifier,
              style: AionText.bodySm.copyWith(color: c.textMuted),
            ),
          ],
        ),
        const SizedBox(height: AionSpacing.sp4),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.surface,
                    border: Border.all(
                      color: hasDirectoryError ? c.danger : c.border,
                      width: hasDirectoryError ? 1.5 : 1,
                    ),
                    borderRadius: BorderRadius.all(AionRadius.lg),
                    boxShadow: hasDirectoryError
                        ? [
                            BoxShadow(
                              color: c.errorRing(ThemeScope.of(context).isDark),
                              spreadRadius: 3,
                            ),
                          ]
                        : const [],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Text(
                      chosenDirectory ??
                          context.l10n.newProjectLocationPlaceholder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AionText.key.copyWith(
                        fontSize: 12.5,
                        color: chosenDirectory != null
                            ? c.textPrimary
                            : c.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AionSpacing.sp8),
              GestureDetector(
                onTap: onBrowseDirectory,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.surfaceHover,
                    border: Border.all(color: c.borderStrong, width: 1),
                    borderRadius: BorderRadius.all(AionRadius.lg),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                      child: Text(
                        context.l10n.newProjectLocationBrowseAction,
                        style: AionText.button.copyWith(
                          fontSize: 13,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AionSpacing.sp4),
        Text(
          context.l10n.newProjectLocationHint,
          style: AionText.bodySm.copyWith(color: c.textMuted),
        ),
        if (hasDirectoryError) ...[
          const SizedBox(height: AionSpacing.sp4),
          _InlineError(
            colors: c,
            message: context.l10n.newProjectLocationDirectoryInUseError,
          ),
        ],
      ],
    );
  }
}

/// The mobile/web informational notice replacing the directory picker
/// (no filesystem access on those platforms).
class _NoDirectoryNotice extends StatelessWidget {
  const _NoDirectoryNotice({required this.colors});

  final AionColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final isDark = ThemeScope.of(context).isDark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.noticeFill(isDark),
        border: Border.all(color: c.noticeBorder(isDark), width: 1),
        borderRadius: BorderRadius.all(AionRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PhosphorIcon(
              PhosphorIcons.databaseLight,
              size: 15,
              color: c.primary,
            ),
            const SizedBox(width: AionSpacing.sp8),
            Expanded(
              child: Text(
                context.l10n.newProjectNoDirectoryNotice,
                style: AionText.bodySm.copyWith(
                  fontSize: 12.5,
                  color: c.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The (currently read-only) baseline-version field.
class _BaselineVersionField extends StatelessWidget {
  const _BaselineVersionField({required this.colors});

  final AionColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.newProjectBaselineVersionLabel,
          style: AionText.label.copyWith(color: c.textSecondary),
        ),
        const SizedBox(height: AionSpacing.sp4),
        DecoratedBox(
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.border, width: 1),
            borderRadius: BorderRadius.all(AionRadius.lg),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            child: Row(
              children: [
                Text(
                  'v0.1.0',
                  style: AionText.key.copyWith(
                    fontSize: 13.5,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(width: AionSpacing.sp8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.primarySubtle,
                    borderRadius: BorderRadius.all(AionRadius.sm),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    child: Text(
                      context.l10n.newProjectBaselineVersionLatestTag,
                      style: AionText.chip.copyWith(color: c.primary),
                    ),
                  ),
                ),
                const Spacer(),
                PhosphorIcon(
                  PhosphorIcons.caretDownLight,
                  size: 11,
                  color: c.textMuted,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AionSpacing.sp4),
        Text(
          context.l10n.newProjectBaselineVersionHint,
          style: AionText.bodySm.copyWith(color: c.textMuted),
        ),
      ],
    );
  }
}

/// The submit footer button.
class _Footer extends StatelessWidget {
  const _Footer({required this.isSubmitting, required this.onSubmit});

  final bool isSubmitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: isSubmitting
          ? context.l10n.newProjectSubmittingAction
          : context.l10n.newProjectSubmitAction,
      isFullWidth: true,
      onPressed: isSubmitting ? null : onSubmit,
    );
  }
}

/// A small "!"-in-circle glyph plus danger-colored error text, used for
/// this form's inline validation messages.
class _InlineError extends StatelessWidget {
  const _InlineError({required this.colors, required this.message});

  final AionColors colors;
  final String message;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: c.danger, width: 1.4),
            shape: BoxShape.circle,
          ),
          child: SizedBox(
            width: 14,
            height: 14,
            child: Center(
              child: Text(
                '!',
                style: AionText.label.copyWith(
                  fontSize: 10,
                  color: c.danger,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: AionText.bodySm.copyWith(fontSize: 12, color: c.danger),
          ),
        ),
      ],
    );
  }
}
