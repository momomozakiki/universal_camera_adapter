import 'package:flutter_test/flutter_test.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

import 'mock_camera_adapter.dart';

/// Covers `CameraAdapter.featureMatrix` from a consumer's side, through
/// [MockCameraAdapter] — both the concrete **base derivation** every backend
/// inherits for free, and the **override** path a backend takes when reality
/// differs from that derivation.
///
/// That split is the Open/Closed win the matrix exists for: adding a feature is
/// one enum value plus one mapping edit in `camera_adapter.dart`, with no
/// lockstep change across backends.
void main() {
  const device = CameraDevice(id: 'dev-1', name: 'Mock');

  Future<MockCameraAdapter> opened({
    CameraCapabilities capabilities = const CameraCapabilities(),
    CameraFeatureMatrix? featureMatrix,
  }) async {
    final adapter = MockCameraAdapter(
      devices: const [device],
      capabilities: capabilities,
      featureMatrix: featureMatrix,
    );
    await adapter.open(device);
    return adapter;
  }

  group('base derivation from capabilities', () {
    test('zoom/pan/tilt follow the capability flags', () async {
      final adapter = await opened(
        capabilities: const CameraCapabilities(
          hasZoom: true,
          hasPan: true,
          maxZoomLevel: 4,
        ),
      );

      final matrix = adapter.featureMatrix;
      expect(matrix.isSupported(CameraFeature.zoom), isTrue);
      expect(matrix.isSupported(CameraFeature.pan), isTrue);
      expect(matrix.isSupported(CameraFeature.tilt), isFalse);
      expect(
        matrix.statusOf(CameraFeature.tilt),
        CameraFeatureStatus.unsupported,
        reason: 'an absent capability is unsupported, never unvalidated',
      );
    });

    test('an all-false capabilities struct reports no PTZ at all', () async {
      final adapter = await opened();
      final matrix = adapter.featureMatrix;

      for (final feature in kFeatureBundles['ptz']!) {
        expect(matrix.isSupported(feature), isFalse, reason: '$feature');
      }
    });

    test('the generic primitives default fail-safe, not optimistically',
        () async {
      // This assertion is inverted from what it used to be, and the inversion
      // is the point. The base derivation once defaulted frameCapture and the
      // scanning features to `supported` on the reasoning that captureFrame is
      // a required contract method, relying on a doc note telling authors they
      // "MUST override" to downgrade. That failed open: a backend that simply
      // forgot inherited a claim its hardware could not honour, and the user
      // was told the *camera* lacked a feature the *app* had not wired.
      //
      // Undeclared now means `unvalidated` — unknown, not proven. Nothing is
      // enabled on an unproven claim (isSupported stays false), but the UI can
      // say "Under development" instead of "Not supported". A backend that has
      // verified a feature declares it via `declaredFeatures`.
      final adapter = await opened();
      final matrix = adapter.featureMatrix;

      for (final feature in <CameraFeature>[
        CameraFeature.frameCapture,
        CameraFeature.qrScanning,
        CameraFeature.barcodeScanning,
      ]) {
        expect(
          matrix.statusOf(feature),
          CameraFeatureStatus.unvalidated,
          reason: '$feature must not be claimed without a declaration',
        );
        expect(matrix.isSupported(feature), isFalse, reason: '$feature');
      }
    });

    test('a declared feature wins over the fail-safe default', () async {
      // declaredFeatures is the single place a claim is written; featureMatrix
      // layers it over the derivation.
      final adapter = MockCameraAdapter(
        devices: const [CameraDevice(id: 'a', name: 'A')],
        capabilities: const CameraCapabilities(),
        declared: const <CameraFeature, CameraFeatureStatus>{
          CameraFeature.frameCapture: CameraFeatureStatus.supported,
        },
      );
      await adapter.open(const CameraDevice(id: 'a', name: 'A'));

      expect(
        adapter.featureMatrix.statusOf(CameraFeature.frameCapture),
        CameraFeatureStatus.supported,
      );
      expect(adapter.featureMatrix.isSupported(CameraFeature.frameCapture),
          isTrue);
    });

    test('features awaiting a future epic are unvalidated, not unsupported',
        () async {
      final adapter = await opened();
      final matrix = adapter.featureMatrix;

      expect(
        matrix.statusOf(CameraFeature.textRecognitionOcr),
        CameraFeatureStatus.unvalidated,
      );
      expect(
        matrix.statusOf(CameraFeature.twoWayAudio),
        CameraFeatureStatus.unvalidated,
      );
      expect(
        matrix.statusOf(CameraFeature.motionEvents),
        CameraFeatureStatus.unvalidated,
      );
      // unvalidated is not supported — scanning-style gates stay closed.
      expect(matrix.isSupported(CameraFeature.textRecognitionOcr), isFalse);
    });

    test('the matrix is fully populated for every feature', () async {
      final adapter = await opened();
      final matrix = adapter.featureMatrix;

      for (final feature in CameraFeature.values) {
        expect(matrix.statusOf(feature), isNotNull, reason: '$feature');
      }
    });
  });

  group('override path', () {
    test('an overriding backend wins over the derivation', () async {
      // The shape a backend with an unwired captureFrame must adopt: capabilities
      // say zoom works, but frame capture is downgraded so scanning stays gated.
      final adapter = await opened(
        capabilities: const CameraCapabilities(hasZoom: true, maxZoomLevel: 8),
        featureMatrix: CameraFeatureMatrix.fromStatuses(
          const <CameraFeature, CameraFeatureStatus>{
            CameraFeature.frameCapture: CameraFeatureStatus.unvalidated,
            CameraFeature.qrScanning: CameraFeatureStatus.unvalidated,
            CameraFeature.barcodeScanning: CameraFeatureStatus.unvalidated,
          },
        ),
      );

      final matrix = adapter.featureMatrix;
      expect(matrix.isSupported(CameraFeature.frameCapture), isFalse);
      expect(matrix.isSupported(CameraFeature.qrScanning), isFalse);
      expect(
        matrix.isSupported(CameraFeature.zoom),
        isFalse,
        reason: 'an explicit matrix replaces the derivation wholesale — it does '
            'not merge with capabilities behind the backend author\'s back',
      );
    });

    test('withStatuses adjusts a derived matrix without rebuilding it',
        () async {
      final adapter = await opened(
        capabilities: const CameraCapabilities(hasZoom: true, maxZoomLevel: 8),
      );
      final adjusted = adapter.featureMatrix.withStatuses(
        const <CameraFeature, CameraFeatureStatus>{
          CameraFeature.frameCapture: CameraFeatureStatus.unvalidated,
        },
      );

      expect(adjusted.isSupported(CameraFeature.frameCapture), isFalse);
      expect(adjusted.isSupported(CameraFeature.zoom), isTrue,
          reason: 'untouched entries survive');
    });
  });

  group('post-open contract', () {
    test('the derived matrix throws StateError before open', () {
      final adapter = MockCameraAdapter(devices: const [device]);
      expect(() => adapter.featureMatrix, throwsStateError);
    });

    test('an overridden matrix throws StateError before open too', () {
      final adapter = MockCameraAdapter(
        devices: const [device],
        featureMatrix: CameraFeatureMatrix.fromStatuses(
          const <CameraFeature, CameraFeatureStatus>{},
        ),
      );
      expect(() => adapter.featureMatrix, throwsStateError);
    });

    test('it throws again after close', () async {
      final adapter = await opened();
      expect(adapter.featureMatrix, isNotNull);
      await adapter.close();
      expect(() => adapter.featureMatrix, throwsStateError);
    });
  });
}
