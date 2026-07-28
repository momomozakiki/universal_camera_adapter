import 'package:flutter/material.dart';

import '../camera_session.dart';
import '../error_messages.dart';
import '../widgets/camera_bar.dart';
import '../widgets/camera_stage.dart';

/// The baseline tool: pick a camera, Connect, see the live preview, adjust zoom
/// (when supported), Capture a frame, Disconnect. Exercises the core
/// [CameraSession] / `CameraAdapter` contract end to end.
class PreviewTab extends StatelessWidget {
  const PreviewTab({super.key, required this.session});

  final CameraSession session;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        final theme = Theme.of(context);
        // Enablement comes from the feature matrix (uniform across every
        // backend); the numeric *range* comes from capabilities, the only place
        // it exists. Both are derived once on the session so this tab and PtzTab
        // cannot disagree. Capabilities may legitimately be **absent** — a
        // backend can implement the matrix without the legacy struct (ONVIF
        // today) — so the preview never depends on it, and only the zoom slider
        // degrades. Never assumed: a phone may report min == max.
        final zoomEnabled = session.zoomEnabled;
        final zoomRange = session.zoomRange;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CameraBar(session: session),
              const SizedBox(height: 12),
              if (session.busy && !session.isOpen)
                const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (session.isOpen) ...[
                CameraStage(session: session),
                const SizedBox(height: 16),
                Text('Zoom', style: theme.textTheme.titleSmall),
                Slider(
                  value: session.zoom.clamp(zoomRange.min, zoomRange.max),
                  min: zoomRange.min,
                  max: zoomRange.max,
                  onChanged: zoomEnabled ? session.setZoom : null,
                ),
                if (!zoomEnabled)
                  Text(
                    session.capabilities == null
                        ? 'This camera does not report a zoom range.'
                        : 'This camera reports no zoom range.',
                    style: theme.textTheme.bodySmall,
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _capture(context),
                  icon: const Icon(Icons.camera),
                  label: const Text('Capture'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _capture(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await session.captureFrame();
      messenger.showSnackBar(
        SnackBar(content: Text('Captured ${bytes.length} bytes.')),
      );
    } on Object catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(describeCameraError(e, action: 'capturing a frame')),
        ),
      );
    }
  }
}
