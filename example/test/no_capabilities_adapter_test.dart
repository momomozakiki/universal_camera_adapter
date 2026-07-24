import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';
import 'package:universal_camera_adapter_example/camera_session.dart';
import 'package:universal_camera_adapter_example/tabs/preview_tab.dart';
import 'package:universal_camera_adapter_example/tabs/ptz_tab.dart';

/// A backend that implements [CameraAdapter.featureMatrix] but **not**
/// [CameraAdapter.capabilities] — exactly the shape of `ONVIFCameraAdapter`,
/// whose `capabilities` is still `_planned()` and throws [UnimplementedError].
///
/// This is the fake the existing suite was missing: `_FakeAdapter` and
/// `_RecordingAdapter` both return a real [CameraCapabilities], so nothing
/// covered the "capabilities is genuinely absent" path and a live ONVIF camera
/// red-screened the Preview and PTZ tabs.
class _NoCapabilitiesAdapter extends CameraAdapter {
  _NoCapabilitiesAdapter(this._devices);

  final List<CameraDevice> _devices;
  bool _open = false;

  @override
  Future<List<CameraDevice>> listDevices() async => _devices;

  @override
  Future<void> open(
    CameraDevice device, {
    Duration timeout = kDefaultCameraTimeout,
  }) async {
    _open = true;
  }

  @override
  Future<void> close() async {
    _open = false;
  }

  @override
  bool get isOpen => _open;

  @override
  CameraCapabilities get capabilities =>
      throw UnimplementedError('capabilities is not implemented yet.');

  /// Mirrors `ONVIFCameraAdapter.featureMatrix`: built explicitly because the
  /// base derivation cannot read [capabilities].
  @override
  CameraFeatureMatrix get featureMatrix {
    if (!_open) {
      throw StateError('Not open. Call open(device) first.');
    }
    return CameraFeatureMatrix.fromStatuses(
      const <CameraFeature, CameraFeatureStatus>{
        CameraFeature.zoom: CameraFeatureStatus.unsupported,
        CameraFeature.pan: CameraFeatureStatus.unsupported,
        CameraFeature.tilt: CameraFeatureStatus.unsupported,
        CameraFeature.frameCapture: CameraFeatureStatus.unvalidated,
        CameraFeature.qrScanning: CameraFeatureStatus.unvalidated,
        CameraFeature.barcodeScanning: CameraFeatureStatus.unvalidated,
        CameraFeature.textRecognitionOcr: CameraFeatureStatus.unvalidated,
        CameraFeature.twoWayAudio: CameraFeatureStatus.unvalidated,
        CameraFeature.motionEvents: CameraFeatureStatus.unvalidated,
      },
    );
  }

  /// Deliberately **expands** rather than self-sizing, mirroring media_kit's
  /// `Video` (what `ONVIFCameraAdapter` returns) rather than `CameraPreview`.
  ///
  /// This is the shape that broke the app: the original fake returned a
  /// fixed-size `SizedBox`, which is happy under unbounded height, so the tab
  /// tests passed while the real ONVIF preview asserted during layout and left
  /// the whole UI unclickable.
  @override
  Widget buildPreview() {
    if (!_open) {
      throw StateError('Not open. Call open(device) first.');
    }
    return const SizedBox.expand(
      key: Key('fake-preview'),
      child: ColoredBox(color: Color(0xFF000000)),
    );
  }

  @override
  Future<Uint8List> captureFrame({
    Duration timeout = kDefaultCameraTimeout,
  }) async => Uint8List(0);

  @override
  Future<void> setZoom(
    double factor, {
    Duration timeout = kDefaultCameraTimeout,
  }) async => throw UnsupportedError('This backend has no zoom.');

  // setPan / setTilt inherit the contract's UnsupportedError default.
}

/// A misbehaving backend: throws [StateError] from `capabilities` while it is
/// genuinely open. That is a contract violation, **not** an absent-capabilities
/// case, so the session must let it propagate rather than masking it as null —
/// only [UnimplementedError] is swallowed.
class _StateErrorAdapter extends _NoCapabilitiesAdapter {
  _StateErrorAdapter(super.devices);

  @override
  CameraCapabilities get capabilities =>
      throw StateError('Camera is not open. Call open(device) first.');
}

const _device = CameraDevice(
  id: '192.168.0.217:80',
  name: 'IP camera',
  lensFacing: CameraLensFacing.external,
);

