import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';
import 'package:universal_camera_adapter/src/onvif/onvif_http_client.dart';
import 'package:universal_camera_adapter/src/onvif/onvif_media_service.dart';
import 'package:universal_camera_adapter/src/onvif/rtsp_preview.dart';

const _deviceInfoSuccess = '''<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
  <soap:Body>
    <GetDeviceInformationResponse xmlns="http://www.onvif.org/ver10/device/wsdl">
      <Manufacturer>Hikvision</Manufacturer>
    </GetDeviceInformationResponse>
  </soap:Body>
</soap:Envelope>''';

/// A no-network fake so adapter tests never touch a real SOAP endpoint.
class _FakeMediaService implements OnvifMediaServiceBase {
  _FakeMediaService({this.profiles = const [OnvifProfile(token: 'Profile_1', name: 'Main')]});

  final List<OnvifProfile> profiles;
  Duration? lastGetProfilesTimeout;
  String? lastStreamUriProfileToken;
  bool throwOnGetProfiles = false;
  bool throwOnGetStreamUri = false;

  @override
  Future<List<OnvifProfile>> getProfiles({Duration timeout = kDefaultCameraTimeout}) async {
    lastGetProfilesTimeout = timeout;
    if (throwOnGetProfiles) {
      throw StateError('simulated GetProfiles failure');
    }
    return profiles;
  }

  @override
  Future<Uri> getStreamUri(String profileToken, {Duration timeout = kDefaultCameraTimeout}) async {
    lastStreamUriProfileToken = profileToken;
    if (throwOnGetStreamUri) {
      throw StateError('simulated GetStreamUri failure');
    }
    return Uri.parse('rtsp://192.168.0.107:554/Streaming/Channels/101');
  }
}

/// A no-native-player fake so adapter tests never touch media_kit.
class _FakePreviewController implements OnvifPreviewController {
  Uri? openedUri;
  String? openedUsername;
  String? openedPassword;
  bool disposed = false;

  @override
  Future<void> open(
    Uri streamUri, {
    String? username,
    String? password,
    Duration timeout = kDefaultCameraTimeout,
  }) async {
    openedUri = streamUri;
    openedUsername = username;
    openedPassword = password;
  }

  @override
  Widget buildWidget() => const SizedBox.shrink();

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  group('ONVIFCameraAdapter media service + preview wiring', () {
    late _FakeMediaService fakeMediaService;
    late _FakePreviewController fakePreview;
    late ONVIFCameraAdapter adapter;

    ONVIFCameraAdapter buildAdapter(http.Client httpClient) {
      fakeMediaService = _FakeMediaService();
      fakePreview = _FakePreviewController();
      return ONVIFCameraAdapter(
        credentials: const OnvifCredentials(
          host: '192.168.0.107',
          port: 8000,
          username: 'admin',
          password: 'ABCDEF',
        ),
        httpClientFactory: () => OnvifHttpClient(client: httpClient),
        mediaServiceFactory: ({
          required String host,
          required int port,
          String? username,
          String? password,
          required OnvifHttpClient httpClient,
        }) =>
            fakeMediaService,
        previewFactory: () => fakePreview,
      );
    }

    test('open() resolves the stream URI and opens the preview player', () async {
      final client = MockClient((request) async => http.Response(_deviceInfoSuccess, 200));
      adapter = buildAdapter(client);

      await adapter.open(const CameraDevice(id: '192.168.0.107', name: 'cam'));

      expect(adapter.isOpen, isTrue);
      expect(fakeMediaService.lastStreamUriProfileToken, 'Profile_1');
      expect(fakePreview.openedUri, Uri.parse('rtsp://192.168.0.107:554/Streaming/Channels/101'));
    });

    test('buildPreview() returns the preview widget once open', () async {
      final client = MockClient((request) async => http.Response(_deviceInfoSuccess, 200));
      adapter = buildAdapter(client);
      await adapter.open(const CameraDevice(id: 'x', name: 'x'));

      expect(adapter.buildPreview(), isA<Widget>());
    });

    test('buildPreview() throws StateError before open()', () {
      adapter = ONVIFCameraAdapter(
        credentials: const OnvifCredentials(host: 'h', username: 'admin', password: 'pw'),
      );
      expect(() => adapter.buildPreview(), throwsA(isA<StateError>()));
    });

    test('close() disposes the preview player', () async {
      final client = MockClient((request) async => http.Response(_deviceInfoSuccess, 200));
      adapter = buildAdapter(client);
      await adapter.open(const CameraDevice(id: 'x', name: 'x'));

      await adapter.close();

      expect(fakePreview.disposed, isTrue);
      expect(adapter.isOpen, isFalse);
    });

    test('open() throws StateError and never opens the preview when no profiles are returned', () async {
      final client = MockClient((request) async => http.Response(_deviceInfoSuccess, 200));

      final adapterWithEmptyProfiles = ONVIFCameraAdapter(
        credentials: const OnvifCredentials(host: 'h', username: 'admin', password: 'pw'),
        httpClientFactory: () => OnvifHttpClient(client: client),
        mediaServiceFactory: ({
          required String host,
          required int port,
          String? username,
          String? password,
          required OnvifHttpClient httpClient,
        }) =>
            _FakeMediaService(profiles: const []),
        previewFactory: () => _FakePreviewController(),
      );

      await expectLater(
        adapterWithEmptyProfiles.open(const CameraDevice(id: 'x', name: 'x')),
        throwsA(isA<StateError>()),
      );
      expect(adapterWithEmptyProfiles.isOpen, isFalse);
    });

    test('open() rethrows and cleans up when GetStreamUri fails', () async {
      final client = MockClient((request) async => http.Response(_deviceInfoSuccess, 200));
      adapter = buildAdapter(client);
      fakeMediaService.throwOnGetStreamUri = true;

      await expectLater(
        adapter.open(const CameraDevice(id: 'x', name: 'x')),
        throwsA(isA<StateError>()),
      );
      expect(adapter.isOpen, isFalse);
    });
  });
}
