import 'package:flutter_test/flutter_test.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';
import 'package:universal_camera_adapter_example/camera_session.dart';

import 'support/session_fakes.dart';

void main() {
  group('CameraSession — selectedProfileId', () {
    test('falls back to the active profile when nothing is selected', () async {
      final adapter = RecordingAdapter(const [
        CameraDevice(id: 'dev-a', name: 'A'),
      ]);
      final registry = CameraAdapterRegistry()
        ..register('builtin', () => adapter, asDefault: true);
      final store = FakeProfileStore([buildProfile(id: 'a', isDefault: true)]);

      final session = CameraSession(registry, profileStore: store);
      await session.restore();

      // No explicit selectProfile, but the dropdown still reflects the live one.
      expect(session.activeProfile?.id, 'a');
      expect(session.selectedProfileId, 'a');
    });

    test('selectProfile overrides the fallback and notifies listeners',
        () async {
      final adapter = RecordingAdapter(const [
        CameraDevice(id: 'dev-a', name: 'A'),
      ]);
      final registry = CameraAdapterRegistry()
        ..register('builtin', () => adapter, asDefault: true);
      final store = FakeProfileStore([
        buildProfile(id: 'a', isDefault: true),
        buildProfile(id: 'b'),
      ]);

      final session = CameraSession(registry, profileStore: store);
      await session.restore();

      var notified = 0;
      session.addListener(() => notified++);
      session.selectProfile('b');

      expect(session.selectedProfileId, 'b');
      expect(notified, greaterThan(0));
    });
  });

  group('CameraSession — connectSelectedProfile', () {
    test('connects the targeted profile through the secret-merging path',
        () async {
      // ONVIF-shaped: non-enumerable, credential merged from the secret store.
      final adapter = RecordingAdapter(const [], enumerable: false);
      final registry = CameraAdapterRegistry()
        ..register('onvif', () => adapter, asDefault: true);
      final store = FakeProfileStore([
        buildProfile(id: 'p1', backendType: 'onvif'),
      ]);
      final secrets = FakeSecretStore()..secrets['p1/password'] = 'hunter2';

      final session = CameraSession(
        registry,
        profileStore: store,
        secretStore: secrets,
      );
      await session.loadProfiles();
      session.selectProfile('p1');
      await session.connectSelectedProfile();

      expect(session.isOpen, isTrue);
      expect(session.activeProfile?.id, 'p1');
      // The credential reached the adapter — the reconnect bug this fixes.
      expect(adapter.openedWith?.metadata['password'], 'hunter2');
    });

    test('a missing target clears the selection and reports it', () async {
      final adapter = RecordingAdapter(const [
        CameraDevice(id: 'dev-a', name: 'A'),
      ]);
      final registry = CameraAdapterRegistry()
        ..register('builtin', () => adapter, asDefault: true);
      final session = CameraSession(registry, profileStore: FakeProfileStore());

      session.selectProfile('ghost');
      await session.connectSelectedProfile();

      expect(session.selectedProfileId, isNull);
      expect(session.error, 'That camera is no longer saved.');
      expect(adapter.openCount, 0);
    });

    test('rolls the selection back when the connect fails to open', () async {
      final adapter =
          RecordingAdapter(const [], enumerable: false, failOpen: true);
      final registry = CameraAdapterRegistry()
        ..register('onvif', () => adapter, asDefault: true);
      final store = FakeProfileStore([
        buildProfile(id: 'p1', backendType: 'onvif'),
      ]);

      final session = CameraSession(registry, profileStore: store);
      await session.loadProfiles();
      session.selectProfile('p1');
      await session.connectSelectedProfile();

      expect(session.isOpen, isFalse);
      // Rolled back off the failed profile rather than pinned to it…
      expect(session.selectedProfileId, isNull);
      // …with the adapter's own error surfaced, not the "no longer saved" one.
      expect(session.error, isNot('That camera is no longer saved.'));
      expect(session.error, isNotNull);
    });
  });

  group('CameraSession — deleteProfile clears selection', () {
    test('drops _selectedProfileId when it pointed at the deleted profile',
        () async {
      final adapter = RecordingAdapter(const [
        CameraDevice(id: 'dev-p1', name: 'Cam'),
      ]);
      final registry = CameraAdapterRegistry()
        ..register('builtin', () => adapter, asDefault: true);
      final store = FakeProfileStore([buildProfile(id: 'p1')]);

      final session = CameraSession(registry, profileStore: store);
      await session.loadProfiles();
      session.selectProfile('p1');
      await session.deleteProfile('p1');

      // Without the clear, the getter would still echo the stale 'p1'.
      expect(session.selectedProfileId, isNull);
    });
  });

  group('CameraSession — refreshDevices hardening', () {
    test('treats a non-enumerable backend as a no-op, not an error', () async {
      final adapter = RecordingAdapter(const [], enumerable: false);
      final registry = CameraAdapterRegistry()
        ..register('onvif', () => adapter, asDefault: true);

      final session = CameraSession(registry);
      await session.refreshDevices();

      expect(session.error, isNull);
      expect(session.busy, isFalse);
    });
  });
}
