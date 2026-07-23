import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

import 'adapter_types.dart';

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
  CameraSession(
    this._registry, {
    CameraProfileStore? profileStore,
    CameraSecretStore? secretStore,
  })  : _adapter = _registry.createDefault(),
        _adapterType = _registry.defaultType!,
        _profileStore = profileStore,
        _secretStore = secretStore;

  final CameraAdapterRegistry _registry;

  /// Both optional: a consumer that never saves a camera (and every existing
  /// test) constructs `CameraSession(registry)` and gets the original
  /// live-discovery-only behaviour.
  final CameraProfileStore? _profileStore;
  final CameraSecretStore? _secretStore;

  CameraAdapter _adapter;

  String _adapterType;
  String get adapterType => _adapterType;

  List<CameraProfile> _profiles = const <CameraProfile>[];

  /// Saved cameras, most recently created first. Empty until [loadProfiles].
  List<CameraProfile> get profiles => _profiles;

  CameraProfile? _activeProfile;

  /// The saved camera currently driving the session, if any. `null` when the
  /// open device came from live discovery rather than a profile.
  CameraProfile? get activeProfile => _activeProfile;

  final Set<String> _unavailableProfileIds = <String>{};

  /// Profile ids that did not match any device the backend could enumerate, so
  /// were not opened. The Cameras tab greys these out. See [_findMatchingDevice].
  Set<String> get unavailableProfileIds =>
      Set<String>.unmodifiable(_unavailableProfileIds);

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
  ///
  /// Still the source of numeric detail — zoom min/max. For "is this feature
  /// available at all?", prefer [featureMatrix].
  CameraCapabilities? get capabilities =>
      _adapter.isOpen ? _adapter.capabilities : null;

  /// Feature support of the *open* device, or null when nothing is open.
  ///
  /// This is what feature UI should gate on: it is uniform across every
  /// backend and degrades to "not supported" rather than requiring the caller
  /// to know which backend is live.
  CameraFeatureMatrix? get featureMatrix =>
      _adapter.isOpen ? _adapter.featureMatrix : null;

  /// Whether the open device supports [feature]. `false` when nothing is open,
  /// so callers can gate without a null check.
  bool supports(CameraFeature feature) =>
      featureMatrix?.isSupported(feature) ?? false;

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

  // --- Saved cameras (CameraProfile) ---

  /// How a saved profile is matched back to a live device, keyed by backend.
  ///
  /// A table rather than a `switch`: a new backend adds a row (or relies on the
  /// id fallback) instead of editing a conditional. This is the **only**
  /// type-keyed construct in the app, and it is identity resolution, not
  /// feature logic — `camera-adapter-authoring` §6 forbids type-branching in
  /// *feature* code, which this is not. Feature code uses [featureMatrix].
  ///
  /// Matching on [CameraDevice.id] alone is wrong in general: `camera_profile.dart`
  /// documents that id as ephemeral (a USB index, a discovery-time handle), so a
  /// camera that re-enumerated in a different order would look "gone" while
  /// sitting right there.
  static final Map<String, bool Function(CameraProfile, CameraDevice)>
      _profileMatchers = <String, bool Function(CameraProfile, CameraDevice)>{
    // Stable per machine — the camera plugin's own index/name.
    'builtin': _matchesById,
    // Stable — the EZVIZ cloud serial, e.g. BK0381480.
    'ezviz': _matchesById,
    // The endpoint *is* the identity; an ONVIF id can be a URN that changes
    // across reboots while host/port stay put.
    'onvif': (profile, device) {
      final host = profile.device.metadata['host'];
      if (host == null) return _matchesById(profile, device);
      return device.metadata['host'] == host &&
          device.metadata['port'] == profile.device.metadata['port'];
    },
  };

  static bool _matchesById(CameraProfile profile, CameraDevice device) =>
      device.id == profile.device.id;

  /// Loads saved profiles into [profiles]. No-op without a profile store.
  Future<void> loadProfiles() async {
    final store = _profileStore;
    if (store == null) return;
    final loaded = await store.loadAll();
    if (_disposed) return;
    _update(() => _profiles = loaded);
  }

  /// Loads saved cameras and opens the default one, falling back to live
  /// discovery when there is nothing saved.
  ///
  /// Call once at startup in place of [refreshDevices]. An empty store never
  /// fabricates a profile — it simply behaves as the app did before profiles
  /// existed, yielding a transient selection only.
  Future<void> restore() async {
    await loadProfiles();
    if (_disposed) return;

    final target = _defaultProfile();
    if (target == null) {
      await refreshDevices();
      return;
    }
    await switchToProfile(target);
    if (_activeProfile == null && !_adapter.isOpen) {
      // The restore didn't take (device gone, camera unreachable). Fall back so
      // the user still has a working app rather than an empty screen.
      await refreshDevices();
    }
  }

  CameraProfile? _defaultProfile() {
    if (_profiles.isEmpty) return null;
    for (final profile in _profiles) {
      if (profile.isDefault) return profile;
    }
    // No explicit default — most recently created wins.
    return _profiles.reduce(
      (a, b) => b.createdAt.isAfter(a.createdAt) ? b : a,
    );
  }

  /// Opens a saved camera: fetches its secret, merges it into a **transient**
  /// copy of the device, and opens that through the profile's backend.
  ///
  /// The merged copy is never stored — [selectedDevice] and the persisted
  /// profile both keep the secret-free device. That transient merge is how a
  /// credential reaches an adapter without the `CameraAdapter` contract ever
  /// growing a credential parameter.
  Future<void> switchToProfile(CameraProfile profile) async {
    _update(() {
      _busy = true;
      _error = null;
      _unavailableProfileIds.remove(profile.id);
    });

    if (profile.backendType != _adapterType) {
      try {
        await _serialized(_adapter.close);
      } on Object catch (_) {
        // The outgoing adapter is being discarded regardless.
      }
      if (_disposed) return;
      _update(() {
        _adapter = _registry.create(profile.backendType);
        _adapterType = profile.backendType;
        _devices = const <CameraDevice>[];
        _selectedId = null;
        _zoom = 1;
      });
    }

    // Re-validate against live discovery where the backend can enumerate.
    final device = await _resolveProfileDevice(profile);
    if (_disposed) return;
    if (device == null) {
      _update(() {
        _busy = false;
        _activeProfile = null;
        _unavailableProfileIds.add(profile.id);
        _error = '${profile.displayName} was not found. '
            'Reconnect it, or remove the saved camera.';
      });
      return;
    }

    final connectable = await _withSecret(profile, device);
    if (_disposed) return;
    _update(() => _activeProfile = profile);
    await openDevice(connectable, remember: device);
    if (_disposed) return;
    if (!_adapter.isOpen) {
      _update(() => _activeProfile = null);
    }
  }

  /// Resolves the live [CameraDevice] for [profile], or null when the backend
  /// can enumerate and the camera is no longer there.
  Future<CameraDevice?> _resolveProfileDevice(CameraProfile profile) async {
    final List<CameraDevice> devices;
    try {
      devices = await _serialized(() => _adapter.listDevices());
    } on UnimplementedError {
      // The backend cannot enumerate at all (ONVIF today — WS-Discovery is
      // deferred). Duck-typed on the contract rather than checking the backend
      // name, so an ONVIF backend that later gains discovery starts being
      // re-validated with no change here. open() is then the validation: it
      // does a real round-trip and fails with the usual typed errors.
      return profile.device;
    } on Object {
      // Enumeration failed for some other reason (permissions, transient). Try
      // the saved device rather than declaring the camera gone.
      return profile.device;
    }
    if (_disposed) return null;
    _update(() => _devices = devices);

    final matcher = _profileMatchers[profile.backendType] ?? _matchesById;
    for (final device in devices) {
      if (matcher(profile, device)) return device;
    }
    return null;
  }

  /// Merges the profile's stored secret into a throwaway copy of [device].
  Future<CameraDevice> _withSecret(
    CameraProfile profile,
    CameraDevice device,
  ) async {
    final store = _secretStore;
    if (store == null) return device;
    final merged = <String, dynamic>{...device.metadata};
    for (final key in kCameraSecretKeys) {
      final secret = await store.getSecret(profile.id, key);
      if (secret != null && secret.isNotEmpty) merged[key] = secret;
    }
    return merged.length == device.metadata.length
        ? device
        : device.copyWith(metadata: merged);
  }

  /// Saves [profile] and immediately switches to it.
  Future<void> saveAndSwitchTo(CameraProfile profile) async {
    final store = _profileStore;
    if (store != null) {
      await store.save(profile);
      await loadProfiles();
    }
    if (_disposed) return;
    await switchToProfile(profile);
  }

  /// Deletes a saved camera **and its secrets**, closing it first if it is live.
  Future<void> deleteProfile(String profileId) async {
    final store = _profileStore;
    if (store == null) return;
    if (_activeProfile?.id == profileId) {
      await close();
      _update(() => _activeProfile = null);
    }
    // Secrets first: a profile removed while its secrets survive would leave
    // them unreachable and undeletable, since they are keyed by its id.
    await _secretStore?.deleteSecretsForProfile(profileId);
    await store.delete(profileId);
    _unavailableProfileIds.remove(profileId);
    await loadProfiles();
  }

  /// Marks [profileId] as the camera to restore at next launch.
  Future<void> setDefaultProfile(String profileId) async {
    final store = _profileStore;
    if (store == null) return;
    await store.setDefault(profileId);
    await loadProfiles();
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
  /// [remember] overrides what is stored in [devices], for when the device
  /// being opened carries a secret that must not be retained. `switchToProfile`
  /// passes the secret-free original here while opening the merged copy, so the
  /// credential exists only for the duration of the `open` call and never sits
  /// in session state where a later plain [open] could reuse or a debug dump
  /// could expose it.
  Future<void> openDevice(CameraDevice device, {CameraDevice? remember}) async {
    final stored = remember ?? device;
    _update(() {
      final idx = _devices.indexWhere((d) => d.id == stored.id);
      _devices = idx >= 0
          ? [
              for (var i = 0; i < _devices.length; i++)
                i == idx ? stored : _devices[i],
            ]
          : [..._devices, stored];
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
