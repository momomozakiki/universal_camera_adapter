import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';
import 'package:universal_camera_adapter_example/feature_support_doc.dart';
import 'package:universal_camera_adapter_example/main.dart';

/// Keeps `docs/camera/feature-support.md` honest.
///
/// Generating the table needs Flutter (the registry builds real adapters), so
/// it lives in a test rather than a `dart run` script — which turns out to be
/// the better home anyway: the same run that regenerates the file also *guards*
/// it, so a backend whose declaration changed cannot leave a stale published
/// table behind.
///
///   cd example
///   UPDATE_FEATURE_DOC=1 flutter test test/feature_support_doc_test.dart
void main() {
  const path = '../docs/camera/feature-support.md';

  test('the published feature-support table matches the backends', () {
    final registry = buildRegistry();
    final declarations = <String, Map<CameraFeature, CameraFeatureStatus>>{
      for (final type in registry.registeredTypes)
        type: registry.create(type).declaredFeatures,
    };

    final file = File(path);
    final exists = file.existsSync();

    // Reuse the committed date when only the table body matters, so a
    // regenerate that changes nothing produces no diff.
    final existing = exists ? file.readAsStringSync() : '';
    final previousDate = RegExp(r'^last_validated: (.+)$', multiLine: true)
        .firstMatch(existing)
        ?.group(1);

    final regenerating = Platform.environment['UPDATE_FEATURE_DOC'] == '1';
    final expected = renderFeatureSupportDoc(
      declarations,
      lastValidated: regenerating || previousDate == null
          ? DateTime.now().toIso8601String().split('T').first
          : previousDate,
    );

    if (regenerating) {
      file.writeAsStringSync(expected);
      return;
    }

    expect(
      exists,
      isTrue,
      reason: '$path is missing. Regenerate it with:\n'
          '  cd example && UPDATE_FEATURE_DOC=1 flutter test '
          'test/feature_support_doc_test.dart',
    );
    expect(
      existing,
      expected,
      reason: 'A backend\'s declaredFeatures changed but $path was not '
          'regenerated. Run:\n'
          '  cd example && UPDATE_FEATURE_DOC=1 flutter test '
          'test/feature_support_doc_test.dart',
    );
  });
}
