// ONVIF Device Service HTTP transport: POSTs SOAP envelopes, enforces the
// input-hardening rules for every byte off the wire (size-cap before
// parsing, timeout, typed-error mapping), and falls back to RFC 2617 HTTP
// Digest when a device rejects WS-UsernameToken with a Digest challenge.

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Maximum SOAP response body accepted before it's handed to the XML parser.
/// Guards against a misbehaving/hostile device streaming an unbounded body.
const int maxOnvifResponseBytes = 1 * 1024 * 1024; // 1 MB

const String _devicePath = '/onvif/device_service';

/// Path suffix for the ONVIF Media service endpoint.
const String onvifMediaServicePath = '/onvif/media_service';

/// Posts ONVIF SOAP envelopes to a device's `device_service` endpoint.
///
/// Credentials are only ever used to compute a digest/response value; the raw
/// password is never logged, thrown in an exception message, or sent as
/// plaintext (WS-UsernameToken sends only the SHA1 digest; the HTTP Digest
/// fallback sends only the RFC 2617 `response` hash).
class OnvifHttpClient {
  OnvifHttpClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// POSTs [envelope] to `http://$host:$port$path` ([path] defaults to the
  /// Device service endpoint; pass [onvifMediaServicePath] for Media service
  /// calls).
  ///
  /// - Throws [TimeoutException] if no response arrives within [timeout].
  /// - Throws [StateError] on an HTTP 401 that a Digest retry can't resolve
  ///   (bad credentials) — never includes the credentials in the message.
  /// - Throws [FormatException] if the response body exceeds
  ///   [maxOnvifResponseBytes].
  /// - Returns the raw response body (still-untrusted XML) for the caller to
  ///   validate/parse.
  Future<String> post(
    String host,
    int port,
    String envelope, {
    String? username,
    String? password,
    required Duration timeout,
    String path = _devicePath,
  }) async {
    if (host.isEmpty || port < 1 || port > 65535) {
      throw StateError('Invalid ONVIF host/port.');
    }
    final uri = Uri.parse('http://$host:$port$path');

    final first = await _send(uri, envelope, timeout: timeout);
    if (first.statusCode != 401) {
      return _boundedBody(first);
    }

    final challenge = first.headers['www-authenticate'];
    if (challenge == null || username == null || password == null) {
      throw StateError('ONVIF authentication failed (HTTP 401).');
    }

    final digestHeader = _buildDigestHeader(
      challenge: challenge,
      method: 'POST',
      uri: path,
      username: username,
      password: password,
    );
    if (digestHeader == null) {
      throw StateError('ONVIF authentication failed (HTTP 401).');
    }

    final retry = await _send(
      uri,
      envelope,
      timeout: timeout,
      extraHeaders: {'Authorization': digestHeader},
    );
    if (retry.statusCode == 401) {
      throw StateError('ONVIF authentication failed (HTTP 401).');
    }
    return _boundedBody(retry);
  }

  /// Sends [envelope] and returns the response with its body already
  /// size-capped *while streaming* — a hostile/misbehaving device is cut off
  /// as soon as it exceeds [maxOnvifResponseBytes], never buffered in full
  /// first (that would defeat the point of the cap).
  Future<http.Response> _send(
    Uri uri,
    String envelope, {
    required Duration timeout,
    Map<String, String>? extraHeaders,
  }) async {
    final request = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/soap+xml; charset=utf-8'
      ..body = envelope;
    if (extraHeaders != null) {
      request.headers.addAll(extraHeaders);
    }

    final http.StreamedResponse streamed;
    try {
      streamed = await _client.send(request).timeout(timeout);
    } on TimeoutException {
      rethrow;
    } catch (e) {
      throw StateError('ONVIF request failed: $e');
    }

    final builder = BytesBuilder(copy: false);
    try {
      await for (final chunk in streamed.stream.timeout(timeout)) {
        builder.add(chunk);
        if (builder.length > maxOnvifResponseBytes) {
          throw const FormatException(
            'ONVIF response exceeded maxOnvifResponseBytes.',
          );
        }
      }
    } on TimeoutException {
      rethrow;
    } on FormatException {
      rethrow;
    } catch (e) {
      throw StateError('ONVIF response read failed: $e');
    }

    return http.Response.bytes(
      builder.takeBytes(),
      streamed.statusCode,
      headers: streamed.headers,
    );
  }

