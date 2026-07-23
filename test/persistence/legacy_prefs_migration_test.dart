import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

/// In-memory [CameraProfileStore] — no `shared_preferences`, so the migration's
/// own prefs access is the only thing under test here.
class _FakeProfileStore implements CameraProfileStore {
  final List<CameraProfile> saved = <CameraProfile>[];

  @override
  Future<List<CameraProfile>> loadAll() async => List.of(saved);

  @override
  Future<void> save(CameraProfile profile) async => saved.add(profile);

  @override
  Future<void> delete(String id) async => saved.removeWhere((p) => p.id == id);

  @override
  Future<void> setDefault(String id) async {}
}

class _FakeSecretStore implements CameraSecretStore {
  _FakeSecretStore({this.failOnWrite = false});

  /// Simulates encrypted storage being unavailable, to prove a failed write
  /// leaves the legacy plaintext keys intact.
  final bool failOnWrite;

  final Map<String, String> secrets = <String, String>{};

  @override
  Future<String?> getSecret(String profileId, String key) async =>
      secrets['$profileId/$key'];

  @override
  Future<void> setSecret(String profileId, String key, String value) async {
    if (failOnWrite) throw StateError('secure storage unavailable');
    secrets['$profileId/$key'] = value;
  }

  @override
  Future<void> deleteSecretsForProfile(String profileId) async {
    secrets.removeWhere((k, _) => k.startsWith('$profileId/'));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const onvifSource = LegacyCameraSetup(
    backendType: 'onvif',
    displayName: 'Imported ONVIF camera',
    metadataKeys: <String, String>{
      'host': 'onvif_tab.host',
      'username': 'onvif_tab.username',
    },
    extraMetadata: <String, dynamic>{'port': 8000},
    secretPrefsKey: 'onvif_tab.password',
    secretName: 'password',
    requiredMetadataKey: 'host',
  );

  const legacyValues = <String, Object>{
    'onvif_tab.host': '192.168.0.217',
    'onvif_tab.username': 'admin',
    'onvif_tab.password': 'hunter2',
  };

  late _FakeProfileStore profiles;
  late _FakeSecretStore secrets;

  Future<int> run({
    _FakeSecretStore? secretStore,
    List<LegacyCameraSetup> sources = const <LegacyCameraSetup>[onvifSource],
  }) {
    return migrateLegacyCameraSetup(
      profileStore: profiles,
      secretStore: secretStore ?? secrets,
      sources: sources,
    );
  }

  setUp(() {
    profiles = _FakeProfileStore();
    secrets = _FakeSecretStore();
    SharedPreferences.setMockInitialValues(legacyValues);
  });

  group('migrateLegacyCameraSetup', () {
    test('imports a legacy camera into the profile and secret stores', () async {
      expect(await run(), 1);

      final profile = profiles.saved.single;
      expect(profile.backendType, 'onvif');
      expect(profile.device.metadata['host'], '192.168.0.217');
      expect(profile.device.metadata['username'], 'admin');
      // Never persisted by the old view, supplied via extraMetadata.
      expect(profile.device.metadata['port'], 8000);

      expect(secrets.secrets['${profile.id}/password'], 'hunter2');
    });

    test('the imported profile does not carry the password', () async {
      await run();
      final profile = profiles.saved.single;
      expect(profile.device.metadata.containsKey('password'), isFalse);
      expect(profile.toJson().toString(), isNot(contains('hunter2')));
    });

    test('legacy keys are removed once re-homed', () async {
      await run();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('onvif_tab.host'), isNull);
      expect(prefs.getString('onvif_tab.username'), isNull);
      expect(prefs.getString('onvif_tab.password'), isNull);
    });

    test('a second run is a no-op (guard set)', () async {
      expect(await run(), 1);
      expect(await run(), 0);
      expect(profiles.saved, hasLength(1));
    });

    test('nothing to migrate still sets the guard and imports nothing', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      expect(await run(), 0);
      expect(profiles.saved, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('uca.migrated_legacy_prefs'), isTrue);
    });

    test('a failed secret write leaves the legacy keys INTACT', () async {
      // The property that matters most: never delete a plaintext secret we
      // could not re-home. A failed migration must be retryable.
      final failing = _FakeSecretStore(failOnWrite: true);
      await expectLater(run(secretStore: failing), throwsStateError);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('onvif_tab.password'), 'hunter2');
      expect(prefs.getString('onvif_tab.host'), '192.168.0.217');
      expect(prefs.getBool('uca.migrated_legacy_prefs'), isNull);
      expect(profiles.saved, isEmpty);
    });

    test('a source with no usable config is skipped, its keys untouched', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'onvif_tab.username': 'admin', // no host → nothing to connect to
      });
      expect(await run(), 0);
      expect(profiles.saved, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('onvif_tab.username'), 'admin');
    });

    test('blank and wrong-typed legacy values are treated as absent', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'onvif_tab.host': '   ',
        'onvif_tab.username': 'admin',
      });
      expect(await run(), 0);
      expect(profiles.saved, isEmpty);
    });

    test('a wrong-typed key does not throw', () async {
      // Untrusted input: a hand-edited or version-skewed prefs file must not
      // brick startup.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'onvif_tab.host': 42,
        'onvif_tab.username': 'admin',
      });
      expect(await run(), 0);
    });

    test('an optional missing field is simply omitted', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'onvif_tab.host': '10.0.0.5',
      });
      expect(await run(), 1);
      final metadata = profiles.saved.single.device.metadata;
      expect(metadata['host'], '10.0.0.5');
      expect(metadata.containsKey('username'), isFalse);
    });

    test('multiple sources import independently', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        ...legacyValues,
        'ezviz_tab.verification_code': 'ABCDEF',
      });
      const ezvizSource = LegacyCameraSetup(
        backendType: 'ezviz',
        displayName: 'Imported EZVIZ camera',
        metadataKeys: <String, String>{'serial': 'ezviz_tab.serial'},
        secretPrefsKey: 'ezviz_tab.verification_code',
        secretName: 'verificationCode',
        requiredMetadataKey: 'serial',
      );
      // No serial was ever stored, so EZVIZ is correctly skipped while ONVIF
      // still imports — one unusable source must not block the others.
      expect(await run(sources: const [onvifSource, ezvizSource]), 1);
      expect(profiles.saved.single.backendType, 'onvif');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ezviz_tab.verification_code'), 'ABCDEF');
    });
  });
}
