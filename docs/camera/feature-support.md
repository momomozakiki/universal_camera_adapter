---
title: Camera Feature Support Matrix
version: 1.0
last_validated: 2026-07-27
official: true
source: generated
generator: example/test/feature_support_doc_test.dart
tags: [features, capabilities, matrix, backends]
applies_when: "Checking which backend supports which feature, or integrating a new camera plugin."
---

# Camera feature support by backend

> **Generated file — do not edit by hand.** The source of truth
> is each backend's `declaredFeatures`. Regenerate with:
>
> ```
> cd example
> UPDATE_FEATURE_DOC=1 flutter test test/feature_support_doc_test.dart
> ```

| Feature | builtin | ezviz | onvif |
|---|---|---|---|
| `zoom` | Under development | Not supported | Not supported |
| `pan` | Not supported | Not supported | Not supported |
| `tilt` | Not supported | Not supported | Not supported |
| `frameCapture` | Available | Under development | Under development |
| `qrScanning` | Available | Under development | Under development |
| `barcodeScanning` | Available | Under development | Under development |
| `textRecognitionOcr` | Under development | Under development | Under development |
| `twoWayAudio` | Not supported | Under development | Under development |
| `motionEvents` | Not supported | Under development | Under development |

## What the three states mean

- **Available** — manually tested and confirmed working.
- **Under development** — wired up but not yet confirmed on real
  hardware. Stays disabled in the UI: the app is unfinished, the
  camera is not at fault.
- **Not supported** — genuinely absent (e.g. no PTZ on a fixed
  webcam).

See `docs/camera/feature-matrix.md` for the model behind these,
and `.claude/skills/camera-adapter-authoring/SKILL.md` for the
checklist a new backend must satisfy.
