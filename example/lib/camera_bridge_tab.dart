import 'package:flutter/material.dart';

import 'camera_session.dart';
import 'ezviz/ezviz_bridge_view.dart';
import 'onvif/onvif_connect_view.dart';

enum _BridgeMode { cloud, onvif }

/// Entry point for network/IP-camera backends: a mode selector — Cloud
/// (EZVIZ) vs local-network (ONVIF) — in front of the existing
/// [EzvizBridgeView] or the new [OnvifConnectView].
///
/// This widget swaps its child by ordinary conditional rendering (not its
/// own nested `IndexedStack`), deliberately: when [_mode] changes, the
/// previously-shown child is removed from the tree in the normal way, so
/// Flutter disposes it (closing any open camera) before the next view is
/// built. Only the outer tab list in `main.dart` uses `IndexedStack`, to
/// keep the other tabs alive across tab switches — this internal mode
/// switch is not wrapped in that, so switching *mode* here always tears the
/// previous view down cleanly, while switching *tabs* away from and back to
/// Bridge preserves whichever mode view is currently showing.
class CameraBridgeTab extends StatefulWidget {
  const CameraBridgeTab({super.key, required this.session});

  final CameraSession session;

  @override
  State<CameraBridgeTab> createState() => _CameraBridgeTabState();
}

class _CameraBridgeTabState extends State<CameraBridgeTab> {
  _BridgeMode? _mode;

  @override
  Widget build(BuildContext context) {
    switch (_mode) {
      case null:
        return _buildSelector();
      case _BridgeMode.cloud:
        return Column(
          children: [
            _buildChangeModeBar(),
            Expanded(child: EzvizBridgeView(session: widget.session)),
          ],
        );
      case _BridgeMode.onvif:
        return Column(
          children: [
            _buildChangeModeBar(),
            const Expanded(child: OnvifConnectView()),
          ],
        );
    }
  }

  Widget _buildChangeModeBar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () => setState(() => _mode = null),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Change mode'),
          ),
        ],
      ),
    );
  }

  Widget _buildSelector() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hub_outlined, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Connect to a camera over the network.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => setState(() => _mode = _BridgeMode.cloud),
              child: const Text('Cloud (EZVIZ)'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => setState(() => _mode = _BridgeMode.onvif),
              child: const Text('Local network (ONVIF)'),
            ),
          ],
        ),
      ),
    );
  }
}
