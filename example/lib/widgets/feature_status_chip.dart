import 'package:flutter/material.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

import '../feature_messages.dart';

/// Renders one feature's tri-state support: Available / Under development /
/// Not supported.
///
/// Shown for **every** status, not only the negative ones — a feature that
/// works says so. Colours reuse the app's existing palette
/// (`colorSchemeSeed: Colors.indigo`, Material 3) rather than introducing new
/// tokens: the container/on-container pairs carry M3's contrast guarantee, the
/// same way [CameraErrorBanner] pairs `errorContainer`/`onErrorContainer`.
class FeatureStatusChip extends StatelessWidget {
  const FeatureStatusChip({
    super.key,
    required this.feature,
    required this.status,
    this.detailOverride,
  });

  final CameraFeature feature;
  final CameraFeatureStatus status;

  /// Replaces the generated explanation when the caller knows something more
  /// specific (e.g. a zoom range read from `CameraCapabilities`).
  final String? detailOverride;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final message = describeFeatureStatus(feature, status);

    final (Color background, Color foreground) = switch (status) {
      CameraFeatureStatus.supported => (
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
        ),
      CameraFeatureStatus.unvalidated => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
        ),
      // Muted rather than coloured: "not supported" is a fact about the
      // hardware, not a problem to draw the eye to. Matches the existing
      // outline-toned Icons.block treatment in the PTZ tab.
      CameraFeatureStatus.unsupported => (
          Colors.transparent,
          scheme.outline,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(message.icon, size: 16, color: foreground),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  detailOverride ?? message.detail,
                  style: theme.textTheme.bodySmall?.copyWith(color: foreground),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
