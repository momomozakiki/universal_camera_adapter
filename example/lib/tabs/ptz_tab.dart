import 'package:flutter/material.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

import '../camera_session.dart';
import '../widgets/no_camera.dart';

/// Zoom / Pan / Tilt test surface, gated entirely by the open device's
/// [CameraFeatureMatrix]. Each slider is enabled only when the feature reports
/// `supported` and calls the real `setZoom`/`setPan`/`setTilt`; otherwise it is
/// disabled with an explanatory note. On a typical Android phone Pan and Tilt
/// (and sometimes Zoom) read "not supported" — that is capability negotiation
/// working, not a bug.
///
/// **This file names no backend.** It asks the matrix "may I?" and never "which
/// camera is this?" — `camera-adapter-authoring` §6.
///
/// The zoom *range* still comes from [CameraCapabilities]: the matrix carries a
/// tri-state status and a free-form metadata map, not a numeric range, and the
/// base derivation populates no metadata. So the two types do different jobs
/// here — matrix for "may I?", capabilities for "between what?" — and that is
/// deliberate, not a half-finished migration to "complete" by inventing a range
/// on the matrix.
///
/// `session.capabilities` is **nullable**, and not only when nothing is open: a
/// backend may implement the matrix while its capabilities struct is still
/// unimplemented (ONVIF today). The matrix is therefore the mandatory surface
/// and capabilities the optional one — never dereference it with `!`.
class PtzTab extends StatefulWidget {
  const PtzTab({super.key, required this.session});

  final CameraSession session;

  @override
  State<PtzTab> createState() => _PtzTabState();
}

class _PtzTabState extends State<PtzTab> {
  double _pan = 0.5;
  double _tilt = 0.5;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.session,
      builder: (context, _) {
        final session = widget.session;
        if (!session.isOpen) {
          return NoCameraPlaceholder(
            session: session,
            icon: Icons.control_camera_outlined,
            message: 'Connect a camera to test PTZ controls.',
          );
        }
        // Both derived once on the session, so this tab and PreviewTab cannot
        // disagree about the range or the gate.
        final zoomRange = session.zoomRange;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _CapabilitySlider(
              label: 'Zoom',
              enabled: session.zoomEnabled,
              value: session.zoom.clamp(zoomRange.min, zoomRange.max),
              min: zoomRange.min,
              max: zoomRange.max,
              unsupportedNote: session.capabilities == null
                  ? 'This camera does not report a zoom range.'
                  : 'This camera reports no zoom range.',
              onChanged: session.setZoom,
            ),
            _CapabilitySlider(
              label: 'Pan',
              enabled: session.supports(CameraFeature.pan),
              value: _pan,
              min: 0,
              max: 1,
              unsupportedNote: 'Pan is not supported by this camera.',
              onChanged: (v) {
                setState(() => _pan = v);
                session.setPan(v);
              },
            ),
            _CapabilitySlider(
              label: 'Tilt',
              enabled: session.supports(CameraFeature.tilt),
              value: _tilt,
              min: 0,
              max: 1,
              unsupportedNote: 'Tilt is not supported by this camera.',
              onChanged: (v) {
                setState(() => _tilt = v);
                session.setTilt(v);
              },
            ),
          ],
        );
      },
    );
  }
}

/// A labelled slider that grays out (with a note) when the capability is absent,
/// so the capability-driven UI is visibly wired even before a PTZ backend exists.
class _CapabilitySlider extends StatelessWidget {
  const _CapabilitySlider({
    required this.label,
    required this.enabled,
    required this.value,
    required this.min,
    required this.max,
    required this.unsupportedNote,
    required this.onChanged,
  });

  final String label;
  final bool enabled;
  final double value;
  final double min;
  final double max;
  final String unsupportedNote;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: theme.textTheme.titleMedium),
              const SizedBox(width: 8),
              if (!enabled)
                Icon(
                  Icons.block,
                  size: 16,
                  color: theme.colorScheme.outline,
                ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: enabled ? onChanged : null,
          ),
          if (!enabled)
            Text(unsupportedNote, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
