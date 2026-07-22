import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:universal_camera_adapter/src/onvif/onvif_http_client.dart';

void main() {
  group('OnvifHttpClient.post', () {
    test('sends no Authorization header when no challenge is issued', () async {
      final client = MockClient((request) async {
        expect(request.headers.containsKey('authorization'), isFalse);
        return http.Response('ok', 200);
      });
      final result = await OnvifHttpClient(client: client).post(
        'h',
        80,
        '<env/>',
        username: 'admin',
        password: 'pw',
        timeout: const Duration(seconds: 5),
      );
      expect(result, 'ok');
    });

    test('falls back to the no-qop formula on a bare Digest challenge (no qop)', () async {
      var call = 0;
      final client = MockClient((request) async {
        call++;
        if (call == 1) {
          return http.Response(
            '',
            401,
            headers: {'www-authenticate': 'Digest realm="onvif", nonce="n1"'},
          );
        }
        final auth = request.headers['authorization']!;
        expect(auth, isNot(contains('qop=')));
        expect(auth, isNot(contains('cnonce=')));
        return http.Response('ok', 200);
      });
      final result = await OnvifHttpClient(client: client).post(
        'h',
        80,
        '<env/>',
        username: 'admin',
        password: 'pw',
        timeout: const Duration(seconds: 5),
      );
      expect(result, 'ok');
    });

    test('an unsupported qop (auth-int only) falls back to the no-qop header, not a broken cnonce=null one', () async {
      var call = 0;
      final client = MockClient((request) async {
        call++;
        if (call == 1) {
          return http.Response(
            '',
            401,
            headers: {
              'www-authenticate': 'Digest realm="onvif", nonce="n1", qop="auth-int"',
            },
          );
        }
        final auth = request.headers['authorization']!;
        // The bug this guards against: sending `qop=auth` + `cnonce="null"`
        // when the response was actually computed with the no-qop formula.
        expect(auth, isNot(contains('cnonce="null"')));
        expect(auth, isNot(contains('qop=auth')));
        return http.Response('ok', 200);
      });
      final result = await OnvifHttpClient(client: client).post(
        'h',
        80,
        '<env/>',
        username: 'admin',
        password: 'pw',
        timeout: const Duration(seconds: 5),
      );
      expect(result, 'ok');
    });

    test('throws StateError (not a raw exception) on a transport failure', () async {
      final client = MockClient((request) async => throw Exception('connection refused'));
      await expectLater(
        OnvifHttpClient(client: client).post(
          'h',
          80,
          '<env/>',
          timeout: const Duration(seconds: 5),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('throws FormatException for an oversized response', () async {
      final oversized = 'x' * (maxOnvifResponseBytes + 1);
      final client = MockClient((request) async => http.Response(oversized, 200));
      await expectLater(
        OnvifHttpClient(client: client).post(
          'h',
          80,
          '<env/>',
          timeout: const Duration(seconds: 5),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws StateError for an empty host or invalid port', () async {
      final client = MockClient((request) async => http.Response('ok', 200));
      await expectLater(
        OnvifHttpClient(client: client)
            .post('', 80, '<env/>', timeout: const Duration(seconds: 5)),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        OnvifHttpClient(client: client)
            .post('h', 0, '<env/>', timeout: const Duration(seconds: 5)),
        throwsA(isA<StateError>()),
      );
    });
  });
}
