// presentation/screens/create_ticket_screen.dart — Create-ticket form screen (presentation layer).

import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:aion/core/theme/aion_radius.dart';
import 'package:aion/core/theme/theme_scope.dart';
import 'package:aion/core/widgets/app_button.dart';
import 'package:aion/core/widgets/app_dropdown.dart';
import 'package:aion/core/widgets/app_header.dart';
import 'package:aion/core/widgets/app_text_field.dart';
import 'package:aion/core/widgets/app_toast.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_state.dart';

/// The `/tickets/new` route: title, type, priority, and description fields
/// followed by a full-width submit button. Reads [TicketsCubit] from the
/// root-level provider and navigates back to `/tickets` on success.
class CreateTicketScreen extends StatefulWidget {
  /// Creates a [CreateTicketScreen].
  const CreateTicketScreen({super.key});

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

  TicketType _selectedType = TicketType.task;
  TicketPriority _selectedPriority = TicketPriority.none;
  bool _isSubmitting = false;

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
          description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
          priority: _selectedPriority,
        );
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return BlocListener<TicketsCubit, TicketsState>(
      listener: (context, state) {
        if (state is TicketCreated) {
          context.go('/tickets');
        } else if (state is TicketsError) {
          AppToast.show(context, state.message);
          setState(() => _isSubmitting = false);
        }
      },
      child: ColoredBox(
        color: c.background,
        child: Column(
          children: [
            AppHeader(
              title: 'New ticket',
              showBack: true,
              onBack: () => context.go('/tickets'),
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppTextField(
                      labelText: 'Title',
                      isRequired: true,
                      hintText: 'Ticket title',
                      controller: _titleController,
                      focusNode: _titleFocus,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _typeFocus.requestFocus(),
                    ),
                    const SizedBox(height: AionSpacing.sp20),
                    AppDropdown<TicketType>(
                      labelText: 'Type',
                      value: _selectedType,
                      items: TicketType.values,
                      onChanged: (v) => setState(() => _selectedType = v),
                      itemLabel: (v) => v.name,
                      focusNode: _typeFocus,
                    ),
                    const SizedBox(height: AionSpacing.sp20),
                    AppDropdown<TicketPriority>(
                      labelText: 'Priority',
                      value: _selectedPriority,
                      items: TicketPriority.values,
                      onChanged: (v) => setState(() => _selectedPriority = v),
                      itemLabel: (v) => v.name,
                      focusNode: _priorityFocus,
                    ),
                    const SizedBox(height: AionSpacing.sp20),
                    AppTextField(
                      labelText: 'Description',
                      isOptional: true,
                      hintText: 'Add details…',
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
                label: 'Create ticket',
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
