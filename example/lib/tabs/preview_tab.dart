import 'package:flutter/material.dart';

import '../camera_session.dart';

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
              Row(
                children: [
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: session.selectedId,
                      hint: const Text('Select a camera'),
                      items: [
                        for (final device in session.devices)
                          DropdownMenuItem(
                            value: device.id,
                            child: Text(
                              device.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: session.busy
                          ? null
                          : (id) {
                              if (id == null) return;
                              // Already streaming → switch to the new device
                              // immediately; otherwise just change the target.
                              if (session.isOpen) {
                                session.open(id);
                              } else {
                                session.select(id);
                              }
                            },
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh camera list',
                    icon: const Icon(Icons.refresh),
                    onPressed: session.busy ? null : session.refreshDevices,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (session.error != null) ...[
                _ErrorBanner(session.error!),
                const SizedBox(height: 12),
              ],
              if (session.busy && !session.isOpen)
                const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (session.isOpen) ...[
                // The preview MUST be given a bounded height. This Column sits
                // in a SingleChildScrollView, so it offers its children an
                // unbounded height — and `buildPreview()` carries no sizing
                // guarantee: `CameraPreview` (built-in) self-sizes from its
                // aspect ratio, but media_kit's `Video` (ONVIF/RTSP) expands to
                // fill and asserts "BoxConstraints forces an infinite height".
                // That assertion leaves the box with no size, after which every
                // hit test in the **whole app** throws "Cannot hit test a render
                // box that has never been laid out" and nothing is clickable
                // anywhere — not just on this tab. AspectRatio bounds it for
                // every backend without naming any of them.
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: session.buildPreview(),
                  ),
                ),
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
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: session.busy ? null : session.close,
                      icon: const Icon(Icons.stop),
                      label: const Text('Disconnect'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: () => _capture(context),
                      icon: const Icon(Icons.camera),
                      label: const Text('Capture'),
                    ),
                  ],
                ),
              ] else
                FilledButton.icon(
                  onPressed: session.selectedId == null
                      ? null
                      : () => session.open(),
                  icon: const Icon(Icons.videocam),
                  label: const Text('Connect'),
                ),
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
      messenger.showSnackBar(SnackBar(content: Text('Capture failed: $e')));
    }
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
