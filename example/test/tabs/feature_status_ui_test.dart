import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';
import 'package:universal_camera_adapter_example/widgets/feature_status_chip.dart';

/// The UI half of the tri-state contract: all three statuses must be visibly
/// different, and the positive one must be shown at all.
void main() {
  Future<void> pumpChip(
    WidgetTester tester,
    CameraFeature feature,
    CameraFeatureStatus status,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: Scaffold(
          body: FeatureStatusChip(feature: feature, status: status),
        ),
      ),
    );
  }

  testWidgets('each status renders its own label', (tester) async {
    for (final (status, expected) in const <(CameraFeatureStatus, String)>[
      (CameraFeatureStatus.supported, 'Available'),
      (CameraFeatureStatus.unvalidated, 'Under development'),
      (CameraFeatureStatus.unsupported, 'Not supported'),
    ]) {
      await pumpChip(tester, CameraFeature.pan, status);
      expect(find.text(expected), findsOneWidget, reason: '$status');
    }
  });

  testWidgets('a supported feature is announced, not left silent',
      (tester) async {
    // Previously a working feature rendered a bare control with no label, so
    // "working" and "silently broken" looked identical.
    await pumpChip(tester, CameraFeature.zoom, CameraFeatureStatus.supported);
    expect(find.text('Available'), findsOneWidget);
    expect(find.textContaining('Tested and working'), findsOneWidget);
  });

  testWidgets('an unvalidated feature does not blame the camera',
      (tester) async {
    await pumpChip(
      tester,
      CameraFeature.frameCapture,
      CameraFeatureStatus.unvalidated,
    );
    expect(find.textContaining('not yet confirmed'), findsOneWidget);
    expect(find.textContaining('does not have'), findsNothing);
  });

  testWidgets('an unsupported feature names the missing capability',
      (tester) async {
    await pumpChip(tester, CameraFeature.tilt, CameraFeatureStatus.unsupported);
    expect(find.textContaining('does not have tilt'), findsOneWidget);
  });

  testWidgets('detailOverride replaces the generated explanation',
      (tester) async {
    // How the PTZ tab shows a real zoom range, which the matrix cannot carry.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeatureStatusChip(
            feature: CameraFeature.zoom,
            status: CameraFeatureStatus.supported,
            detailOverride: 'Range 1.0×–5.0×.',
          ),
        ),
      ),
    );
    expect(find.text('Range 1.0×–5.0×.'), findsOneWidget);
    expect(find.textContaining('Tested and working'), findsNothing);
  });
}
