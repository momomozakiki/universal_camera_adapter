import 'package:flutter/material.dart';

import '../camera_session.dart';

/// The shared camera selector every live-camera tab carries, so switching
/// between saved cameras looks and behaves the same everywhere: a dropdown of
/// **all** saved cameras plus a connect/disconnect toggle, with a single error
/// surface below.
///
/// Backend-agnostic: it drives [CameraSession.connectSelectedProfile], which
/// routes through `switchToProfile` so a credentialed backend (ONVIF) re-merges
/// its secret on reconnect. Wrap in the tab's existing `AnimatedBuilder` so it
/// rebuilds on session changes.
class CameraBar extends StatelessWidget {
  const CameraBar({super.key, required this.session});

  final CameraSession session;

  @override
  Widget build(BuildContext context) {
    final profiles = session.profiles;
    final ids = profiles.map((p) => p.id).toSet();
    // Guard the value: a DropdownButton asserts if `value` matches no item.
    final value = ids.contains(session.selectedProfileId)
        ? session.selectedProfileId
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButton<String>(
                isExpanded: true,
                value: value,
                hint: Text(
                  profiles.isEmpty ? 'No saved cameras' : 'Select a camera',
                ),
                items: [
                  for (final profile in profiles)
                    DropdownMenuItem(
                      value: profile.id,
                      child: Text(
                        profile.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: session.busy || profiles.isEmpty
                    ? null
                    : (id) {
                        if (id == null) return;
                        session.selectProfile(id);
                        session.connectSelectedProfile();
                      },
              ),
            ),
            const SizedBox(width: 12),
            if (session.isOpen)
              OutlinedButton.icon(
                onPressed: session.busy ? null : session.close,
                icon: const Icon(Icons.stop),
                label: const Text('Disconnect'),
              )
            else
              FilledButton.icon(
                onPressed: session.busy || session.selectedProfileId == null
                    ? null
                    : session.connectSelectedProfile,
                icon: const Icon(Icons.videocam),
                label: const Text('Connect'),
              ),
          ],
        ),
        if (session.error != null) ...[
          const SizedBox(height: 12),
          CameraErrorBanner(session.error!),
        ],
      ],
    );
  }
}

/// The app's one error surface, shared by every tab through [CameraBar].
class CameraErrorBanner extends StatelessWidget {
  const CameraErrorBanner(this.message, {super.key});

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
