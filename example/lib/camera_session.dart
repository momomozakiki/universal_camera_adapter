import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

/// The single shared camera lifecycle for the whole example app.
///
/// The [CameraAdapter] contract allows **at most one open device per adapter**
/// ([CameraAdapter.open] closes any previous device first), so every tab drives
/// the *same* session rather than each owning an adapter that would fight over
/// the one physical camera. The tabs are pure consumers: they read this
/// notifier and call [open]/[close]/[captureFrame]/[setZoom] — the Golden Rule
/// in practice.
///
/// The session holds a [CameraAdapterRegistry] rather than a fixed adapter so
/// it can [switchTo] a different backend (e.g. after a setup wizard obtains
/// credentials for a cloud camera) without every tab needing to rebuild
/// around a new session — this is a minimal, in-memory equivalent of Epic
/// 2.5's not-yet-built `CameraProfile`/persistence stack.
///
/// Every call into the adapter is funneled through a **serialized queue**
/// because `FlutterCameraAdapter` is not reentrant-safe: concurrent
/// open/close/capture (rapid dropdown changes, a Refresh racing an open, or
/// dispose racing an in-flight capture) can otherwise interleave and leak a
/// `CameraController`. Chaining every call guarantees at most one is in flight,
/// in call order — including across a [switchTo], since queued closures read
/// the current adapter lazily at execution time, not at enqueue time. The one
/// deliberate exception: the close call that targets the adapter being
/// replaced/discarded (inside [switchTo] and [close] itself) binds to that
/// specific instance eagerly, so it closes the adapter that was actually live
/// when the call was made, not whatever `_adapter` happens to be by the time
/// the queue reaches it. (Idiom ported from odb_library's
/// `CameraPage._serialized`.)
class CameraSession extends ChangeNotifier {
  CameraSession(this._registry)
      : _adapter = _registry.createDefault(),
        _adapterType = _registry.defaultType!;

  final CameraAdapterRegistry _registry;
  CameraAdapter _adapter;

  String _adapterType;
  String get adapterType => _adapterType;

  List<CameraDevice> _devices = const <CameraDevice>[];
  List<CameraDevice> get devices => _devices;

  String? _selectedId;
  String? get selectedId => _selectedId;

  bool _busy = false;
  bool get busy => _busy;

  String? _error;
  String? get error => _error;

  double _zoom = 1;
  double get zoom => _zoom;

  bool _disposed = false;

  bool get isOpen => _adapter.isOpen;

  /// Capabilities of the *open* device, or null when nothing is open (reading
  /// [CameraAdapter.capabilities] before open throws by contract).
  CameraCapabilities? get capabilities =>
      _adapter.isOpen ? _adapter.capabilities : null;

  CameraDevice? get selectedDevice => _deviceById(_selectedId);

