// presentation/cubit/anthropic_provider_config_cubit.dart — AnthropicProviderConfigCubit (presentation layer).

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/core/contracts/provider_id.dart';
import 'package:aion/core/contracts/provider_registry.dart';
import 'package:aion/features/providers/domain/enums/provider_connection_status.dart';
import 'package:aion/features/providers/domain/repositories/anthropic_api_key_repository.dart';
import 'package:aion/features/providers/presentation/cubit/anthropic_provider_config_state.dart';

/// Business logic for the Settings screen's new "PROVIDERS" section —
/// separate from `ProviderSettingsCubit` (which always tracks *whichever
/// provider Frontier currently resolves to*, not a specific provider), one
/// cubit per concern, same split as `AutomationSettingsCubit`/
/// `ModelRoutingCubit`/`ExecutionContextCapCubit`. Holds real logic (not a
/// thin pass-through) per `project.md`'s Cubit-vs-repository split:
/// [saveApiKey]'s trimming/clearing and [testConnection]'s no-op guards
/// live here, not in [_repository]. See
/// `aion-arch/changes/anthropic-messages-api-provider/design.md` §6.
class AnthropicProviderConfigCubit extends Cubit<AnthropicProviderConfigState> {
  /// Creates an [AnthropicProviderConfigCubit] backed by [_repository]
  /// (API-key storage) and [_registry] (resolves the
  /// `AnthropicMessagesApiProvider` a connection test pings).
  AnthropicProviderConfigCubit(this._repository, this._registry)
    : super(const AnthropicProviderConfigLoading());

  final AnthropicApiKeyRepository _repository;
  final ProviderRegistry _registry;

  /// Reads whether an API key is currently stored and emits
  /// [AnthropicProviderConfigReady] with `status: unknown`. Never pings
  /// the API — unlike `ProviderSettingsCubit.load`, a Messages API call is
  /// a real, billed token request, so this only checks storage, not
  /// connectivity (see proposal.md's Non-goals).
  Future<void> load() async {
    final apiKey = await _repository.getApiKey();
    if (isClosed) return;
    emit(
      AnthropicProviderConfigReady(
        hasApiKey: apiKey != null && apiKey.isNotEmpty,
        status: ProviderConnectionStatus.unknown,
      ),
    );
  }

  /// Trims [rawKey] and persists it via [_repository]; an empty result
  /// clears the stored key. Re-emits with `hasApiKey` updated and `status`
  /// reset to `unknown` — a changed key invalidates any prior test result.
  Future<void> saveApiKey(String rawKey) async {
    final trimmed = rawKey.trim();
    await _repository.setApiKey(trimmed.isEmpty ? null : trimmed);
    if (isClosed) return;
    emit(
      AnthropicProviderConfigReady(
        hasApiKey: trimmed.isNotEmpty,
        status: ProviderConnectionStatus.unknown,
      ),
    );
  }

  /// Pings the cheapest available Anthropic Messages API model
  /// (`availableModels.last`, i.e. Haiku — minimizing the cost of a
  /// connectivity check) with a minimal `ping` request, mapping the
  /// result the same way `ProviderSettingsCubit._runConnectionTest` does.
  /// No-ops if no key is stored, or a test is already `checking`.
  Future<void> testConnection() async {
    final current = state;
    if (current is! AnthropicProviderConfigReady) return;
    if (!current.hasApiKey) return;
    if (current.status == ProviderConnectionStatus.checking) return;

    emit(
      AnthropicProviderConfigReady(
        hasApiKey: current.hasApiKey,
        status: ProviderConnectionStatus.checking,
      ),
    );

    final provider = _registry.providerById(ProviderId.anthropicMessagesApi);
    final model = provider.availableModels.last;
    String? overageMessage;
    String? errorMessage;
    try {
      final events = await provider.client.run(
        AgentRequest(prompt: 'ping', model: model.modelId),
      );
      await for (final event in events) {
        switch (event) {
          case AgentTextEvent():
          case AgentToolUseEvent():
          case AgentToolCallEvent(): // never emitted — this call sends no tools
          case AgentDoneEvent():
          case AgentCancelledEvent(): // never emitted — this call sets no runId
            break;
          case AgentOverageDetectedEvent(:final message):
            overageMessage = message;
          case AgentErrorEvent(:final message):
            errorMessage = provider.normalizeErrorMessage(message);
        }
      }
    } catch (error) {
      errorMessage = provider.normalizeErrorMessage(error.toString());
    }

    if (isClosed) return;
    emit(
      AnthropicProviderConfigReady(
        hasApiKey: current.hasApiKey,
        status: errorMessage != null
            ? ProviderConnectionStatus.disconnected
            : ProviderConnectionStatus.connected,
        statusMessage: errorMessage ?? overageMessage,
      ),
    );
  }
}