CameraSession _sessionWith(CameraAdapter adapter) {
  final registry = CameraAdapterRegistry()
    ..register('no-caps', () => adapter, asDefault: true);
  return CameraSession(registry);
}

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  group('a backend whose capabilities throws UnimplementedError', () {
    test('session.capabilities is null instead of throwing', () async {
      final session = _sessionWith(_NoCapabilitiesAdapter(const [_device]));
      expect(session.capabilities, isNull, reason: 'nothing open yet');

      await session.openDevice(_device);

      expect(session.isOpen, isTrue);
      expect(session.capabilities, isNull);
      expect(session.featureMatrix, isNotNull);
    });

    test('open still succeeds: no error, selection and zoom are set', () async {
      final session = _sessionWith(_NoCapabilitiesAdapter(const [_device]));

      await session.openDevice(_device);

      expect(
        session.error,
        isNull,
        reason: 'a successful open must not be reported as a failure just '
            'because the backend has no capabilities struct',
      );
      expect(session.selectedId, _device.id);
      expect(session.zoom, 1.0);
      expect(session.busy, isFalse);
    });

    test('zoom is reported unsupported via the matrix', () async {
      final session = _sessionWith(_NoCapabilitiesAdapter(const [_device]));
      await session.openDevice(_device);

      expect(session.supports(CameraFeature.zoom), isFalse);
      expect(session.supports(CameraFeature.pan), isFalse);
      expect(session.supports(CameraFeature.tilt), isFalse);
    });

    testWidgets('PreviewTab renders the preview with the zoom slider disabled',
        (tester) async {
      final session = _sessionWith(_NoCapabilitiesAdapter(const [_device]));
      await session.openDevice(_device);

      await _pump(tester, PreviewTab(session: session));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('fake-preview')), findsOneWidget);

      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.onChanged, isNull, reason: 'no zoom range to drive');
    });

    testWidgets('an expanding preview is given a bounded height', (tester) async {
      // Regression: PreviewTab's Column sits in a SingleChildScrollView, so it
      // offers unbounded height. A preview that expands (media_kit's Video, i.e.
      // every ONVIF camera) then asserts during layout and is left with no size,
      // after which EVERY hit test in the app throws and the entire UI goes
      // dead — not just this tab. Asserting a finite, non-zero height is what
      // pins that.
      final session = _sessionWith(_NoCapabilitiesAdapter(const [_device]));
      await session.openDevice(_device);

      await _pump(tester, PreviewTab(session: session));
      await tester.pump();

      expect(tester.takeException(), isNull);
      final size = tester.getSize(find.byKey(const Key('fake-preview')));
      expect(size.height.isFinite, isTrue);
      expect(size.height, greaterThan(0));
      expect(size.width, greaterThan(0));
    });

    testWidgets('the whole tab stays hit-testable with an expanding preview',
        (tester) async {
      // The user-visible symptom was "I cannot click anything", so assert the
      // thing that actually broke: a tap still reaches an interactive widget.
      final session = _sessionWith(_NoCapabilitiesAdapter(const [_device]));
      await session.openDevice(_device);

      await _pump(tester, PreviewTab(session: session));
      await tester.pump();

      // ensureVisible first: the 16:9 preview pushes the buttons below the fold
      // of the test viewport, and a tap that silently misses would prove
      // nothing. Scrolling itself also exercises hit testing.
      await tester.ensureVisible(find.text('Disconnect'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disconnect'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(session.isOpen, isFalse, reason: 'the tap actually reached it');
    });

    testWidgets('PtzTab builds with every slider disabled', (tester) async {
      final session = _sessionWith(_NoCapabilitiesAdapter(const [_device]));
      await session.openDevice(_device);

      await _pump(tester, PtzTab(session: session));
      await tester.pump();

      expect(tester.takeException(), isNull);
      final sliders = tester.widgetList<Slider>(find.byType(Slider));
      expect(sliders, hasLength(3));
      for (final slider in sliders) {
        expect(slider.onChanged, isNull);
      }
    });
  });

  group('capabilities error handling is narrow', () {
    test('a StateError while open still propagates', () async {
      final session = _sessionWith(_StateErrorAdapter(const [_device]));
      await session.openDevice(_device);

      expect(session.isOpen, isTrue);
      expect(() => session.capabilities, throwsStateError);
    });

    test('nothing open short-circuits before the adapter is asked', () {
      final session = _sessionWith(_StateErrorAdapter(const [_device]));
      expect(session.capabilities, isNull);
    });
  });
}
