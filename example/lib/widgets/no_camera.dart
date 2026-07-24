import 'package:flutter/material.dart';

/// Shown by the non-Preview tabs, below the shared [CameraBar], when no camera
/// is open. Message-only: connecting is the job of the [CameraBar] above it (its
/// dropdown + Connect route through the credential-safe `connectSelectedProfile`
/// path), so this no longer carries its own Connect button — an earlier inline
/// `session.open()` here reconnected ONVIF without its stored secret.
class NoCameraPlaceholder extends StatelessWidget {
  const NoCameraPlaceholder({
    super.key,
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

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
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Pick a camera above to connect. Set one up on the Cameras tab '
              'first if the list is empty.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
