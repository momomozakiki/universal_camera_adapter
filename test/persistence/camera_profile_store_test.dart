import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = SharedPreferencesCameraProfileStore.storageKey;

  CameraProfile profile({
    required String id,
    String backendType = 'builtin',
    String name = 'Camera',
    bool isDefault = false,
    DateTime? createdAt,
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) {
    return CameraProfile(
      id: id,
      backendType: backendType,
      displayName: name,
      device: CameraDevice(
        id: 'dev-$id',
        name: name,
        lensFacing: CameraLensFacing.external,
        metadata: metadata,
      ),
      createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
      isDefault: isDefault,
    );
  }

  group('SharedPreferencesCameraProfileStore', () {
    late SharedPreferencesCameraProfileStore store;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      store = SharedPreferencesCameraProfileStore();
    });

    test('empty store loads an empty list', () async {
      expect(await store.loadAll(), isEmpty);
    });

    test('save then loadAll round-trips every field', () async {
      final saved = profile(
        id: 'a',
        backendType: 'onvif',
        name: 'Front Door',
        createdAt: DateTime.utc(2026, 7, 23, 10, 30),
        metadata: <String, dynamic>{'host': '192.168.1.50', 'port': 80},
      );
      await store.save(saved);

      final loaded = await store.loadAll();
      expect(loaded, hasLength(1));
      final got = loaded.single;
      expect(got.id, 'a');
      expect(got.backendType, 'onvif');
      expect(got.displayName, 'Front Door');
      expect(got.createdAt, DateTime.utc(2026, 7, 23, 10, 30));
      expect(got.device.id, 'dev-a');
      expect(got.device.lensFacing, CameraLensFacing.external);
      expect(got.device.metadata['host'], '192.168.1.50');
      expect(got.device.metadata['port'], 80);
      // Full value-equality also holds (proves nothing silently dropped).
      expect(got, saved);
    });

    test('save updates an existing profile in place (matched by id)', () async {
      await store.save(profile(id: 'a', name: 'Old'));
      await store.save(profile(id: 'a', name: 'New'));
      final loaded = await store.loadAll();
      expect(loaded, hasLength(1));
      expect(loaded.single.displayName, 'New');
    });

    test('saving a default flips every other default off', () async {
      await store.save(profile(id: 'a', isDefault: true));
      await store.save(profile(id: 'b', isDefault: true));
      final loaded = await store.loadAll();
      expect(loaded.firstWhere((p) => p.id == 'a').isDefault, isFalse);
      expect(loaded.firstWhere((p) => p.id == 'b').isDefault, isTrue);
      expect(loaded.where((p) => p.isDefault), hasLength(1));
    });

    test('setDefault moves the flag to exactly one profile', () async {
      await store.save(profile(id: 'a', isDefault: true));
      await store.save(profile(id: 'b'));
      await store.setDefault('b');
      final loaded = await store.loadAll();
      expect(loaded.firstWhere((p) => p.id == 'a').isDefault, isFalse);
      expect(loaded.firstWhere((p) => p.id == 'b').isDefault, isTrue);
    });

    test('setDefault throws ArgumentError for an unknown id', () async {
      await store.save(profile(id: 'a'));
      expect(() => store.setDefault('missing'), throwsArgumentError);
    });

    test('deleting a non-default leaves the default untouched', () async {
      await store.save(profile(id: 'a', isDefault: true));
      await store.save(profile(id: 'b'));
      await store.delete('b');
      final loaded = await store.loadAll();
      expect(loaded, hasLength(1));
      expect(loaded.single.id, 'a');
      expect(loaded.single.isDefault, isTrue);
    });

    test('deleting the default promotes the most-recent remaining', () async {
      await store.save(profile(id: 'a', isDefault: true, createdAt: DateTime.utc(2026, 1, 1)));
      await store.save(profile(id: 'b', createdAt: DateTime.utc(2026, 3, 1)));
      await store.save(profile(id: 'c', createdAt: DateTime.utc(2026, 2, 1)));
      await store.delete('a');
      final loaded = await store.loadAll();
      // 'b' is the most recent of the survivors, so it becomes default.
      expect(loaded.firstWhere((p) => p.id == 'b').isDefault, isTrue);
      expect(loaded.firstWhere((p) => p.id == 'c').isDefault, isFalse);
      expect(loaded.where((p) => p.isDefault), hasLength(1));
    });

    test('deleting the last profile leaves an empty store with no default', () async {
      await store.save(profile(id: 'a', isDefault: true));
      await store.delete('a');
      expect(await store.loadAll(), isEmpty);
    });

    test('malformed JSON loads as empty (never throws)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{key: 'not json {'});
      expect(await SharedPreferencesCameraProfileStore().loadAll(), isEmpty);
    });

    test('an unknown schema version loads as empty', () async {
      final envelope = jsonEncode(<String, dynamic>{
        'version': 999,
        'profiles': <dynamic>[profile(id: 'a').toJson()],
      });
      SharedPreferences.setMockInitialValues(<String, Object>{key: envelope});
      expect(await SharedPreferencesCameraProfileStore().loadAll(), isEmpty);
    });

    test('a single malformed profile entry is skipped, valid ones kept', () async {
      final envelope = jsonEncode(<String, dynamic>{
        'version': SharedPreferencesCameraProfileStore.schemaVersion,
        'profiles': <dynamic>[
          profile(id: 'good').toJson(),
          <String, dynamic>{'id': 'bad-no-device'}, // missing device → skipped
          'garbage', // not even a map → skipped
        ],
      });
      SharedPreferences.setMockInitialValues(<String, Object>{key: envelope});
      final loaded = await SharedPreferencesCameraProfileStore().loadAll();
      expect(loaded, hasLength(1));
      expect(loaded.single.id, 'good');
    });
  });

  group('CameraProfile', () {
    test('create() mints a v4 UUID and a UTC createdAt', () {
      final p = CameraProfile.create(
        backendType: 'onvif',
        displayName: 'Cam',
        device: const CameraDevice(id: '1', name: 'Cam'),
      );
      expect(p.createdAt.isUtc, isTrue);
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(p.id),
        isTrue,
        reason: 'id should be an RFC-4122 v4 UUID, got ${p.id}',
      );
    });

    test('fromJson returns null when id or device is missing', () {
      expect(CameraProfile.fromJson('not a map'), isNull);
      expect(CameraProfile.fromJson(<String, dynamic>{'device': <String, dynamic>{'id': '1', 'name': 'x'}}), isNull);
      expect(CameraProfile.fromJson(<String, dynamic>{'id': 'a'}), isNull);
    });

    test('fromJson falls back on wrong-typed optional fields', () {
      final p = CameraProfile.fromJson(<String, dynamic>{
        'id': 'a',
        'backendType': 123, // wrong type → ''
        'device': <String, dynamic>{'id': '1', 'name': 'Cam', 'lensFacing': 'bogus'},
        'createdAt': 'not-a-date',
        'isDefault': 'yes', // not true → false
      });
      expect(p, isNotNull);
      expect(p!.backendType, '');
      expect(p.displayName, 'Cam'); // falls back to device name
      expect(p.device.lensFacing, CameraLensFacing.unknown);
      expect(p.isDefault, isFalse);
    });
  });
}
