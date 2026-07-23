import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';
import 'package:universal_camera_adapter_example/camera_session.dart';

/// Records the device it was actually opened with, so the transient
/// secret-merge can be asserted from the adapter's side.
class _RecordingAdapter extends CameraAdapter {
  _RecordingAdapter(this._devices, {this.enumerable = true, this.failOpen = false});

  final List<CameraDevice> _devices;

  /// When false, [listDevices] throws `UnimplementedError` the way
  /// `ONVIFCameraAdapter` does today (WS-Discovery deferred).
  final bool enumerable;

  final bool failOpen;

  CameraDevice? openedWith;
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
    if (failOpen) throw StateError('camera unreachable');
    _open = true;
  }

  @override
  Future<void> close() async => _open = false;

  @override
  bool get isOpen => _open;

  @override
  CameraCapabilities get capabilities {
    if (!_open) throw StateError('_RecordingAdapter: no device is open.');
    return const CameraCapabilities();
  }

  @override
  Widget buildPreview() => const SizedBox.shrink();

  @override
  Future<Uint8List> captureFrame({
    Duration timeout = kDefaultCameraTimeout,
  }) async => Uint8List(0);

  @override
  Future<void> setZoom(
    double factor, {
    Duration timeout = kDefaultCameraTimeout,
  }) async {}
}

