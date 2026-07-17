// RTSP preview seam — PLANNED (ROADMAP v1.1). Scaffolding only.
//
// The live-preview widget for an ONVIF camera. When implemented it will use
// `package:media_kit` + `package:media_kit_video` (added in v1.1 — a heavy
// native dependency deliberately kept out of v1.0 so local-camera consumers
// don't pull it in), with:
//   - RTSP over **TCP** transport (avoids UDP packet loss);
//   - the player created inside ONVIFCameraAdapter.open() and disposed in
//     close() — the consumer MUST call close() to release the player and its
//     network sockets;
//   - buildPreview() returning a media_kit Video widget.
//
// INPUT-HARDENING TODO (see the input-hardening skill):
//   - Only accept an `rtsp://` URI validated by OnvifMediaService; never feed
//     the player a raw, unvalidated URI from an untrusted response.
//   - Time-box connection establishment; map failures to the typed surface.

/// Placeholder for the RTSP preview controller. Not yet implemented.
class RtspPreview {
  const RtspPreview();

  /// Opens an RTSP stream at [streamUri] over TCP. Planned for v1.1.
  Future<void> open(Uri streamUri) {
    throw UnimplementedError('RTSP preview is planned (ROADMAP v1.1).');
  }

  /// Releases the player and its network resources. Planned for v1.1.
  Future<void> dispose() async {
    // No-op in scaffolding.
  }
}
