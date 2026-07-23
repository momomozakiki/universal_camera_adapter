import 'package:flutter_test/flutter_test.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';
import 'package:universal_camera_adapter_example/adapter_types.dart';
import 'package:universal_camera_adapter_example/setup/onvif_setup_wizard.dart';

/// Covers the security-critical half of `OnvifSetupWizard`: which fields end up
/// in the persisted (plaintext, loggable) profile versus the transient device
/// handed to `open()`. Pure — no widgets, no network, no platform channels.
void main() {
  OnvifSetupDraft draft({
    String host = '192.168.0.217',
    String port = '80',
    String username = 'admin',
    String password = 'hunter2',
    String displayName = 'Front door',
  }) {
    return buildOnvifSetupDraft(
      host: host,
      port: port,
      username: username,
      password: password,
      displayName: displayName,
    );
  }

  group('buildOnvifSetupDraft — secret split', () {
    test('the persisted profile never carries the password', () {
      final result = draft();
      expect(result.profile.device.metadata.containsKey('password'), isFalse);
      // Belt and braces: nothing anywhere in the profile stringifies to it.
      expect(result.profile.toJson().toString(), isNot(contains('hunter2')));
    });

    test('the transient device does carry it, for open()', () {
      final result = draft();
      expect(result.password, 'hunter2');
      expect(result.connectableDevice.metadata['password'], 'hunter2');
      // And is a *copy* — the profile's own device is untouched.
      expect(result.profile.device.metadata.containsKey('password'), isFalse);
    });

    test('the transient device is exactly what the adapter can parse', () {
      // Proves the wizard and ONVIFCameraAdapter.open() agree on the shape.
      final credentials = OnvifCredentials.fromMetadata(
        draft().connectableDevice.metadata,
      );
      expect(credentials.host, '192.168.0.217');
      expect(credentials.port, 80);
      expect(credentials.username, 'admin');
      expect(credentials.password, 'hunter2');
    });

    test('no password means no secret to write', () {
      final result = draft(password: '');
      expect(result.password, isNull);
      // connectableDevice is then the persisted device itself — nothing merged.
      expect(result.connectableDevice.metadata.containsKey('password'), isFalse);
      expect(result.connectableDevice, result.profile.device);
    });
  });

  group('buildOnvifSetupDraft — profile shape', () {
    test('non-secret connection details round-trip into metadata', () {
      final metadata = draft(port: '8000').profile.device.metadata;
      expect(metadata['host'], '192.168.0.217');
      expect(metadata['port'], 8000);
      expect(metadata['username'], 'admin');
    });

    test('a blank port persists the normalized default, not empty text', () {
      // The raw field is a String; what gets stored must be the parsed int, or
      // a later restore would carry '' and fail differently than a fresh setup.
      final metadata = draft(port: '').profile.device.metadata;
      expect(metadata['port'], kDefaultOnvifPort);
      expect(metadata['port'], isA<int>());
    });

    test('a numeric-String port is normalized to an int', () {
      expect(draft(port: '8000').profile.device.metadata['port'], 8000);
    });

    test('backendType matches the registered adapter type', () {
      expect(draft().profile.backendType, kOnvifAdapterType);
    });

    test('device id is host:port — the key a restore matches on', () {
      expect(draft(port: '8000').profile.device.id, '192.168.0.217:8000');
    });

    test('a blank name falls back to the host', () {
      final result = draft(displayName: '   ');
      expect(result.profile.displayName, '192.168.0.217');
      expect(result.profile.device.name, '192.168.0.217');
    });

    test('fields are trimmed', () {
      final result = draft(
        host: '  192.168.0.217  ',
        username: '  admin  ',
        displayName: '  Front door  ',
      );
      expect(result.profile.device.metadata['host'], '192.168.0.217');
      expect(result.profile.device.metadata['username'], 'admin');
      expect(result.profile.displayName, 'Front door');
    });

    test('a blank username is omitted rather than stored empty', () {
      final metadata = draft(username: '  ').profile.device.metadata;
      expect(metadata.containsKey('username'), isFalse);
    });

    test('each call mints a distinct profile id', () {
      // Two cameras added in a row must not collide — the id keys their secrets.
      expect(draft().profile.id, isNot(draft().profile.id));
    });

    test('lensFacing is external', () {
      expect(draft().profile.device.lensFacing, CameraLensFacing.external);
    });
  });

  group('buildOnvifSetupDraft — validation happens before any network work', () {
    test('a missing host throws StateError', () {
      expect(() => draft(host: '   '), throwsStateError);
    });

    test('a malformed port throws FormatException', () {
      expect(() => draft(port: 'abc'), throwsA(isA<FormatException>()));
      expect(() => draft(port: '0'), throwsA(isA<FormatException>()));
      expect(() => draft(port: '99999'), throwsA(isA<FormatException>()));
    });

    test('validation errors never echo the password', () {
      Object? caught;
      try {
        draft(port: 'abc', password: 'hunter2');
      } on Object catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      expect(caught.toString(), isNot(contains('hunter2')));
    });
  });
}
