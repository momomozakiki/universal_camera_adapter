---
title: Camera Profiles and Persistence
version: 1.0
last_validated: 2026-07-22
official: false
source: project-internal
tags: [profiles, persistence, storage, secure-storage, preferences]
applies_when: "Designing the Cameras tab or implementing per-user camera save/recall behavior."
---

# Camera profiles and persistence

**Version 1.0** — *user-saved camera lists, secure secret storage, default selection.*

## Revision History
| Version | Date       | Change   |
|---------|------------|----------|
| 1.0     | 2026-07-22 | Initial. |

## What's stored: `CameraProfile`

A user-facing record of a camera the app has connected to before:

```dart
@immutable
class CameraProfile {
  /// Stable UUID assigned at save-time, distinct from CameraDevice.id 
  /// (which may be ephemeral—e.g., an ONVIF IP that changes).
  final String id;
  
  /// Registry key: 'builtin', 'onvif', 'ezviz', etc.
  final String backendType;
  
  /// User-editable friendly name. Defaults to device name.
  final String displayName;
  
  /// Snapshot of the device: id/name/lensFacing/metadata sufficient to re-locate/re-open it.
  /// Backend-specific connection config (ONVIF host/port, EZVIZ serial) lives in metadata.
  final CameraDevice device;
  
  /// Exactly one true across all profiles, enforced by the store.
  final bool isDefault;
  
  /// When the profile was first saved.
  final DateTime createdAt;
}
```

**Key invariant:** A `CameraProfile` object is always safe to log, export, or inspect — no secrets
are embedded in it. Secrets (EZVIZ verification codes, OAuth refresh tokens) are stored separately
in a secure-storage-backed system, keyed by profile `id`.

## Where it lives: two stores, split by sensitivity

### Non-secret profile list → `CameraProfileStore`

The list of all saved profiles (name, device ID, backend type, timestamps) is **not sensitive** —
it can live in simple persistent storage. Default implementation uses `shared_preferences` (JSON-encoded
list), matching the precedent of other non-sensitive config already stored there (e.g., bridge host
field in the old EZVIZ tab).

```dart
/// Injected interface; app can supply its own.
abstract class CameraProfileStore {
  /// Load all saved profiles.
  Future<List<CameraProfile>> loadAll();
  
  /// Save or update a profile.
  Future<void> save(CameraProfile profile);
  
  /// Delete a profile by id.
  Future<void> delete(String id);
  
  /// Set a profile as default. Atomically flips the previous default off.
  /// Only one profile can be default at a time.
  Future<void> setDefault(String id);
}
```

Located in `lib/src/persistence/camera_profile_store.dart`, with a default
`SharedPreferencesCameraProfileStore` implementation. This allows apps with their own persistence
layer (e.g., Firebase, SQLite) to inject their own backend without being locked to `shared_preferences`.

### Secrets → `CameraSecretStore` (secure storage)

Backend-specific secrets are stored separately, always in encrypted storage (Android Keystore /
iOS Keychain), **never** in `shared_preferences`. This directly fixes today's EZVIZ tab behavior
where verification codes are stored unencrypted.

```dart
/// Injected interface; app can supply its own.
abstract class CameraSecretStore {
  /// Retrieve a secret (e.g., verification code) for a profile.
  /// Returns null if not found.
  Future<String?> getSecret(String profileId, String key);
  
  /// Store a secret for a profile.
  Future<void> setSecret(String profileId, String key, String value);
  
  /// Delete all secrets for a profile (e.g., on profile deletion).
  Future<void> deleteSecretsForProfile(String profileId);
}
```

Located in `lib/src/persistence/camera_secret_store.dart`, with a default
`FlutterSecureStorageCameraSecretStore` implementation (wraps `flutter_secure_storage`).

**Key design:** adapters never directly read the secure store. An adapter's factory or the
app-layer setup wizard reads the secret and passes it as a parameter to the adapter's `open()`
method or constructor, keeping the adapter free of a storage-plugin dependency (single
responsibility, testability).

