import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';
import 'package:universal_camera_adapter_example/adapter_types.dart';
import 'package:universal_camera_adapter_example/setup/builtin_camera_setup_wizard.dart';

/// Regression tests for the screen in the bug report: the "Built-in camera"
/// wizard rendering a full CameraX Java stack trace.
///
/// The load-bearing assertion is the negative one — that no raw platform text
/// survives to the widget tree, whatever the adapter throws.

/// Substrings that must never be rendered.
const List<String> _forbidden = <String>[
  'at androidx.',
  'PlatformException',
  'java.util.concurrent',
  'ExecutionException',
  'Stacktrace',
  'Bad state:',
];

/// The screenshot's exception, shaped the way Pigeon's `wrapError` builds it.
PlatformException _cameraXNoCamera() => PlatformException(
      code: 'ExecutionException',
      message: 'java.util.concurrent.ExecutionException: '
          'androidx.camera.core.InitializationException: '
          'androidx.camera.core.CameraUnavailableException: Device reporting '
          'less cameras than anticipated. Available cameras: 0',
      details: 'Cause: ..., Stacktrace: \tat androidx.camera.core.CameraX'
          '.lambda\$initAndRetryRecursively\$3(CameraX.java:527)',
    );

/// Minimal adapter whose `listDevices` is the only interesting behaviour.
class _ProbeAdapter extends CameraAdapter {
  _ProbeAdapter({this.devices = const <CameraDevice>[], this.error});

  final List<CameraDevice> devices;
  final Object? error;
  int listCount = 0;

  @override
  Map<CameraFeature, CameraFeatureStatus> get declaredFeatures =>
      const <CameraFeature, CameraFeatureStatus>{};

  @override
  Future<List<CameraDevice>> listDevices() async {
    listCount++;
    if (error != null) throw error!;
    return devices;
  }

  @override
  Future<void> open(CameraDevice device,
      {Duration timeout = kDefaultCameraTimeout}) async {}

  @override
  Future<void> close() async {}

  @override
  bool get isOpen => false;

  @override
  CameraCapabilities get capabilities => throw StateError('not open');

  @override
  Widget buildPreview() => throw StateError('not open');

  @override
  Future<Uint8List> captureFrame({Duration timeout = kDefaultCameraTimeout}) =>
      throw StateError('not open');

  @override
  Future<void> setZoom(double factor,
          {Duration timeout = kDefaultCameraTimeout}) =>
      throw UnsupportedError('probe adapter has no zoom');
}

void _expectNothingRaw(WidgetTester tester) {
  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .join('\n');
  for (final needle in _forbidden) {
    expect(
      texts.contains(needle),
      isFalse,
      reason: 'raw platform text "$needle" reached the screen:\n$texts',
    );
  }
}

void main() {
  // The wizard builds its own subtree, so it needs a BuildContext from a
  // pumped app; build it inside a host widget instead.
  Widget host(CameraAdapterRegistry registry) => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => BuiltinCameraSetupWizard(registry: registry)
                .build(context, onComplete: (_) {}, onCancel: () {}),
          ),
        ),
      );

  Future<_ProbeAdapter> pump(
    WidgetTester tester, {
    List<CameraDevice> devices = const <CameraDevice>[],
    Object? error,
  }) async {
    final adapter = _ProbeAdapter(devices: devices, error: error);
    final registry = CameraAdapterRegistry()
      ..register(kBuiltinAdapterType, () => adapter);
    // Tear the old tree down first: pumping the same widget type again reuses
    // the existing State, so initState (and therefore the probe) would not
    // re-run and a second pump in one test would silently show stale text.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(host(registry));
    await tester.pumpAndSettle();
    return adapter;
  }

  testWidgets('no cameras shows the friendly empty state', (tester) async {
    await pump(tester);

    expect(find.text('No built-in camera found'), findsOneWidget);
    expect(find.textContaining('reconnect it and tap Refresh'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    _expectNothingRaw(tester);
  });

  testWidgets('a raw CameraX PlatformException never reaches the screen',
      (tester) async {
    // The bug: this exact object used to be interpolated with '$e'.
    await pump(tester, error: _cameraXNoCamera());

    expect(find.text('No built-in camera found'), findsOneWidget);
    _expectNothingRaw(tester);
  });

  testWidgets('a permission failure shows the adapter\'s own instructions',
      (tester) async {
    await pump(
      tester,
      error: StateError(
        'Camera access is blocked. Allow the camera permission in Settings.',
      ),
    );

    expect(find.textContaining('Camera access is blocked'), findsOneWidget);
    _expectNothingRaw(tester);
  });

  testWidgets('the hint differs by cause', (tester) async {
    await pump(tester);
    final emptyHint = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join('\n');

    await pump(tester, error: StateError('Could not list cameras.'));
    final failureHint = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join('\n');

    expect(
      emptyHint,
      isNot(failureHint),
      reason: 'an empty device list and a failed probe must not read the same',
    );
    expect(failureHint, contains('Tap Refresh to try again'));
  });

  testWidgets('Refresh re-runs the probe', (tester) async {
    final adapter = await pump(tester);
    expect(adapter.listCount, 1);

    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();

    expect(adapter.listCount, 2);
  });

  testWidgets('devices are listed when present', (tester) async {
    await pump(tester, devices: const <CameraDevice>[
      CameraDevice(id: '0', name: 'Back camera'),
    ]);

    expect(find.text('Back camera'), findsOneWidget);
    expect(find.text('No built-in camera found'), findsNothing);
  });
}
