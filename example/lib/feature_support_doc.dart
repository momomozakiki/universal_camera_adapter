/// Renders `docs/camera/feature-support.md` from the live backend
/// declarations.
///
/// Kept as a pure function rather than a script because generating it needs
/// Flutter (the registry builds real adapters), which a plain `dart run`
/// cannot compile. `test/feature_support_doc_test.dart` both regenerates the
/// file and fails when the committed copy has drifted — so the table cannot go
/// stale without the suite saying so.
library;

import 'package:universal_camera_adapter/universal_camera_adapter.dart';

/// Bumped by hand when the *shape* of the document changes.
const String kFeatureSupportDocVersion = '1.0';

/// The user-facing name of [status] — the same three words the UI uses, so the
/// doc and the app never disagree about vocabulary.
String featureSupportCell(CameraFeatureStatus status) {
  switch (status) {
    case CameraFeatureStatus.supported:
      return 'Available';
    case CameraFeatureStatus.unvalidated:
      return 'Under development';
    case CameraFeatureStatus.unsupported:
      return 'Not supported';
  }
}

/// Builds the full markdown document for [declarations] (backend type →
/// declared statuses).
///
/// [lastValidated] is passed in rather than read from the clock so the output
/// is deterministic: a regenerated-but-unchanged file must not produce a diff.
String renderFeatureSupportDoc(
  Map<String, Map<CameraFeature, CameraFeatureStatus>> declarations, {
  required String lastValidated,
}) {
  final types = declarations.keys.toList()..sort();
  final buffer = StringBuffer()
    ..writeln('---')
    ..writeln('title: Camera Feature Support Matrix')
    ..writeln('version: $kFeatureSupportDocVersion')
    ..writeln('last_validated: $lastValidated')
    ..writeln('official: true')
    ..writeln('source: generated')
    ..writeln('generator: example/test/feature_support_doc_test.dart')
    ..writeln('tags: [features, capabilities, matrix, backends]')
    ..writeln('applies_when: "Checking which backend supports which feature, '
        'or integrating a new camera plugin."')
    ..writeln('---')
    ..writeln()
    ..writeln('# Camera feature support by backend')
    ..writeln()
    ..writeln('> **Generated file — do not edit by hand.** The source of truth')
    ..writeln('> is each backend\'s `declaredFeatures`. Regenerate with:')
    ..writeln('>')
    ..writeln('> ```')
    ..writeln('> cd example')
    ..writeln('> UPDATE_FEATURE_DOC=1 flutter test test/feature_support_doc_test.dart')
    ..writeln('> ```')
    ..writeln()
    ..writeln('| Feature | ${types.join(' | ')} |')
    ..writeln('|---|${types.map((_) => '---').join('|')}|');

  for (final feature in CameraFeature.values) {
    final cells = types.map((type) {
      final status =
          declarations[type]![feature] ?? CameraFeatureStatus.unvalidated;
      return featureSupportCell(status);
    });
    buffer.writeln('| `${feature.name}` | ${cells.join(' | ')} |');
  }

  buffer
    ..writeln()
    ..writeln('## What the three states mean')
    ..writeln()
    ..writeln('- **Available** — manually tested and confirmed working.')
    ..writeln('- **Under development** — wired up but not yet confirmed on real')
    ..writeln('  hardware. Stays disabled in the UI: the app is unfinished, the')
    ..writeln('  camera is not at fault.')
    ..writeln('- **Not supported** — genuinely absent (e.g. no PTZ on a fixed')
    ..writeln('  webcam).')
    ..writeln()
    ..writeln('See `docs/camera/feature-matrix.md` for the model behind these,')
    ..writeln('and `.claude/skills/camera-adapter-authoring/SKILL.md` for the')
    ..writeln('checklist a new backend must satisfy.');

  return buffer.toString();
}
