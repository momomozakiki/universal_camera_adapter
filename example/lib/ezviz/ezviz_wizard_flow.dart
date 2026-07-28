import 'package:ezviz_flutter/ezviz_flutter.dart';
import 'package:flutter/material.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

import '../error_messages.dart';
import 'ezviz_camera_adapter.dart';

/// Called when the user picks a device. Returning a [Future] lets the flow show
/// a spinner while the caller does whatever it does with the choice — open a
/// session, mint a profile, write a secret — and surface a thrown error inline.
typedef EzvizDeviceChosen = Future<void> Function(
  CameraDevice device,
  String? verificationCode,
);

/// The EZVIZ onboarding steps, with no opinion about what happens afterwards.
///
/// Owns exactly three things: sign in with the user's own EZVIZ account, list
/// that account's devices, and collect the verification code an encrypted
/// device needs. It then hands the chosen device to [onDeviceChosen] and stops
/// — it does not open cameras, drive a [CameraSession], or persist anything.
///
/// That split is the point: the steps are the same regardless of what the
/// caller does with the result, so they live here once and `EzvizSetupWizard`
/// wraps them. Previously this logic was fused to `CameraSession` inside the
/// old `ezviz_setup_wizard.dart`, which is why it could not be reused.
///
/// **This widget deliberately persists nothing.** The old version cached the
/// verification code in a bespoke `ezviz_tab.verification_code`
/// `SharedPreferences` key — the per-camera-type storage hack that Epic 2.5
/// exists to remove (`state-management` Rule 6). Secrets now go to a
/// `CameraSecretStore`, keyed by profile id, which only the caller can do
/// because only the caller mints the profile.
class EzvizWizardFlow extends StatefulWidget {
  const EzvizWizardFlow({
    super.key,
    required this.onDeviceChosen,
    this.onBeforeSignOut,
    this.onCancel,
  });

  /// Invoked with the picked device and the verification code as typed
  /// (`null` when blank). Throw to have the message shown inline.
  final EzvizDeviceChosen onDeviceChosen;

  /// Optional cleanup run before EZVIZ sign-out — e.g. closing a session that
  /// is currently streaming from the account being signed out of.
  final Future<void> Function()? onBeforeSignOut;

  /// When non-null, a "Cancel" affordance is offered on the sign-in step.
  final VoidCallback? onCancel;

  @override
  State<EzvizWizardFlow> createState() => _EzvizWizardFlowState();
}

enum _WizardStep { signIn, devices, connecting }