  Future<void> _opQueue = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() op) {
    final result = _opQueue.then((_) => op());
    // Keep the chain alive on failure so one error can't wedge the queue.
    _opQueue = result.then((_) {}, onError: (_) {});
    return result;
  }

  void _update(void Function() mutate) {
    if (_disposed) return;
    mutate();
    notifyListeners();
  }

  /// The live preview widget for the open device. Guard on [isOpen] first.
  ///
  /// Multiple tabs may each call this: [CameraAdapter.buildPreview] returns a
  /// `Texture` widget over the shared controller, and multiple `Texture`s over
  /// one controller render fine in Flutter — no single-preview hoisting needed.
  Widget buildPreview() => _adapter.buildPreview();

  /// Switches to the backend registered under [type] (a no-op if it's already
  /// current). Closes and discards the current adapter, creates a fresh
  /// instance of [type] from the registry, and resets device/selection/zoom
  /// state — a device id or zoom range from one backend is meaningless
  /// against another. Lists (but does not open) devices on the new backend
  /// before returning, same as [refreshDevices].
  ///
  /// Throws [StateError] if [type] isn't registered — always a hardcoded
  /// constant in this app, never user input, so callers don't need to
  /// recover from it. If it does throw, the outgoing adapter has already been
  /// closed but the session's fields are left pointing at it (no half switch).
  Future<void> switchTo(String type) async {
    if (type == _adapterType) return;
    _update(() {
      _busy = true;
      _error = null;
    });
    try {
      await _serialized(_adapter.close);
    } on Object catch (_) {
      // Best-effort — the outgoing adapter is being discarded regardless.
    }
    if (_disposed) return;
    _update(() {
      _adapter = _registry.create(type);
      _adapterType = type;
      _devices = const <CameraDevice>[];
      _selectedId = null;
      _zoom = 1;
      _busy = false;
    });
    await refreshDevices();
  }

  /// Lists devices without opening anything. Drops back to disconnected if the
  /// open device vanished from the refreshed list, and auto-selects the first
  /// device when nothing valid is selected.
  Future<void> refreshDevices() async {
    _update(() {
      _busy = true;
      _error = null;
    });
    try {
      final devices = await _serialized(() => _adapter.listDevices());
      if (_disposed) return;
      if (_adapter.isOpen && !devices.any((d) => d.id == _selectedId)) {
        // The streaming device is gone — don't leave the selection pointing at
        // a different device than what's open; drop to disconnected instead.
        await _serialized(() => _adapter.close());
      }
      if (_disposed) return;
      _update(() {
        _devices = devices;
        _busy = false;
        if (!_adapter.isOpen &&
            (_selectedId == null ||
                !devices.any((d) => d.id == _selectedId))) {
          _selectedId = devices.isEmpty ? null : devices.first.id;
        }
        _error = devices.isEmpty ? 'No camera was found on this device.' : null;
      });
    } on Object catch (e) {
      _update(() {
        _busy = false;
        _error = _describe(e);
      });
    }
  }

  /// Changes the selected device without opening it (used by the dropdown).
  void select(String deviceId) => _update(() => _selectedId = deviceId);

  /// Opens [deviceId] (or the current selection). `open()` closes any previous
  /// device first, so there is no need to close explicitly here.
  Future<void> open([String? deviceId]) async {
    final device = _deviceById(deviceId ?? _selectedId);
    if (device == null) return;
    await _open(device);
  }

  /// Opens [device] directly rather than resolving it by id from [devices].
  /// For backends that need extra per-connection data attached to the
  /// [CameraDevice] before opening — e.g. EZVIZ's verification code via
  /// `device.metadata['verificationCode']` (see `EzvizCameraAdapter`'s doc
  /// comment) — which [refreshDevices] has no way to know about. [device]
  /// replaces the matching entry in [devices] (by id), or is appended if new,
  /// so later plain [open] calls (e.g. from a device dropdown) keep using it.
  Future<void> openDevice(CameraDevice device) async {
    _update(() {
      final idx = _devices.indexWhere((d) => d.id == device.id);
      _devices = idx >= 0
          ? [
              for (var i = 0; i < _devices.length; i++)
                i == idx ? device : _devices[i],
            ]
          : [..._devices, device];
    });
    await _open(device);
  }

  Future<void> _open(CameraDevice device) async {
    _update(() {
      _busy = true;
      _error = null;
    });
    try {
      await _serialized(() => _adapter.open(device));
      if (_disposed) {
        // Disposed while this open was queued — release rather than leak it.
        await _serialized(_adapter.close);
        return;
      }
      final caps = _adapter.capabilities;
      _update(() {
        _selectedId = device.id;
        _busy = false;
        _zoom = caps.minZoomLevel;
      });
    } on Object catch (e) {
      _update(() {
        _busy = false;
        _error = _describe(e);
      });
    }
  }

  Future<void> close() async {
    _update(() {
      _busy = true;
      _error = null;
    });
    try {
      await _serialized(_adapter.close);
    } on Object catch (e) {
      _update(() => _error = _describe(e));
    } finally {
      _update(() => _busy = false);
    }
  }

  /// Sets zoom (optimistically updates the slider, then applies). Only call
  /// when `capabilities!.hasZoom` — the UI gates this.
  Future<void> setZoom(double value) async {
    _update(() => _zoom = value);
    try {
      await _serialized(() => _adapter.setZoom(value));
    } on Object catch (e) {
      _update(() => _error = _describe(e));
    }
  }

  /// Pans the camera. Only call when `capabilities!.hasPan` — otherwise the
  /// contract throws [UnsupportedError] (surfaced as [error]).
  Future<void> setPan(double angle) async {
    try {
      await _serialized(() => _adapter.setPan(angle));
    } on Object catch (e) {
      _update(() => _error = _describe(e));
    }
  }

  /// Tilts the camera. Only call when `capabilities!.hasTilt`.
  Future<void> setTilt(double angle) async {
    try {
      await _serialized(() => _adapter.setTilt(angle));
    } on Object catch (e) {
      _update(() => _error = _describe(e));
    }
  }

  /// Captures one frame through the shared serialized queue. Rethrows the
  /// adapter's typed errors so the frame scanner / gallery can react.
  Future<Uint8List> captureFrame() => _serialized(() => _adapter.captureFrame());

  CameraDevice? _deviceById(String? id) {
    if (id == null) return null;
    for (final device in _devices) {
      if (device.id == id) return device;
    }
    return null;
  }

  /// Maps the contract's typed errors to a short, user-facing string.
  String _describe(Object error) {
    if (error is StateError) return error.message;
    if (error is TimeoutException) {
      return 'The camera took too long to respond.';
    }
    if (error is UnsupportedError) {
      return error.message ?? 'This camera does not support that.';
    }
    return '$error';
  }

  @override
  void dispose() {
    _disposed = true;
    // Always release what we opened, even mid-flight.
    unawaited(_serialized(_adapter.close));
    super.dispose();
  }
}
