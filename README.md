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
across a project tracker, a chat window, and an editor.

## Status

Early and actively developed, solo project. The foundational architecture
is locked and validated by a real v1 slice: ticket data model, list/board/
detail views (including kanban), drift-backed local persistence, inline
editing, and the full non-Material design token system. The agentic
coding/watcher/model-routing layers described above are architecture, not
yet shipped. Spec/design history is tracked in a companion private repo.

## Stack

- Flutter — single codebase targeting iOS, Android, web, macOS, Windows,
  Linux
- flutter_bloc (Cubit) for state management
- drift (SQLite) for local persistence — local-first, no backend
- go_router for navigation
- Custom non-Material design system (two themes, Arctic/Obsidian) —
  no ThemeData/MaterialApp/Scaffold anywhere in the app

Development follows a spec-driven workflow (OpenSpec-style: explore →
propose → apply → verify → archive) tracked in a companion private repo.

## License

MIT — see [LICENSE](LICENSE).
