import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:universal_camera_adapter/src/onvif/onvif_http_client.dart';
import 'package:universal_camera_adapter/src/onvif/onvif_media_service.dart';

const _profilesSuccess = '''<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
  <soap:Body>
    <GetProfilesResponse xmlns="http://www.onvif.org/ver10/media/wsdl">
      <Profiles token="Profile_1" fixed="true">
        <Name>MainStream</Name>
      </Profiles>
      <Profiles token="Profile_2">
        <Name>SubStream</Name>
      </Profiles>
    </GetProfilesResponse>
  </soap:Body>
</soap:Envelope>''';

const _profilesWithOneMalformedEntry = '''<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
  <soap:Body>
    <GetProfilesResponse xmlns="http://www.onvif.org/ver10/media/wsdl">
      <Profiles>
        <Name>NoToken</Name>
      </Profiles>
      <Profiles token="Profile_2">
        <Name>SubStream</Name>
      </Profiles>
    </GetProfilesResponse>
  </soap:Body>
</soap:Envelope>''';

const _streamUriSuccess = '''<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
  <soap:Body>
    <GetStreamUriResponse xmlns="http://www.onvif.org/ver10/media/wsdl">
      <MediaUri>
        <Uri>rtsp://192.168.0.107:554/Streaming/Channels/101</Uri>
      </MediaUri>
    </GetStreamUriResponse>
  </soap:Body>
</soap:Envelope>''';

const _streamUriHttpScheme = '''<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
  <soap:Body>
    <GetStreamUriResponse xmlns="http://www.onvif.org/ver10/media/wsdl">
      <MediaUri><Uri>http://evil.example.com/steal</Uri></MediaUri>
    </GetStreamUriResponse>
  </soap:Body>
</soap:Envelope>''';

const _soapFault = '''<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
  <soap:Body>
    <soap:Fault><soap:Reason>Sender not authorized</soap:Reason></soap:Fault>
  </soap:Body>
</soap:Envelope>''';

OnvifMediaService _serviceWith(http.Client client) => OnvifMediaService(
      host: '192.168.0.107',
      port: 8000,
      username: 'admin',
      password: 'ABCDEF',
      httpClient: OnvifHttpClient(client: client),
    );

void main() {
  group('OnvifMediaService.getProfiles', () {
    test('parses profile token + name pairs', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/onvif/media_service');
        expect(request.body, contains('GetProfiles'));
        return http.Response(_profilesSuccess, 200);
      });
      final profiles = await _serviceWith(client).getProfiles();

      expect(profiles, hasLength(2));
      expect(profiles[0].token, 'Profile_1');
      expect(profiles[0].name, 'MainStream');
      expect(profiles[1].token, 'Profile_2');
      expect(profiles[1].name, 'SubStream');
    });

    test('skips a malformed profile entry without failing the whole call', () async {
      final client = MockClient((request) async => http.Response(_profilesWithOneMalformedEntry, 200));
      final profiles = await _serviceWith(client).getProfiles();

      expect(profiles, hasLength(1));
      expect(profiles.single.token, 'Profile_2');
    });

    test('throws StateError on a SOAP Fault', () async {
      final client = MockClient((request) async => http.Response(_soapFault, 200));
      await expectLater(_serviceWith(client).getProfiles(), throwsA(isA<StateError>()));
    });

    test('throws FormatException when GetProfilesResponse is missing', () async {
      final client = MockClient((request) async => http.Response(
            '<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">'
            '<soap:Body><Unexpected/></soap:Body></soap:Envelope>',
            200,
          ));
      await expectLater(_serviceWith(client).getProfiles(), throwsA(isA<FormatException>()));
    });

    test('throws FormatException on malformed XML', () async {
      final client = MockClient((request) async => http.Response('not xml <<', 200));
      await expectLater(_serviceWith(client).getProfiles(), throwsA(isA<FormatException>()));
    });

    test('throws TimeoutException when the device never responds', () async {
      final client = MockClient((request) async {
        await Future<void>.delayed(const Duration(seconds: 5));
        return http.Response(_profilesSuccess, 200);
      });
      await expectLater(
        _serviceWith(client).getProfiles(timeout: const Duration(milliseconds: 50)),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  group('OnvifMediaService.getStreamUri', () {
    test('returns a validated rtsp:// URI', () async {
      final client = MockClient((request) async {
        expect(request.body, contains('GetStreamUri'));
        expect(request.body, contains('RTP-Unicast'));
        expect(request.body, contains('ProfileToken'));
        return http.Response(_streamUriSuccess, 200);
      });
      final uri = await _serviceWith(client).getStreamUri('Profile_1');

      expect(uri.scheme, 'rtsp');
      expect(uri.host, '192.168.0.107');
    });

    test('rejects a non-rtsp scheme (never auto-follows an arbitrary URI)', () async {
      final client = MockClient((request) async => http.Response(_streamUriHttpScheme, 200));
      await expectLater(
        _serviceWith(client).getStreamUri('Profile_1'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws StateError on a SOAP Fault', () async {
      final client = MockClient((request) async => http.Response(_soapFault, 200));
      await expectLater(
        _serviceWith(client).getStreamUri('Profile_1'),
        throwsA(isA<StateError>()),
      );
    });

    test('throws FormatException on an oversized response', () async {
      final oversized = 'x' * (maxOnvifResponseBytes + 1);
      final client = MockClient((request) async => http.Response(oversized, 200));
      await expectLater(
        _serviceWith(client).getStreamUri('Profile_1'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
