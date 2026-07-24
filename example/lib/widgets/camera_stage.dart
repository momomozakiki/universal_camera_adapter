import 'package:flutter/material.dart';

import '../camera_session.dart';

/// The one live-preview container every camera tab uses, so the preview is the
/// **same size** everywhere. Guard on [CameraSession.isOpen] before building it.
///
/// The preview MUST be given a bounded height. Tabs place this in scrolling
/// columns that offer an unbounded height, and `buildPreview()` carries no
/// sizing guarantee: `CameraPreview` (built-in) self-sizes from its aspect
/// ratio, but media_kit's `Video` (ONVIF/RTSP) expands to fill and asserts
/// "BoxConstraints forces an infinite height". That assertion leaves the box
/// with no size, after which every hit test in the **whole app** throws "Cannot
/// hit test a render box that has never been laid out" and nothing is clickable
/// anywhere. The fixed [AspectRatio] bounds it for every backend without naming
/// any of them; backends letterbox (contain-fit) inside it rather than stretch.
/// Centralising it here means no tab can regress the guard.
class CameraStage extends StatelessWidget {
  const CameraStage({super.key, required this.session, this.overlay});

  final CameraSession session;

  /// Optional content stacked on top of the preview (e.g. a scanner hint).
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: overlay == null
            ? session.buildPreview()
            : Stack(
                fit: StackFit.expand,
                children: [
                  session.buildPreview(),
                  overlay!,
                ],
              ),
      ),
    );
  }
}
