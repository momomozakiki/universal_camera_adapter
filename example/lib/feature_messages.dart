/// User-facing vocabulary for [CameraFeatureStatus].
///
/// The contract has been tri-state since Epic 2.5 — `supported` /
/// `unvalidated` / `unsupported` — but the UI used to collapse it back to a
/// boolean through `CameraSession.supports()`, so "wired up but unproven" and
/// "this hardware cannot do it" read identically. A backend still being
/// integrated (EZVIZ's frame capture today) therefore accused the *camera* of
/// lacking a feature the *app* had not finished wiring.
///
/// This file is that missing third message, in one place so no tab invents its
/// own wording. See `docs/camera/feature-matrix.md`.
library;

import 'package:flutter/material.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

/// How one feature's support level is presented.
typedef FeatureStatusMessage = ({String label, String detail, IconData icon});

/// Human-readable names for every [CameraFeature].
///
/// Exhaustive by construction — `feature_messages_test.dart` asserts every enum
/// value has an entry, so adding a tenth feature fails the suite until it is
/// named here rather than shipping as `CameraFeature.somethingNew`.
const Map<CameraFeature, String> kFeatureLabels = <CameraFeature, String>{
  CameraFeature.zoom: 'zoom',
  CameraFeature.pan: 'pan',
  CameraFeature.tilt: 'tilt',
  CameraFeature.frameCapture: 'still-frame capture',
  CameraFeature.qrScanning: 'QR scanning',
  CameraFeature.barcodeScanning: 'barcode scanning',
  CameraFeature.textRecognitionOcr: 'text recognition (OCR)',
  CameraFeature.twoWayAudio: 'two-way audio',
  CameraFeature.motionEvents: 'motion events',
};

/// The display name of [feature].
String featureLabel(CameraFeature feature) =>
    kFeatureLabels[feature] ?? feature.name;

/// The label, explanation and icon for [feature] at [status].
///
/// Every status returns a message — including the positive one. A supported
/// feature previously rendered a bare control with no confirmation, which left
/// "working" and "silently broken" looking the same.
FeatureStatusMessage describeFeatureStatus(
  CameraFeature feature,
  CameraFeatureStatus status,
) {
  final name = featureLabel(feature);
  switch (status) {
    case CameraFeatureStatus.supported:
      return (
        label: 'Available',
        detail: 'Tested and working on this camera.',
        icon: Icons.check_circle_outline,
      );
    case CameraFeatureStatus.unvalidated:
      return (
        label: 'Under development',
        detail: 'Support for $name is wired up but not yet confirmed on this '
            'camera, so it stays disabled for now.',
        icon: Icons.construction_outlined,
      );
    case CameraFeatureStatus.unsupported:
      return (
        label: 'Not supported',
        detail: 'This camera does not have $name.',
        icon: Icons.block,
      );
  }
}
