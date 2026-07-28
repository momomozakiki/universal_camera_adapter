import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';
import 'package:universal_camera_adapter_example/adapter_types.dart';
import 'package:universal_camera_adapter_example/camera_session.dart';

/// Covers `CameraSession.statusOf` — the tri-state read the feature UI depends
/// on — including the branch that only fires on a misbehaving backend.

const CameraDevice _device = CameraDevice(id: 'a', name: 'A');

/// Declares a status per feature and can be told to report no matrix at all.
class _DeclaringAdapter extends CameraAdapter {
  _DeclaringAdapter({
    this.declared = const <CameraFeature, CameraFeatureStatus>{},
    this.hasZoom = false,
    this.nullMatrix = false,
  });

  final Map<CameraFeature, CameraFeatureStatus> declared;
  final bool hasZoom;

  /// Simulates a backend that is open but cannot produce a matrix — the
  /// contract-violating case `statusOf` has to survive.
  final bool nullMatrix;

  bool _open = false;

  @override
  Map<CameraFeature, CameraFeatureStatus> get declaredFeatures => declared;

  @override
  Future<List<CameraDevice>> listDevices() async => const <CameraDevice>[_device];

  @override
  Future<void> open(CameraDevice device,
      {Duration timeout = kDefaultCameraTimeout}) async {
    _open = true;
  }

  @override
  Future<void> close() async => _open = false;

  @override
  bool get isOpen => _open;

  @override
  CameraCapabilities get capabilities {
    if (!_open) throw StateError('not open');
    return CameraCapabilities(
      hasZoom: hasZoom,
      minZoomLevel: hasZoom ? 1.0 : 1.0,
      maxZoomLevel: hasZoom ? 4.0 : 1.0,
    );
  }

  @override
  CameraFeatureMatrix get featureMatrix {
    if (nullMatrix) throw UnimplementedError('no matrix');
    return super.featureMatrix;
  }

  @override
  Widget buildPreview() => const SizedBox.shrink();

  @override
  Future<Uint8List> captureFrame({Duration timeout = kDefaultCameraTimeout}) =>
      throw StateError('not open');

  @override
  Future<void> setZoom(double factor,
          {Duration timeout = kDefaultCameraTimeout}) async =>
      {};
}

/// CameraSession takes a registry, not an adapter — build a one-backend
/// registry around [adapter] so these tests drive the real session.
CameraSession _sessionFor(CameraAdapter adapter) {
  final registry = CameraAdapterRegistry()
    ..register(kBuiltinAdapterType, () => adapter, asDefault: true);
  return CameraSession(registry);
}

void main() {
  test('reports unsupported for every feature while closed', () {
    final session = _sessionFor(_DeclaringAdapter());

    for (final feature in CameraFeature.values) {
      expect(
        session.statusOf(feature),
        CameraFeatureStatus.unsupported,
        reason: feature.name,
      );
    }
  });

  test('surfaces each declared status once open', () async {
    final session = _sessionFor(_DeclaringAdapter(
        hasZoom: true,
        declared: const <CameraFeature, CameraFeatureStatus>{
          CameraFeature.frameCapture: CameraFeatureStatus.supported,
          CameraFeature.pan: CameraFeatureStatus.unsupported,
          CameraFeature.qrScanning: CameraFeatureStatus.unvalidated,
        },
      ));
    await session.refreshDevices();
    await session.open(_device.id);

    expect(session.statusOf(CameraFeature.frameCapture),
        CameraFeatureStatus.supported);
    expect(session.statusOf(CameraFeature.pan), CameraFeatureStatus.unsupported);
    expect(session.statusOf(CameraFeature.qrScanning),
        CameraFeatureStatus.unvalidated);
  });

  test('an undeclared feature is unvalidated, not unsupported', () async {
    // The fail-safe default: unknown must not be reported as proven absent.
    final session = _sessionFor(_DeclaringAdapter());
    await session.refreshDevices();
    await session.open(_device.id);

    expect(
      session.statusOf(CameraFeature.motionEvents),
      CameraFeatureStatus.unvalidated,
    );
  });

  test('statusOf describes while supports gates', () async {
    // The rule the whole tri-state design rests on: an unvalidated feature is
    // *described* as under development but stays non-interactive, because it
    // may genuinely throw.
    final session = _sessionFor(_DeclaringAdapter(
        declared: const <CameraFeature, CameraFeatureStatus>{
          CameraFeature.frameCapture: CameraFeatureStatus.unvalidated,
        },
      ));
    await session.refreshDevices();
    await session.open(_device.id);

    expect(session.statusOf(CameraFeature.frameCapture),
        CameraFeatureStatus.unvalidated);
    expect(session.supports(CameraFeature.frameCapture), isFalse);
  });

  test('an open backend that cannot produce a matrix degrades safely',
      () async {
    // Contract-violating, but it must not crash the feature UI.
    final session =
        _sessionFor(_DeclaringAdapter(nullMatrix: true));
    await session.refreshDevices();
    await session.open(_device.id);

    expect(session.isOpen, isTrue);
    expect(session.featureMatrix, isNull);
    expect(
      session.statusOf(CameraFeature.zoom),
      CameraFeatureStatus.unsupported,
    );
    expect(session.supports(CameraFeature.zoom), isFalse);
  });
}
