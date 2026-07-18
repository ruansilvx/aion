// core/markdown/ticket_markdown_template.dart — Ticket Markdown frontmatter schema (core layer).

/// Field names and ordering for the ticket <-> Markdown frontmatter
/// schema, shared by [TicketMarkdownSerializer]'s serialize/parse pair so
/// they stay in lockstep. Deliberately plain string constants, not an
/// enum — frontmatter keys are a wire format, not a domain concept.
abstract final class TicketMarkdownTemplate {
  /// Frontmatter key for [Ticket.ticketId].
  static const ticketId = 'ticketId';

  /// Frontmatter key for [Ticket.type] (`TicketType.name`).
  static const type = 'type';

  /// Frontmatter key for [Ticket.status] (`TicketStatus.name`).
  static const status = 'status';

  /// Frontmatter key for [Ticket.priority] (`TicketPriority.name`).
  static const priority = 'priority';

  /// Frontmatter key for [Ticket.parentId].
  static const parentId = 'parentId';

  /// Frontmatter key for [Ticket.estimate].
  static const estimate = 'estimate';

  /// Frontmatter key for [Ticket.timeSpent].
  static const timeSpent = 'timeSpent';

  /// Frontmatter key for [Ticket.createdAt] (ISO-8601).
  static const createdAt = 'createdAt';

  /// Frontmatter key for [Ticket.updatedAt] (ISO-8601).
  static const updatedAt = 'updatedAt';

  /// Deterministic key order used when serializing frontmatter, so diffs
  /// reflect real field changes rather than incidental key reordering.
  /// `title` and `description` are deliberately excluded from frontmatter
  /// — design.md's frontmatter example omitted `title` entirely (a real
  /// gap, not an intentional exclusion); [TicketMarkdownSerializer] models
  /// it as the body's leading `# Title` heading instead, matching the
  /// Obsidian-like hand-editable format this schema is meant to support.
  /// `description` is everything in the body after that heading.
  static const List<String> fieldOrder = [
    ticketId,
    type,
    status,
    priority,
    parentId,
    estimate,
    timeSpent,
    createdAt,
    updatedAt,
  ];

  /// The frontmatter delimiter line, opening and closing the YAML block.
  static const delimiter = '---';
}
