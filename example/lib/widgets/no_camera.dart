import 'package:flutter/material.dart';

import '../camera_session.dart';

/// Shown by the non-Preview tabs when no camera is open: a short message plus
/// an inline **Connect** that opens the session's selected/first device — so a
/// tab is usable without bouncing the user back to the Preview tab. It never
/// auto-opens; the user taps Connect.
class NoCameraPlaceholder extends StatelessWidget {
  const NoCameraPlaceholder({
    super.key,
    required this.session,
    required this.icon,
    required this.message,
  });

  final CameraSession session;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDevice = session.selectedId != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            if (session.error != null) ...[
              Text(
                session.error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed:
                  hasDevice && !session.busy ? () => session.open() : null,
              icon: session.busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.videocam),
              label: Text(hasDevice ? 'Connect camera' : 'No camera available'),
            ),
          ],
        ),
      ),
    );
  }
}
