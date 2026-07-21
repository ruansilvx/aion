// core.dart — Barrel for core infrastructure: database, routing, localization, utils (core layer).

export 'agent/agent_bridge_locator.dart';
export 'agent/claude_agent_sdk_client.dart';
export 'contracts/active_project_provider.dart';
export 'contracts/agent_model_client.dart';
export 'contracts/embedding_provider.dart';
export 'contracts/page_ticket_provider.dart';
export 'database/app_database.dart';
export 'database/registry_database.dart';
export 'embeddings/bundled_embedding_provider.dart';
export 'embeddings/wordpiece_tokenizer.dart';
export 'git/git_repository_client.dart';
export 'localization/context_localizations_x.dart';
export 'markdown/ticket_markdown_linter.dart';
export 'markdown/ticket_markdown_parse_result.dart';
export 'markdown/ticket_markdown_serializer.dart';
export 'markdown/ticket_markdown_template.dart';
export 'routing/app_router.dart';
export 'routing/ticket_navigation.dart';
export 'utils/duration_format.dart';
export 'utils/platform_utils.dart';
export 'utils/relative_time_format.dart';
