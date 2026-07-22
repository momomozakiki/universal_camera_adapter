// ONVIF SOAP envelope builder — the single place that builds ONVIF SOAP
// envelopes and their WS-Security header, so services never hand-roll XML
// (DRY — see `dart-solid-principles`).
//
// Auth: WS-UsernameToken (PasswordDigest) — Base64(SHA1(Nonce + Created +
// Password)). HTTP Digest (RFC 2617) is a separate fallback, built in
// `onvif_http_client.dart` from the server's `WWW-Authenticate` challenge.
//
// This class only builds strings — no network calls, no parsing of untrusted
// input — so it stays trivially unit-testable.

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// A WS-UsernameToken security header: the nonce/timestamp/digest triple an
/// ONVIF device expects in the SOAP `<Security>` header.
class WsUsernameToken {
  const WsUsernameToken({
    required this.username,
    required this.nonceBase64,
    required this.created,
    required this.passwordDigestBase64,
  });

  final String username;

  /// Base64-encoded random nonce (raw bytes, not the digest input).
  final String nonceBase64;

  /// UTC creation timestamp in strict ISO8601 form (`...T...Z`).
  final String created;

  /// `Base64(SHA1(nonce_bytes + created + password))`.
  final String passwordDigestBase64;
}

/// Builds ONVIF SOAP envelopes and their WS-Security header.
class OnvifSoap {
  const OnvifSoap();

  /// Builds a WS-UsernameToken (PasswordDigest) header for [username]/[password].
  ///
  /// Uses a cryptographically random 16-byte nonce (`Random.secure()` — a
  /// plain `Random()` is not acceptable for a security-token nonce) and the
  /// current UTC time. Never logs or echoes [password]; only the resulting
  /// digest is exposed.
  WsUsernameToken wsUsernameToken(String username, String password) {
    final nonceBytes = _secureNonce(16);
    final created = DateTime.now().toUtc().toIso8601String();
    final digestInput = <int>[
      ...nonceBytes,
      ...utf8.encode(created),
      ...utf8.encode(password),
    ];
    final digest = sha1.convert(digestInput).bytes;
    return WsUsernameToken(
      username: username,
      nonceBase64: base64.encode(nonceBytes),
      created: created,
      passwordDigestBase64: base64.encode(digest),
    );
  }

  /// Builds a SOAP 1.2 envelope for [action] with an optional [body] (already
  /// XML-escaped element name/value pairs) and an optional [token] security
  /// header.
  String buildEnvelope(
    String action, {
    Map<String, String>? body,
    WsUsernameToken? token,
  }) {
    final security = token == null
        ? ''
        : '''
      <Security xmlns="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" soap:mustUnderstand="1">
        <UsernameToken>
          <Username>${_escape(token.username)}</Username>
          <Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest">${token.passwordDigestBase64}</Password>
          <Nonce EncodingType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary">${token.nonceBase64}</Nonce>
          <Created xmlns="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">${token.created}</Created>
        </UsernameToken>
      </Security>
''';
    final bodyFields = (body ?? const {})
        .entries
        .map((e) => '<${e.key}>${_escape(e.value)}</${e.key}>')
        .join();
    return '''<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
  <soap:Header>
$security  </soap:Header>
  <soap:Body>
    <$action xmlns="http://www.onvif.org/ver10/device/wsdl">$bodyFields</$action>
  </soap:Body>
</soap:Envelope>''';
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

List<int> _secureNonce(int length) {
  final random = Random.secure();
  return List<int>.generate(length, (_) => random.nextInt(256));
}
