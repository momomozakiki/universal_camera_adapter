// ONVIF Media service client: GetProfiles + GetStreamUri, built on
// OnvifSoap (single envelope builder) + OnvifHttpClient (transport,
// size-cap, Digest retry) + package:xml.
//
// Input-hardening: every response is parsed defensively (validate shape,
// then read — no bare casts), malformed responses map to FormatException,
// and a returned stream URI is scheme-validated before being handed back —
// this backend never auto-follows a URI to an arbitrary destination.

import 'dart:async';

import 'package:xml/xml.dart';

import '../camera_adapter.dart' show kDefaultCameraTimeout;
import 'onvif_http_client.dart';
import 'onvif_soap.dart';

/// A single ONVIF media profile (token + human name).
class OnvifProfile {
  const OnvifProfile({required this.token, required this.name});

  final String token;
  final String name;

  @override
  String toString() => 'OnvifProfile(token: $token, name: $name)';
}

/// The ONVIF Media service operations `ONVIFCameraAdapter` depends on. A
/// seam so the adapter can be unit tested against a fake, without a real
/// HTTP client (input-hardening: no real sockets in unit tests).
abstract class OnvifMediaServiceBase {
  Future<List<OnvifProfile>> getProfiles({Duration timeout = kDefaultCameraTimeout});

  Future<Uri> getStreamUri(String profileToken, {Duration timeout = kDefaultCameraTimeout});
}

/// Client for the ONVIF Media service (`GetProfiles`, `GetStreamUri`).
///
/// Credentials are only ever used to compute a WS-UsernameToken digest / HTTP
/// Digest response; the raw password is never logged or echoed in an error.
class OnvifMediaService implements OnvifMediaServiceBase {
  OnvifMediaService({
    required this.host,
    required this.port,
    this.username,
    this.password,
    OnvifSoap soap = const OnvifSoap(),
    required OnvifHttpClient httpClient,
  })  : _soap = soap,
        _httpClient = httpClient;

  final String host;
  final int port;
  final String? username;
  final String? password;

  final OnvifSoap _soap;
  final OnvifHttpClient _httpClient;

  /// Retrieves the media profiles this device exposes.
  ///
  /// Individual malformed `<Profiles>` entries are skipped (degraded input,
  /// not fatal — input-hardening Rule 3); a SOAP Fault or a response with no
  /// recognizable `GetProfilesResponse` element is fatal and throws.
  @override
  Future<List<OnvifProfile>> getProfiles({
    Duration timeout = kDefaultCameraTimeout,
  }) async {
    final envelope = _soap.getProfilesEnvelope(token: _token());
    final body = await _post(envelope, timeout: timeout);
    return _parseProfiles(body);
  }

  /// Resolves the RTSP stream URI for [profileToken] (RTP-Unicast over TCP).
  ///
  /// Throws [FormatException] if the response is malformed or the returned
  /// URI does not use the `rtsp://` scheme — this method never hands back an
  /// arbitrary/unvalidated URI.
  @override
  Future<Uri> getStreamUri(
    String profileToken, {
    Duration timeout = kDefaultCameraTimeout,
  }) async {
    final envelope = _soap.getStreamUriEnvelope(profileToken, token: _token());
    final body = await _post(envelope, timeout: timeout);
    return _parseStreamUri(body);
  }

  WsUsernameToken? _token() {
    final user = username;
    final pass = password;
    return (user != null && pass != null) ? _soap.wsUsernameToken(user, pass) : null;
  }

  Future<String> _post(String envelope, {required Duration timeout}) => _httpClient.post(
        host,
        port,
        envelope,
        username: username,
        password: password,
        timeout: timeout,
        path: onvifMediaServicePath,
      );

  List<OnvifProfile> _parseProfiles(String body) {
    final document = _parseXml(body, context: 'GetProfiles');
    _throwOnSoapFault(document, action: 'GetProfiles');

    final responseNodes =
        document.descendants.whereType<XmlElement>().where((e) => e.name.local == 'GetProfilesResponse');
    if (responseNodes.isEmpty) {
      throw const FormatException(
        'ONVIF response did not contain a GetProfilesResponse element.',
      );
    }

    final profiles = <OnvifProfile>[];
    final profileNodes =
        document.descendants.whereType<XmlElement>().where((e) => e.name.local == 'Profiles');
    for (final node in profileNodes) {
      final token = node.getAttribute('token');
      if (token == null || token.isEmpty) {
        // Degraded input: skip a profile we can't identify rather than
        // failing the whole call.
        continue;
      }
      final nameNode = node.childElements.where((e) => e.name.local == 'Name').firstOrNull;
      final name = nameNode?.innerText.trim() ?? token;
      profiles.add(OnvifProfile(token: token, name: name));
    }
    return profiles;
  }

  Uri _parseStreamUri(String body) {
    final document = _parseXml(body, context: 'GetStreamUri');
    _throwOnSoapFault(document, action: 'GetStreamUri');

    final uriNode = document.descendants.whereType<XmlElement>().where((e) => e.name.local == 'Uri').firstOrNull;
    if (uriNode == null) {
      throw const FormatException(
        'ONVIF GetStreamUri response did not contain a <Uri> element.',
      );
    }
    final raw = uriNode.innerText.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme.toLowerCase() != 'rtsp') {
      throw FormatException(
        'ONVIF GetStreamUri returned an unexpected scheme (expected rtsp://).',
        _redactCredentials(raw),
      );
    }
    // Never auto-follow a stream URI to a host other than the camera we
    // authenticated against — a compromised/spoofed response must not be
    // able to redirect playback to an arbitrary destination.
    if (uri.host.toLowerCase() != host.toLowerCase()) {
      throw FormatException(
        'ONVIF GetStreamUri returned a URI for an unexpected host.',
        _redactCredentials(raw),
      );
    }
    return uri;
  }

  XmlDocument _parseXml(String body, {required String context}) {
    try {
      return XmlDocument.parse(body);
    } on XmlException catch (e) {
      throw FormatException('Malformed ONVIF $context response: ${e.message}');
    }
  }

  void _throwOnSoapFault(XmlDocument document, {required String action}) {
    final elementLocalNames = document.descendants.whereType<XmlElement>().map((e) => e.name.local).toSet();
    if (elementLocalNames.contains('Fault')) {
      throw StateError('ONVIF device returned a SOAP Fault for $action.');
    }
  }

  /// Strips any embedded userinfo (`user:pass@`) before a raw URI ever
  /// reaches an exception message.
  String _redactCredentials(String uri) => uri.replaceFirst(RegExp(r'//[^/@]+@'), '//<redacted>@');
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
