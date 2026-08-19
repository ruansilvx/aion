// domain/entities/workflow_status.dart — WorkflowStatus entity (domain layer).

import 'package:equatable/equatable.dart';

import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/enums/workflow_status_role.dart';

/// A single project-configured ticket-workflow status — the data-driven
/// replacement for what used to be a fixed `TicketStatus` enum value. See
/// `aion-arch/changes/configurable-ticket-workflow/design.md` §1.2.
///
/// [name] is unique within its scope: unique among all shared-base entries
/// ([ticketType] `null`), and unique among a given [ticketType]'s
/// extensions. A base [name] and an extension [name] may collide across
/// different [ticketType] scopes without conflict, since a per-type merged
/// view never combines two different types together.
///
/// [role] is restricted to the shared-base set only — a per-type extension
/// status can never hold a role, because `done`/`executionTrigger` must
/// resolve consistently for a blocker or child of *any* type, not just the
/// type an extension was added for. [WorkflowConfigCubit] enforces this
/// restriction; this entity itself performs no validation.
class WorkflowStatus extends Equatable {
  /// Internal UUID v4 primary key.
  final String id;

  /// The status name written to `Ticket.status`. Unique within its scope —
  /// see this class's own dartdoc.
  final String name;

  /// The user-facing label shown on tickets and in workflow settings.
  final String displayName;

  /// `null` for a shared-base status, applying to every [TicketType]; a
  /// non-`null` value scopes this status as a per-type extension, visible
  /// only for tickets of that type.
  final TicketType? ticketType;

  /// This status's position within its scope's ordering — lower sorts
  /// first.
  final int sortOrder;

  /// The semantic gate/trigger slot this status fills, or `null` for a
  /// status with no special meaning to `TicketsCubit`. Always `null` when
  /// [ticketType] is non-`null` — see this class's own dartdoc.
  final WorkflowStatusRole? role;

  /// Creates a [WorkflowStatus].
  const WorkflowStatus({
    required this.id,
    required this.name,
    required this.displayName,
    this.ticketType,
    required this.sortOrder,
    this.role,
  });

  @override
  List<Object?> get props => [id, name, displayName, ticketType, sortOrder, role];

  /// Returns a copy of this status with the given fields replaced. [role]
  /// and [ticketType] are nullable and therefore take a zero-arg setter —
  /// pass `() => null` to explicitly clear one of them, or omit the
  /// parameter entirely to leave it unchanged, mirroring `Ticket.copyWith`'s
  /// own convention.
  WorkflowStatus copyWith({
    String? name,
    String? displayName,
    TicketType? Function()? ticketType,
    int? sortOrder,
    WorkflowStatusRole? Function()? role,
  }) {
    return WorkflowStatus(
      id: id,
      name: name ?? this.name,
      displayName: displayName ?? this.displayName,
      ticketType: ticketType != null ? ticketType() : this.ticketType,
      sortOrder: sortOrder ?? this.sortOrder,
      role: role != null ? role() : this.role,
    );
  }
}
