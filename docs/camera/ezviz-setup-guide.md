---
title: EZVIZ Camera Setup Guide (Per-User On-Device)
version: 1.2
last_validated: 2026-07-22
official: false
source: project-internal
tags: [ezviz, setup, authentication, onboarding, per-user, cs-h6c]
applies_when: "Implementing the EzvizCameraAdapter or onboarding EZVIZ cameras in an app."
---

# EZVIZ camera setup guide (per-user, on-device)

**Version 1.2** — *verified on-device login and device-specific verification codes, replacing the
bridge-based diagnostic approach.*

## Revision History
| Version | Date       | Change   |
|---------|------------|----------|
| 1.2     | 2026-07-22 | Documented the `stopRealPlay` hang (found live, fixed in `EzvizCameraAdapter.close()`) alongside the 3 already-known non-replying calls; added a "latent landmines" list of 7 more never-replying native calls found by a follow-up audit, currently unused by this repo's own code. |
| 1.1     | 2026-07-22 | Fixed Step 5's sample to match `CameraAdapter.open()`'s real signature (no `verificationCode` parameter — travels via `device.metadata`); noted the actual pre-Epic-2.5 flow is `EzvizSetupWizard` + `CameraSession.switchTo`/`openDevice`. |
| 1.0     | 2026-07-22 | Initial; documents native SDK hosted login mechanism (confirmed working on real hardware). |

## Why a per-user approach

Each EZVIZ user has their own account and device list at EZVIZ's cloud platform. This app must
support multiple end-users, each seeing only their own cameras — not a shared app-level login,
which conflates users and breaks multi-tenant assumptions. The corrected onboarding flow ensures
user-scoped authentication and device-specific verification codes.

## Prerequisites (outside this app)

1. **EZVIZ account exists** — user has already created/registered an account at `ezvizlife.com` or
   the EZVIZ mobile app.
2. **At least one camera is bound to that account** — user has physically set up and Wi-Fi-provisioned
   the camera through EZVIZ's official mobile app (BLE/SoftAP handshake + serial/verification-code
   scan). **This app never provisions a fresh camera onto Wi-Fi.** Provisioning is outside scope and
   remains an EZVIZ-official-app responsibility.

## Corrected onboarding flow (step-by-step)

### Step 0 (one-time, outside this app)

User unboxes an EZVIZ camera, installs the official EZVIZ mobile app, creates/logs into their
EZVIZ account, and Wi-Fi-provisions the camera by scanning the serial + verification-code sticker
(BLE negotiation + SoftAP handshake). The camera now appears in that account's device list.

### Step 1 (this app: "Add EZVIZ camera", no account detected)

The Cameras tab's "Add camera" dialog detects no EZVIZ login yet. It displays:
- A brief explanation: *"This app uses your EZVIZ account to access cameras you've already set up
  in the official EZVIZ app. Before we continue, you'll need an EZVIZ account with at least one
  camera already added."*
- Two buttons:
  - *"Open EZVIZ app"* (deep-links to Play Store / App Store listing of official EZVIZ mobile app).
  - *"Visit EZVIZ web portal"* (deep-links to `ezvizlife.com` for account registration/device management).

This app performs **no registration itself.** We acknowledge the hard dependency on the official
app's provisioning workflow.

### Step 2 (this app: per-user native login)

User taps the setup wizard's *"Log in with EZVIZ"* button. The app calls
`EzvizAuthManager.openLoginPage()` — this is a native SDK-hosted login page, rendered entirely by
EZVIZ's own servers in a WebView managed by the native plugin. The login page is served by EZVIZ;
this app never sees the user's password.

**Key detail:** The native `EzvizManager.kt` (in the vendored `ezviz_flutter` plugin) handles the
session entirely. Upon successful login, the plugin caches the resulting access token to disk
(native-side persistence) and provides it to the app via `getAccessToken()`.

**Result:** a `userAccessToken` (scoped to this specific EZVIZ end-user, distinct from the
app-level `appKey`/`appSecret` used for initial plugin initialization). This token is valid for an
app-defined expiry window and can be refreshed via a refresh token if the app implements that.

### Step 3 (this app: device list)

