// domain/enums/provider_connection_status.dart — ProviderConnectionStatus enum (domain layer).

/// Connection-check outcome for the configured provider, tracked by
/// `ProviderSettingsCubit` (`presentation/cubit/provider_settings_cubit.dart`).
enum ProviderConnectionStatus {
  /// Not yet checked this session.
  unknown,

  /// A connection test is currently running.
  checking,

  /// The last test succeeded.
  connected,

  /// The last test failed — see `ProviderSettingsReady.statusMessage` for
  /// the human-readable reason.
  disconnected,
}
