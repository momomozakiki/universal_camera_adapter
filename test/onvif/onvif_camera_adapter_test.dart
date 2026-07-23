import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';
import 'package:universal_camera_adapter/src/onvif/onvif_http_client.dart';
import 'package:universal_camera_adapter/src/onvif/onvif_media_service.dart';
import 'package:universal_camera_adapter/src/onvif/rtsp_preview.dart';

/// A working fake media service: this test file is about the auth flow
/// (WS-UsernameToken/Digest), not GetProfiles/GetStreamUri, so [open] should
/// sail through media resolution by default. Tests that care about media
/// failures live in `onvif_media_service_test.dart`.
class _FakeMediaService implements OnvifMediaServiceBase {
  _FakeMediaService({Uri? streamUri})
      : streamUri = streamUri ?? Uri.parse('rtsp://192.168.0.107:554/stream1');

  final Uri streamUri;

  @override
  Future<List<OnvifProfile>> getProfiles({Duration timeout = kDefaultCameraTimeout}) async =>
      const [OnvifProfile(token: 'profile1', name: 'Main')];

  @override
  Future<Uri> getStreamUri(String profileToken, {Duration timeout = kDefaultCameraTimeout}) async =>
      streamUri;
}

/// A no-op fake preview player — no real media_kit/native player in unit tests.
class _FakePreview implements OnvifPreviewController {
  bool opened = false;
  Uri? openedUri;

  @override
  Future<void> open(
    Uri streamUri, {
    String? username,
    String? password,
    Duration timeout = kDefaultCameraTimeout,
  }) async {
    opened = true;
    openedUri = streamUri;
  }

  @override
  Widget buildWidget() => const SizedBox.shrink();

  @override
  Future<void> dispose() async {}
}

const _deviceInfoSuccess = '''<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
  <soap:Body>
    <GetDeviceInformationResponse xmlns="http://www.onvif.org/ver10/device/wsdl">
      <Manufacturer>Hikvision</Manufacturer>
      <Model>DS-2CD2421G0</Model>
    </GetDeviceInformationResponse>
  </soap:Body>
</soap:Envelope>''';

const _soapFault = '''<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
  <soap:Body>
    <soap:Fault><soap:Reason>Sender not authorized</soap:Reason></soap:Fault>
  </soap:Body>
</soap:Envelope>''';

ONVIFCameraAdapter _adapterWith(http.Client client) => ONVIFCameraAdapter(
      credentials: const OnvifCredentials(
        host: '192.168.0.107',
        port: 8000,
        username: 'admin',
        password: 'ABCDEF',
      ),
      httpClientFactory: () => OnvifHttpClient(client: client),
      mediaServiceFactory: ({
        required host,
        required port,
        username,
        password,
        required httpClient,
      }) =>
          _FakeMediaService(),
      previewFactory: _FakePreview.new,
    );

void main() {
  group('ONVIFCameraAdapter.open (WS-UsernameToken auth)', () {
    test('succeeds on a valid GetDeviceInformation response', () async {
      final client = MockClient((request) async {
        expect(request.headers['content-type'], contains('application/soap+xml'));
        expect(request.body, contains('GetDeviceInformation'));
        expect(request.body, contains('UsernameToken'));
        return http.Response(_deviceInfoSuccess, 200);
      });
      final adapter = _adapterWith(client);

      await adapter.open(const CameraDevice(id: '192.168.0.107', name: 'cam'));

      expect(adapter.isOpen, isTrue);
      await adapter.close();
      expect(adapter.isOpen, isFalse);
    });

    test('throws StateError on a SOAP Fault (rejected auth)', () async {
      final client = MockClient((request) async => http.Response(_soapFault, 200));
      final adapter = _adapterWith(client);

      await expectLater(
        adapter.open(const CameraDevice(id: 'x', name: 'x')),
        throwsA(isA<StateError>()),
      );
      expect(adapter.isOpen, isFalse);
    });

    test('throws StateError on a bare HTTP 401 with no usable challenge', () async {
      final client = MockClient((request) async => http.Response('', 401));
      final adapter = _adapterWith(client);

      await expectLater(
        adapter.open(const CameraDevice(id: 'x', name: 'x')),
        throwsA(isA<StateError>()),
      );
    });

    test('retries with RFC 2617 Digest on a Digest challenge and succeeds', () async {
      var call = 0;
      final client = MockClient((request) async {
        call++;
        if (call == 1) {
          return http.Response(
            '',
            401,
            headers: {
              'www-authenticate': 'Digest realm="onvif", nonce="abc123", qop="auth"',
            },
          );
        }
        final auth = request.headers['authorization'] ?? '';
        expect(auth, startsWith('Digest '));
        expect(auth, contains('username="admin"'));
        expect(auth, contains('realm="onvif"'));
        expect(auth, contains('response="'));
        return http.Response(_deviceInfoSuccess, 200);
      });
      final adapter = _adapterWith(client);

      await adapter.open(const CameraDevice(id: 'x', name: 'x'));
      expect(adapter.isOpen, isTrue);
      expect(call, 2);
    });

    test('throws TimeoutException when the device never responds', () async {
      final client = MockClient((request) async {
        await Future<void>.delayed(const Duration(seconds: 5));
        return http.Response(_deviceInfoSuccess, 200);
      });
      final adapter = ONVIFCameraAdapter(
        credentials: const OnvifCredentials(host: 'h', username: 'admin', password: 'pw'),
        httpClientFactory: () => OnvifHttpClient(client: client),
      );

      await expectLater(
        adapter.open(
          const CameraDevice(id: 'x', name: 'x'),
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('throws FormatException on malformed XML', () async {
      final client = MockClient((request) async => http.Response('not xml at all <<', 200));
      final adapter = _adapterWith(client);

      await expectLater(
        adapter.open(const CameraDevice(id: 'x', name: 'x')),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException on an oversized response', () async {
      final oversized = 'x' * (maxOnvifResponseBytes + 1);
      final client = MockClient((request) async => http.Response(oversized, 200));
      final adapter = _adapterWith(client);

      await expectLater(
        adapter.open(const CameraDevice(id: 'x', name: 'x')),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws StateError when credentials are missing', () async {
      final adapter = ONVIFCameraAdapter();
      await expectLater(
        adapter.open(const CameraDevice(id: 'x', name: 'x')),
        throwsA(isA<StateError>()),
      );
    });

    test('a failed open() never logs the raw password', () async {
      final client = MockClient((request) async => http.Response(_soapFault, 200));
      final adapter = _adapterWith(client);

      try {
        await adapter.open(const CameraDevice(id: 'x', name: 'x'));
        fail('expected open() to throw');
      } catch (e) {
        expect(e.toString(), isNot(contains('ABCDEF')));
      }
    });

    test('second open() after close() succeeds (fresh client per open)', () async {
      final client = MockClient((request) async => http.Response(_deviceInfoSuccess, 200));
      final adapter = _adapterWith(client);

      await adapter.open(const CameraDevice(id: 'x', name: 'x'));
      await adapter.close();
      await adapter.open(const CameraDevice(id: 'x', name: 'x'));
      expect(adapter.isOpen, isTrue);
    });
  });
}