class _EzvizWizardFlowState extends State<EzvizWizardFlow>
    with WidgetsBindingObserver {
  final _codeController = TextEditingController();

  _WizardStep _step = _WizardStep.signIn;
  bool _busy = false;
  String? _error;

  /// Set right before [EzvizAuthManager.openLoginPage] launches the hosted
  /// login page, cleared once we've checked for a token on the next resume.
  /// Guards against re-checking on unrelated app resumes (e.g. switching
  /// apps briefly while already on the device list).
  bool _awaitingSignIn = false;

  List<EzvizDeviceInfo> _devices = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _codeController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingSignIn) {
      _awaitingSignIn = false;
      _checkSignInAfterResume();
    }
  }

  /// `initSDK` must run *before* `getAccessToken` (see
  /// `ezviz_camera_adapter.dart`'s doc comment and `history/2026-W30.md` for
  /// the native-side confirmation this was carried over from `ezviz_tab.dart`).
  Future<void> _bootstrap() async {
    try {
      await EzvizManager.shared()
          .initSDK(EzvizInitOptions(appKey: kEzvizAppKey, accessToken: ''))
          .timeout(kDefaultCameraTimeout);
      final cached = await EzvizAuthManager.getAccessToken().timeout(
        kDefaultCameraTimeout,
      );
      if (!mounted) return;
      if (cached != null) {
        setState(() => _step = _WizardStep.devices);
        await _loadDevices();
      } else {
        setState(() => _step = _WizardStep.signIn);
      }
    } on Object catch (e) {
      // Nothing loaded yet at this point — fall back to the sign-in step so
      // the user has a button to retry from, rather than a dead blank screen.
      if (mounted) {
        setState(() {
          _step = _WizardStep.signIn;
          _error = describeCameraError(
            e,
            action: 'checking for a signed-in account',
          );
        });
      }
    }
  }

  Future<void> _signIn() async {
    setState(() => _error = null);
    _awaitingSignIn = true;
    // Deliberately no `areaId` — see ezviz_camera_adapter.dart / the retired
    // ezviz_tab.dart for why: any areaId string gets discarded natively in
    // favor of a hardcoded `openLoginPage(0)` call.
    final launched = await EzvizAuthManager.openLoginPage();
    if (!launched && mounted) {
      _awaitingSignIn = false;
      setState(() => _error = 'Could not open the EZVIZ sign-in page.');
    }
  }

  Future<void> _checkSignInAfterResume() async {
    try {
      // The SDK may need a moment to finish writing its native cache after
      // the login activity returns control to this app.
      await Future.delayed(const Duration(milliseconds: 500));
      final token = await EzvizAuthManager.getAccessToken().timeout(
        kDefaultCameraTimeout,
      );
      if (!mounted) return;
      if (token == null) {
        setState(() => _error = 'Sign-in was cancelled or failed. Try again.');
        return;
      }
      await EzvizManager.shared()
          .initSDK(
            EzvizInitOptions(appKey: kEzvizAppKey, accessToken: token.accessToken),
          )
          .timeout(kDefaultCameraTimeout);
      if (!mounted) return;
      setState(() => _step = _WizardStep.devices);
      await _loadDevices();
    } on Object catch (e) {
      // Already past sign-in (a token was returned) — stay on whichever step
      // we're on and just surface the error, rather than bouncing the user
      // back to sign-in after a real sign-in success just because this next
      // call timed out.
      if (mounted) {
        setState(() => _error = describeCameraError(e, action: 'signing in'));
      }
    }
  }

  Future<void> _signOut() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onBeforeSignOut?.call();
      await EzvizAuthManager.logout();
      if (!mounted) return;
      setState(() {
        _devices = [];
        _step = _WizardStep.signIn;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadDevices() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final devices = await EzvizDeviceManager.getDeviceList().timeout(
        kDefaultCameraTimeout,
      );
      if (mounted) setState(() => _devices = devices);
    } on Object catch (e) {
      if (mounted) {
        setState(
          () => _error = describeCameraError(e, action: 'loading your devices'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose(EzvizDeviceInfo info) async {
    final code = _codeController.text.trim();
    setState(() {
      _step = _WizardStep.connecting;
      _error = null;
    });
    final device = CameraDevice(
      id: info.deviceSerial,
      name: info.deviceName,
      lensFacing: CameraLensFacing.external,
      metadata: <String, dynamic>{
        'brand': 'ezviz',
        // Advisory only — the adapter reports hasPan/hasTilt false until
        // setPan/setTilt are actually wired (camera-adapter-authoring §2).
        'isSupportPTZ': info.isSupportPTZ,
        'cameraNum': info.cameraNum,
      },
    );
    try {
      await widget.onDeviceChosen(device, code.isEmpty ? null : code);
      if (!mounted) return;
      // Always land back on `devices`, even on success. A host may render its
      // own view over this flow while connected; the moment that view goes
      // away — by any path, including one this widget never hears about —
      // this step is what shows. Leaving it at `connecting` rendered a
      // permanent spinner, which was the general form of a whole bug class.
      setState(() => _step = _WizardStep.devices);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _WizardStep.devices;
        _error = describeCameraError(e, action: 'connecting to that camera');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case _WizardStep.signIn:
        return _buildSignInStep();
      case _WizardStep.devices:
        return _buildDevicesStep();
      case _WizardStep.connecting:
        return const Center(child: CircularProgressIndicator());
    }
  }

  Widget _buildSignInStep() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_outlined, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Sign in with your own EZVIZ account to see your cameras. '
              'This opens EZVIZ\'s own sign-in page — this app never sees '
              'your password.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ),
            FilledButton(
              onPressed: _signIn,
              child: const Text('Sign in with EZVIZ'),
            ),
            if (widget.onCancel != null) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: widget.onCancel,
                child: const Text('Cancel'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDevicesStep() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _codeController,
            decoration: const InputDecoration(
              labelText: 'Verification code (only if encrypted)',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: _devices.isEmpty
              ? Center(
                  child: Text(
                    _busy ? 'Loading devices…' : 'No cameras found on this account.',
                  ),
                )
              : ListView.builder(
                  itemCount: _devices.length,
                  itemBuilder: (context, i) {
                    final device = _devices[i];
                    return ListTile(
                      leading: const Icon(Icons.videocam_outlined),
                      title: Text(device.deviceName),
                      subtitle: Text(device.deviceSerial),
                      onTap: _busy ? null : () => _choose(device),
                    );
                  },
                ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _loadDevices,
                  child: const Text('Refresh devices'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _signOut,
                  child: const Text('Sign out'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
