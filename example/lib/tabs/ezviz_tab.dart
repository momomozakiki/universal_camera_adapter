import 'dart:convert';

import 'package:ezviz_flutter/ezviz_flutter.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Test surface for the EZVIZ Open Platform bridge (`scripts/ezviz_bridge.py`).
///
/// The bridge is EZVIZ-agnostic to this tab: it only ever returns a device
/// list and the account's `appKey`/`accessToken`. Playback is handled by
/// [_EzvizNativePlayer] below, a thin wrapper around `ezviz_flutter`'s
/// low-level `EzvizPlayer`/`EzvizPlayerController` (not its `EzvizSimplePlayer`
/// convenience widget - see that class's doc comment for why) - this tab
/// holds no EZVIZ protocol logic itself beyond driving that small wrapper.
///
/// The bridge is tied to one EZVIZ account via server-side environment
/// variables, so there is no login step here - this tab just lists that
/// account's cameras and plays whichever one is tapped.
class EzvizTab extends StatefulWidget {
  const EzvizTab({super.key});

  @override
  State<EzvizTab> createState() => _EzvizTabState();
}

enum _Step { devices, video }

class _EzvizDevice {
  const _EzvizDevice({required this.serial, this.name, this.model});

  final String serial;
  final String? name;
  final String? model;

  factory _EzvizDevice.fromJson(Map<String, dynamic> json) => _EzvizDevice(
    serial: json['serial'] as String,
    name: json['name'] as String?,
    model: json['model'] as String?,
  );
}

class _EzvizTabState extends State<EzvizTab> {
  static const _prefsBridgeHostKey = 'ezviz_tab.bridge_host';
  static const _prefsCodeKey = 'ezviz_tab.verification_code';

  final _bridgeHostController = TextEditingController(
    text: '127.0.0.1:8765',
  );
  final _codeController = TextEditingController();

  _Step _step = _Step.devices;
  bool _busy = false;
  String? _error;

  List<_EzvizDevice> _devices = [];
  String? _appKey;
  String? _accessToken;
  _EzvizDevice? _playingDevice;
  String? _playerState;

  /// Bumped every time the user taps "Connect". Feeds the [EzvizSimplePlayer]
  /// key below so each tap forces a brand-new player instance - the plugin's
  /// own initState is where the verification code is actually applied
  /// (`_currentPassword = widget.encryptionPassword`), so reusing an existing
  /// instance (e.g. the plugin's built-in "Retry" button) silently ignores
  /// any code typed after that instance was first created.
  int _connectAttempt = 0;

  @override
  void initState() {
    super.initState();
    _restoreSavedFields();
  }

  @override
  void dispose() {
    _bridgeHostController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _restoreSavedFields() async {
    final prefs = await SharedPreferences.getInstance();
    final savedHost = prefs.getString(_prefsBridgeHostKey);
    final savedCode = prefs.getString(_prefsCodeKey);
    if (savedHost != null) _bridgeHostController.text = savedHost;
    if (savedCode != null) _codeController.text = savedCode;
    await _loadDevices();
  }

  Future<void> _savePref(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Uri _bridgeUri(String path, [Map<String, String>? query]) {
    return Uri.http(_bridgeHostController.text.trim(), path, query);
  }

  Future<void> _loadDevices() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final devicesResponse = await http.get(_bridgeUri('/devices'));
      final configResponse = await http.get(_bridgeUri('/config'));
      final devicesBody = jsonDecode(devicesResponse.body) as Map<String, dynamic>;
      final configBody = jsonDecode(configResponse.body) as Map<String, dynamic>;
      if (devicesResponse.statusCode != 200) {
        setState(
          () => _error = devicesBody['error'] as String? ?? 'Could not list devices.',
        );
        return;
      }
      if (configResponse.statusCode != 200) {
        setState(
          () => _error = configBody['error'] as String? ?? 'Could not load account config.',
        );
        return;
      }
      final devices = (devicesBody['devices'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(_EzvizDevice.fromJson)
          .toList();
      setState(() {
        _devices = devices;
        _appKey = configBody['appKey'] as String;
        _accessToken = configBody['accessToken'] as String;
      });
    } catch (e) {
      setState(
        () => _error =
            'Could not reach the bridge at ${_bridgeHostController.text}. '
            'Is scripts/ezviz_bridge.py running? ($e)',
      );
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

  void _openStream(_EzvizDevice device) {
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
      case _Step.devices:
        return _buildDevicesStep();
      case _Step.video:
        return _buildVideoStep();
    }
  }

  Widget _buildDevicesStep() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _bridgeHostController,
                decoration: const InputDecoration(
                  labelText: 'Bridge host:port',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => _savePref(_prefsBridgeHostKey, value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _codeController,
                decoration: const InputDecoration(
                  labelText: 'Default verification code (only if encrypted)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => _savePref(_prefsCodeKey, value),
              ),
            ],
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
                      title: Text(device.name ?? device.serial),
                      subtitle: Text(
                        [
                          device.serial,
                          if (device.model != null) device.model!,
                        ].join(' · '),
                      ),
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
          child: OutlinedButton(
            onPressed: _busy ? null : _loadDevices,
            child: const Text('Refresh devices'),
          ),
        ),
      ],
    );
  }

  Widget _buildVideoStep() {
    final device = _playingDevice;
    final appKey = _appKey;
    final accessToken = _accessToken;
    final code = _codeController.text.trim();
    final ready = device != null && appKey != null && accessToken != null;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(device?.name ?? device?.serial ?? ''),
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
                    key: ValueKey('${device.serial}::$code::$_connectAttempt'),
                    appKey: appKey,
                    accessToken: accessToken,
                    deviceSerial: device.serial,
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
