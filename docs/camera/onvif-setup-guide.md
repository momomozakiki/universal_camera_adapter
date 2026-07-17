---
title: ONVIF / IP-Camera Setup Guide
version: 0.1
last_validated: 2026-07-18
official: false
source: agent-generated
tags: [onvif, rtsp, ws-discovery, network-permissions, planned]
applies_when: "Setting up or implementing the ONVIF/IP-camera backend (v1.1)."
estimated_tokens: 600
---

# ONVIF / IP-camera setup guide (planned — v1.1)

**Version 0.1** — *placeholder: the ONVIF backend is scaffolding today (throws `UnimplementedError`).*

## Revision History
| Version | Date       | Change                          |
|---------|------------|---------------------------------|
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

## Planned behavior (v1.1)

- **Auth:** WS-UsernameToken (PasswordDigest, `Base64(SHA1(Nonce + Created + Password))`) and HTTP
  Digest fallback.
- **Discovery:** manual IP entry, plus optional WS-Discovery.
- **Media:** GetProfiles → GetStreamUri (RTSP) → preview via `media_kit` over **TCP** transport.
- **Snapshot:** GetSnapshotUri → size-capped HTTP GET.
- **PTZ:** AbsoluteMove for pan/tilt/zoom, reported through `CameraCapabilities`.

## Security

Every byte off the wire is untrusted — implementation must follow the `input-hardening` skill and
`SECURITY.md`: size-cap responses before parsing, no bare casts on parsed XML, ReDoS-safe regex,
scheme/host-validate returned URIs, credentials from runtime config only, and no secrets in logs.
