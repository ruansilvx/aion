import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/features/providers/data/repositories/secure_storage_anthropic_api_key_repository.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late MockFlutterSecureStorage storage;
  late SecureStorageAnthropicApiKeyRepository repository;

  const key = 'provider_config.anthropic_api_key';

  setUp(() {
    storage = MockFlutterSecureStorage();
    repository = SecureStorageAnthropicApiKeyRepository(storage);
  });

  group('SecureStorageAnthropicApiKeyRepository', () {
    test('getApiKey reads the stored value by its fixed key name', () async {
      when(
        () => storage.read(key: key),
      ).thenAnswer((_) async => 'sk-ant-abc123');

      expect(await repository.getApiKey(), 'sk-ant-abc123');
      verify(() => storage.read(key: key)).called(1);
    });

    test('getApiKey returns null when nothing is stored', () async {
      when(() => storage.read(key: key)).thenAnswer((_) async => null);

      expect(await repository.getApiKey(), isNull);
    });

    test('setApiKey writes a non-empty key round-trip', () async {
      when(
        () => storage.write(key: key, value: 'sk-ant-abc123'),
      ).thenAnswer((_) async {});

      await repository.setApiKey('sk-ant-abc123');

      verify(() => storage.write(key: key, value: 'sk-ant-abc123')).called(1);
      verifyNever(() => storage.delete(key: key));
    });

    test('setApiKey(null) deletes the stored key rather than writing', () async {
      when(() => storage.delete(key: key)).thenAnswer((_) async {});

      await repository.setApiKey(null);

      verify(() => storage.delete(key: key)).called(1);
      verifyNever(
        () => storage.write(key: any(named: 'key'), value: any(named: 'value')),
      );
    });

    test(
      "setApiKey('') deletes the stored key rather than storing an empty "
      'value',
      () async {
        when(() => storage.delete(key: key)).thenAnswer((_) async {});

        await repository.setApiKey('');

        verify(() => storage.delete(key: key)).called(1);
        verifyNever(
          () =>
              storage.write(key: any(named: 'key'), value: any(named: 'value')),
        );
      },
    );
  });
}
