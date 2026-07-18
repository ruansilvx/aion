// data/services/active_ticket_view_registry.dart — ActiveTicketViewRegistry (data layer).

import 'package:flutter/foundation.dart';

/// Tracks which ticket, if any, the user is currently viewing in
/// `TicketDetailScreen`. One instance per open project, provided
/// alongside the other ticket-feature services in `WorkspaceShell`.
///
/// [TicketMarkdownReconciler] reads [activeTicketId] to decide whether an
/// incoming external-edit reconcile should apply in the background
/// (not the viewed ticket) or defer until the user navigates away (is
/// the viewed ticket) — see design.md's reconcile flow.
class ActiveTicketViewRegistry {
  /// The `ticketId` of the ticket currently shown in `TicketDetailScreen`,
  /// or `null` if no detail screen is mounted. `TicketDetailScreen` sets
  /// this in `initState` and clears it in `dispose`.
  final ValueNotifier<String?> activeTicketId = ValueNotifier(null);
}
