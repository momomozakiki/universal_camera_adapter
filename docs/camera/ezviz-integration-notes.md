---
title: EZVIZ Camera Integration Notes (test tooling)
version: 1.0
last_validated: 2026-07-21
official: false
source: project-internal
tags: [ezviz, cs-h6c, android, windows, ezviz_flutter, diagnostic]
applies_when: "Working on, debugging, or extending the EZVIZ test tab (example/lib/tabs/ezviz_tab.dart) or the bridge (scripts/ezviz_bridge.py)."
---

# EZVIZ camera integration notes

**Status: working on Android. Not supported on Windows** (by design — see
[Platform support](#platform-support)). This is diagnostic/example tooling, not part of the
`CameraAdapter` contract — it exists to prove live-view connectivity to a real EZVIZ camera
(model CS-H6c) ahead of/alongside the project's own ONVIF backend work (Epic 2 in
[`docs/plan/ROADMAP.md`](../plan/ROADMAP.md)).

## Revision History
| Version | Date       | Change                                                    |
|---------|------------|------------------------------------------------------------|
| 1.0     | 2026-07-21 | Initial write-up after getting live view working on Android. |

## The two pieces

1. **`scripts/ezviz_bridge.py`** — a small stdlib-only Python HTTP server that wraps EZVIZ's
   official **Open Platform** cloud API (`open.ezvizlife.com`). It is tied to *one* EZVIZ
   developer account via environment variables:
   ```
   EZVIZ_APP_KEY=...
   EZVIZ_APP_SECRET=...
   python scripts/ezviz_bridge.py [--host 0.0.0.0] [--port 8765]
   ```
   On startup it fetches (and auto-refreshes) an access token, then exposes:
   - `GET /devices` → `[{"serial", "name", "model"}, ...]` (from `device/list`)
   - `GET /config` → `{"appKey": "...", "accessToken": "..."}`

   It does **not** proxy video bytes and does **not** fetch a stream URL — see
   [Why no stream URL](#why-no-stream-url-hlsrtmpezopen-all-ruled-out) below.

2. **`example/lib/tabs/ezviz_tab.dart`** — a Flutter tab with three parts:
   - A device list, fetched from the bridge's `/devices` + `/config`.
   - A verification-code text field (persisted across app restarts via `shared_preferences`)
     and an explicit **Connect**/**Reconnect** button.
   - `_EzvizNativePlayer` — a small custom widget (bottom of the file) that plays the camera's
     live feed using the `ezviz_flutter` pub package's **low-level** primitives directly. See
     [Current working solution](#current-working-solution-_ezviznativeplayer) for why it's
     custom rather than using that package's higher-level convenience widget.

## Why no stream URL (HLS/RTMP/ezopen all ruled out)

The natural-looking approach — call `live/address/get` and hand a URL to a normal video player
(`media_kit`, already in the example's dependency tree at the time) — was tried and empirically
ruled out for this account/camera:

| `protocol=` | Result |
|---|---|
| `2` (HLS) | Returns a `.m3u8` URL, but the playlist always points at a fixed EZVIZ error-placeholder segment (`ErrCode/9053_0.ts`) — plays nothing, regardless of retries or a fresh URL. |
| `3` (RTMP) | Returns a URL, but the RTMP relay refuses the connection outright (`ffmpeg`: I/O error). |
| `1` (`ezopen://`) | The only one that actually "succeeds" — but `ezopen://` is EZVIZ's own proprietary URI scheme, not playable by any standard player (ffmpeg/VLC/`media_kit`). It needs EZVIZ's own client-side logic to resolve. |

Conclusion: this account/region's Open Platform deployment doesn't have server-side transcoding
provisioned. The only viable path is to let an EZVIZ-aware client (their JS player, or their
native SDK) do the actual stream resolution — hence the pivot to `ezviz_flutter`.

## The other dead end: local-SDK (`pyezvizapi`)

Before the Open Platform pivot, this camera was targeted via its local network SDK (ports
9010/9020) using the community-maintained `pyezvizapi` Python library (same one Home Assistant's
EZVIZ integration uses). This was **conclusively ruled out**: the library's stream decoder
doesn't understand this camera's local packets at all — they use an "IDMX" packet container
`pyezvizapi` doesn't parse, independent of whether the device's video encryption is on or off
(confirmed by disabling encryption entirely on the camera and re-testing — captured bytes were
still unparseable, not just encrypted). This is a genuine gap in that library for this
camera/firmware, not something safe to patch around. `scripts/ezviz_bridge.py` no longer depends
on `pyezvizapi` at all.

## Current working solution: `_EzvizNativePlayer`

`ezviz_flutter` (pub.dev, third-party, wraps EZVIZ's own native Android/iOS SDKs) ships a
convenience widget, `EzvizSimplePlayer`, that looks like the obvious choice. **It doesn't work
for this use case** — it has a real bug (below). `_EzvizNativePlayer` instead drives the
package's lower-level, still-public primitives directly:

- `EzvizManager.shared().initSDK(EzvizInitOptions(appKey:, accessToken:))` — once, in `initState`,
  **awaited to completion** before anything else touches the player.
- `EzvizPlayer(onCreated: ...)` — a bare `AndroidView`/`UiKitView` wrapper; its `onCreated`
  callback hands back an `EzvizPlayerController`.
- On that controller, in order: `setPlayerEventHandler(...)` (must be first, or early status
  events are missed), then `initPlayerByDevice(serial, channelNo)`, then (if a verification code
  was entered) `setPlayVerifyCode(code)`, then `startRealPlay()`.
- Status/errors arrive asynchronously via the event handler (`EzvizPlayerStatus`: `1`=init,
  `2`=playing, `9`=error), not via those method calls' return values — see the second bug below
  for why that distinction matters.
- `dispose()` mirrors what `EzvizSimplePlayer` does internally: `removePlayerEventHandler()`,
  `stopRealPlay()`, `release()`.

The tab gives `_EzvizNativePlayer` a `key: ValueKey('$serial::$code::$connectAttempt')`. Changing
the key forces Flutter to fully dispose the old instance and construct a fresh one — this is what
makes editing the code field and tapping **Connect** always start a clean attempt, regardless of
whether the previous attempt errored out.

### Bug #1 (in `EzvizSimplePlayer`): verification code is silently never applied

Traced in `ezviz_flutter` 1.2.7's `lib/widgets/ezviz_simple_player.dart`:
- `_initializePlayer()` is the *only* place that calls `setPlayVerifyCode()`.
- `_handlePlayerStatus()` sets `_isPlayerInitialized = true` as soon as the native SDK reports
  status `1` ("Init") — which fires immediately after the platform view is created,
  unconditionally, well before `_initializePlayer()` has run.
- `_startLiveStream()` only calls `_initializePlayer()` `if (!_isPlayerInitialized)`. Since that
  flag is already `true`, `_initializePlayer()` — and therefore `setPlayVerifyCode()` — is
  **skipped every time**, for both `autoPlay` and the widget's own built-in "Retry" button.

Confirmed via `adb logcat`: the plugin's own `🔐 Setting verification code` debug line never
appeared across ~9 real playback attempts, no matter what the UI did — including moving the code
field onto the same screen as the player and forcing a fresh widget instance per attempt. The
camera kept rejecting playback with a native error translating to *"Video password incorrect; the
initial password is the 6-digit verification code on the device label."*, even with the
**confirmed-correct** code (verified directly from the camera's own Device Information screen in
the EZVIZ app, not just its printed label).

**Fix**: stop using `EzvizSimplePlayer`; call the lower-level primitives ourselves in the right
order (see above). This is what `_EzvizNativePlayer` does.

### Bug #2 (in the native plugin code itself): three method calls never resolve

After switching to the low-level API and correctly `await`-ing each call in sequence
(`initPlayerByDevice` → `setPlayVerifyCode` → `startRealPlay`), playback got stuck at
`Player state: initialized` forever — no error, no progress. Traced into the plugin's **native**
Kotlin side (`android/src/main/kotlin/.../EzvizView.kt`, `onMethodCall`): the handlers for
`initPlayerByDevice`, `setPlayVerifyCode`, and `startRealPlay` never call
`result.success(...)`/`result.error(...)` at all (unlike e.g. `openSound`/`capturePicture`, which
do). A Flutter method-channel call that never gets a native response leaves its Dart `Future`
pending forever — `await`-ing any of these three hangs indefinitely, and everything after that
`await` in the calling code simply never runs.

**Fix**: don't `await` these three specific calls. Fire them one after another without waiting
(method-channel calls on the same channel are dispatched in order by the platform, so this still
reaches the native SDK calls in the correct sequence) and rely entirely on the **separate event
channel** (already wired via `setPlayerEventHandler`) to learn what actually happened. This is
what finally got the camera to play.

## Platform support

`ezviz_flutter` only ships Android and iOS native implementations — there is no Windows
implementation, and none is planned by that package. This tab is therefore **Android/iOS-only**,
by the same kind of constraint that separately ruled out `webview_flutter_windows` for an earlier
(abandoned) approach: it required a C++23 compiler this project's Windows MSVC toolchain doesn't
have. `example/pubspec.yaml` depends on `ezviz_flutter` with no Windows-side plugin; the rest of
the example app (`Preview`, `QR`, `Barcode`, `Gallery`, `PTZ` tabs — all backed by
`universal_camera_adapter` itself, not this tab) still builds and runs on Windows normally.

## How to test end-to-end

1. Start the bridge (needs your own EZVIZ Open Platform `AppKey`/`Secret`, registered under the
   *same* EZVIZ account that owns the camera — device binding is exclusive to one account):
   ```
   EZVIZ_APP_KEY=... EZVIZ_APP_SECRET=... python scripts/ezviz_bridge.py --host 0.0.0.0 --port 8765
   ```
2. Run the example app on an Android device: `flutter run -d <device-id>` from `example/`.
3. If the device is connected via USB (rather than sharing a Wi-Fi network with the machine
   running the bridge), forward the port over the cable instead of relying on network topology:
   ```
   adb reverse tcp:8765 tcp:8765
   ```
   then use `127.0.0.1:8765` as the "Bridge host:port" field in the app. This survives adb-server
   restarts poorly — re-run `adb reverse` if the app suddenly can't reach the bridge after one.
4. In the EZVIZ tab: tap a device, enter its verification code (if the device has video
   encryption enabled — check the camera's own Privacy Settings in the EZVIZ app), tap Connect.
5. To confirm what's actually happening under the hood rather than trusting the UI alone, grep
   logcat for the tab's own debug line and the plugin's event stream:
   ```
   adb logcat -d | grep -i "Applying verification code\|Player status"
   ```
   `status: 2` means playing; `status: 9` carries a `message` with the native SDK's error text.

## Known rough edges (this session's hardware, not necessarily universal)

- `ezviz_flutter`'s Gradle setup emits a "Kotlin Gradle Plugin (KGP)" deprecation warning on every
  build — informational only as of this writing, not a build failure.
- `flutter run`'s auto-launch on this test phone occasionally failed with a transient Android
  `Cannot make calls to a recycled instance!` error even though the APK built and installed fine;
  `adb shell am start -n <package>/.MainActivity` launched the already-installed build without
  issue when that happened.
