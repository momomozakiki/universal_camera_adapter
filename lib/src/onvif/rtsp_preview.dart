// RTSP preview: the live-preview widget for an ONVIF camera, backed by
// `package:media_kit` + `package:media_kit_video`.
//
// - RTSP over TCP transport (avoids UDP packet loss) via the native
//   `rtsp-transport` mpv property.
// - The player is created in ONVIFCameraAdapter.open() and disposed in
//   close() — the consumer MUST call close() to release the player and its
//   network sockets.
// - Only ever opened with an `rtsp://` URI already validated by
//   OnvifMediaService — never fed a raw, unvalidated URI.
//
// [OnvifPreviewController] is a thin seam so ONVIFCameraAdapter can be unit
// tested with a fake in place of the real media_kit-backed player (no native
// player/socket in test runs).

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../camera_adapter.dart' show kDefaultCameraTimeout;

/// Abstraction over an RTSP preview player.
abstract class OnvifPreviewController {
  /// Opens [streamUri] (must already be `rtsp://`) for playback.
  ///
  /// [username]/[password], when supplied, authenticate the RTSP session
  /// itself — a separate concern from the ONVIF SOAP auth already performed
  /// to resolve [streamUri]; many cameras (e.g. EZVIZ) require both.
  ///
  /// Throws [TimeoutException] if the RTSP handshake doesn't complete within
  /// [timeout] — a camera that never responds (or a spoofed target) must not
  /// hang [ONVIFCameraAdapter.open] forever.
  Future<void> open(
    Uri streamUri, {
    String? username,
    String? password,
    Duration timeout = kDefaultCameraTimeout,
  });

  /// Builds the widget that renders the live feed. Only valid after [open]
  /// has completed.
  Widget buildWidget();

  /// Releases the player and its network resources. Safe to call more than
  /// once.
  Future<void> dispose();
}

/// [OnvifPreviewController] backed by a real `media_kit` [Player].
class RtspPreview implements OnvifPreviewController {
  RtspPreview() : _player = Player();

  final Player _player;
  VideoController? _controller;
  bool _disposed = false;

  @override
  Future<void> open(
    Uri streamUri, {
    String? username,
    String? password,
    Duration timeout = kDefaultCameraTimeout,
  }) async {
    if (streamUri.scheme.toLowerCase() != 'rtsp') {
      throw StateError('RtspPreview only accepts rtsp:// URIs.');
    }
    _controller = VideoController(_player);

    final platform = _player.platform;
    if (platform is NativePlayer) {
      // Prefer TCP transport — avoids UDP packet loss on flaky camera LANs.
      await platform.setProperty('rtsp-transport', 'tcp').timeout(timeout);
      // mpv buffers aggressively by default (optimized for on-demand video,
      // not a live feed), so the displayed frame falls further behind the
      // live edge the longer playback runs. `low-latency` + disabling the
      // cache is the documented fix for a live RTSP source; deliberately
      // NOT using `untimed`/`no-correct-pts` (play back "as fast as
      // possible") since both are documented to break audio sync, and this
      // stream carries an AAC audio track.
      await platform.setProperty('profile', 'low-latency').timeout(timeout);
      await platform.setProperty('cache', 'no').timeout(timeout);
    }

    // The RTSP session has its own auth, separate from the ONVIF SOAP auth
    // already used to resolve streamUri — embed as URI userinfo (the form
    // mpv/media_kit's underlying player expects for RTSP credentials).
    final authenticatedUri = (username != null && password != null)
        ? streamUri.replace(
            userInfo: '${Uri.encodeComponent(username)}:${Uri.encodeComponent(password)}',
          )
        : streamUri;
    await _player.open(Media(authenticatedUri.toString())).timeout(timeout);
  }

  @override
  Widget buildWidget() {
    final controller = _controller;
    if (controller == null) {
      throw StateError('RtspPreview.open() has not completed yet.');
    }
    return Video(controller: controller);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _controller = null;
    await _player.dispose();
  }
}
