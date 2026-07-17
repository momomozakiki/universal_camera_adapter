// ONVIF Media service seam — PLANNED (ROADMAP v1.1). Scaffolding only.
//
// Wraps the ONVIF Media service: GetProfiles, GetStreamUri (RTSP), and
// GetSnapshotUri. Built on OnvifSoap (single envelope builder) + package:xml.
//
// INPUT-HARDENING TODO (see the input-hardening skill):
//   - Validate the XML shape of every response; no bare casts on nodes.
//   - Scheme/host-validate returned URIs: GetStreamUri must start with
//     `rtsp://`, GetSnapshotUri with `http(s)://`; do NOT auto-follow a URI to
//     an arbitrary host pulled from an untrusted response.
//   - Size-cap the snapshot download before decoding the image bytes.
//   - Map network failures to TimeoutException, malformed XML to FormatException.

/// A single ONVIF media profile (token + human name). Planned for v1.1.
class OnvifProfile {
  const OnvifProfile({required this.token, required this.name});

  final String token;
  final String name;
}

/// Placeholder for the ONVIF Media service client. Not yet implemented.
class OnvifMediaService {
  const OnvifMediaService();

  /// Lists media profiles. Planned for v1.1.
  Future<List<OnvifProfile>> getProfiles() {
    throw UnimplementedError('ONVIF GetProfiles is planned (ROADMAP v1.1).');
  }

  /// Resolves the RTSP stream URI for [profileToken]. Planned for v1.1.
  Future<Uri> getStreamUri(String profileToken) {
    throw UnimplementedError('ONVIF GetStreamUri is planned (ROADMAP v1.1).');
  }

  /// Resolves the HTTP snapshot URI for [profileToken]. Planned for v1.1.
  Future<Uri> getSnapshotUri(String profileToken) {
    throw UnimplementedError('ONVIF GetSnapshotUri is planned (ROADMAP v1.1).');
  }
}