Example: EZVIZ adapter + verification code:
```dart
// Cameras tab reads the secret
final verificationCode = await secretStore.getSecret(profile.id, 'verification_code');

// Pass it to the adapter
final adapter = registry.create('ezviz');
await adapter.open(profile.device, verificationCode: verificationCode);
```

## Default camera selection

Exactly **one** `CameraProfile.isDefault == true` across all profiles, enforced by
`CameraProfileStore.setDefault(id)` — atomically flips the previous default off.

### On fresh install

If no profile has been saved yet (new user, or only live-discovered cameras), the app falls back to
existing behavior: `registry.createDefault()` or the first result from `listDevices()`. The profile
system is **additive**, never required for the app to function.

### When the current default is deleted

- **Option A:** Auto-promote the oldest/most-recently-used remaining profile.
- **Option B:** Clear default entirely, fall back to live discovery.

The implementation should choose one explicitly and document it as user-visible behavior, not leave
it as a silent implementation detail.

## Relationship to discovery pipeline

The Cameras tab displays both:
- **Live discovery results** (§2 in [`discovery-pipeline.md`](discovery-pipeline.md)) — cameras found
  just now on the network or cloud account.
- **Saved profiles** — past cameras the user has connected to, persisted across app sessions.

A camera can be in both (the user saved it before, and it's showing up in today's discovery) — these
are separate concerns. Saving a profile doesn't "lock" discovery; discovery doesn't require a
profile to be saved first.

## Secrets split by backend

Each backend defines what secrets it needs:

- **`FlutterCameraAdapter` (local device):** no secrets.
- **`ONVIFCameraAdapter` (IP cameras):** username/password (if the camera uses HTTP Digest or
  WS-UsernameToken auth).
- **`EzvizCameraAdapter`:** verification code (per-device, device-specific; see
  [`ezviz-setup-guide.md`](ezviz-setup-guide.md)). OAuth refresh tokens, if the app implements
  token refresh, would also live here.

The setup wizard for each backend is responsible for writing its secrets to the store before
returning the `CameraProfile`. The profile itself never contains the secret.

## Multi-user / multi-account handling

**Not fully designed this round.** Flag for product owner: if two different app-level accounts
share one device installation (e.g., a shared tablet where User A and User B each have their own
EZVIZ login), `CameraProfileStore` and `CameraSecretStore` need a namespacing concept (scoped by
app-user id). Decide now whether this is needed; if yes, add a `scopeId` parameter to both store
interfaces rather than retrofitting later.

## Secure storage platform support

`flutter_secure_storage` backing varies by platform (Android Keystore, iOS Keychain, Windows
DPAPI, Web localStorage). Since EZVIZ is Android/iOS-only anyway (no Windows `ezviz_flutter`
plugin), the risk is modest, but `camera-profiles.md` should state which platforms the secure
store is validated on rather than assume universal parity. At minimum:
- **Android:** Keystore-backed, secure.
- **iOS:** Keychain-backed, secure.
- **Windows:** validated but lower-priority for EZVIZ.

Check the `flutter_secure_storage` pub.dev page for current platform coverage before marking any
as official.

## Risks and open questions

- **Rate limiting on discovery refresh** — the Cameras tab should not call
  `CameraDiscoveryPipeline.discover()` on every resume/focus; add caching with a short TTL (e.g.,
  cache for 5 minutes, refetch only on explicit user refresh). EZVIZ's `device/list` is rate-limited
  per AppKey.
- **Offline fallback** — if the app is offline and can't reach the discovery pipeline, the Cameras
  tab should still render saved profiles and offer "retry" affordances, not blank out.
- **Deleted-camera cleanup** — if a camera was deleted from the user's EZVIZ account (outside the
  app), should the app detect this and auto-remove the stale profile, or leave it as a disconnected
  placeholder? Design a clear policy.
