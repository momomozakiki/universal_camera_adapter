import 'package:flutter/material.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

import '../camera_session.dart';
import '../feature_messages.dart';
import '../widgets/camera_bar.dart';
import '../widgets/camera_empty_state.dart';
import '../widgets/feature_status_chip.dart';

/// The full feature checklist for the connected camera — every
/// [CameraFeature] with its tri-state status.
///
/// Two jobs. For a user it answers "what can this camera actually do?" in one
/// place instead of discovering it by finding a greyed-out control. For someone
/// integrating a new backend it is the verification surface: connect real
/// hardware, work down the list, and promote a declaration from
/// `unvalidated` → `supported` only once it is confirmed here.
///
/// Names no backend — it asks the matrix, never "which camera is this?"
/// (`camera-adapter-authoring` §6).
class FeaturesTab extends StatelessWidget {
  const FeaturesTab({super.key, required this.session});

  final CameraSession session;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        final theme = Theme.of(context);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            CameraBar(session: session),
            const SizedBox(height: 12),
            if (!session.isOpen)
              const CameraEmptyState(
                icon: Icons.fact_check_outlined,
                headline: 'Connect a camera to see what it supports.',
                hint: kConnectACameraHint,
              )
            else ...[
              Text(
                'Feature support',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Reported by the connected camera. "Under development" means '
                'the app has wired the feature but has not yet confirmed it on '
                'this hardware — it is not a fault of the camera.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              for (final feature in CameraFeature.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _titleCase(feature),
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      FeatureStatusChip(
                        feature: feature,
                        status: session.statusOf(feature),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  /// "still-frame capture" → "Still-frame capture".
  static String _titleCase(CameraFeature feature) {
    final label = featureLabel(feature);
    if (label.isEmpty) return label;
    return label[0].toUpperCase() + label.substring(1);
  }
}
