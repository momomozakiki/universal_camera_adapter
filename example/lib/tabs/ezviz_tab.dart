import 'package:ezviz_flutter/ezviz_flutter.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// This project's registered EZVIZ Open Platform AppKey - a public app
/// identifier, not a secret. Confirmed from `ezviz_flutter`'s native side
/// (`EzvizManager.kt: initSDK()`): only the AppKey is ever passed to
/// `EZGlobalSDK.initLib(app, appKey)`; the AppSecret never appears anywhere
/// in the native SDK init path (it's only used by the separate Open
/// Platform REST `token/get` call this tab no longer makes). Every user of
/// this app shares this one AppKey, the same way the official EZVIZ app
/// bundles its own single key for all of its accounts - what's per-user is
/// the access token obtained via [EzvizAuthManager.openLoginPage] below.
const _kEzvizAppKey = '59c8ee7cf07e45c3bec8978950c3d484';

/// Test surface for `ezviz_flutter`'s native per-user login + live-view.
///
/// Each user signs in with their own EZVIZ account via EZVIZ's own
/// SDK-hosted login page ([EzvizAuthManager.openLoginPage]) - this app never
/// sees a password. The native SDK caches the resulting access token itself
/// (persists across restarts, refreshes silently), so this tab holds no
/// credential storage of its own beyond the always-visible verification-code
/// field for encrypted devices. Playback is handled by [_EzvizNativePlayer]
/// below, a thin wrapper around `ezviz_flutter`'s low-level
/// `EzvizPlayer`/`EzvizPlayerController` (not its `EzvizSimplePlayer`
/// convenience widget - see that class's doc comment for why).
class EzvizTab extends StatefulWidget {
  const EzvizTab({super.key});

  @override
  State<EzvizTab> createState() => _EzvizTabState();
}

enum _Step { signIn, devices, video }

class _EzvizTabState extends State<EzvizTab> with WidgetsBindingObserver {
  static const _prefsCodeKey = 'ezviz_tab.verification_code';

  final _codeController = TextEditingController();

  _Step _step = _Step.signIn;
  bool _busy = false;
  String? _error;

  /// Set right before [EzvizAuthManager.openLoginPage] launches the hosted
  /// login page, cleared once we've checked for a token on the next resume.
  /// Guards against re-checking on unrelated app resumes (e.g. switching
  /// apps briefly while already on the device list).
  bool _awaitingSignIn = false;

  List<EzvizDeviceInfo> _devices = [];
  String? _accessToken;
  EzvizDeviceInfo? _playingDevice;
  String? _playerState;

  /// Bumped every time the user taps "Connect". Feeds the
  /// [_EzvizNativePlayer] key below so each tap forces a brand-new player
  /// instance - the correct sequence (initPlayerByDevice -> setPlayVerifyCode
  /// -> startRealPlay) only runs from a fresh instance's initState.
  int _connectAttempt = 0;

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

  /// `initSDK` must run *before* `getAccessToken` - confirmed via adb logcat:
  /// calling `getAccessToken` first throws natively (`EZGlobalSDK.getInstance()`
  /// is null until `initLib` has run), which the Dart wrapper swallows into a
  /// plain `null`, so a cached-token check done first always looks empty.
  /// `initSDK`'s native `initLib()` call restores any previously-persisted
  /// token from the SDK's own local storage on its own; this tab's vendored
  /// copy of `ezviz_flutter` (see `example/third_party/ezviz_flutter`) was
  /// also patched to stop unconditionally overwriting that restored token
  /// with an empty string, so calling `initSDK` here with `accessToken: ''`
  /// is safe - it never destroys a real cached token.
  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCode = prefs.getString(_prefsCodeKey);
    if (savedCode != null) _codeController.text = savedCode;

