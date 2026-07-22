---
title: ONVIF / IP-Camera Setup Guide
version: 0.2
last_validated: 2026-07-22
official: false
source: agent-generated
tags: [onvif, rtsp, ws-discovery, network-permissions, planned]
applies_when: "Setting up or implementing the ONVIF/IP-camera backend (v1.1)."
estimated_tokens: 650
---

# ONVIF / IP-camera setup guide (partially implemented — v1.1 in progress)

**Version 0.2** — auth (`open`/`close`/`isOpen`) is implemented; discovery, media/RTSP preview,
snapshot, and PTZ remain scaffolding (throw `UnimplementedError`).

## Revision History
| Version | Date       | Change                          |
|---------|------------|---------------------------------|
| 0.2     | 2026-07-22 | Auth implemented: WS-UsernameToken (PasswordDigest) + HTTP Digest fallback. |
| 0.1     | 2026-07-18 | Initial stub: network permissions. |

`ONVIFCameraAdapter` will support IP cameras implementing the ONVIF standard. This guide will grow
into the full setup manual as v1.1 lands; today it records the **network-permission requirements** so
they aren't forgotten.

## Network permissions

### Android
Add to `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<!-- Only if WS-Discovery (UDP multicast auto-discovery) is enabled: -->
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
```

### Windows
WS-Discovery uses UDP multicast on **port 3702**. A firewall rule may be required to allow
inbound + outbound UDP 3702. RTSP streams are typically TCP on port 554.

## Implemented behavior (v1.1, partial)

- **Auth (done):** `ONVIFCameraAdapter.open()` authenticates via WS-UsernameToken
  (PasswordDigest, `Base64(SHA1(Nonce + Created + Password))`), built by the hand-rolled
  `OnvifSoap`/`OnvifHttpClient` seam (`http` + `xml` + `crypto` — **not** the pub.dev `onvif`
  package). If the device challenges with HTTP 401 + `WWW-Authenticate: Digest`, the client retries
  once with an RFC 2617 Digest `Authorization` header computed from the server-supplied
  realm/nonce/qop. Credentials are supplied by the caller via `OnvifCredentials(host, port,
  username, password)` — there is no hardcoded `admin` username or forced case conversion; that
  convention (Hikvision-firmware devices commonly use `admin` + a device-sticker code) is a UI
  default for callers to apply, not adapter logic. Validated with a `GetDeviceInformation` probe;
  a SOAP `Fault` or malformed/incomplete XML maps to `StateError`/`FormatException` per the typed
  error surface. `close()` disposes the underlying `http.Client`.

## Planned behavior (not yet implemented)

- **Discovery:** manual IP entry, plus optional WS-Discovery — deferred to Epic 2.5's
  `CameraDiscoveryPipeline`/`NetworkDiscoverable` mixin, not a standalone ONVIF-only discoverer.
- **Media:** GetProfiles → GetStreamUri (RTSP) → preview via `media_kit` over **TCP** transport
  (not `flutter_vlc_player`).
- **Snapshot:** GetSnapshotUri → size-capped HTTP GET.
- **PTZ:** AbsoluteMove for pan/tilt/zoom, reported through `CameraCapabilities`.
- **Profile/secret caching:** Epic 2.5's `CameraProfileStore` (non-secret config, e.g.
  `shared_preferences`) + `CameraSecretStore` (credentials, `flutter_secure_storage` — never raw
  prefs).

## Security

Every byte off the wire is untrusted — implementation must follow the `input-hardening` skill and
`SECURITY.md`: size-cap responses before parsing, no bare casts on parsed XML, ReDoS-safe regex,
scheme/host-validate returned URIs, credentials from runtime config only, and no secrets in logs.
