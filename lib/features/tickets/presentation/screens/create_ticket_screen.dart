// presentation/screens/create_ticket_screen.dart — Create-ticket form screen (presentation layer).

import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_state.dart';
import 'package:aion/features/tickets/presentation/screens/tickets_board_view.dart';
import 'package:aion/features/tickets/presentation/widgets/ticket_parent_picker.dart';

/// Payload passed via go_router's `extra` when navigating to
/// `/workspace/tickets/new` with pre-selected type/parent values — used by
/// `DocumentationScreen`'s "+ New page"/"+ New resource" actions. See
/// `appRouter`'s `/workspace/tickets/new` route builder, which reads this
/// and falls back to a plain [CreateTicketScreen] when `extra` isn't one
/// of these (e.g. every other navigation to this route).
class CreateTicketRouteExtra {
  /// Creates a [CreateTicketRouteExtra] carrying [initialType]/
  /// [initialParentId].
  const CreateTicketRouteExtra({this.initialType, this.initialParentId});

  /// Forwarded to [CreateTicketScreen.initialType].
  final TicketType? initialType;

  /// Forwarded to [CreateTicketScreen.initialParentId].
  final String? initialParentId;
}

/// The `/tickets/new` route: title, type, parent, priority, and
/// description fields followed by a full-width submit button. The parent
/// field is hidden whenever the selected type is [TicketType.epic] (epics
/// are always subtree roots). Reads [TicketsCubit] from the root-level
/// provider and navigates back to `/tickets` on success.
class CreateTicketScreen extends StatefulWidget {
  /// Creates a [CreateTicketScreen]. [initialType]/[initialParentId] seed
  /// the type/parent fields — used when opened from `DocumentationScreen`'s
  /// "+ New page"/"+ New resource" actions; omitted (defaulting to
  /// [TicketType.task] with no parent) at every other call site.
  const CreateTicketScreen({
    super.key,
    this.initialType,
    this.initialParentId,
  });

  /// Ticket type the type field starts pre-selected to. `null` defaults
  /// to [TicketType.task], matching this screen's original behavior.
  final TicketType? initialType;

  /// Parent ticket id the parent field starts pre-selected to. `null`
  /// leaves the parent field unset, matching this screen's original
  /// behavior.
  final String? initialParentId;

  @override
  State<CreateTicketScreen> createState() => _CreateTicketScreenState();
}

class _CreateTicketScreenState extends State<CreateTicketScreen> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _titleFocus = FocusNode();
  final _typeFocus = FocusNode();
  final _priorityFocus = FocusNode();
  final _descFocus = FocusNode();

  late TicketType _selectedType;
  TicketPriority _selectedPriority = TicketPriority.none;
  String? _selectedParentId;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialType ?? TicketType.task;
    _selectedParentId = widget.initialParentId;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _titleFocus.dispose();
    _typeFocus.dispose();
    _priorityFocus.dispose();
    _descFocus.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() => _isSubmitting = true);
    context.read<TicketsCubit>().createTicket(
      type: _selectedType,
      title: _titleController.text.trim(),
      description: _descController.text.trim().isEmpty
          ? null
          : _descController.text.trim(),
      priority: _selectedPriority,
      parentId: _selectedParentId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return BlocListener<TicketsCubit, TicketsState>(
      listener: (context, state) {
        if (state is TicketCreated) {
          context.go('/workspace/tickets');
        } else if (state is TicketsError) {
          final message = state.reason != null
              ? ticketsErrorMessage(context, state.reason!)
              : state.message;
          AppToast.show(context, message);
          setState(() => _isSubmitting = false);
        }
      },
      child: ColoredBox(
        color: c.background,
        child: Column(
          children: [
            AppHeader(
              title: context.l10n.commonNewTicket,
              showBack: true,
              onBack: () => context.go('/workspace/tickets'),
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
                      hintText: context.l10n.createTicketTitleHint,
                      controller: _titleController,
                      focusNode: _titleFocus,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _typeFocus.requestFocus(),
                    ),
                    const SizedBox(height: AionSpacing.sp20),
                    AppDropdown<TicketType>(
                      labelText: context.l10n.createTicketTypeLabel,
                      value: _selectedType,
                      items: TicketType.values,
                      onChanged: (v) => setState(() {
                        _selectedType = v;
                        _selectedParentId = null;
                      }),
                      itemLabel: (v) => ticketTypeLabel(context, v),
                      focusNode: _typeFocus,
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOut,
                      alignment: Alignment.topCenter,
                      child: _selectedType == TicketType.epic
                          ? const SizedBox.shrink()
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: AionSpacing.sp20),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      context.l10n.createTicketParentLabel,
                                      style: AionText.label.copyWith(
                                        color: c.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      context.l10n.commonOptionalMarker,
                                      style: AionText.bodySm.copyWith(
                                        color: c.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 7),
                                TicketParentPicker(
                                  ticketType: _selectedType,
                                  currentParentId: _selectedParentId,
                                  candidatesLoader: () => context
                                      .read<TicketsCubit>()
                                      .getValidParentCandidatesForType(
                                        _selectedType,
                                      ),
                                  onParentSelected: (id) =>
                                      setState(() => _selectedParentId = id),
                                  variant: TicketParentPickerVariant.formField,
                                  isDisabled: _isSubmitting,
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: AionSpacing.sp20),
                    AppDropdown<TicketPriority>(
                      labelText: context.l10n.createTicketPriorityLabel,
                      value: _selectedPriority,
                      items: TicketPriority.values,
                      onChanged: (v) => setState(() => _selectedPriority = v),
                      itemLabel: (v) => ticketPriorityLabel(context, v),
                      focusNode: _priorityFocus,
                    ),
                    const SizedBox(height: AionSpacing.sp20),
                    AppTextField(
                      labelText: context.l10n.createTicketDescriptionLabel,
                      isOptional: true,
                      hintText: context.l10n.createTicketDescriptionHint,
                      controller: _descController,
                      focusNode: _descFocus,
                      maxLines: 6,
                      textInputAction: TextInputAction.done,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: AppButton(
                label: context.l10n.commonCreateTicket,
                variant: AppButtonVariant.primary,
                isFullWidth: true,
                onPressed: _isSubmitting ? null : _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