  String _boundedBody(http.Response response) => utf8.decode(response.bodyBytes);

  void close() => _client.close();
}

/// Builds an RFC 2617 Digest `Authorization` header from a server
/// `WWW-Authenticate` challenge, or `null` if the challenge can't be parsed
/// (e.g. not a Digest challenge).
///
/// HA1 = MD5(username:realm:password)
/// HA2 = MD5(method:uri)
/// response = MD5(HA1:nonce:HA2)                      (qop absent — common for ONVIF)
///          = MD5(HA1:nonce:nc:cnonce:qop:HA2)         (qop=auth present)
String? _buildDigestHeader({
  required String challenge,
  required String method,
  required String uri,
  required String username,
  required String password,
}) {
  if (!challenge.trim().toLowerCase().startsWith('digest')) return null;
  final params = _parseDigestParams(challenge);
  final realm = params['realm'];
  final nonce = params['nonce'];
  if (realm == null || nonce == null) return null;
  final qop = params['qop'];
  final opaque = params['opaque'];

  // Only the "auth" qop is supported; anything else (e.g. auth-int-only)
  // falls back to the no-qop formula below, which such a server will reject —
  // that's a clean auth failure, not a header we send anyway with mismatched
  // response/qop fields.
  final useQop = qop != null && qop.split(',').map((s) => s.trim()).contains('auth');

  final ha1 = md5.convert(utf8.encode('$username:$realm:$password')).toString();
  final ha2 = md5.convert(utf8.encode('$method:$uri')).toString();

  String response;
  String? cnonce;
  const nc = '00000001';
  if (useQop) {
    cnonce = _secureNonceHex(8);
    response = md5
        .convert(utf8.encode('$ha1:$nonce:$nc:$cnonce:auth:$ha2'))
        .toString();
  } else {
    response = md5.convert(utf8.encode('$ha1:$nonce:$ha2')).toString();
  }

  final buffer = StringBuffer(
    'Digest username="$username", realm="$realm", nonce="$nonce", '
    'uri="$uri", response="$response"',
  );
  if (useQop) buffer.write(', qop=auth, nc=$nc, cnonce="$cnonce"');
  if (opaque != null) buffer.write(', opaque="$opaque"');
  return buffer.toString();
}

/// Header values are bounded by the HTTP client itself, but cap defensively
/// before running a regex over attacker-influenced text (input-hardening).
const int _maxChallengeLength = 2048;

/// Time budget for the regex pass below, in addition to the length cap — an
/// attacker-influenced `WWW-Authenticate` value is untrusted input regardless
/// of source (input-hardening: every regex over external text needs both a
/// length cap and a time budget).
const Duration _maxChallengeParseTime = Duration(milliseconds: 50);

Map<String, String> _parseDigestParams(String challenge) {
  if (challenge.length > _maxChallengeLength) return const {};
  final stopwatch = Stopwatch()..start();
  final withoutScheme = challenge.replaceFirst(RegExp(r'^\s*Digest\s+', caseSensitive: false), '');
  final params = <String, String>{};
  for (final match in RegExp(r'(\w+)="?([^",]+)"?').allMatches(withoutScheme)) {
    if (stopwatch.elapsed > _maxChallengeParseTime) return const {};
    params[match.group(1)!] = match.group(2)!;
  }
  return params;
}

String _secureNonceHex(int byteLength) {
  final random = Random.secure();
  final bytes = List<int>.generate(byteLength, (_) => random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
