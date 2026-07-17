---
name: input-hardening
description: >-
  Use as the security lens whenever this package touches data that came from outside the process —
  a `CameraDevice` metadata/config map, ONVIF SOAP/XML responses, RTSP/stream URIs, snapshot bytes
  off an HTTP GET, or WS-Discovery UDP replies. Trigger whenever a request mentions untrusted or
  external input, hardening, sanitizing, input validation, ONVIF/SOAP/XML parsing, RTSP, injection,
  ReDoS / catastrophic-backtracking regex, secrets/tokens/credentials/passwords in code, DoS or
  resource exhaustion, frame/buffer/response size limits, "is this input safe to parse", or
  reviewing the attack surface of the ONVIF backend — even if the word "security" never appears.
  Defer the adapter contract itself to [[camera-adapter-authoring]]; this skill is about not
  trusting what comes in. Use it before adding a cast, a regex, a new inbound field, or a network call.
---

# Input hardening — trust nothing that came off the network

Camera backends sit between **untrusted sources** — an IP camera that may misbehave or be spoofed,
credentials/host a user typed, SOAP/XML and RTSP payloads off the wire, UDP discovery replies from
anything on the LAN — and consumer widgets that render whatever we hand back. The `FlutterCameraAdapter`
path is local hardware; the **ONVIF path is the wide part of the attack surface**. Parsing hostile
input must not crash, hang, or leak. That safety isn't automatic — it's a set of habits this skill
names so they don't erode one cast or one regex at a time.

The boundary is simple: **the moment a value crosses into the process from a socket, an HTTP
response, or a config the user typed, it is untrusted** until validated. [[camera-adapter-authoring]]
owns *how* an adapter is shaped and its typed error surface; this skill owns the orthogonal
question — *did we assume this input was well-formed when we had no right to?*

## Rule 1 — Validate before you parse; never bare-cast config or XML

An ONVIF connection config (host, port, username, password) and every parsed XML node is a
`Map`/`dynamic` landmine: missing, wrong type, out of range. Validate the config **at the top of
`open()`, before any network connect**, collecting all problems, then fail loudly with a `StateError`
(user-facing) — not a `TypeError` deep in a SOAP parse loop. Same for parsed XML: check the shape,
then read; wrap malformed responses in `FormatException` with context.

Check types with `is!` and only then read — never `xml.getElement('Uri')!.text as String` or a bare
`node['token'] as String` on attacker-controlled XML, because a bare cast turns a spoofed camera
response into an uncaught runtime exception.

```dart
// Good: validate, then read.
final uriNode = env.findAllElements('Uri').firstOrNull;
if (uriNode == null) {
  throw FormatException('GetStreamUri response missing <Uri>', body);
}
final uri = uriNode.innerText.trim();
if (!uri.startsWith('rtsp://')) {
  throw FormatException('Unexpected stream URI scheme', uri);
}
```

**Smell:** a bare `as` / `!` on a value pulled straight from parsed XML or a config map; parsing that
begins before the config is validated; validation that *throws mid-loop* instead of failing up front.

## Rule 2 — Every regex over external input gets a length cap and a time budget

A regex applied to attacker-controlled text (a SOAP body, a stream URI, a device name) is a ReDoS
waiting to happen: a crafted input makes the pattern backtrack for seconds and pins the isolate.
Defend in two layers whenever you run a regex over network/device text:

1. **Pre-flight length cap** — reject inputs/patterns longer than a `maxLength` constant before
   matching.
2. **Runtime time budget** — wrap the match in a `Stopwatch` against a `timeoutMs` constant; if it
   blows the budget, **fall back safely** (treat the field as absent/opaque) and surface a warning —
   don't let it run unbounded.

Prefer a real XML parser (`package:xml`) over regex for structured SOAP; reserve regex for small,
bounded extraction and always guard it. **Smell:** `RegExp(pattern).allMatches(soapBody)` with no
length guard and no timeout — one malicious response hangs the parser.

## Rule 3 — Recoverable input problems degrade; fatal ones map to the typed surface

