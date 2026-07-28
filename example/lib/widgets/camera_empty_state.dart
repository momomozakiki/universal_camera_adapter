import 'package:flutter/material.dart';

/// The standing hint for a tab that is soft-gated on having a camera open.
///
/// Connecting is the [CameraBar]'s job — its dropdown and Connect route through
/// the credential-safe `connectSelectedProfile` path — so these panels tell the
/// user where to go rather than offering their own Connect button. An earlier
/// inline `session.open()` here reconnected ONVIF without its stored secret.
const String kConnectACameraHint =
    'Pick a camera above to connect. Set one up on the Cameras tab first if '
    'the list is empty.';

/// The app's one "nothing here, and here's what to do about it" panel.
///
/// Shared so that no camera connected, an absent camera, a blocked permission
/// and a failed probe all look like the same considered state rather than
/// several ad-hoc layouts — and so none of them is ever a raw exception dump.
///
/// Replaces the former `NoCameraPlaceholder`, which was the same
/// icon + headline + hint panel with its hint hard-coded; that hard-coded
/// string is now [kConnectACameraHint], passed explicitly by the tabs that
/// want it.
class CameraEmptyState extends StatelessWidget {
  const CameraEmptyState({
    super.key,
    required this.icon,
    required this.headline,
    this.hint,
    this.actions = const <Widget>[],
  });

  final IconData icon;

  /// The one-line summary, e.g. "No built-in camera found".
  final String headline;

  /// What the user can do about it. Cause-specific — the whole reason this
  /// takes a hint rather than deriving one.
  final String? hint;

  /// Optional buttons rendered below the hint.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              headline,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (hint != null) ...[
              const SizedBox(height: 8),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(spacing: 12, alignment: WrapAlignment.center, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}
