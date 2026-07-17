# Security Policy

## Scope

`universal_camera_adapter` abstracts both local device cameras and **external network/IP cameras
(ONVIF/RTSP)**. The local backend touches only on-device hardware; the **ONVIF backend consumes
untrusted network input** (SOAP/XML responses, RTSP/stream URIs, snapshot bytes, WS-Discovery UDP
replies) and is therefore the widest part of the attack surface.

## Secure-development posture

All code that parses or acts on external input must follow the **`input-hardening`** skill
(`.claude/skills/input-hardening/SKILL.md`). In short:

1. **Validate before parse; no bare casts** on untrusted config or parsed XML — check the shape,
   then read; wrap malformed responses in `FormatException`.
2. **Bound every regex** over external text with a length cap **and** a time budget (ReDoS-safe);
   prefer a real XML parser for structured SOAP.
3. **Degrade, don't crash** on recoverable bad input; map fatal conditions to the typed error
   surface (`StateError`/`TimeoutException`/`FormatException`).
4. **Bound and time-box network I/O** — size-cap responses *before* parsing, honor the
   `Duration timeout` on every call, validate returned URI scheme/host, prefer RTSP over TCP.
5. **No secrets in code or diagnostics** — camera credentials come from runtime config, never
   literals; redact credentials in error/log messages.

Changes touching untrusted input are expected to pass the **`security-reviewer`** gate
(`.claude/agents/security-reviewer.md`) before commit.

## Reporting a vulnerability

Please report suspected vulnerabilities privately via the repository's GitHub **Security Advisories**
("Report a vulnerability"), or by opening a minimal issue that does **not** disclose exploit details
publicly. We aim to acknowledge reports promptly and coordinate a fix and disclosure timeline.
