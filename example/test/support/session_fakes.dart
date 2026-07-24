import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

/// Shared fakes for the selection/camera-bar tests. Mirrors the private harness
/// in `camera_session_profile_test.dart`, exposed so several test files can
/// drive a real [CameraSession] without each re-declaring the same doubles.

/// Records the device it was opened with and can simulate the two ONVIF-shaped
/// behaviours: non-enumerable discovery and a failing open.
class RecordingAdapter extends CameraAdapter {
  RecordingAdapter(
    this._devices, {
    this.enumerable = true,
    this.failOpen = false,
  });

  final List<CameraDevice> _devices;

  /// When false, [listDevices] throws `UnimplementedError` the way
  /// `ONVIFCameraAdapter` does today (WS-Discovery deferred).
  final bool enumerable;

  /// When true, [open] throws after recording, like an unreachable camera.
  final bool failOpen;

  CameraDevice? openedWith;
  int openCount = 0;
  bool _open = false;

  @override
  Future<List<CameraDevice>> listDevices() async {
    if (!enumerable) throw UnimplementedError('discovery is planned');
    return _devices;
  }

  @override
  Future<void> open(
    CameraDevice device, {
    Duration timeout = kDefaultCameraTimeout,
  }) async {
    openedWith = device;
    openCount++;
    if (failOpen) {
      _open = false;
      throw StateError('camera unreachable');
    }
    _open = true;
  }

  @override
  Future<void> close() async => _open = false;

  @override
  bool get isOpen => _open;

  @override
  CameraCapabilities get capabilities {
    if (!_open) throw StateError('RecordingAdapter: no device is open.');
    return const CameraCapabilities();
  }

  @override
  Widget buildPreview() => const SizedBox.shrink(key: Key('preview'));

  @override
  Future<Uint8List> captureFrame({
    Duration timeout = kDefaultCameraTimeout,
  }) async =>
      Uint8List(0);

  @override
  Future<void> setZoom(
    double factor, {
    Duration timeout = kDefaultCameraTimeout,
  }) async {}
}

class FakeProfileStore implements CameraProfileStore {
  FakeProfileStore([List<CameraProfile>? initial])
      : saved = List.of(initial ?? const <CameraProfile>[]);

  final List<CameraProfile> saved;

  @override
  Future<List<CameraProfile>> loadAll() async => List.of(saved);

  @override
  Future<void> save(CameraProfile profile) async {
    saved.removeWhere((p) => p.id == profile.id);
    saved.add(profile);
  }

  @override
  Future<void> delete(String id) async => saved.removeWhere((p) => p.id == id);

  @override
  Future<void> setDefault(String id) async {
    for (var i = 0; i < saved.length; i++) {
      saved[i] = saved[i].copyWith(isDefault: saved[i].id == id);
    }
  }
}

class FakeSecretStore implements CameraSecretStore {
  final Map<String, String> secrets = <String, String>{};

  @override
  Future<String?> getSecret(String profileId, String key) async =>
      secrets['$profileId/$key'];

  @override
  Future<void> setSecret(String profileId, String key, String value) async =>
      secrets['$profileId/$key'] = value;

  @override
  Future<void> deleteSecretsForProfile(String profileId) async =>
      secrets.removeWhere((k, _) => k.startsWith('$profileId/'));
}

CameraProfile buildProfile({
  required String id,
  String backendType = 'builtin',
  String name = 'Cam',
  bool isDefault = false,
  DateTime? createdAt,
  CameraDevice? device,
}) {
  return CameraProfile(
    id: id,
    backendType: backendType,
    displayName: name,
    device: device ?? CameraDevice(id: 'dev-$id', name: name),
    createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
    isDefault: isDefault,
  );
}
