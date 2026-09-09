# Aion

A spec-based AI agentic code assistant with a Jira-like project management
structure, built as a single Flutter app across all platforms.

## Core concept

Everything is a **ticket** — epics, stories, tasks, resources, Notion-style
pages, and agent chats all share one model. Tickets link to each other
freely, chats are tied to tickets and can branch into subtickets, and all
ticket/code data is versioned. The app embeds full agentic coding
capability (file edits, git, MCP, skills) alongside multi-model routing
(local + cloud, switchable, with a cost-aware Auto mode) — so planning,
tracking, and executing the work happen in the same place instead of
across a project tracker, a chat window, and an editor. A Hub screen
manages multiple independent projects, each with its own local database
and git repo.

## Status

**v0.1.0, the first release.** What's shipped: the full ticket data model
and Board/List views (kanban, search, filters, bulk edit, trash); drift-
backed local persistence with git-projected Markdown and on-device
embeddings; the complete non-Material design system; a pluggable
model-provider layer (Claude Agent SDK today, a second Anthropic-Messages-
API provider proven against it) with per-phase model routing; real
agentic coding execution — isolated git worktrees, a pre-PR verify gate,
concurrent/cancellable/restart-safe runs, PR metadata and a notification
center; and a ticket-native spec-driven workflow (explore → propose →
apply → verify → archive) with project-configurable statuses/stages,
workflow skill attachments, and decision graphs for automation
confidence. Aion now drives its own further development through that
same ticket-native workflow. Solo project, actively developed.

## Stack

- Flutter — single codebase targeting iOS, Android, web, macOS, Windows,
  Linux
- flutter_bloc (Cubit) for state management
- drift (SQLite) for local persistence — local-first, no backend
- go_router for navigation
- Custom non-Material design system (two themes, Arctic/Obsidian) —
  no ThemeData/MaterialApp/Scaffold anywhere in the app

## License

MIT — see [LICENSE](LICENSE).