With a valid `userAccessToken`, the app calls EZVIZ's `EzvizDeviceManager.getDeviceList()`. This
returns all cameras registered under this user's account. Each becomes a candidate `CameraProfile`:
- `id`: a stable UUID (assigned by the app, not from EZVIZ).
- `device.id`: the EZVIZ serial number.
- `device.metadata`: model, channel number, encryption state (if exposed by the API).
- `backendType`: `'ezviz'`.
- `displayName`: user-editable; defaults to the device name from EZVIZ.

### Step 4 (this app: device-specific verification code, only if needed)

User selects a device from the list. The app checks the device's reported encryption state:

- **If encryption is disabled (or unknown):** skip verification-code entry.
- **If encryption is enabled or not reported:** prompt the user once with a text field:
  *"Enter this camera's 6-character verification code (shown on the device label or in the EZVIZ
  app's Device Information screen)."*

The verification code is **never displayed back** to the user after entry; never logged; and stored
**only in `flutter_secure_storage`** (encrypted), keyed by the profile `id`. It is never persisted
to `shared_preferences`.

### Step 5 (connect)

> **Today (pre-Epic-2.5):** the actual selectable flow is `EzvizSetupWizard` →
> `CameraSession.switchTo('ezviz')` → `CameraSession.openDevice(device)`, with the verification code
> embedded directly in `device.metadata['verificationCode']` — see
> `example/lib/ezviz/ezviz_setup_wizard.dart`. There is no `CameraProfile`/`secretStore` yet; the
> code is kept in plaintext `SharedPreferences` for now. The sample below is the **target design**
> once Epic 2.5's profile/secret-store persistence lands, not current behavior — note in particular
> that `CameraAdapter.open()` has no `verificationCode` parameter; it reads the code from the
> device's own `metadata` map.

When the user opens a saved EZVIZ camera profile:

```dart
// Cameras tab reads the stored verification code (if any)
final verificationCode = await secretStore.getSecret(profile.id, 'verification_code');

// Create the adapter and open the device — the code travels via metadata,
// since CameraAdapter.open() has no dedicated parameter for it.
final adapter = registry.create('ezviz');
final device = verificationCode == null
    ? profile.device
    : profile.device.copyWith(
        metadata: {...profile.device.metadata, 'verificationCode': verificationCode},
      );
await adapter.open(device);

// The adapter's buildPreview() and captureFrame() are now available
```

The adapter's implementation calls (internally):
1. `EzvizManager.shared().initSDK(...)` — once, with the user token from step 2.
2. `EzvizPlayer(onCreated: ...)` — platform view for rendering.
3. `initPlayerByDevice(serial, channelNo)` — prepare the device.
4. (If verification code was stored) `setPlayVerifyCode(code)` — decrypt the stream.
5. `startRealPlay()` — begin playback.

**Important sequencing detail:** Steps 3–5 must fire **without awaiting** their individual
completions (see "Known upstream issues" below) — actual success/failure is reported via the
separate event handler (`EzvizPlayerStatus`), not the call's return value.

## Implementation notes: vendored, patched `ezviz_flutter`

The EZVIZ adapter depends on **`ezviz_flutter` 1.2.7, vendored and patched** (not the pub.dev
package). The pub.dev version has four confirmed bugs found during implementation and testing on real
hardware (test phone CPH2113):

### Bug #1: Empty AndroidManifest in native AAR

The published `io.github.ezviz-open:ezviz-sdk:5.27` AAR declares two login-related activities
(`EzvizWebViewActivity`, `EZAuthHandleActivity`) in Kotlin source but ships an empty
`AndroidManifest.xml` (zero activity declarations). Calling `openLoginPage()` fails with *"Unable
to find explicit activity class."*

**Fix:** Declare both activities explicitly in `example/android/app/src/main/AndroidManifest.xml`:
```xml
<activity
    android:name="com.ezvizlife.ezviz_flutter.login.EzvizWebViewActivity"
    android:screenOrientation="portrait"
    android:windowSoftInputMode="adjustResize" />
<activity
    android:name="com.ezvizlife.login.EZAuthHandleActivity"
    android:screenOrientation="portrait"
    android:windowSoftInputMode="adjustResize" />
```

