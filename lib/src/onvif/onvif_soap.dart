// ONVIF SOAP seam — PLANNED (ROADMAP v1.1). Scaffolding only; no network code.
//
// When implemented, this module is the single place that builds ONVIF SOAP
// envelopes and their security header, so services never hand-roll XML (DRY —
// see `dart-solid-principles`). It will depend on `package:http` (requests) and
// `package:xml` (parsing), added in v1.1.
//
// Auth: WS-UsernameToken (PasswordDigest) — Base64(SHA1(Nonce + Created +
// Password)) — and HTTP Digest as a fallback.
//
// INPUT-HARDENING TODO (mandatory before this ships — see the input-hardening skill):
//   - Size-cap every HTTP/SOAP response BEFORE handing it to the XML parser
//     (reject bodies over a `maxResponseBytes` constant → DoS guard).
//   - No bare `as`/`!` casts on parsed XML nodes; validate the shape, then read.
//   - Wrap malformed/unexpected XML in FormatException(message, body-with-secrets-redacted).
//   - Any regex over response text gets a length cap AND a Stopwatch time budget.
//   - Credentials come from OnvifCredentials (runtime config), never literals;
//     never log the password, nonce, or full Authorization/security header.

/// Placeholder for the SOAP envelope builder. Not yet implemented.
class OnvifSoap {
  const OnvifSoap();

  /// Builds a SOAP request envelope for [action] with an optional
  /// WS-UsernameToken security header. Planned for v1.1.
  String buildEnvelope(String action, {Map<String, String>? body}) {
    throw UnimplementedError('ONVIF SOAP envelope building is planned (ROADMAP v1.1).');
  }
}
