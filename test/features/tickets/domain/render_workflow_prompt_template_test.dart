// test/features/tickets/domain/render_workflow_prompt_template_test.dart — renderWorkflowPromptTemplate unit tests.

import 'package:flutter_test/flutter_test.dart';

import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/entities/workflow_prompt_template.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/utils/render_workflow_prompt_template.dart';

void main() {
  final ticket = Ticket(
    id: 'ticket-1',
    ticketId: 'AIO-1',
    type: TicketType.bug,
    title: 'Login crashes on submit',
    description: 'Tapping submit twice crashes the app.',
    status: 'needsRepro',
    priority: TicketPriority.high,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  test('substitutes every supported variable', () {
    const template = WorkflowPromptTemplate(
      id: 't1',
      name: 'All variables',
      body:
          'Title: {{ticket.title}}\n'
          'Description: {{ticket.description}}\n'
          'Type: {{ticket.type}}\n'
          'Status: {{ticket.status}}\n'
          'Priority: {{ticket.priority}}',
    );

    final result = renderWorkflowPromptTemplate(template, ticket);

    expect(
      result,
      'Title: Login crashes on submit\n'
      'Description: Tapping submit twice crashes the app.\n'
      'Type: bug\n'
      'Status: needsRepro\n'
      'Priority: high',
    );
  });

  test('substitutes ticket.description as empty string when null', () {
    final noDescription = ticket.copyWith(description: () => null);
    const template = WorkflowPromptTemplate(
      id: 't2',
      name: 'Description only',
      body: 'Description: [{{ticket.description}}]',
    );

    final result = renderWorkflowPromptTemplate(template, noDescription);

    expect(result, 'Description: []');
  });

  test('leaves an unrecognized placeholder untouched', () {
    const template = WorkflowPromptTemplate(
      id: 't3',
      name: 'Unknown variable',
      body: 'Assignee: {{ticket.assignee}}',
    );

    final result = renderWorkflowPromptTemplate(template, ticket);

    expect(result, 'Assignee: {{ticket.assignee}}');
  });

  test('round-trips a template with no placeholders as-is', () {
    const template = WorkflowPromptTemplate(
      id: 't4',
      name: 'No variables',
      body: 'Please investigate this thoroughly.',
    );

    final result = renderWorkflowPromptTemplate(template, ticket);

    expect(result, 'Please investigate this thoroughly.');
  });
}