### Bug #2: Token clobbering on cold start

`initSDK(appKey, accessToken)` calls `setAccessToken(accessToken)` unconditionally, even when
`accessToken` is empty. The SDK silently restores a cached token from disk, but calling `initSDK`
with `accessToken: ''` unconditionally wipes it. If the app bootstrap sequence called
`getAccessToken()` *before* `initSDK()` (which throws natively since the SDK singleton doesn't exist
yet), every cold start fell into a "not logged in" branch and required signing in again.

**Fix (app-side):** Reorder bootstrap to call `initSDK` before `getAccessToken`.

**Fix (vendored plugin-side):** Modified `EzvizManager.kt`'s `initSDK` handler to only call
`setAccessToken` when the token is non-empty.

### Bug #3/4: `getDeviceList` shape mismatch

The native code sent a nested structure with a raw `EZVideoLevel` enum value, crashing the
method-channel codec. Additionally, the actual Dart model (`EzvizDeviceInfo` in
`ezviz_definition.dart`) expects a flat shape with `cameraNum`, which the native mapping didn't
provide.

**Fix (vendored plugin-side):** Rewrote the Kotlin-side native mapping to produce the flat shape
Dart's `EzvizDeviceInfo` deserializer expects.

## Known upstream issues: non-awaitable method calls

Two additional issues exist in the native Kotlin code (not fixed in the vendored plugin, only
worked around):

