// presentation/cubit/provider_settings_cubit.dart — ProviderSettingsCubit (presentation layer).

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/features/providers/domain/enums/agent_model.dart';
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
/// The connection test always pings whichever [AgentModel] is currently
/// configured for [ModelPhase.frontier] — re-read fresh from
/// [_repository] on every [load]/[testConnection] call rather than
/// cached, so it always reflects the latest Frontier-tier setting without
/// this cubit needing to listen to `ModelRoutingCubit`. Model *selection*
/// itself happens exclusively through `ModelRoutingCubit`'s three tier
/// dropdowns — this cubit no longer owns a `selectModel` method.
class ProviderSettingsCubit extends Cubit<ProviderSettingsState> {
  /// Creates a [ProviderSettingsCubit] backed by [_client] (the
  /// configured [AgentModelClient]) and [_repository] (per-phase model
  /// routing, used here only to resolve the Frontier-tier model to ping).
  ProviderSettingsCubit(this._client, this._repository)
    : super(const ProviderSettingsLoading());

  final AgentModelClient _client;
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

  /// Sends a minimal `ping` [AgentRequest] against [model] and maps the
  /// resulting event stream to [ProviderConnectionStatus.connected]/
  /// [ProviderConnectionStatus.disconnected]. An [AgentOverageDetectedEvent]
  /// on an otherwise-successful run sets `connected` with that event's
  /// message as the status message, rather than treating it as a failure.
  Future<void> _runConnectionTest(AgentModel model) async {
    emit(
      ProviderSettingsReady(
        selectedModel: model,
        status: ProviderConnectionStatus.checking,
      ),
    );

    String? overageMessage;
    String? errorMessage;
    try {
      final events = await _client.run(
        AgentRequest(prompt: 'ping', model: model.id),
      );
      await for (final event in events) {
        switch (event) {
          case AgentTextEvent():
          case AgentToolUseEvent():
          case AgentDoneEvent():
            break;
          case AgentOverageDetectedEvent(:final message):
            overageMessage = message;
          case AgentErrorEvent(:final message):
            errorMessage = message;
        }
      }
    } catch (error) {
      errorMessage = error.toString();
    }

    if (isClosed) return;
    emit(
      ProviderSettingsReady(
        selectedModel: model,
        status: errorMessage != null
            ? ProviderConnectionStatus.disconnected
            : ProviderConnectionStatus.connected,
        statusMessage: errorMessage ?? overageMessage,
      ),
    );
  }
}
