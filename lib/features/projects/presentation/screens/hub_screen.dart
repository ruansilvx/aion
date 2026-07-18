// presentation/screens/hub_screen.dart — HubScreen, Aion's project list/switcher entry point (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/projects/domain/entities/project.dart';
import 'package:aion/features/projects/presentation/cubit/project_hub_cubit.dart';
import 'package:aion/features/projects/presentation/cubit/project_hub_state.dart';
import 'package:aion/features/projects/presentation/widgets/empty_hub_state.dart';
import 'package:aion/features/projects/presentation/widgets/project_card.dart';

/// The `/hub` route — Aion's project list/switcher and the app's initial
/// route. Lists every known project (empty-state on first run) and
/// offers "New Project". Selecting a project's Open action makes it
/// active (via [onOpenProject]) and navigates into the workspace. See
/// `aion-arch/changes/multi-project-hub/design.md` §2.
class HubScreen extends StatefulWidget {
  /// Creates a [HubScreen]. [onOpenProject] is called with the chosen
  /// project when the user opens one; [onNewProject] is called when the
  /// "New Project" action is activated.
  const HubScreen({
    super.key,
    required this.onOpenProject,
    required this.onNewProject,
  });

  /// Called with the project the user chose to open.
  final ValueChanged<Project> onOpenProject;

  /// Called when the "New Project" action is activated.
  final VoidCallback onNewProject;

  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen> {
  @override
  void initState() {
    super.initState();
    context.read<ProjectHubCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return ColoredBox(
      color: c.background,
      child: SafeArea(
        child: BlocBuilder<ProjectHubCubit, ProjectHubState>(
          builder: (context, state) {
            if (state is ProjectHubEmpty) {
              return EmptyHubState(onNewProject: widget.onNewProject);
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(context, c),
                  const SizedBox(height: AionSpacing.sp24),
                  Expanded(child: _body(context, c, state)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _header(BuildContext context, AionColors c) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.projectHubEyebrow,
              style: AionText.caption.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: AionSpacing.sp4),
            Text(
              context.l10n.projectHubTitle,
              style: AionText.h1.copyWith(color: c.textPrimary),
            ),
          ],
        ),
        AppButton(
          label: context.l10n.projectHubNewProjectAction,
          icon: PhosphorIcons.plusLight,
          onPressed: widget.onNewProject,
        ),
      ],
    );
  }

  Widget _body(BuildContext context, AionColors c, ProjectHubState state) {
    return switch (state) {
      ProjectHubInitial() ||
      ProjectHubLoading() => const Center(child: AppSpinner()),
      ProjectHubLoaded(:final projects) => _grid(projects),
      ProjectHubError() => _error(context, c),
      ProjectHubEmpty() => const SizedBox.shrink(), // handled by build()
    };
  }

  Widget _grid(List<Project> projects) {
    return SingleChildScrollView(
      child: Wrap(
        spacing: AionSpacing.sp16,
        runSpacing: AionSpacing.sp16,
        children: [
          for (final project in projects)
            SizedBox(
              width: 340,
              child: ProjectCard(
                project: project,
                onOpen: () => widget.onOpenProject(project),
                onRemove: () =>
                    context.read<ProjectHubCubit>().removeProject(project.id),
              ),
            ),
        ],
      ),
    );
  }

  Widget _error(BuildContext context, AionColors c) {
    return Center(
      child: GestureDetector(
        onTap: () => context.read<ProjectHubCubit>().load(),
        child: Text(
          context.l10n.projectHubErrorRetry,
          style: AionText.body.copyWith(color: c.danger),
        ),
      ),
    );
  }
}