1. **`initPlayerByDevice`, `setPlayVerifyCode`, `startRealPlay`, and `stopRealPlay` never call
   `result.success()`** — awaiting these calls in Dart hangs indefinitely. The first three were
   caught during the original playback work; `stopRealPlay` was found later (2026-07-22) when
   `EzvizCameraAdapter.close()` awaited `EzvizPlayerController.stopRealPlay()` and hung forever,
   wedging `CameraSession`'s serialized call queue — every operation after the first `close()`
   on an open EZVIZ device (Disconnect, switching backends, even the app's own dispose) stalled
   in "busy" for the rest of the session. Workaround: fire all four sequentially without
   awaiting; rely on the separate event channel (wired via `setPlayerEventHandler`) to learn
   success/failure. `release`/`playerRelease` is fine — its Dart wrapper never awaits the channel
   call in the first place.

2. **`EzvizSimplePlayer` (the plugin's convenience widget) has a logic bug** — it marks
   `_isPlayerInitialized = true` before calling `_initializePlayer()` (the only place that calls
   `setPlayVerifyCode()`), so the verification code is silently skipped. Workaround: drive the
   plugin's lower-level `EzvizPlayer` + `EzvizPlayerController` primitives directly (as the
   `EzvizCameraAdapter` does internally).

These are known to exist in `ezviz_flutter` 1.2.7. Formal patches have **not yet been contributed
upstream** — the vendored copy stays in this repo until that's decided/done.

### Latent landmines: more never-replying native calls, currently unused

A 2026-07-22 audit (prompted by the `stopRealPlay` discovery above) checked every method-channel
call in the vendored plugin's Kotlin source for the same "native handler never calls
`result.success()`/`result.error()`" pattern. Seven more methods have it, but are **not currently
called anywhere in this repo's own code** (`EzvizCameraAdapter`/`EzvizSetupWizard`), so they're not
active bugs today — only traps for a future contributor who adopts one of them and awaits its Dart
wrapper the normal way:

- `EzvizPlayerController.initPlayerByUrl`, `initPlayerByUser`, `startReplay`, `stopReplay`
  (`ezviz_player.dart`, each `await`s its channel call; the matching `EzvizView.kt` branches never
  reply — `initPlayerByUser`'s entire native body is commented out).
- `EzvizManager.enableLog`, `enableP2P`, `setAccessToken` (`ezviz.dart`, each `await`s its channel
  call; the matching `FlutterEzvizPlugin.kt` branches call a `result`-less native overload and never
  reply).

If any of these is ever adopted, apply the same workaround as the four calls above: fire it without
`await` and rely on the event channel (if applicable) rather than the method call's own return value.

## Authentication and third-party identity providers

The native login page is rendered entirely by EZVIZ's own servers. Whether it supports third-party
identity providers (e.g., "Sign in with Google") is determined by EZVIZ's server-side configuration,
outside the scope of this app's implementation. Worth noting as an informational detail, not a
blocker.

## Risks & open questions

### Architecture risks (cross-backend)

1. **Token expiry and refresh.** The user access token has a finite lifetime. The app needs a
   refresh-before-expiry strategy and a clear *"Session expired, please log in again"* UX path,
   distinct from device-open errors. Consider an EZVIZ-specific marker (e.g., `AuthExpiredError`)
   alongside the existing typed `StateError` surface to distinguish *"auth expired"* from *"camera
   unreachable."*

2. **Revoking access.** If a user logs out inside this app, or revokes app access inside EZVIZ's
   settings, cached device lists and profiles referencing that account should be invalidated. Define
   a *"log out"* action clearing the cached token and prompting whether to also delete associated
   `CameraProfile` entries or leave them as disconnected placeholders.

3. **Multi-account / multi-tenant.** If two app-level user accounts share one device installation,
   `CameraProfileStore` / `CameraSecretStore` need a namespacing concept (scoped by app-user id). See
   [`camera-profiles.md`](camera-profiles.md) for details.

4. **AppSecret-in-binary exposure.** The app-level `appKey` (public) is passed to `initSDK()`;
   `appSecret` is never touched by this flow (the native SDK handles OAuth internally). Verify with
   EZVIZ that `appSecret` can be safely omitted from a distributed mobile binary. If a production
   app needs `appSecret` for other EZVIZ flows (e.g., direct cloud API calls), consider an
   injectable "token exchange" callback so the app can route through a backend service rather than
   embedding the secret client-side.

### EZVIZ-specific operational questions (pending re-verification)

The native-login implementation has been confirmed working end-to-end on real hardware (test device,
one account, one camera, one sign-in attempt). Pending full re-verification before v1.3 release:

- **Playback post-rewrite:** the `EzvizCameraAdapter.buildPreview()` should reuse the proven
  `_EzvizNativePlayer` sequencing from the old bridge-based test tab, but hasn't been re-clicked
  through with the new native login flow end-to-end.
- **Token persistence post-fix:** bug #2's fixes should allow a force-quit/relaunch to restore the
  token without re-signing in, but this hasn't been explicitly re-tested since the fixes.
- **Sign-out flow:** was tested once successfully; should re-verify it clears the token, returns to
  sign-in, and doesn't leave stale profiles.

### Feature-specific gaps

1. **Frame capture from platform views (§3.5 in [`feature-matrix.md`](feature-matrix.md))** —
   `EzvizCameraAdapter.captureFrame()` may be blocked if the native plugin lacks a "capture to
   file" method-channel. Must verify against `ezviz_flutter`'s real API surface before deciding
   whether `frameCapture` is `supported` or `unsupported` for EZVIZ cameras.

2. **Digital vs. optical zoom.** Many EZVIZ cameras' "zoom" is digital (client-side crop), not an
   SDK PTZ call. The feature matrix should flag this distinction so implementers don't conflate it
   with mechanical zoom.

3. **Rate limiting on device list.** `device/list` is rate-limited per AppKey. The discovery
   pipeline should cache Stage 2b results with a short TTL (e.g., 5 minutes), refetch only on
   explicit user refresh.

4. **Offline / no-network handling.** EZVIZ requires internet reachability to the Open Platform
   cloud. The Cameras tab should surface this backend-specific requirement (e.g., a declared
   `requiresInternet: bool` per backend type) so a user with no signal understands why EZVIZ
   cameras show unavailable while a USB webcam still works.

## See also

- [`camera-profiles.md`](camera-profiles.md) — how verification codes and tokens are stored.
- [`discovery-pipeline.md`](discovery-pipeline.md) — how the Cameras tab discovers EZVIZ devices
  post-login.
- [`add-camera-wizard.md`](add-camera-wizard.md) — how the setup flow is modularized into a
  reusable wizard.
- [`ezviz-integration-notes.md`](ezviz-integration-notes.md) — historical record of the diagnostic
  bridge-based approach and the early bugs discovered.
