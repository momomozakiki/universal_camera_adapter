import 'package:ezviz_flutter/ezviz_flutter.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

import '../adapter_types.dart';
import '../camera_session.dart';
import '../tabs/preview_tab.dart';
import 'ezviz_camera_adapter.dart';

/// Onboarding for EZVIZ cloud cameras: sign in with the user's own EZVIZ
/// account, pick a device, and hand off into the shared [CameraSession] via
/// [CameraSession.switchTo] + [CameraSession.openDevice].
///
/// Playback itself is not this widget's job — once connected, it renders the
/// same [PreviewTab] every other backend uses, driven by [EzvizCameraAdapter]
/// through the ordinary [CameraAdapter] contract. This widget only owns the
/// three onboarding steps: sign-in, device list + verification code, and the
/// brief "connecting" transition between them and the shared session.
class EzvizSetupWizard extends StatefulWidget {
  const EzvizSetupWizard({super.key, required this.session});

  final CameraSession session;

  @override
  State<EzvizSetupWizard> createState() => _EzvizSetupWizardState();
}

enum _WizardStep { signIn, devices, connecting }

class _EzvizSetupWizardState extends State<EzvizSetupWizard>
    with WidgetsBindingObserver {
  static const _prefsCodeKey = 'ezviz_tab.verification_code';

  final _codeController = TextEditingController();

  _WizardStep _step = _WizardStep.signIn;
  bool _busy = false;
  String? _error;
  bool _showDeviceList = false;

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
    final prefs = await SharedPreferences.getInstance();
    final savedCode = prefs.getString(_prefsCodeKey);
    if (savedCode != null) _codeController.text = savedCode;

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
          _error = 'Could not check for a signed-in account: $e';
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
      if (mounted) setState(() => _error = 'Could not finish signing in: $e');
    }
  }

  Future<void> _signOut() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.session.adapterType == kEzvizAdapterType) {
        await widget.session.close();
      }
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

  Future<void> _savePref(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
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
      if (mounted) setState(() => _error = 'Could not load devices: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect(EzvizDeviceInfo info) async {
    final code = _codeController.text.trim();
    setState(() {
      _step = _WizardStep.connecting;
      _showDeviceList = false;
      _error = null;
    });
    try {
      await widget.session.switchTo(kEzvizAdapterType);
      final device = CameraDevice(
        id: info.deviceSerial,
        name: info.deviceName,
        lensFacing: CameraLensFacing.external,
        metadata: <String, dynamic>{
          'brand': 'ezviz',
          'isSupportPTZ': info.isSupportPTZ,
          'cameraNum': info.cameraNum,
          if (code.isNotEmpty) 'verificationCode': code,
        },
      );
      await widget.session.openDevice(device);
      if (!mounted) return;
      // Always land back on _step = devices, even on success: build()'s
      // connected-view branch takes priority while isOpen stays true, but
      // the moment the session is closed by ANY path — this wizard's own
      // buttons, or PreviewTab's own "Disconnect" button reached through the
      // reused connected view, which calls session.close() directly and has
      // no way to notify this wizard — that branch stops matching and falls
      // through to this switch. Leaving _step at .connecting (as it was set
      // above) meant that fallback rendered a permanent spinner instead of
      // the device list; this is the general fix for that whole bug class,
      // not just the specific buttons already handled by _switchDevice()/
      // _useBuiltin().
      setState(() {
        _step = _WizardStep.devices;
        _error = widget.session.error;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _WizardStep.devices;
        _error = '$e';
      });
    }
  }

  Future<void> _switchDevice() async {
    setState(() {
      _busy = true;
      _showDeviceList = true;
      _step = _WizardStep.devices;
    });
    // Refreshes the wizard's own device list (what _buildDevicesStep()
    // actually renders) — session.refreshDevices() would populate
    // CameraSession's list instead, which this screen never reads.
    await _loadDevices();
  }

  Future<void> _useBuiltin() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.switchTo(kBuiltinAdapterType);
      // adapterType is now builtin, so the connected-view branch in build()
      // stops matching and falls through to the _step switch below — reset
      // it off whatever it was left at (.connecting, from the original
      // _connect() call) or it renders a permanent spinner. Devices are
      // still loaded (still signed in), so the device list is the right
      // landing spot for reconnecting to EZVIZ later.
      if (mounted) setState(() => _step = _WizardStep.devices);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.session,
      builder: (context, _) {
        if (widget.session.adapterType == kEzvizAdapterType &&
            widget.session.isOpen &&
            !_showDeviceList) {
          return _ConnectedEzvizView(
            session: widget.session,
            onSwitchDevice: _busy ? null : _switchDevice,
            onUseBuiltin: _busy ? null : _useBuiltin,
          );
        }
        switch (_step) {
          case _WizardStep.signIn:
            return _buildSignInStep();
          case _WizardStep.devices:
            return _buildDevicesStep();
          case _WizardStep.connecting:
            return const Center(child: CircularProgressIndicator());
        }
      },
    );
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
            onChanged: (value) => _savePref(_prefsCodeKey, value),
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
                      onTap: _busy ? null : () => _connect(device),
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
    return Column(
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
    );
  }
}
