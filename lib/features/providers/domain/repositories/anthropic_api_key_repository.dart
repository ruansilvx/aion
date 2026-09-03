// domain/repositories/anthropic_api_key_repository.dart — AnthropicApiKeyRepository abstract interface (domain layer).

/// Plain storage interface for the user's Anthropic Messages API key —
/// reads/writes only, no validation, matching every other repository in this
/// feature (`ExecutionContextCapRepository`, `ModelRoutingRepository`).
/// Trimming/empty-string handling is the consuming Cubit's job
/// (`AnthropicProviderConfigCubit.saveApiKey`), per `project.md`'s
/// Cubit-domain-logic split. See `AIO-110` §5.
abstract interface class AnthropicApiKeyRepository {
  /// Returns the currently stored API key, or `null` if none is stored.
  Future<String?> getApiKey();

  /// Stores [apiKey]. A `null` or empty value clears the stored key
  /// instead of persisting an empty string.
  Future<void> setApiKey(String? apiKey);
}
