import 'package:flutter_test/flutter_test.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';
import 'package:universal_camera_adapter_example/feature_messages.dart';
import 'package:universal_camera_adapter_example/main.dart';

import 'support/session_fakes.dart';

/// The feature checklist gate.
///
/// Integrating a new camera plugin must not let a feature slip through
/// undeclared — that is how a backend ends up silently inheriting a claim its
/// hardware cannot honour, and how the user gets told the *camera* lacks
/// something the *app* never wired.
///
/// Discovery is deliberately not a hard-coded list of adapter classes: it walks
/// [buildRegistry], so a newly registered backend is enrolled the moment it is
/// registered rather than whenever someone remembers to update a parallel list.
/// [CameraFeature] being a closed enum does the other half — add a tenth value
/// and every backend fails here until each one states a position on it.
void main() {
  final registry = buildRegistry();

  group('every registered backend declares every feature', () {
    for (final type in registry.registeredTypes) {
      test(type, () {
        final adapter = registry.create(type);
        final declared = adapter.declaredFeatures;

        final missing = CameraFeature.values
            .where((f) => !declared.containsKey(f))
            .map((f) => f.name)
            .toList();

        expect(
          missing,
          isEmpty,
          reason: "Backend '$type' has not declared: ${missing.join(', ')}.\n"
              'Every CameraFeature must be declared supported / unvalidated / '
              'unsupported in `declaredFeatures`.\n'
              'See docs/camera/feature-matrix.md.',
        );
      });
    }
  });

  test('the gate rejects a backend that declares nothing', () {
    // A gate that cannot fail is not a gate. This pins the actual mechanism:
    // `declaredFeatures` defaults to an empty map, so a backend that never
    // overrides it is caught rather than passing by inheritance.
    final undeclared =
        RecordingAdapter(const <CameraDevice>[]).declaredFeatures;
    final missing =
        CameraFeature.values.where((f) => !undeclared.containsKey(f));
    expect(
      missing,
      hasLength(CameraFeature.values.length),
      reason: 'An adapter that declares nothing must report every feature as '
          'missing — otherwise the checklist above proves nothing.',
    );
  });

  test('registry actually yielded backends to check', () {
    // Guards the gate itself: an empty registry would make every test above
    // vacuously pass and silently disable the checklist.
    expect(registry.registeredTypes, isNotEmpty);
  });

  test('every feature has a human-readable label', () {
    final unlabelled = CameraFeature.values
        .where((f) => !kFeatureLabels.containsKey(f))
        .map((f) => f.name)
        .toList();
    expect(
      unlabelled,
      isEmpty,
      reason: 'Add these to kFeatureLabels in feature_messages.dart so the UI '
          'never shows a raw enum name: ${unlabelled.join(', ')}.',
    );
  });
}
