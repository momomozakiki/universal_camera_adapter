import 'package:flutter/material.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

import '../camera_session.dart';
import '../widgets/camera_bar.dart';
import '../widgets/camera_empty_state.dart';
import '../widgets/camera_stage.dart';
import '../widgets/feature_status_chip.dart';

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
        // Both derived once on the session, so this tab and PreviewTab cannot
        // disagree about the range or the gate.
        final zoomRange = session.zoomRange;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            CameraBar(session: session),
            const SizedBox(height: 12),
            if (!session.isOpen)
              const CameraEmptyState(
                icon: Icons.control_camera_outlined,
                headline: 'Connect a camera to test PTZ controls.',
                hint: kConnectACameraHint,
              )
            else ...[
              CameraStage(session: session),
              const SizedBox(height: 16),
            ],
            if (session.isOpen) ...[
              _CapabilitySlider(
                label: 'Zoom',
                feature: CameraFeature.zoom,
                // Status now comes from the matrix like every other feature.
                // This used to key off `capabilities == null`, which was the one
                // place the tab bypassed the matrix entirely.
                status: session.statusOf(CameraFeature.zoom),
                enabled: session.zoomEnabled,
                value: session.zoom.clamp(zoomRange.min, zoomRange.max),
                min: zoomRange.min,
                max: zoomRange.max,
                // The numeric range is the one thing the matrix cannot carry,
                // so it stays the chip's detail in both directions: the span
                // when there is one, the reason when there is not.
                detailOverride: session.capabilities == null
                    ? 'This camera does not report a zoom range.'
                    : session.zoomEnabled
                        ? 'Range ${zoomRange.min.toStringAsFixed(1)}×'
                            '–${zoomRange.max.toStringAsFixed(1)}×.'
                        : 'This camera reports no zoom range.',
                onChanged: session.setZoom,
              ),
              _CapabilitySlider(
                label: 'Pan',
                feature: CameraFeature.pan,
                status: session.statusOf(CameraFeature.pan),
                enabled: session.supports(CameraFeature.pan),
                value: _pan,
                min: 0,
                max: 1,
                onChanged: (v) {
                  setState(() => _pan = v);
                  session.setPan(v);
                },
              ),
              _CapabilitySlider(
                label: 'Tilt',
                feature: CameraFeature.tilt,
                status: session.statusOf(CameraFeature.tilt),
                enabled: session.supports(CameraFeature.tilt),
                value: _tilt,
                min: 0,
                max: 1,
                onChanged: (v) {
                  setState(() => _tilt = v);
                  session.setTilt(v);
                },
              ),
            ],
          ],
        );
      },
    );
  }
}

/// A labelled slider paired with the feature's tri-state status chip.
///
/// The chip renders in **every** state, not just the negative ones: a working
/// control now confirms it works, and — the reason this changed — a feature the
/// app has wired but not yet validated reads "Under development" instead of
/// blaming the camera for not supporting it.
///
/// [enabled] stays separate from [status] on purpose. Messaging is tri-state;
/// interaction is binary, because an `unvalidated` control may still throw.
class _CapabilitySlider extends StatelessWidget {
  const _CapabilitySlider({
    required this.label,
    required this.feature,
    required this.status,
    required this.enabled,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.detailOverride,
  });

  final String label;
  final CameraFeature feature;
  final CameraFeatureStatus status;
  final bool enabled;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String? detailOverride;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          FeatureStatusChip(
            feature: feature,
            status: status,
            detailOverride: detailOverride,
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}
