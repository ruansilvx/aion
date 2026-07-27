// presentation/widgets/chat_meta_header.dart — ChatMetaHeader compact pinned header (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/presentation/screens/tickets_list_screen.dart';
import 'package:aion/features/tickets/presentation/widgets/ticket_overflow_menu.dart';

/// The compact pinned header a `chat` ticket's [TicketMetadataSection]
/// collapses into as `ChatTranscriptPane`'s transcript scrolls — back
/// button, ticket-id badge, overflow menu, title, chat type chip, and
/// status indicator. Per
/// `aion-arch/changes/chat-transcript-ux-redesign/design.md` §0.1.
class ChatMetaHeader extends StatelessWidget {
  /// Creates a [ChatMetaHeader] for [ticket].
  const ChatMetaHeader({super.key, required this.ticket, required this.onBack});

  /// The `chat` ticket this compact header summarizes.
  final Ticket ticket;

  /// Called when the back button is tapped.
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Semantics(
                label: context.l10n.commonBack,
                button: true,
                child: GestureDetector(
                  onTap: onBack,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.surfaceHover,
                      border: Border.all(color: c.border, width: 1),
                      borderRadius: BorderRadius.all(AionRadius.iconBtn),
                    ),
                    child: SizedBox(
                      width: 37,
                      height: 37,
                      child: Center(
                        child: PhosphorIcon(
                          PhosphorIcons.caretLeftLight,
                          size: 20,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: c.surfaceHover,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  child: Text(
                    ticket.ticketId,
                    style: AionText.key.copyWith(color: c.textSecondary),
                  ),
                ),
              ),
              const Spacer(),
              TicketOverflowMenu(ticket: ticket),
            ],
          ),
          const SizedBox(height: AionSpacing.sp8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ticket.title,
                style: AionText.h2.copyWith(
                  fontSize: 19,
                  letterSpacing: -0.018 * 19,
                  color: c.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AionSpacing.sp8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  TypeChip(type: ticket.type, isRow: false),
                  const SizedBox(width: 12),
                  StatusIndicator(status: ticket.status),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
