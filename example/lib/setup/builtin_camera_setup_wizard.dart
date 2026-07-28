import 'dart:async';

import 'package:flutter/material.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

import '../adapter_types.dart';
import '../error_messages.dart';
import '../widgets/camera_empty_state.dart';

/// Setup flow for local device cameras (phone cameras, USB webcams).
///
/// The simplest possible wizard: local cameras are auto-detected and need no
/// credentials, so "setup" is just picking one and naming it. It is still
/// registered rather than special-cased, so the Phase E chooser can render
/// every backend uniformly with no `if (type == 'builtin')` branch — which is
/// the whole reason the registry exists.
///
/// Collects no secret, so it takes no `CameraSecretStore`.
class BuiltinCameraSetupWizard extends CameraSetupWizard {
  BuiltinCameraSetupWizard({required this.registry});

  final CameraAdapterRegistry registry;

  @override
  String get backendType => kBuiltinAdapterType;

  @override
  String get displayName => 'Built-in camera';

  @override
  IconData get icon => Icons.photo_camera_outlined;

  @override
  Widget build(
    BuildContext context, {
    required ValueChanged<CameraProfile> onComplete,
    required VoidCallback onCancel,
  }) {
    return _BuiltinDevicePicker(
      registry: registry,
      onComplete: onComplete,
      onCancel: onCancel,
    );
  }
}

class _BuiltinDevicePicker extends StatefulWidget {
  const _BuiltinDevicePicker({
    required this.registry,
    required this.onComplete,
    required this.onCancel,
  });

  final CameraAdapterRegistry registry;
  final ValueChanged<CameraProfile> onComplete;
  final VoidCallback onCancel;

  @override
  State<_BuiltinDevicePicker> createState() => _BuiltinDevicePickerState();
}

/// Why the picker has nothing to offer — drives which hint the user sees.
///
/// Kept separate from the message itself so the *cause* survives into `build`;
/// a bare `String? _error` could only ever produce one hint.
///
/// Deliberately **not** carrying a `permission` case. A blocked permission
/// arrives as a [StateError] whose message the adapter already tailored to the
/// platform ("Settings → Privacy & security → Camera" on Windows, "Settings →
/// Apps → Permissions" on Android). Re-detecting it here would mean matching on
/// that message text — the same brittle substring coupling this change removed
/// from the adapter. The layer that knows the cause writes the words; this
/// layer shows them.
enum _Cause {
  /// Enumeration succeeded and returned nothing.
  empty,

  /// Enumeration failed; [_BuiltinDevicePickerState._error] carries the
  /// adapter's written explanation, permission-related or not.
  failure,
}

class _BuiltinDevicePickerState extends State<_BuiltinDevicePicker> {
  List<CameraDevice> _devices = const <CameraDevice>[];
  bool _busy = true;
  String? _error;
  _Cause _cause = _Cause.empty;

  /// Guards the "exactly one callback, exactly once" invariant.
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Enumerating IS the connectivity check for this backend. Deliberately
      // not a full open(): the local camera is a single exclusive resource, so
      // opening it here would fight the live CameraSession for it — and unlike
      // a network camera, a device that enumerates is reachable by definition.
      final adapter = widget.registry.create(kBuiltinAdapterType);
      final devices = await adapter.listDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _busy = false;
        _error = null;
        _cause = _Cause.empty;
      });
    } on TimeoutException {
      _fail('The camera list took too long to load.', _Cause.failure);
    } on StateError catch (e) {
      // The adapter has already replaced any platform text with a written
      // message — including the platform-specific permission instructions —
      // so this is safe to show verbatim.
      _fail(e.message, _Cause.failure);
    } on Object catch (e) {
      // Off-contract: describeCameraError logs it and returns a written
      // sentence, so nothing of the raw object reaches the screen.
      _fail(
        describeCameraError(e, action: 'looking for cameras'),
        _Cause.failure,
      );
    }
  }

  void _fail(String message, _Cause cause) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
      _cause = cause;
    });
  }

  /// What the user can actually do, per cause.
  String get _hint {
    switch (_cause) {
      case _Cause.empty:
        return "This device doesn't report a camera. If one is attached, "
            'reconnect it and tap Refresh.';
      case _Cause.failure:
        return '${_error ?? 'The camera list could not be loaded.'} '
            'Tap Refresh to try again.';
    }
  }

  void _choose(CameraDevice device) {
    if (_finished) return;
    _finished = true;
    widget.onComplete(
      CameraProfile.create(
        backendType: kBuiltinAdapterType,
        displayName: device.name,
        device: device,
      ),
    );
  }

  void _cancel() {
    if (_finished) return;
    _finished = true;
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _busy
              ? const Center(child: CircularProgressIndicator())
              : _devices.isEmpty
                  ? CameraEmptyState(
                      icon: Icons.no_photography_outlined,
                      headline: kNoBuiltinCameraFound,
                      hint: _hint,
                    )
                  : ListView.builder(
                      itemCount: _devices.length,
                      itemBuilder: (context, i) {
                        final device = _devices[i];
                        return ListTile(
                          leading: const Icon(Icons.photo_camera_outlined),
                          title: Text(device.name),
                          subtitle: Text('${device.lensFacing.name} · ${device.id}'),
                          onTap: () => _choose(device),
                        );
                      },
                    ),
        ),
        if (_error != null && _devices.isNotEmpty)
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
                  onPressed: _busy ? null : _load,
                  child: const Text('Refresh'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextButton(
                  onPressed: _cancel,
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
