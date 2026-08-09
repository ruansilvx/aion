// data/repositories/secure_storage_anthropic_api_key_repository.dart — SecureStorageAnthropicApiKeyRepository (data layer).

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:aion/features/providers/domain/repositories/anthropic_api_key_repository.dart';

/// `flutter_secure_storage`-backed implementation of
/// [AnthropicApiKeyRepository] — the first real consumer of that
/// dependency; everything else in the app today is `shared_preferences`
/// (nothing else has been a real secret). One key
/// (`provider_config.anthropic_api_key`). `setApiKey(null)` or an empty
/// string deletes the key rather than storing an empty value. See
/// `aion-arch/changes/anthropic-messages-api-provider/design.md` §5.
class SecureStorageAnthropicApiKeyRepository
    implements AnthropicApiKeyRepository {
  /// Creates a [SecureStorageAnthropicApiKeyRepository] backed by
  /// [_storage].
  SecureStorageAnthropicApiKeyRepository(this._storage);

  final FlutterSecureStorage _storage;

  static const _key = 'provider_config.anthropic_api_key';

  @override
  Future<String?> getApiKey() => _storage.read(key: _key);

  @override
  Future<void> setApiKey(String? apiKey) => (apiKey == null || apiKey.isEmpty)
      ? _storage.delete(key: _key)
      : _storage.write(key: _key, value: apiKey);
}
