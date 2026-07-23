import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'camera_profile.dart';

/// Persistence for the non-secret list of [CameraProfile]s.
///
/// This stores only the safe-to-log profile records (see the [CameraProfile]
/// invariant); secrets live in a separate `CameraSecretStore`. The interface is
/// injectable so an app can swap the default `shared_preferences`-backed
/// implementation for its own (SQLite, a cloud store, an in-memory fake in
/// tests).
///
/// **Default-selection contract:** at most one profile has `isDefault == true`
/// at a time, enforced by the mutation methods here. Deleting the current
/// default auto-promotes the most-recently-created remaining profile; an empty
/// store simply has no default (the caller falls back to live discovery).
abstract class CameraProfileStore {
  /// All saved profiles. Never throws: an unreadable/corrupt store loads as an
  /// empty list rather than crashing the app on upgrade.
  Future<List<CameraProfile>> loadAll();

  /// Inserts or updates [profile] (matched by [CameraProfile.id]). If
  /// [CameraProfile.isDefault] is `true`, every other profile is flipped off so
  /// exactly one default remains.
  Future<void> save(CameraProfile profile);

  /// Removes the profile with [id]. If it was the default, the most-recent
  /// remaining profile is promoted to default.
  Future<void> delete(String id);

  /// Makes [id] the sole default. Throws [ArgumentError] if no profile has [id].
  Future<void> setDefault(String id);
}

/// [CameraProfileStore] backed by `shared_preferences`, storing the whole list
/// as one JSON document under a single key.
///
/// The document is a **versioned envelope** — `{"version": 1, "profiles": [...]}`
/// — so a future schema change can be detected and migrated (or safely ignored)
/// rather than mis-parsed. Loads are defensive: a missing key, malformed JSON,
/// an unknown version, or a wrong-typed body all resolve to an empty list, and a
/// single malformed profile entry is skipped rather than failing the whole load.
class SharedPreferencesCameraProfileStore implements CameraProfileStore {
  /// The `shared_preferences` key holding the JSON envelope.
  static const String storageKey = 'uca.camera_profiles';

  /// Current on-disk schema version.
  static const int schemaVersion = 1;

  @override
  Future<List<CameraProfile>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    return _decode(prefs.getString(storageKey));
  }

  @override
  Future<void> save(CameraProfile profile) async {
    final profiles = await loadAll();
    final incoming = profile;

    var replaced = false;
    final next = <CameraProfile>[];
    for (final existing in profiles) {
      if (existing.id == incoming.id) {
        next.add(incoming);
        replaced = true;
      } else if (incoming.isDefault) {
        // Enforce the single-default rule: flip every other profile off.
        next.add(existing.copyWith(isDefault: false));
      } else {
        next.add(existing);
      }
    }
    if (!replaced) next.add(incoming);

    await _persist(next);
  }

  @override
  Future<void> delete(String id) async {
    final profiles = await loadAll();
    final removed = profiles.where((p) => p.id == id).toList();
    if (removed.isEmpty) return; // Nothing to do.

    final next = profiles.where((p) => p.id != id).toList();
    final removedWasDefault = removed.first.isDefault;
    if (removedWasDefault && next.isNotEmpty && !next.any((p) => p.isDefault)) {
      final promoted = _mostRecent(next);
      for (var i = 0; i < next.length; i++) {
        next[i] = next[i].copyWith(isDefault: next[i].id == promoted.id);
      }
    }

    await _persist(next);
  }

  @override
  Future<void> setDefault(String id) async {
    final profiles = await loadAll();
    if (!profiles.any((p) => p.id == id)) {
      throw ArgumentError.value(id, 'id', 'No saved camera profile with this id');
    }
    final next = profiles
        .map((p) => p.copyWith(isDefault: p.id == id))
        .toList(growable: false);
    await _persist(next);
  }

  Future<void> _persist(List<CameraProfile> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    final envelope = <String, dynamic>{
      'version': schemaVersion,
      'profiles': profiles.map((p) => p.toJson()).toList(),
    };
    await prefs.setString(storageKey, jsonEncode(envelope));
  }

  /// Decodes the stored envelope into profiles, defaulting to `[]` on any
  /// problem (missing/malformed/unknown-version), skipping individual bad entries.
  List<CameraProfile> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const <CameraProfile>[];

    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const <CameraProfile>[];
    }
    if (decoded is! Map) return const <CameraProfile>[];
    if (decoded['version'] != schemaVersion) return const <CameraProfile>[];

    final rawProfiles = decoded['profiles'];
    if (rawProfiles is! List) return const <CameraProfile>[];

    final profiles = <CameraProfile>[];
    for (final entry in rawProfiles) {
      final profile = CameraProfile.fromJson(entry);
      if (profile != null) profiles.add(profile);
    }
    return profiles;
  }

  CameraProfile _mostRecent(List<CameraProfile> profiles) => profiles.reduce(
        (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
      );
}
