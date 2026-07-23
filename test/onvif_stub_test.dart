import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

void main() {
  group('ONVIFCameraAdapter (scaffolding)', () {
    test('registers under "onvif" and is a CameraAdapter', () {
      final registry = CameraAdapterRegistry()
        ..register('onvif', ONVIFCameraAdapter.new);
      expect(registry.isRegistered('onvif'), isTrue);
      expect(registry.create('onvif'), isA<CameraAdapter>());
    });

    test('is not open and close() is a safe no-op', () async {
      final adapter = ONVIFCameraAdapter();
      expect(adapter.isOpen, isFalse);
      await adapter.close(); // must not throw
    });

    test('still-planned methods throw UnimplementedError (capture/PTZ/discovery)', () async {
      final adapter = ONVIFCameraAdapter(
        credentials: const OnvifCredentials(host: '192.168.1.100'),
      );
      await expectLater(adapter.listDevices(), throwsUnimplementedError);
      expect(() => adapter.capabilities, throwsUnimplementedError);
      await expectLater(adapter.captureFrame(), throwsUnimplementedError);
    });

    test('buildPreview before open throws StateError (implemented, not planned)', () {
      final adapter = ONVIFCameraAdapter(
        credentials: const OnvifCredentials(host: '192.168.1.100'),
      );
      expect(adapter.buildPreview, throwsA(isA<StateError>()));
    });

    test(
      'open() throws StateError when neither the constructor nor device.metadata '
      'supplies a host',
      () async {
        // Credentials are no longer constructor-only: open() falls back to
        // OnvifCredentials.fromMetadata(device.metadata). With both empty there
        // is still no host, so the StateError now originates from that parse.
        final adapter = ONVIFCameraAdapter();
        await expectLater(
          adapter.open(const CameraDevice(id: 'x', name: 'x')),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('credentials redact the password in toString', () {
      const creds = OnvifCredentials(
        host: 'cam.local',
        username: 'admin',
        password: 'hunter2',
      );
      expect(creds.toString(), isNot(contains('hunter2')));
      expect(creds.toString(), contains('redacted'));
    });
  });

  group('OnvifCredentials.fromMetadata', () {
    OnvifCredentials parse(Map<String, dynamic> metadata) =>
        OnvifCredentials.fromMetadata(metadata);

    test('reads a full, well-formed map', () {
      final creds = parse(<String, dynamic>{
        'host': '192.168.0.217',
        'port': 8000,
        'username': 'admin',
        'password': 'hunter2',
      });
      expect(creds.host, '192.168.0.217');
      expect(creds.port, 8000);
      expect(creds.username, 'admin');
      expect(creds.password, 'hunter2');
    });

    test('host alone is enough; port defaults to 80', () {
      final creds = parse(<String, dynamic>{'host': 'cam.local'});
      expect(creds.host, 'cam.local');
      expect(creds.port, kDefaultOnvifPort);
      expect(creds.port, 80);
      expect(creds.username, isNull);
      expect(creds.password, isNull);
    });

    test('port survives a JSON/text round-trip as a numeric String', () {
      expect(parse(<String, dynamic>{'host': 'c', 'port': '8000'}).port, 8000);
      expect(parse(<String, dynamic>{'host': 'c', 'port': ' 554 '}).port, 554);
    });

    test('host is trimmed, and empty optional fields normalize to null', () {
      final creds = parse(<String, dynamic>{
        'host': '  cam.local  ',
        'username': '',
        'password': '',
      });
      expect(creds.host, 'cam.local');
      expect(creds.username, isNull);
      expect(creds.password, isNull);
    });

    test('unknown brand-specific keys are ignored, not fatal', () {
      // The point of ONVIF: extra vendor keys ride along harmlessly.
      final creds = parse(<String, dynamic>{
        'host': 'cam.local',
        'verificationCode': 'ABCDEF',
        'serialNumber': 'BK0381480',
      });
      expect(creds.host, 'cam.local');
    });

    test('an absent host is a StateError (missing config, not malformed)', () {
      expect(() => parse(<String, dynamic>{}), throwsStateError);
      expect(() => parse(<String, dynamic>{'port': 80}), throwsStateError);
    });

    test('a present-but-unusable host is a FormatException', () {
      expect(() => parse(<String, dynamic>{'host': 123}),
          throwsA(isA<FormatException>()));
      expect(() => parse(<String, dynamic>{'host': ''}),
          throwsA(isA<FormatException>()));
      expect(() => parse(<String, dynamic>{'host': '   '}),
          throwsA(isA<FormatException>()));
      expect(() => parse(<String, dynamic>{'host': 'a' * 256}),
          throwsA(isA<FormatException>()));
    });

    test('a malformed or out-of-range port is a FormatException', () {
      for (final bad in <Object>['abc', 0, -1, 65536, 3.5, <String>[]]) {
        expect(
          () => parse(<String, dynamic>{'host': 'cam.local', 'port': bad}),
          throwsA(isA<FormatException>()),
          reason: 'port: $bad should be rejected',
        );
      }
    });

    test('wrong-typed username/password are FormatExceptions', () {
      expect(() => parse(<String, dynamic>{'host': 'c', 'username': 42}),
          throwsA(isA<FormatException>()));
      expect(() => parse(<String, dynamic>{'host': 'c', 'password': true}),
          throwsA(isA<FormatException>()));
    });

    test('all problems are reported together, not just the first', () {
      Object? caught;
      try {
        parse(<String, dynamic>{'host': 123, 'port': 'abc', 'username': 7});
      } on Object catch (e) {
        caught = e;
      }
      expect(caught, isA<FormatException>());
      final message = caught.toString();
      expect(message, contains('host'));
      expect(message, contains('port'));
      expect(message, contains('username'));
    });

    test('a malformed-password error never echoes the password', () {
      // The parse reports the offending key's *type*, never its value — a
      // secret must not leak into an error message (`input-hardening` Rule 5).
      Object? caught;
      try {
        parse(<String, dynamic>{'host': 'cam.local', 'password': 12345});
      } on Object catch (e) {
        caught = e;
      }
      expect(caught, isA<FormatException>());
      expect(caught.toString(), isNot(contains('12345')));
    });

    test('credentials built from metadata still redact the password', () {
      final creds = parse(<String, dynamic>{
        'host': 'cam.local',
        'password': 'hunter2',
      });
      expect(creds.password, 'hunter2');
      expect(creds.toString(), isNot(contains('hunter2')));
      expect(creds.toString(), contains('redacted'));
    });

    test('open() uses device.metadata when no constructor credentials exist',
        () async {
      // The registry tear-off path: a zero-arg adapter must now get far enough
      // to attempt a connection instead of failing up front on a null field.
      // Reaching an unroutable host means the parse succeeded — the failure is
      // a real network outcome on the typed surface, not a StateError about
      // missing credentials.
      final adapter = ONVIFCameraAdapter();
      await expectLater(
        adapter.open(
          const CameraDevice(
            id: 'cam-1',
            name: 'Front Door',
            metadata: <String, dynamic>{'host': '192.0.2.1', 'port': 80},
          ),
          timeout: const Duration(milliseconds: 200),
        ),
        throwsA(anyOf(isA<TimeoutException>(), isA<StateError>())),
      );
      expect(adapter.isOpen, isFalse);
    });

    test('constructor credentials win over device.metadata', () async {
      // Precedence matters: onvif_connect_view.dart still constructs directly.
      final adapter = ONVIFCameraAdapter(
        credentials: const OnvifCredentials(host: '192.0.2.1'),
      );
      Object? caught;
      try {
        await adapter.open(
          // Deliberately malformed — it must never be parsed, because the
          // constructor value takes precedence.
          const CameraDevice(
            id: 'x',
            name: 'x',
            metadata: <String, dynamic>{'host': 123},
          ),
          timeout: const Duration(milliseconds: 200),
        );
      } on Object catch (e) {
        caught = e;
      }
      // It still fails (192.0.2.1 is unroutable TEST-NET-1), but with a network
      // outcome — never the FormatException the bad metadata would have caused.
      expect(caught, isNot(isA<FormatException>()));
      expect(caught, anyOf(isA<TimeoutException>(), isA<StateError>()));
    });
  });
}