class _FakeProfileStore implements CameraProfileStore {
  _FakeProfileStore([List<CameraProfile>? initial])
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

class _FakeSecretStore implements CameraSecretStore {
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

CameraProfile profile({
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

void main() {
  group('CameraSession — restore', () {
    test('opens the profile flagged default', () async {
      final adapter = _RecordingAdapter(const [
        CameraDevice(id: 'dev-a', name: 'A'),
        CameraDevice(id: 'dev-b', name: 'B'),
      ]);
      final registry = CameraAdapterRegistry()
        ..register('builtin', () => adapter, asDefault: true);
      final store = _FakeProfileStore([
        profile(id: 'a'),
        profile(id: 'b', isDefault: true),
      ]);

      final session = CameraSession(registry, profileStore: store);
      await session.restore();

      expect(session.activeProfile?.id, 'b');
      expect(adapter.openedWith?.id, 'dev-b');
      expect(session.isOpen, isTrue);
    });

    test('falls back to the most recent when nothing is flagged', () async {
      final adapter = _RecordingAdapter(const [
        CameraDevice(id: 'dev-old', name: 'Old'),
        CameraDevice(id: 'dev-new', name: 'New'),
      ]);
      final registry = CameraAdapterRegistry()
        ..register('builtin', () => adapter, asDefault: true);
      final store = _FakeProfileStore([
        profile(id: 'old', createdAt: DateTime.utc(2026, 1, 1)),
        profile(id: 'new', createdAt: DateTime.utc(2026, 6, 1)),
      ]);

      final session = CameraSession(registry, profileStore: store);
      await session.restore();

      expect(session.activeProfile?.id, 'new');
    });

    test('an empty store falls back to live discovery and persists nothing',
        () async {
      final adapter = _RecordingAdapter(const [
        CameraDevice(id: 'dev-1', name: 'Webcam'),
      ]);
      final registry = CameraAdapterRegistry()
        ..register('builtin', () => adapter, asDefault: true);
      final store = _FakeProfileStore();

      final session = CameraSession(registry, profileStore: store);
      await session.restore();

      // Devices listed and one selected, but nothing opened and no synthetic
      // profile invented — exactly the pre-profiles behaviour.
      expect(session.devices.map((d) => d.id), ['dev-1']);
      expect(session.selectedId, 'dev-1');
      expect(session.isOpen, isFalse);
      expect(session.activeProfile, isNull);
      expect(store.saved, isEmpty);
    });

    test('works without any stores injected (headless / existing callers)',
        () async {
      final adapter = _RecordingAdapter(const [
        CameraDevice(id: 'dev-1', name: 'Webcam'),
      ]);
      final registry = CameraAdapterRegistry()
        ..register('builtin', () => adapter, asDefault: true);

      final session = CameraSession(registry);
      await session.restore();

      expect(session.profiles, isEmpty);
      expect(session.devices, hasLength(1));
    });
  });

  group('CameraSession — re-validation match keys', () {
    test('builtin: a profile whose device vanished is marked unavailable',
        () async {
      // The camera was unplugged: enumeration succeeds but no longer lists it.
      final adapter = _RecordingAdapter(const [
        CameraDevice(id: 'dev-other', name: 'Other'),
      ]);
      final registry = CameraAdapterRegistry()
        ..register('builtin', () => adapter, asDefault: true);
      final store = _FakeProfileStore([profile(id: 'gone', isDefault: true)]);

      final session = CameraSession(registry, profileStore: store);
      await session.restore();

      expect(session.unavailableProfileIds, contains('gone'));
      expect(adapter.openedWith, isNull, reason: 'must not open a stale device');
      expect(session.activeProfile, isNull);
      // Still usable: falls back to discovery rather than a dead screen.
      expect(session.devices, hasLength(1));
    });

    test('onvif: matches on host+port even when the device id differs', () async {
      // An ONVIF id can be a URN that changes across reboots; the endpoint is
      // the real identity.
      const live = CameraDevice(
        id: 'urn:uuid:completely-different',
        name: 'Front door',
        metadata: {'host': '192.168.0.217', 'port': 80},
      );
      final adapter = _RecordingAdapter(const [live]);
      final registry = CameraAdapterRegistry()
        ..register('onvif', () => adapter, asDefault: true);
      final store = _FakeProfileStore([
        profile(
          id: 'p1',
          backendType: 'onvif',
          isDefault: true,
          device: const CameraDevice(
            id: '192.168.0.217:80',
            name: 'Front door',
            metadata: {'host': '192.168.0.217', 'port': 80},
          ),
        ),
      ]);

      final session = CameraSession(registry, profileStore: store);
      await session.restore();

      expect(session.activeProfile?.id, 'p1');
      expect(adapter.openedWith?.id, live.id);
    });

    test('onvif: a different host does not match', () async {
      const live = CameraDevice(
        id: 'x',
        name: 'Other camera',
        metadata: {'host': '10.0.0.9', 'port': 80},
      );
      final adapter = _RecordingAdapter(const [live]);
      final registry = CameraAdapterRegistry()
        ..register('onvif', () => adapter, asDefault: true);
      final store = _FakeProfileStore([
        profile(
          id: 'p1',
          backendType: 'onvif',
          isDefault: true,
          device: const CameraDevice(
            id: '192.168.0.217:80',
            name: 'Front door',
            metadata: {'host': '192.168.0.217', 'port': 80},
          ),
        ),
      ]);

      final session = CameraSession(registry, profileStore: store);
      await session.restore();

      expect(session.unavailableProfileIds, contains('p1'));
    });

    test('a non-enumerable backend skips discovery and opens directly',
        () async {
      // ONVIFCameraAdapter.listDevices() throws UnimplementedError today.
      // Restore must not surface that as a failure — open() is the validation.
      final adapter = _RecordingAdapter(const [], enumerable: false);
      final registry = CameraAdapterRegistry()
        ..register('onvif', () => adapter, asDefault: true);
      final store = _FakeProfileStore([
        profile(id: 'p1', backendType: 'onvif', isDefault: true),
      ]);

      final session = CameraSession(registry, profileStore: store);
      await session.restore();

      expect(session.activeProfile?.id, 'p1');
      expect(adapter.openedWith?.id, 'dev-p1');
      expect(session.unavailableProfileIds, isEmpty);
    });

    test('an unreachable camera surfaces an error and clears activeProfile',
        () async {
      final adapter =
          _RecordingAdapter(const [], enumerable: false, failOpen: true);
      final registry = CameraAdapterRegistry()
        ..register('onvif', () => adapter, asDefault: true);
      final store = _FakeProfileStore([
        profile(id: 'p1', backendType: 'onvif', isDefault: true),
      ]);

      final session = CameraSession(registry, profileStore: store);
      await session.restore();

      expect(session.isOpen, isFalse);
      expect(session.activeProfile, isNull);
      expect(session.error, isNotNull);
    });
  });

  group('CameraSession — secret transport', () {
    test('the secret reaches the adapter but never session state', () async {
      final adapter = _RecordingAdapter(const [
        CameraDevice(
          id: '192.168.0.217:80',
          name: 'Front door',
          metadata: {'host': '192.168.0.217', 'port': 80},
        ),
      ]);
      final registry = CameraAdapterRegistry()
        ..register('onvif', () => adapter, asDefault: true);
      final saved = profile(
        id: 'p1',
        backendType: 'onvif',
        isDefault: true,
        device: const CameraDevice(
          id: '192.168.0.217:80',
          name: 'Front door',
          metadata: {'host': '192.168.0.217', 'port': 80},
        ),
      );
      final store = _FakeProfileStore([saved]);
      final secrets = _FakeSecretStore()..secrets['p1/password'] = 'hunter2';

      final session = CameraSession(
        registry,
        profileStore: store,
        secretStore: secrets,
      );
      await session.restore();

      // Reached the adapter…
      expect(adapter.openedWith?.metadata['password'], 'hunter2');
      // …but is absent from the persisted profile…
      expect(store.saved.single.device.metadata.containsKey('password'), isFalse);
      // …and from the device the session retained, so a later plain open()
      // cannot silently reuse it and a debug dump cannot leak it.
      expect(
        session.selectedDevice?.metadata.containsKey('password'),
        isFalse,
      );
    });

    test('no stored secret means nothing is merged', () async {
      final adapter = _RecordingAdapter(const [
        CameraDevice(id: 'dev-p1', name: 'Cam'),
      ]);
      final registry = CameraAdapterRegistry()
        ..register('builtin', () => adapter, asDefault: true);
      final store = _FakeProfileStore([profile(id: 'p1', isDefault: true)]);

      final session = CameraSession(
        registry,
        profileStore: store,
        secretStore: _FakeSecretStore(),
      );
      await session.restore();

      expect(adapter.openedWith?.metadata.containsKey('password'), isFalse);
    });
  });

  group('CameraSession — profile management', () {
    test('deleting a profile also deletes its secrets', () async {
      final adapter = _RecordingAdapter(const [
        CameraDevice(id: 'dev-p1', name: 'Cam'),
      ]);
      final registry = CameraAdapterRegistry()
        ..register('builtin', () => adapter, asDefault: true);
      final store = _FakeProfileStore([profile(id: 'p1')]);
      final secrets = _FakeSecretStore()..secrets['p1/password'] = 'hunter2';

      final session = CameraSession(
        registry,
        profileStore: store,
        secretStore: secrets,
      );
      await session.loadProfiles();
      await session.deleteProfile('p1');

      expect(store.saved, isEmpty);
      expect(secrets.secrets, isEmpty,
          reason: 'a secret outliving its profile is unreachable and undeletable');
      expect(session.profiles, isEmpty);
    });

    test('saveAndSwitchTo persists then opens', () async {
      final adapter = _RecordingAdapter(const [
        CameraDevice(id: 'dev-new', name: 'New cam'),
      ]);
      final registry = CameraAdapterRegistry()
        ..register('builtin', () => adapter, asDefault: true);
      final store = _FakeProfileStore();

      final session = CameraSession(registry, profileStore: store);
      await session.saveAndSwitchTo(profile(id: 'new', device: const CameraDevice(id: 'dev-new', name: 'New cam')));

      expect(store.saved.single.id, 'new');
      expect(session.activeProfile?.id, 'new');
      expect(adapter.openedWith?.id, 'dev-new');
    });
  });

  group('CameraSession — updateProfile', () {
    test('persists the edit without adding a second profile', () async {
      final adapter = _RecordingAdapter(const [
        CameraDevice(id: 'dev-p1', name: 'Cam'),
      ]);
      final registry = CameraAdapterRegistry()
        ..register('builtin', () => adapter, asDefault: true);
      final store = _FakeProfileStore([profile(id: 'p1', name: 'Old name')]);

      final session = CameraSession(registry, profileStore: store);
      await session.loadProfiles();
      await session.updateProfile(
        session.profiles.single.copyWith(displayName: 'New name'),
      );

      expect(store.saved, hasLength(1), reason: 'save() upserts on id');
      expect(store.saved.single.displayName, 'New name');
      expect(session.profiles.single.displayName, 'New name');
    });

    test('editing the active camera re-opens it on the new settings', () async {
      final adapter = _RecordingAdapter(const [
        CameraDevice(id: 'dev-p1', name: 'Cam'),
        CameraDevice(id: 'dev-p2', name: 'Cam moved'),
      ]);
      final registry = CameraAdapterRegistry()
        ..register('builtin', () => adapter, asDefault: true);
      final store = _FakeProfileStore([profile(id: 'p1')]);

      final session = CameraSession(registry, profileStore: store);
      await session.restore();
      expect(adapter.openedWith?.id, 'dev-p1');

      await session.updateProfile(
        session.profiles.single.copyWith(
          device: const CameraDevice(id: 'dev-p2', name: 'Cam moved'),
        ),
      );

      expect(adapter.openedWith?.id, 'dev-p2');
      expect(session.activeProfile?.id, 'p1', reason: 'same profile identity');
    });

    test('editing an idle camera leaves the live one alone', () async {
      final adapter = _RecordingAdapter(const [
        CameraDevice(id: 'dev-live', name: 'Live'),
        CameraDevice(id: 'dev-idle', name: 'Idle'),
      ]);
      final registry = CameraAdapterRegistry()
        ..register('builtin', () => adapter, asDefault: true);
      final store = _FakeProfileStore([
        profile(
          id: 'live',
          isDefault: true,
          device: const CameraDevice(id: 'dev-live', name: 'Live'),
        ),
        profile(
          id: 'idle',
          device: const CameraDevice(id: 'dev-idle', name: 'Idle'),
        ),
      ]);

      final session = CameraSession(registry, profileStore: store);
      await session.restore();
      expect(session.activeProfile?.id, 'live');

      final idle = session.profiles.firstWhere((p) => p.id == 'idle');
      await session.updateProfile(idle.copyWith(displayName: 'Renamed'));

      expect(adapter.openedWith?.id, 'dev-live',
          reason: 'editing an idle camera must not steal the live one');
      expect(session.activeProfile?.id, 'live');
      expect(
        session.profiles.firstWhere((p) => p.id == 'idle').displayName,
        'Renamed',
      );
    });

    test('is a no-op without a profile store', () async {
      final adapter = _RecordingAdapter(const [
        CameraDevice(id: 'dev-p1', name: 'Cam'),
      ]);
      final registry = CameraAdapterRegistry()
        ..register('builtin', () => adapter, asDefault: true);

      final session = CameraSession(registry);
      await session.updateProfile(profile(id: 'p1'));

      expect(session.profiles, isEmpty);
    });
  });
}
