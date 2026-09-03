// domain/utils/render_workflow_prompt_template.dart — WorkflowPromptTemplate substitution (domain layer).

import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/entities/workflow_prompt_template.dart';

/// Substitutes every `{{variable}}` placeholder in [template]'s
/// [WorkflowPromptTemplate.body] against [ticket], leaving an
/// unrecognized placeholder's literal text untouched — defensive: a
/// template referencing a since-removed variable degrades to visible
/// text instead of throwing. Supported variables:
///
/// - `{{ticket.title}}` → [Ticket.title]
/// - `{{ticket.description}}` → [Ticket.description] (empty string if `null`)
/// - `{{ticket.type}}` → [Ticket.type]'s enum name
/// - `{{ticket.status}}` → [Ticket.status]
/// - `{{ticket.priority}}` → [Ticket.priority]'s enum name
///
/// No loops, conditionals, or nested lookups — deliberately the simplest
/// substitution that satisfies the idea file's "Aion-native prompt/workflow
/// template" want. See `AIO-2650` §1.4.
String renderWorkflowPromptTemplate(
  WorkflowPromptTemplate template,
  Ticket ticket,
) {
  final variables = <String, String>{
    'ticket.title': ticket.title,
    'ticket.description': ticket.description ?? '',
    'ticket.type': ticket.type.name,
    'ticket.status': ticket.status,
    'ticket.priority': ticket.priority.name,
  };

  return template.body.replaceAllMapped(RegExp(r'\{\{\s*([\w.]+)\s*\}\}'), (
    match,
  ) {
    final key = match.group(1);
    return variables[key] ?? match.group(0)!;
  });
}
