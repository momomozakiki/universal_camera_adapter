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
///
/// **Only the visible tab may build a live preview.** All tabs stay mounted at
/// once inside `main.dart`'s `IndexedStack`, so several `CameraStage`s exist
/// simultaneously. On Android the built-in preview is a *platform view* (not a
/// cheap `Texture` as on Windows), and mounting several over one controller
/// trips a `_dependents.isEmpty` framework assertion when a rebuild (e.g. a
/// rename → `notifyListeners()`) tears them down together. Pass [active] `false`
/// for an off-screen tab so it renders a placeholder and at most one platform
/// view is ever live.
class CameraStage extends StatelessWidget {
  const CameraStage({
    super.key,
    required this.session,
    this.overlay,
    this.active = true,
  });

  final CameraSession session;

  /// Optional content stacked on top of the preview (e.g. a scanner hint).
  final Widget? overlay;

  /// Whether this stage's tab is the currently-visible one. When `false`, the
  /// live preview is not built (see the class doc) — a placeholder fills the
  /// same 16:9 box so layout is unchanged.
  final bool active;

  @override
  Widget build(BuildContext context) {
    // Off-screen: never call buildPreview(), so no camerax platform view mounts.
    final preview =
        active ? session.buildPreview() : const ColoredBox(color: Colors.black);
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: overlay == null
            ? preview
            : Stack(
                fit: StackFit.expand,
                children: [
                  preview,
                  overlay!,
                ],
              ),
      ),
    );
  }
}
