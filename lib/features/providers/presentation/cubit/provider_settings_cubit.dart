// presentation/cubit/provider_settings_cubit.dart — ProviderSettingsCubit (presentation layer).

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/core/contracts/agent_model_descriptor.dart';
import 'package:aion/core/contracts/agent_provider.dart';
import 'package:aion/core/contracts/provider_registry.dart';
import 'package:aion/features/providers/domain/enums/model_phase.dart';
import 'package:aion/features/providers/domain/enums/provider_connection_status.dart';
import 'package:aion/features/providers/domain/repositories/model_routing_repository.dart';
import 'package:aion/features/providers/presentation/cubit/provider_settings_state.dart';

/// Business logic for the Settings screen's provider status card: runs/
/// re-runs a live connection test. Holds real logic (not a thin
/// pass-through) per `project.md`'s Cubit-vs-repository split:
/// [testConnection] refuses to start a second test while one is already
/// `checking`, rather than racing two in-flight tests.
///
/// The connection test always pings whichever [AgentModelDescriptor] is
/// currently configured for [ModelPhase.frontier] — re-read fresh from
/// [_repository] on every [load]/[testConnection] call rather than
/// cached, so it always reflects the latest Frontier-tier setting without
/// this cubit needing to listen to `ModelRoutingCubit`. Its
/// [AgentProvider] (resolved via [_registry]) supplies the
/// [AgentModelClient] to run the ping through,
/// [AgentProvider.normalizeErrorMessage] to clean a `disconnected`
/// result's failure text, and [AgentProvider.displayName] — stashed on
/// every emitted `ProviderSettingsReady.providerDisplayName` so
/// `_ProviderStatusCard`'s title/subline can be provider-derived instead
/// of a hardcoded string, now that a second `AgentProvider` exists. Model
/// *selection* itself happens exclusively through `ModelRoutingCubit`'s
/// three tier dropdowns — this cubit no longer owns a `selectModel`
/// method.
class ProviderSettingsCubit extends Cubit<ProviderSettingsState> {
  /// Creates a [ProviderSettingsCubit] backed by [_registry] (resolves
  /// the configured [AgentProvider]) and [_repository] (per-phase model
  /// routing, used here only to resolve the Frontier-tier model to ping).
  ProviderSettingsCubit(this._registry, this._repository)
    : super(const ProviderSettingsLoading());

  final ProviderRegistry _registry;
  final ModelRoutingRepository _repository;

  /// Reads the currently configured Frontier-tier model, then immediately
  /// runs one connection test against it — the "auto-detected" behavior
  /// `project.md`'s original design described, adapted to Agent SDK's
  /// lack of a plan-introspection API: this is a live test call, not a
  /// static credential check.
  Future<void> load() async {
    final model = await _repository.getModelForPhase(ModelPhase.frontier);
    if (isClosed) return;
    emit(
      ProviderSettingsReady(
        selectedModel: model,
        status: ProviderConnectionStatus.unknown,
        providerDisplayName: _registry
            .providerById(model.providerId)
            .displayName,
      ),
    );
    await _runConnectionTest(model);
  }

  /// Re-runs the connection test against the Frontier-tier model,
  /// re-read fresh from [_repository] so a change made via
  /// `ModelRoutingCubit` since the last test is picked up. No-ops if a
  /// test is already in flight.
  Future<void> testConnection() async {
    final current = state;
    if (current is! ProviderSettingsReady) return;
    if (current.status == ProviderConnectionStatus.checking) return;
    final model = await _repository.getModelForPhase(ModelPhase.frontier);
    await _runConnectionTest(model);
  }

  /// Sends a minimal `ping` [AgentRequest] against [model], through its
  /// [AgentProvider] (resolved via [_registry]), and maps the resulting
  /// event stream to [ProviderConnectionStatus.connected]/
  /// [ProviderConnectionStatus.disconnected]. An
  /// [AgentOverageDetectedEvent] on an otherwise-successful run sets
  /// `connected` with that event's message as the status message, rather
  /// than treating it as a failure. A `disconnected` result's message is
  /// passed through `AgentProvider.normalizeErrorMessage` before being
  /// stored, so a leaked vendor-specific error never reaches the UI raw.
  Future<void> _runConnectionTest(AgentModelDescriptor model) async {
    final provider = _registry.providerById(model.providerId);
    emit(
      ProviderSettingsReady(
        selectedModel: model,
        status: ProviderConnectionStatus.checking,
        providerDisplayName: provider.displayName,
      ),
    );

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
      ProviderSettingsReady(
        selectedModel: model,
        status: errorMessage != null
            ? ProviderConnectionStatus.disconnected
            : ProviderConnectionStatus.connected,
        statusMessage: errorMessage ?? overageMessage,
        providerDisplayName: provider.displayName,
      ),
    );
  }
}