A WS-Discovery reply that's malformed, a camera advertising a profile we can't use, or one snapshot
that fails to download is **expected degraded input**, not a reason to crash the whole adapter. Skip
the bad discovery hit and keep the good ones; return the profiles you could parse. Reserve the typed
errors ([[camera-adapter-authoring]] Rule 4 — `StateError`/`TimeoutException`/`FormatException`) for
genuinely fatal conditions: connection refused, auth rejected, a response we cannot make sense of at
all. Keep the failure *observable* (a logged warning), never a silent empty result.

**Smell:** an out-of-bounds access on a parsed profile list that throws `RangeError`; a `catch` that
swallows a malformed-discovery case and returns empty with no signal.

## Rule 4 — Bound and time-box every network call; validate what it points at

The ONVIF/RTSP path reaches out over the network, so treat every response as hostile even after it
parses:

1. **Size cap responses before parsing** — reject a SOAP/HTTP body or snapshot over a `maxBytes`
   constant **before** feeding it to the XML parser or decoding the image, so a giant payload can't
   exhaust memory (DoS).
2. **Timeout every call** — every network-bound method already takes a `Duration timeout` (default
   15s); honor it on connect, each SOAP round-trip, snapshot GET, and the RTSP handshake. No
   unbounded awaits.
3. **RTSP over TCP** — prefer TCP transport (avoid UDP packet loss); create the player in `open()`,
   dispose in `close()`.
4. **Don't blindly trust a returned URI/host** — a `GetStreamUri`/`GetSnapshotUri` response can point
   anywhere. Validate the scheme (`rtsp://`/`http(s)://`) and, where practical, that the host matches
   the camera you connected to — don't auto-follow it to an arbitrary destination.
5. **WS-Discovery is multicast** — anything on the LAN can answer; every reply is untrusted. Cap the
   number of hits processed and the size of each.

**Smell:** reading an unbounded response into memory before size-checking; an `await` on a network
call with no timeout; auto-connecting to a host pulled straight from an untrusted response.

## Rule 5 — No secrets in code; keep them out of diagnostics too

ONVIF credentials (username/password), digest nonces, and any device secret come from **runtime
config**, never hard-coded literals in the repo (they leak through git history forever). When
something is logged or surfaced in an error/warning message, **redact credentials** — an error that
echoes the password or the full WS-UsernameToken digest just moves the leak. A secret must never
appear in source, in a `StateError`/`FormatException` message, or in a log line.

**Smell:** a string literal that looks like a password/token in `lib/`; an error that interpolates the
full SOAP handshake, the raw `Authorization` header, or the password.

## PR litmus test

- ✅ Is the ONVIF config validated (all problems collected → `StateError`) before any connect, with
  `is!` checks instead of bare `as`/`!` on untrusted config or parsed XML?
- ✅ Does every regex over external input have both a length cap **and** a timeout with a safe fallback?
- ✅ Do degraded inputs (bad discovery hit, unusable profile) degrade gracefully, while fatal ones map
  to `StateError`/`TimeoutException`/`FormatException` — never an unhandled throw or a silent empty result?
- ✅ Is every network response size-capped **before** parsing and every network call timeout-bounded,
  with returned URIs scheme/host-validated?
- ✅ Are there no secret literals in source, and do errors/logs redact credentials?

## References

- `lib/src/onvif/onvif_soap.dart` — SOAP envelope building + WS-UsernameToken (credentials from
  config, never literals); size-cap + validate responses here.
- `lib/src/onvif/onvif_media_service.dart` — `GetProfiles`/`GetStreamUri`/`GetSnapshotUri` parsing;
  validate XML shape, scheme-check returned URIs.
- `lib/src/onvif/rtsp_preview.dart` — RTSP/TCP player lifecycle (create in `open()`, dispose in `close()`).
- `lib/src/camera_adapter.dart` — the typed error surface these rules map onto.
- Related skills: [[camera-adapter-authoring]] (adapter contract + typed errors), [[dart-solid-principles]].

> Paths are intentionally concrete; if they move, update this skill.
