import 'package:flutter_test/flutter_test.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';
import 'package:universal_camera_adapter_example/feature_messages.dart';

void main() {
  group('describeFeatureStatus', () {
    test('gives each status a distinct label, for every feature', () {
      // The regression this guards: the UI used to route everything through a
      // boolean, so "under development" and "not supported" read identically
      // and a half-wired app blamed the camera.
      for (final feature in CameraFeature.values) {
        final labels = CameraFeatureStatus.values
            .map((s) => describeFeatureStatus(feature, s).label)
            .toSet();
        expect(
          labels,
          hasLength(CameraFeatureStatus.values.length),
          reason: '${feature.name} must not collapse two statuses into one '
              'label; got $labels',
        );
      }
    });

    test('uses the three agreed words', () {
      const feature = CameraFeature.zoom;
      expect(
        describeFeatureStatus(feature, CameraFeatureStatus.supported).label,
        'Available',
      );
      expect(
        describeFeatureStatus(feature, CameraFeatureStatus.unvalidated).label,
        'Under development',
      );
      expect(
        describeFeatureStatus(feature, CameraFeatureStatus.unsupported).label,
        'Not supported',
      );
    });

    test('"under development" blames the app, not the camera', () {
      final detail =
          describeFeatureStatus(CameraFeature.frameCapture, CameraFeatureStatus.unvalidated)
              .detail;
      expect(detail, contains('not yet confirmed'));
      // The old wording ("This camera cannot…") is exactly what was wrong.
      expect(detail.toLowerCase(), isNot(contains('cannot')));
    });

    test('every status has a non-empty detail and a distinct icon', () {
      final icons = <Object>{};
      for (final status in CameraFeatureStatus.values) {
        final message = describeFeatureStatus(CameraFeature.pan, status);
        expect(message.detail, isNotEmpty);
        icons.add(message.icon);
      }
      expect(icons, hasLength(CameraFeatureStatus.values.length));
    });
  });

  group('kFeatureLabels', () {
    test('covers every CameraFeature', () {
      // Also asserted by camera_feature_checklist_test; kept here so the
      // failure lands next to the map it is about.
      final missing = CameraFeature.values
          .where((f) => !kFeatureLabels.containsKey(f))
          .map((f) => f.name);
      expect(missing, isEmpty);
    });

    test('never falls back to a raw enum name', () {
      for (final feature in CameraFeature.values) {
        final label = featureLabel(feature);
        expect(label, isNotEmpty);
        // camelCase would mean the fallback fired.
        expect(label, isNot(matches(RegExp(r'[a-z][A-Z]'))));
      }
    });
  });
}
