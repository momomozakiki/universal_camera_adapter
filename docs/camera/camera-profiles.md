---
title: Camera Profiles and Persistence
version: 1.1
last_validated: 2026-07-23
official: true
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
| 1.1     | 2026-07-23 | **Implemented and marked `official`** (Epic 2.5 Phase B, `21fc728`; secret transport Phase C, `4ea58ab`). Three as-built corrections: (1) secrets reach an adapter through a **transient `device.metadata` merge**, not the named `open(device, verificationCode:)` parameter this document previously showed — that parameter was never built and was deliberately rejected as an Open/Closed violation; (2) the deleted-default behaviour is decided (Option A, promote most-recent), not an open A/B choice; (3) the secure-storage section now states which platforms are actually exercised instead of asking the reader to check pub.dev. |

> **Spec version vs. code version.** Versioned independently of the package; a revision row names the
> commits whose behaviour it describes. When code and this document disagree, the code is the source
> of truth and this file is the bug.

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

**Key design:** adapters never directly read the secure store. The app-layer setup wizard or session
reads the secret and hands it to the adapter, keeping the adapter free of a storage-plugin dependency
(single responsibility, testability).

**As built — the transient metadata merge.** The v1.0 draft of this section showed the secret being
passed as a *named parameter* on `open()` (`open(device, verificationCode: …)`). That is **not** what
shipped, and it was the right call to drop: a per-backend parameter on the shared contract would grow
an argument per backend, which is exactly the Open/Closed violation the rest of this epic removes.
Instead the secret is merged into a **throwaway copy** of the device's `metadata` immediately before
`open`, so the contract signature never changes and every backend stays on one uniform `open(device)`
path:

```dart
// CameraSession, restoring a saved camera (example/lib/camera_session.dart):
final merged = <String, dynamic>{...profile.device.metadata};
for (final key in kCameraSecretKeys) {
  final secret = await secretStore.getSecret(profile.id, key);
  if (secret != null && secret.isNotEmpty) merged[key] = secret;
}
final adapter = registry.create(profile.backendType);
await adapter.open(profile.device.copyWith(metadata: merged));
```

The merged copy is never stored: session state and the persisted profile both keep the secret-free
device, so the credential exists only for the duration of the `open` call. Note the loop merges
**every** known secret key without asking which backend is live — a backend simply ignores a metadata
key it does not use — which keeps the secret-transport path free of per-type branching.

Secret key names as shipped (`example/lib/adapter_types.dart`): `'password'` for ONVIF,
`'verificationCode'` for EZVIZ.

## Default camera selection

Exactly **one** `CameraProfile.isDefault == true` across all profiles, enforced by
`CameraProfileStore.setDefault(id)` — atomically flips the previous default off.

### On fresh install

If no profile has been saved yet (new user, or only live-discovered cameras), the app falls back to
existing behavior: `registry.createDefault()` or the first result from `listDevices()`. The profile
system is **additive**, never required for the app to function.

### When the current default is deleted

**Decided and shipped: Option A** — `delete()` auto-promotes the **most-recently-created** remaining
profile (max `createdAt`). Deleting the last profile leaves the store with no default, and the
session falls back to live discovery as on a fresh install. Chosen over "clear the default entirely"
because a user with several saved cameras who removes one still expects the app to open *something*
on next launch rather than dropping back to a device picker.

`save()` also enforces the rule on the way in: saving a profile with `isDefault: true` flips every
other one off, so the invariant cannot be broken by a caller that bypasses `setDefault`.

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
DPAPI, Web localStorage), so this section states what is **actually exercised here** rather than
assuming parity:

- **Windows — exercised.** ONVIF passwords are written and read back through
  `FlutterSecureStorageCameraSecretStore` on every save/restore, verified 2026-07-23. This is the
  only platform the secret store has been driven against real user input.
- **Android — configured, not yet exercised.** `AndroidOptions(encryptedSharedPreferences: true)` is
  set (`camera_secret_store.dart`), but no Android device has been attached since the store landed,
  so the EZVIZ verification-code path is compile-checked only.
- **iOS — untested.** No iOS toolchain in this environment.

**Windows toolchain caveat:** `flutter_secure_storage` needs Visual Studio 2022 with the **C++ ATL**
component; without it the Windows build fails with `fatal error C1083: Cannot open include file:
'atlstr.h'`. Switching VS versions additionally requires `flutter clean` (`CMakeCache.txt` pins the
generator).

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
