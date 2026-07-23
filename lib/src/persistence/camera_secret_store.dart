import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypted storage for per-camera secrets (ONVIF passwords, EZVIZ
/// verification codes, OAuth refresh tokens).
///
/// Deliberately separate from `CameraProfileStore`: profiles are safe-to-log
/// records persisted in the clear, whereas these values must live in
/// platform-encrypted storage (Android Keystore / iOS Keychain), **never** in
/// `shared_preferences`. Secrets are keyed by the owning profile's id, so
/// deleting a profile can drop all of its secrets in one call.
///
/// Adapters never read this store directly — the app-layer setup wizard (or the
/// session, when re-opening) reads a secret and passes it in through
/// `open(device)`, keeping backends free of a storage-plugin dependency.
abstract class CameraSecretStore {
  /// The secret for ([profileId], [key]), or `null` if none is stored.
  Future<String?> getSecret(String profileId, String key);

  /// Stores [value] as the secret for ([profileId], [key]).
  Future<void> setSecret(String profileId, String key, String value);

  /// Removes every secret belonging to [profileId] (called when a profile is
  /// deleted).
  Future<void> deleteSecretsForProfile(String profileId);
}

/// [CameraSecretStore] backed by `flutter_secure_storage`.
///
/// Keys are namespaced `uca_secret.<profileId>.<key>`. `flutter_secure_storage`
/// has no prefix-scoped delete, so [deleteSecretsForProfile] enumerates
/// [FlutterSecureStorage.readAll] and removes the matching keys.
class FlutterSecureStorageCameraSecretStore implements CameraSecretStore {
  FlutterSecureStorageCameraSecretStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const String _keyPrefix = 'uca_secret.';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> getSecret(String profileId, String key) =>
      _storage.read(key: _storageKey(profileId, key));

  @override
  Future<void> setSecret(String profileId, String key, String value) =>
      _storage.write(key: _storageKey(profileId, key), value: value);

  @override
  Future<void> deleteSecretsForProfile(String profileId) async {
    final profilePrefix = '$_keyPrefix$profileId.';
    final all = await _storage.readAll();
    for (final storageKey in all.keys) {
      if (storageKey.startsWith(profilePrefix)) {
        await _storage.delete(key: storageKey);
      }
    }
  }

  String _storageKey(String profileId, String key) =>
      '$_keyPrefix$profileId.$key';
}
