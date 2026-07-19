// features/pages/presentation/screens/page_create_screen.dart — PageCreateScreen (presentation layer).

import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/pages/presentation/cubit/pages_cubit.dart';
import 'package:aion/features/pages/presentation/cubit/pages_state.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';

/// Payload passed via go_router's `extra` when navigating to
/// `/workspace/pages/new` with a pre-selected parent — used by
/// [PageSubPagesSection]'s "+ Add" affordance on `PageDetailScreen`.
class PageCreateRouteExtra {
  /// Creates a [PageCreateRouteExtra] carrying [initialParentId].
  const PageCreateRouteExtra({this.initialParentId});

  /// Forwarded to [PageCreateScreen.initialParentId].
  final String? initialParentId;
}

/// The `/workspace/pages/new` route: a short creation form dedicated to
/// `page`-type tickets — title (required), an optional parent picker, and
/// an optional initial Markdown content field. No type picker (type is
/// fixed to `page`), no priority/estimate fields. Builds its own
/// [PagesCubit], backed by the workspace-scoped [PageTicketProvider] read
/// from context. Per
/// `aion-arch/changes/page-content-markdown-editor/design.md` §8.
class PageCreateScreen extends StatefulWidget {
  /// Creates a [PageCreateScreen]. [initialParentId] pre-selects the
  /// parent field — used when opened from a page's "+ Add" sub-page
  /// affordance.
  const PageCreateScreen({super.key, this.initialParentId});

  /// Parent page id the parent field starts pre-selected to.
  final String? initialParentId;

  @override
  State<PageCreateScreen> createState() => _PageCreateScreenState();
}

class _PageCreateScreenState extends State<PageCreateScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _titleFocus = FocusNode();

  late final PagesCubit _cubit;
  late final PageTicketProvider _provider;

  List<Ticket>? _parentCandidates;
  Ticket? _selectedParent;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _provider = context.read<PageTicketProvider>();
    _cubit = PagesCubit(_provider);
    _loadParentCandidates();
  }

  Future<void> _loadParentCandidates() async {
    final candidates = await _provider.getValidParentCandidatesForPage();
    if (!mounted) return;
    final matches = widget.initialParentId == null
        ? const <Ticket>[]
        : candidates.where((t) => t.id == widget.initialParentId).toList();
    setState(() {
      _parentCandidates = candidates;
      _selectedParent = matches.isEmpty ? null : matches.first;
    });
  }

  @override
  void dispose() {
    _cubit.close();
    _titleController.dispose();
    _contentController.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    setState(() => _isSubmitting = true);
    _cubit.createPage(
      title: title,
      description: _contentController.text.trim().isEmpty
          ? null
          : _contentController.text.trim(),
      parentId: _selectedParent?.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return BlocProvider<PagesCubit>.value(
      value: _cubit,
      child: BlocListener<PagesCubit, PagesState>(
        listener: (context, state) {
          if (state is PageCreated) {
            context.go('/workspace/pages/${state.page.id}');
          } else if (state is PagesError) {
            AppToast.show(context, state.message);
            setState(() => _isSubmitting = false);
          }
        },
        child: ColoredBox(
          color: c.background,
          child: Column(
            children: [
              AppHeader(
                title: context.l10n.documentationNewPageAction,
                showBack: true,
                onBack: () => context.go('/workspace/documentation'),
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppTextField(
                        labelText: context.l10n.createTicketTitleLabel,
                        isRequired: true,
                        hintText: context.l10n.pageCreateTitlePlaceholder,
                        controller: _titleController,
                        focusNode: _titleFocus,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: AionSpacing.sp20),
                      if (_parentCandidates != null) ...[
                        AppDropdown<Ticket?>(
                          labelText: context.l10n.createTicketParentLabel,
                          semanticsLabel: context
                              .l10n
                              .createTicketParentLabel,
                          value: _selectedParent,
                          items: [null, ..._parentCandidates!],
                          itemLabel: (v) =>
                              v?.title ??
                              context.l10n.pageCreateParentFieldPlaceholder,
                          onChanged: (v) =>
                              setState(() => _selectedParent = v),
                        ),
                        const SizedBox(height: AionSpacing.sp20),
                      ],
                      AppTextField(
                        labelText: context.l10n.pageDetailContentLabel,
                        isOptional: true,
                        hintText: context.l10n.pageDetailContentPlaceholder,
                        controller: _contentController,
                        maxLines: null,
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                child: AppButton(
                  label: context.l10n.pageCreateSubmitAction,
                  variant: AppButtonVariant.primary,
                  isFullWidth: true,
                  onPressed: _isSubmitting ? null : _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
