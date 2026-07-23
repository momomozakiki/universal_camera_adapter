import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../camera_types.dart';
import 'camera_profile.dart';
import 'camera_profile_store.dart';
import 'camera_secret_store.dart';

/// Describes one pre-`CameraProfile` camera whose setup was kept in loose
/// `SharedPreferences` keys, so it can be imported into the profile + secret
/// stores.
///
/// Deliberately **backend-agnostic**: the key names live at the call site, not
/// here, so this package carries no knowledge of any particular app's legacy
/// namespace.
@immutable
class LegacyCameraSetup {
  const LegacyCameraSetup({
    required this.backendType,
    required this.displayName,
    this.metadataKeys = const <String, String>{},
    this.extraMetadata = const <String, dynamic>{},
    this.secretPrefsKey,
    this.secretName,
    this.requiredMetadataKey,
  });

  /// Registry type the imported profile is created under, e.g. `'onvif'`.
  final String backendType;

  /// Label for the imported profile. The user can rename it afterwards.
  final String displayName;

  /// Metadata field name → legacy preference key, e.g.
  /// `{'host': 'onvif_tab.host', 'username': 'onvif_tab.username'}`. A key that
  /// is absent or blank is simply omitted from the resulting metadata.
  final Map<String, String> metadataKeys;

  /// Metadata merged in verbatim, for values the legacy scheme never stored.
  final Map<String, dynamic> extraMetadata;

  /// Legacy preference key holding the secret (password, verification code).
  final String? secretPrefsKey;

  /// `CameraSecretStore` key the secret is written under. Required whenever
  /// [secretPrefsKey] is set.
  final String? secretName;

  /// Metadata field that must be present for the import to mean anything — for
  /// an IP camera, `'host'`. When it resolves to nothing, this source is
  /// skipped: there was never a usable camera configured. Defaults to the first
  /// entry of [metadataKeys].
  final String? requiredMetadataKey;
}

/// Imports legacy loose-preference camera setups into [profileStore] /
/// [secretStore], then removes the legacy keys.
///
/// Runs at most once, guarded by [guardKey]. Returns the number of profiles
/// imported (`0` when the guard was already set, or when nothing was found).
///
/// **Ordering is the safety property.** For each source: mint the profile →
/// write its secret → save the profile → only then delete that source's legacy
/// keys. If any step throws, the legacy keys are left **untouched** and the
/// guard is **not** set, so the next launch retries. A secret is never deleted
/// before it has been successfully re-homed — losing a credential silently is
/// far worse than migrating twice.
///
/// A source that yields no usable configuration is skipped and its keys left
/// alone; only a source actually imported has its keys removed.
///
/// This is the one place outside a `CameraProfileStore` implementation that
/// touches raw `SharedPreferences`, and it exists purely to *empty* such keys.
/// Once every install has run it, the call can be deleted.
Future<int> migrateLegacyCameraSetup({
  required CameraProfileStore profileStore,
  required CameraSecretStore secretStore,
  required List<LegacyCameraSetup> sources,
  String guardKey = 'uca.migrated_legacy_prefs',
}) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(guardKey) ?? false) return 0;

  var imported = 0;
  for (final source in sources) {
    final metadata = <String, dynamic>{...source.extraMetadata};
    for (final entry in source.metadataKeys.entries) {
      final value = _readNonEmpty(prefs, entry.value);
      if (value != null) metadata[entry.key] = value;
    }

    final requiredKey = source.requiredMetadataKey ??
        (source.metadataKeys.isEmpty ? null : source.metadataKeys.keys.first);
    final secretPrefsKey = source.secretPrefsKey;
    final secret =
        secretPrefsKey == null ? null : _readNonEmpty(prefs, secretPrefsKey);

    // Nothing worth importing: no endpoint and no secret.
    final hasRequired = requiredKey == null || metadata.containsKey(requiredKey);
    if (!hasRequired && secret == null) continue;
    if (!hasRequired) continue;

    final profile = CameraProfile.create(
      backendType: source.backendType,
      displayName: source.displayName,
      device: CameraDevice(
        id: metadata[requiredKey]?.toString() ?? source.backendType,
        name: source.displayName,
        lensFacing: CameraLensFacing.external,
        metadata: metadata,
      ),
    );

    // Secret first, then the profile: a profile whose secret failed to write
    // would look complete while being unusable.
    final secretName = source.secretName;
    if (secret != null && secretName != null) {
      await secretStore.setSecret(profile.id, secretName, secret);
    }
    await profileStore.save(profile);

    // Only now is it safe to drop the plaintext originals.
    for (final legacyKey in source.metadataKeys.values) {
      await prefs.remove(legacyKey);
    }
    if (secretPrefsKey != null) await prefs.remove(secretPrefsKey);
    imported++;
  }

  await prefs.setBool(guardKey, true);
  return imported;
}

/// Reads a `String` preference, treating blank as absent. Returns `null` for a
/// wrong-typed value rather than throwing — legacy keys are untrusted input
/// (`state-management` Rule 3), and a bad one must not block the migration.
String? _readNonEmpty(SharedPreferences prefs, String key) {
  final Object? raw;
  try {
    raw = prefs.get(key);
  } on Object {
    return null;
  }
  if (raw is! String) return null;
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}