    await EzvizManager.shared().initSDK(
      EzvizInitOptions(appKey: _kEzvizAppKey, accessToken: ''),
    );
    final cached = await EzvizAuthManager.getAccessToken();
    if (cached != null) {
      setState(() {
        _accessToken = cached.accessToken;
        _step = _Step.devices;
      });
      await _loadDevices();
    } else {
      setState(() => _step = _Step.signIn);
    }
  }

  Future<void> _signIn() async {
    setState(() => _error = null);
    _awaitingSignIn = true;
    // Deliberately no `areaId` - checked EzvizManager.kt's native handler
    // directly: passing any areaId string gets discarded and replaced with a
    // hardcoded `openLoginPage(0)` call, a plugin quirk. Omitting it takes
    // the no-arg native path, the SDK's own default/auto-detect region.
    final launched = await EzvizAuthManager.openLoginPage();
    if (!launched) {
      _awaitingSignIn = false;
      setState(() => _error = 'Could not open the EZVIZ sign-in page.');
    }
  }

  Future<void> _checkSignInAfterResume() async {
    // The SDK may need a moment to finish writing its native cache after the
    // login activity returns control to this app.
    await Future.delayed(const Duration(milliseconds: 500));
    final token = await EzvizAuthManager.getAccessToken();
    if (token == null) {
      setState(() => _error = 'Sign-in was cancelled or failed. Try again.');
      return;
    }
    await EzvizManager.shared().initSDK(
      EzvizInitOptions(appKey: _kEzvizAppKey, accessToken: token.accessToken),
    );
    setState(() {
      _accessToken = token.accessToken;
      _step = _Step.devices;
    });
    await _loadDevices();
  }

  Future<void> _signOut() async {
    await EzvizAuthManager.logout();
    setState(() {
      _accessToken = null;
      _devices = [];
      _step = _Step.signIn;
    });
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
      final devices = await EzvizDeviceManager.getDeviceList();
      setState(() => _devices = devices);
    } catch (e) {
      setState(() => _error = 'Could not load devices: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Defers [fn] past the current frame before calling [setState].
  ///
  /// EzvizSimplePlayer calls its onStateChanged/onError callbacks
  /// synchronously from its own initState (before any await), which lands
  /// while this tab's own build is still in progress - calling setState
  /// directly there throws "setState() or markNeedsBuild() called during
  /// build". Scheduling it as a post-frame callback runs it once the current
  /// build has finished instead.
  void _setStateNextFrame(VoidCallback fn) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(fn);
    });
  }

  void _openStream(EzvizDeviceInfo device) {
    setState(() {
      _playingDevice = device;
      _playerState = null;
      _error = null;
      _connectAttempt = 0;
      _step = _Step.video;
    });
  }

  void _connect() {
    setState(() {
      _connectAttempt++;
      _error = null;
      _playerState = null;
    });
  }

  void _backToDevices() {
    setState(() {
      _playingDevice = null;
      _playerState = null;
      _connectAttempt = 0;
      _step = _Step.devices;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case _Step.signIn:
        return _buildSignInStep();
      case _Step.devices:
        return _buildDevicesStep();
      case _Step.video:
        return _buildVideoStep();
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
              'This opens EZVIZ\'s own sign-in page - this app never sees '
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
              labelText: 'Default verification code (only if encrypted)',
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
                      onTap: _busy ? null : () => _openStream(device),
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
                  onPressed: _signOut,
                  child: const Text('Sign out'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVideoStep() {
    final device = _playingDevice;
    final accessToken = _accessToken;
    final code = _codeController.text.trim();
    final ready = device != null && accessToken != null;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(device?.deviceName ?? device?.deviceSerial ?? ''),
              const SizedBox(height: 8),
              TextField(
                controller: _codeController,
                decoration: const InputDecoration(
                  labelText: 'Verification code (only if encrypted)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => _savePref(_prefsCodeKey, value),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: ready ? _connect : null,
                      child: Text(
                        _connectAttempt == 0 ? 'Connect' : 'Reconnect',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _backToDevices,
                      child: const Text('Back to device list'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('Player state: ${_playerState ?? 'unknown'}'),
        ),
        Expanded(
          child: !ready
              ? const Center(child: CircularProgressIndicator())
              : _connectAttempt == 0
              ? const Center(
                  child: Text('Enter the code (if needed) and tap Connect.'),
                )
              : AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _EzvizNativePlayer(
                    // Changing the key forces Flutter to fully dispose the
                    // previous player and construct a new one - the only way
                    // a freshly-typed code reaches a fresh
                    // initPlayerByDevice/setPlayVerifyCode/startRealPlay
                    // sequence.
                    key: ValueKey('${device.deviceSerial}::$code::$_connectAttempt'),
                    appKey: _kEzvizAppKey,
                    accessToken: accessToken,
                    deviceSerial: device.deviceSerial,
                    channelNo: 1,
                    verificationCode: code.isEmpty ? null : code,
                    onStateChanged: (state) =>
                        _setStateNextFrame(() => _playerState = state),
                    onError: (error) =>
                        _setStateNextFrame(() => _error = error),
                  ),
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
      ],
    );
  }
}

/// Thin wrapper around `ezviz_flutter`'s low-level `EzvizPlayer`/
/// `EzvizPlayerController`, driving the native SDK calls ourselves in the
/// correct order.
///
/// Deliberately NOT using the package's own `EzvizSimplePlayer` convenience
/// widget: that widget has a confirmed bug (checked against
/// `ezviz_flutter` 1.2.7's source) where `_handlePlayerStatus` marks its
/// internal `_isPlayerInitialized` flag `true` as soon as the native SDK
/// reports status `1` ("Init") - which happens immediately after the
/// platform view is created, unconditionally - but `setPlayVerifyCode()` is
/// only ever called from `_initializePlayer()`, which `_startLiveStream()`
/// only invokes `if (!_isPlayerInitialized)`. Since that flag is already
/// true by the time the check runs, `setPlayVerifyCode()` - the call that
/// actually applies a device's verification code - is skipped every time,
/// for both `autoPlay` and manual retry. Confirmed via `adb logcat`: the
/// package's own `🔐 Setting verification code` debug line never appeared
/// across ~9 real playback attempts on real hardware, regardless of what
/// this app did on the Dart side. Calling `initPlayerByDevice` ->
/// `setPlayVerifyCode` -> `startRealPlay` ourselves, in that order, avoids
/// the bug entirely.
class _EzvizNativePlayer extends StatefulWidget {
  const _EzvizNativePlayer({
    super.key,
    required this.appKey,
    required this.accessToken,
    required this.deviceSerial,
    required this.channelNo,
    this.verificationCode,
    this.onStateChanged,
    this.onError,
  });

  final String appKey;
  final String accessToken;
  final String deviceSerial;
  final int channelNo;
  final String? verificationCode;
  final void Function(String state)? onStateChanged;
  final void Function(String error)? onError;

  @override
  State<_EzvizNativePlayer> createState() => _EzvizNativePlayerState();
}

class _EzvizNativePlayerState extends State<_EzvizNativePlayer> {
  EzvizPlayerController? _controller;

  /// Must be awaited before touching `initPlayerByDevice` - unlike the
  /// buggy `EzvizSimplePlayer`, the SDK isn't guaranteed ready just because
  /// the native view exists; `EzvizSimplePlayer` itself awaits this same
  /// call to completion before its own `_initializePlayer()` runs.
  late final Future<bool> _sdkReady;

  @override
  void initState() {
    super.initState();
    widget.onStateChanged?.call('initializing');
    _sdkReady = EzvizManager.shared().initSDK(
      EzvizInitOptions(appKey: widget.appKey, accessToken: widget.accessToken),
    );
  }

  @override
  void dispose() {
    _controller?.removePlayerEventHandler();
    _controller?.stopRealPlay();
    _controller?.release();
    super.dispose();
  }

  Future<void> _onPlayerCreated(EzvizPlayerController controller) async {
    _controller = controller;
    controller.setPlayerEventHandler(_onEvent, _onPlatformError);
    try {
      await _sdkReady;
      // Deliberately NOT awaiting initPlayerByDevice/setPlayVerifyCode/
      // startRealPlay below: read ezviz_flutter's native Kotlin side
      // (EzvizView.kt's onMethodCall) - these three method handlers never
      // call `result.success()`/`result.error()` at all, unlike e.g.
      // openSound/capturePicture which do. Awaiting them hangs the Dart
      // Future forever (confirmed via logcat: execution never proceeds past
      // the first `await` here). Actual playback progress/errors are
      // reported through the separate event channel already wired up via
      // setPlayerEventHandler above, not through these calls' return
      // values. Method channel calls on the same channel are dispatched
      // in order, so firing them one after another (without awaiting)
      // still reaches the native SDK in the right sequence.
      controller.initPlayerByDevice(widget.deviceSerial, widget.channelNo);
      final code = widget.verificationCode;
      if (code != null && code.isNotEmpty) {
        debugPrint('Applying verification code');
        controller.setPlayVerifyCode(code);
      }
      controller.startRealPlay();
    } catch (e) {
      widget.onError?.call('Failed to start playback: $e');
    }
  }

  void _onEvent(EzvizEvent event) {
    if (event.eventType != EzvizChannelEvents.playerStatusChange) return;
    final status = event.data;
    if (status is! EzvizPlayerStatus) return;
    if (status.status == 9 && status.message != null) {
      widget.onError?.call(status.message!);
      return;
    }
    widget.onStateChanged?.call(_statusLabel(status.status));
  }

  void _onPlatformError(Object error) {
    widget.onError?.call('Player event error: $error');
  }

  String _statusLabel(int status) {
    switch (status) {
      case 0:
        return 'idle';
      case 1:
        return 'initialized';
      case 2:
        return 'playing';
      case 3:
        return 'paused';
      case 4:
        return 'stopped';
      case 9:
        return 'error';
      default:
        return 'unknown ($status)';
    }
  }

  @override
  Widget build(BuildContext context) {
    return EzvizPlayer(onCreated: _onPlayerCreated);
  }
}
