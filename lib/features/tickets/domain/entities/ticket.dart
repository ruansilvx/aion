import 'dart:typed_data';

import 'package:equatable/equatable.dart';

import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

class Ticket extends Equatable {
  final String id;
  final String ticketId;
  final TicketType type;
  final String title;
  final String? description;
  final TicketStatus status;
  final TicketPriority priority;
  final String? parentId;
  final Uint8List? embedding;
  final int? estimate;
  final int? timeSpent;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Ticket({
    required this.id,
    required this.ticketId,
    required this.type,
    required this.title,
    this.description,
    required this.status,
    this.priority = TicketPriority.none,
    this.parentId,
    this.embedding,
    this.estimate,
    this.timeSpent,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [
        id,
        ticketId,
        type,
        title,
        description,
        status,
        priority,
        parentId,
        embedding,
        estimate,
        timeSpent,
        createdAt,
        updatedAt,
      ];
}
