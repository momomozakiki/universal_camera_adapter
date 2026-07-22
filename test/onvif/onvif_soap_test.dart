import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_camera_adapter/src/onvif/onvif_soap.dart';
import 'package:xml/xml.dart';

void main() {
  group('OnvifSoap.wsUsernameToken', () {
    test('produces a digest matching Base64(SHA1(nonce + created + password))', () {
      const soap = OnvifSoap();
      final token = soap.wsUsernameToken('admin', 's3cret');

      final expectedDigest = base64.encode(
        sha1
            .convert(<int>[
              ...base64.decode(token.nonceBase64),
              ...utf8.encode(token.created),
              ...utf8.encode('s3cret'),
            ])
            .bytes,
      );

      expect(token.passwordDigestBase64, expectedDigest);
      expect(token.username, 'admin');
    });

    test('created is UTC ISO8601', () {
      const soap = OnvifSoap();
      final token = soap.wsUsernameToken('admin', 'pw');
      expect(token.created, endsWith('Z'));
      expect(() => DateTime.parse(token.created), returnsNormally);
    });

    test('nonce is 16 bytes and varies per call', () {
      const soap = OnvifSoap();
      final a = soap.wsUsernameToken('admin', 'pw');
      final b = soap.wsUsernameToken('admin', 'pw');
      expect(base64.decode(a.nonceBase64), hasLength(16));
      expect(a.nonceBase64, isNot(b.nonceBase64));
    });
  });

  group('OnvifSoap.buildEnvelope', () {
    test('includes the security header when a token is supplied', () {
      const soap = OnvifSoap();
      final token = soap.wsUsernameToken('admin', 'pw');
      final envelope = soap.buildEnvelope('GetDeviceInformation', token: token);

      final document = XmlDocument.parse(envelope);
      expect(document.findAllElements('UsernameToken'), isNotEmpty);
      expect(
        document.findAllElements('Password').single.innerText,
        token.passwordDigestBase64,
      );
      expect(
        document.findAllElements('GetDeviceInformation'),
        isNotEmpty,
      );
    });

    test('omits the security header when no token is supplied', () {
      const soap = OnvifSoap();
      final envelope = soap.buildEnvelope('GetDeviceInformation');
      final document = XmlDocument.parse(envelope);
      expect(document.findAllElements('UsernameToken'), isEmpty);
    });

    test('escapes body field values', () {
      const soap = OnvifSoap();
      final envelope = soap.buildEnvelope(
        'SomeAction',
        body: const {'Field': '<script>&"quote"</script>'},
      );
      expect(envelope, isNot(contains('<script>')));
      final document = XmlDocument.parse(envelope); // must not throw
      expect(
        document.findAllElements('Field').single.innerText,
        '<script>&"quote"</script>',
      );
    });
  });
}
