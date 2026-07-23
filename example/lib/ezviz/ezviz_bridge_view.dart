import 'package:flutter/material.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

import '../adapter_types.dart';
import '../camera_session.dart';
import '../tabs/preview_tab.dart';
import 'ezviz_wizard_flow.dart';

/// **Temporary.** Keeps the Bridge tab's EZVIZ path working exactly as it did
/// before the wizard registry landed, by wiring [EzvizWizardFlow] straight into
/// the shared [CameraSession].
///
/// This is the Phase D compatibility shim: the flow was extracted so
/// `EzvizSetupWizard` could reuse it and produce a `CameraProfile`, but nothing
/// consumes profiles until the Cameras tab exists in Phase E. Rather than
/// duplicate 400 lines of onboarding or leave the only working EZVIZ path
/// broken in the interim, the session handoff was reduced to this wrapper.
///
/// **Phase E deletes this file** along with `camera_bridge_tab.dart` — the flow
/// and `EzvizSetupWizard` survive it.
class EzvizBridgeView extends StatefulWidget {
  const EzvizBridgeView({super.key, required this.session});

  final CameraSession session;

  @override
  State<EzvizBridgeView> createState() => _EzvizBridgeViewState();
}

class _EzvizBridgeViewState extends State<EzvizBridgeView> {
  /// The flow stays mounted while the connected view is showing (via [Offstage])
  /// so its state — sign-in step, loaded device list, typed verification code —
  /// survives the toggle, exactly as it did when both were branches of one
  /// widget. This key is how "Switch EZVIZ device" refreshes the list without
  /// tearing the flow down and re-running SDK init.
  final _flowKey = GlobalKey<EzvizWizardFlowState>();

  bool _busy = false;
  bool _showDeviceList = false;

  bool get _connected =>
      widget.session.adapterType == kEzvizAdapterType &&
      widget.session.isOpen &&
      !_showDeviceList;

  Future<void> _connect(CameraDevice device, String? verificationCode) async {
    setState(() => _showDeviceList = false);
    await widget.session.switchTo(kEzvizAdapterType);
    await widget.session.openDevice(
      verificationCode == null
          ? device
          : device.copyWith(
              metadata: <String, dynamic>{
                ...device.metadata,
                'verificationCode': verificationCode,
              },
            ),
    );
    // The session swallows adapter errors into its own `error` field; re-throw
    // so the flow shows the message inline rather than silently landing back
    // on the device list as if it had worked.
    final error = widget.session.error;
    if (error != null) throw StateError(error);
  }

  Future<void> _switchDevice() async {
    setState(() {
      _busy = true;
      _showDeviceList = true;
    });
    try {
      await _flowKey.currentState?.reloadDevices();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _useBuiltin() async {
    setState(() => _busy = true);
    try {
      await widget.session.switchTo(kBuiltinAdapterType);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.session,
      builder: (context, _) {
        final connected = _connected;
        return Stack(
          children: [
            Offstage(
              offstage: connected,
              child: EzvizWizardFlow(
                key: _flowKey,
                onDeviceChosen: _connect,
                onBeforeSignOut: () async {
                  if (widget.session.adapterType == kEzvizAdapterType) {
                    await widget.session.close();
                  }
                },
              ),
            ),
            if (connected)
              _ConnectedEzvizView(
                session: widget.session,
                onSwitchDevice: _busy ? null : _switchDevice,
                onUseBuiltin: _busy ? null : _useBuiltin,
              ),
          ],
        );
      },
    );
  }
}

/// The connected state: a small backend-switch affordance above the same
/// shared [PreviewTab] every other backend uses.
class _ConnectedEzvizView extends StatelessWidget {
  const _ConnectedEzvizView({
    required this.session,
    required this.onSwitchDevice,
    required this.onUseBuiltin,
  });

  final CameraSession session;
  final VoidCallback? onSwitchDevice;
  final VoidCallback? onUseBuiltin;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      // The flow sits behind this in a Stack; without an opaque background it
      // would show through.
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onSwitchDevice,
                    child: const Text('Switch EZVIZ device'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onUseBuiltin,
                    child: const Text('Use phone camera instead'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: PreviewTab(session: session)),
        ],
      ),
    );
  }
}
