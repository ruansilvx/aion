// presentation/cubit/provider_settings_cubit.dart — ProviderSettingsCubit (presentation layer).

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/features/providers/domain/enums/agent_model.dart';
import 'package:aion/features/providers/domain/enums/provider_connection_status.dart';
import 'package:aion/features/providers/domain/repositories/agent_settings_repository.dart';
import 'package:aion/features/providers/presentation/cubit/provider_settings_state.dart';

/// Business logic for the Settings screen: loads the persisted model,
/// runs/re-runs a live connection test, and persists model changes. Holds
/// real logic (not a thin pass-through) per `project.md`'s
/// Cubit-vs-repository split: [testConnection]/[selectModel] refuse to
/// start a second test while one is already `checking`, rather than
/// racing two in-flight tests.
class ProviderSettingsCubit extends Cubit<ProviderSettingsState> {
  /// Creates a [ProviderSettingsCubit] backed by [_client] (the
  /// configured [AgentModelClient]) and [_repository] (persisted model
  /// selection).
  ProviderSettingsCubit(this._client, this._repository)
    : super(const ProviderSettingsLoading());

  final AgentModelClient _client;
  final AgentSettingsRepository _repository;

  /// Loads the persisted model, then immediately runs one connection
  /// test — the "auto-detected" behavior `project.md`'s original design
  /// described, adapted to Agent SDK's lack of a plan-introspection API:
  /// this is a live test call, not a static credential check.
  Future<void> load() async {
    final model = await _repository.getSelectedModel();
    if (isClosed) return;
    emit(
      ProviderSettingsReady(
        selectedModel: model,
        status: ProviderConnectionStatus.unknown,
      ),
    );
    await _runConnectionTest(model);
  }

  /// Re-runs the connection test against the currently selected model.
  /// No-ops if a test is already in flight.
  Future<void> testConnection() async {
    final current = state;
    if (current is! ProviderSettingsReady) return;
    if (current.status == ProviderConnectionStatus.checking) return;
    await _runConnectionTest(current.selectedModel);
  }

  /// Persists [model] as the selection, then re-runs the connection
  /// test against it. No-ops (see [testConnection]) while a test is
  /// already in flight.
  Future<void> selectModel(AgentModel model) async {
    final current = state;
    if (current is! ProviderSettingsReady) return;
    if (current.status == ProviderConnectionStatus.checking) return;
    await _repository.setSelectedModel(model);
    if (isClosed) return;
    emit(
      ProviderSettingsReady(
        selectedModel: model,
        status: ProviderConnectionStatus.unknown,
      ),
    );
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
