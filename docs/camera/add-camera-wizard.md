---
title: Modular Add-Camera Wizard Registry
version: 1.1
last_validated: 2026-07-23
official: true
source: project-internal
tags: [wizard, registry, ui, onboarding, modularity]
applies_when: "Adding a new camera backend or implementing the Cameras tab's 'Add camera' flow."
---

# Modular add-camera wizard registry

**Version 1.0** — *decoupled setup UI from backend logic, enabling new backends to be wired up
with zero hardcoded per-brand screens.*

## Revision History
| Version | Date       | Change   |
|---------|------------|----------|
| 1.0     | 2026-07-22 | Initial. |
| 1.1     | 2026-07-23 | **Implemented and marked `official`** (Epic 2.5 Phase D `13a0697`, Phase E `9533e47`, editing `2abce25`). Added the `supportsEditing`/`buildEditor` pair and the identity-preservation invariant that came with editing a saved camera; documented that renaming is handled generically by the Cameras tab, not by a wizard. Corrected the registry snippet to the as-built surface (`isRegistered`, typed errors, no `asDefault`) and the EZVIZ secret key to the shipped `'verificationCode'`. |

> **Spec version vs. code version.** Versioned independently of the package; a revision row names the
> commits whose behaviour it describes. When code and this document disagree, the code is the source
> of truth and this file is the bug.

## Problem

Today, when a new backend (ONVIF, EZVIZ, etc.) is added, the example app's Cameras tab needs
hardcoded UI: "if it's EZVIZ, show the sign-in flow; if it's ONVIF, show the IP entry screen; if
it's builtin, just show available devices." Adding a tenth backend means adding a tenth `if`
statement. This violates Open/Closed and couples the UI layer to knowledge of every backend's
internal steps.

## Solution: mirror the adapter registry pattern for setup UI

Just as `CameraAdapterRegistry` maps backend type → factory function → adapter instance, introduce
`CameraSetupWizardRegistry` mapping type → wizard factory → UI widget sequence. Registering a new
backend becomes two parallel registrations:

```dart
// At app startup
registry.register('ezviz', EzvizCameraAdapter.new, asDefault: false);
wizards.register('ezviz', EzvizSetupWizard.builder);   // new, parallel registry
```

Adding backend #10 requires no change to the Cameras tab — the wizard automatically appears.

## Interfaces

### `CameraSetupWizard` abstract base

```dart
abstract class CameraSetupWizard {
  /// Backend type: 'builtin', 'onvif', 'ezviz', etc.
  String get backendType;
  
  /// Display name shown in the "Add camera" tile. Example: "Local Camera" / "IP Camera" / "EZVIZ".
  String get displayName;
  
  /// An icon shown in the tile. Example: Icons.camera_alt, Icons.cloud, etc.
  IconData get icon;
  
  /// Build the wizard UI. Called when user taps this backend's tile.
  /// 
  /// Parameters:
  /// - onComplete: called with a CameraProfile once the user has finished setup
  ///   (and any secrets have been written to the SecretStore).
  /// - onCancel: called if the user dismisses/cancels the flow.
  Widget build(
    BuildContext context, {
    required ValueChanged<CameraProfile> onComplete,
    required VoidCallback onCancel,
  });

  /// Whether [buildEditor] is implemented — drives whether a saved camera of
  /// this backend offers an "Edit" action. A capability *query*, so the UI never
  /// branches on the backend type string.
  bool get supportsEditing => false;

  /// Re-open an already-saved profile for editing. Only called when
  /// [supportsEditing] is true; the base implementation throws
  /// [UnsupportedError].
  Widget buildEditor(
    BuildContext context, {
    required CameraProfile profile,
    required ValueChanged<CameraProfile> onComplete,
    required VoidCallback onCancel,
  });
}
```

Each concrete wizard (`BuiltinCameraSetupWizard`, `OnvifSetupWizard`, `EzvizSetupWizard`) owns its
internal step sequence (EZVIZ's steps: login → device list → verification code, all per
[`ezviz-setup-guide.md`](ezviz-setup-guide.md)). The registry never knows a wizard's internal
steps; it only knows the entry point (`build`) and that it eventually calls `onComplete` or
`onCancel`.

### Editing is opt-in

`supportsEditing`/`buildEditor` default to "not supported", mirroring how `CameraAdapter.setPan`/
`setTilt` default to throwing `UnsupportedError`: a backend whose setup is a pure device picker has
nothing to edit, and one whose setup is a vendor cloud sign-in may not be re-enterable field by
field. Those inherit the default and write no dead stub (interface segregation).

**Three invariants every implementation honors** — the first two apply to `build` and `buildEditor`
alike, the third only to `buildEditor`:

1. **The profile passed to `onComplete` is secret-free.** Any secret is written to
   `CameraSecretStore` under `profile.id` *before* `onComplete` fires. If that write throws, neither
   callback fires — otherwise the caller persists a profile whose secret is unreachable.
2. **Exactly one of `onComplete`/`onCancel` fires, exactly once.** The caller pops a route in either,
   so a second call pops a second route.
3. **`buildEditor` preserves identity.** The returned profile keeps the incoming `id`, `createdAt`
   and `isDefault` — build it with `copyWith`, never `CameraProfile.create`. A fresh `id` orphans the
   secret stored under the old one (secrets are keyed by profile id, with no way to reach them
   afterwards) and silently drops the user's default-camera choice. This is precisely why editing is
   a distinct entry point rather than "run the setup flow again".

An editor that collects a secret should re-verify connectivity before completing, exactly as `build`
does — an edit that saves an unreachable endpoint is no better than an add that does.

**Renaming is not a wizard concern.** `CameraProfile.displayName` is a plain field on the generic
profile, so the Cameras tab renames any camera itself via `CameraSession.updateProfile` — including
backends with no editor of their own.

### `CameraSetupWizardRegistry`

Same shape as `CameraAdapterRegistry`, but for UI:

```dart
class CameraSetupWizardRegistry {
  /// Register a wizard factory. Throws ArgumentError on an empty or duplicate type.
  void register(String type, CameraSetupWizardFactory factory);

  /// A fresh wizard instance per call — a wizard drives a stateful multi-step
  /// flow, so two concurrent setups must not share one. Throws StateError
  /// (listing the registered types) on an unknown type.
  CameraSetupWizard create(String type);

  bool isRegistered(String type);

  /// All registered types in registration order, unmodifiable — this is what
  /// the "Add camera" tile chooser iterates.
  List<String> get registeredTypes;
}
```

**Deliberate difference from `CameraAdapterRegistry`: no `asDefault`/`createDefault`.** A default
*backend* is meaningful; a default *setup wizard* is not, since the chooser always shows every tile.
The omission is a decision, not an oversight.

Located in `lib/src/setup/camera_setup_wizard_registry.dart` — a deliberately **separate**
registry from `CameraAdapterRegistry`, respecting Single Responsibility:
- One registry maps type → backend logic.
- The other maps type → setup UI.

A headless consumer that never shows an "add camera" UI never needs the wizard registry.

## How the Cameras tab stays generic

The Cameras tab's *"Add camera"* screen renders one tile per `wizards.registeredTypes()`:

```dart
class AddCameraSheet extends StatelessWidget {
  final CameraAdapterRegistry registry;
  final CameraSetupWizardRegistry wizards;
  
  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: wizards.registeredTypes.length,
      itemBuilder: (context, i) {
        final type = wizards.registeredTypes[i];
        final wizard = wizards.create(type);
        return CameraTypeCard(
          title: wizard.displayName,
          icon: wizard.icon,
          onTap: () => _launchWizard(context, wizard),
        );
      },
    );
  }
  
  void _launchWizard(BuildContext context, CameraSetupWizard wizard) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => wizard.build(
          context,
          onComplete: (profile) {
            // Save the profile, close the dialog, update the cameras list
            Navigator.pop(context);
          },
          onCancel: () {
            Navigator.pop(context);
          },
        ),
      ),
    );
  }
}
```

**Zero per-brand `if` statements.** Tiles appear automatically based on what's registered; the
logic for "how to set up an EZVIZ camera" lives entirely inside `EzvizSetupWizard`, not in the
Cameras tab.

## Secrets are written by the wizard

A wizard collecting a secret (EZVIZ verification code, ONVIF password, etc.) is passed the
injected `CameraSecretStore` as a constructor parameter. Before calling `onComplete(profile)`, the
wizard writes its secrets:

```dart
class EzvizSetupWizard extends CameraSetupWizard {
  final CameraSecretStore secretStore;
  
  EzvizSetupWizard({required this.secretStore});
  
  @override
  Widget build(BuildContext context, {
    required ValueChanged<CameraProfile> onComplete,
    required VoidCallback onCancel,
  }) {
    return _EzvizWizardFlow(
      secretStore: secretStore,
      onComplete: (profile, verificationCode) async {
        // Write the secret before completing
        if (verificationCode != null) {
          await secretStore.setSecret(
            profile.id,
            kEzvizVerificationCodeSecretKey, // 'verificationCode'
            verificationCode,
          );
        }
        // Now hand back the profile (secret-free)
        onComplete(profile);
      },
      onCancel: onCancel,
    );
  }
}
```

The returned `CameraProfile` never contains the secret, only a reference (its own `id`, which the
secret store is keyed by). This keeps profiles safe-to-persist-anywhere per
[`camera-profiles.md`](camera-profiles.md).

## Concrete wizards

### `BuiltinCameraSetupWizard`

The simplest wizard — local cameras need no setup beyond selecting from live `listDevices()` results.
Still registered to keep the chooser screen uniform:

```dart
@override
Widget build(BuildContext context, {
  required ValueChanged<CameraProfile> onComplete,
  required VoidCallback onCancel,
}) {
  return _BuiltinDevicePicker(
    onComplete: onComplete,
    onCancel: onCancel,
  );
}
```

### `OnvifSetupWizard`

Guides the user through ONVIF camera setup:
1. Choose discovery mode (manual IP entry, or WS-Discovery search).
2. (If manual) enter host, port, optional username/password.
3. Test connectivity.
4. Assign a friendly name.
5. Call `onComplete(profile)` (secrets, if auth credentials, written to store first).

### `EzvizSetupWizard`

Implements the corrected per-user EZVIZ flow per [`ezviz-setup-guide.md`](ezviz-setup-guide.md):
1. Detect EZVIZ login state.
2. If not logged in, show the onboarding card (deep-links to official app / web portal).
3. If logged in, show device list.
4. Per selected device, prompt for verification code (if needed).
5. Call `onComplete(profile)` with the verification code written to secure storage.

## Example app Cameras tab reshape

The example app gains a new `CamerasTab` (planned first or second in the bottom nav, since choosing
a camera logically precedes Preview/QR/Barcode/PTZ which all operate on a selected camera):

### What it displays

1. **Discovery pipeline results** (per [`discovery-pipeline.md`](discovery-pipeline.md)), grouped by
   stage:
   - *"This device"* — local cameras (Stage 1).
   - *"Network cameras found"* — ONVIF WS-Discovery results (Stage 2a).
   - *"Your EZVIZ cameras"* or *"Log in to see your EZVIZ cameras"* (Stage 2b).

2. **Saved profiles** (per [`camera-profiles.md`](camera-profiles.md)) with a "Default" badge.
   Re-select, re-order, or delete.

3. **"Add camera" floating action button** — opens the wizard chooser (described above).

### Switching between cameras

A new method on `CameraSession`:

```dart
class CameraSession {
  /// Switch the session to a different camera profile.
  /// Closes the current adapter, creates a new one for the profile's backend,
  /// and opens the device.
  Future<void> switchTo(CameraProfile profile) async {
    await close();
    _adapter = _registry.create(profile.backendType);
    await _adapter.open(profile.device);
  }
}
```

Selecting a different profile from the Cameras tab calls `session.switchTo(profile)`, seamlessly
swapping the underlying adapter (closing the old one first, per the existing one-open-device
invariant) and re-opening the preview.

### Retiring the old EZVIZ tab

`example/lib/tabs/ezviz_tab.dart` (the standalone diagnostic tab for EZVIZ testing via the bridge)
becomes obsolete once `EzvizCameraAdapter` + `EzvizSetupWizard` fully replace it:

- Onboarding is now via the wizard (Steps 1–4 in [`ezviz-setup-guide.md`](ezviz-setup-guide.md)).
- Playback is now via `EzvizCameraAdapter.buildPreview()` (wrapping `_EzvizNativePlayer`'s proven
  logic internally), used by the generic `PreviewTab` with no EZVIZ-specific code.

The tab is removed once the new flow is fully validated. At that time, `scripts/ezviz_bridge.py`
(the diagnostic bridge) is also deleted.

**Note:** This hasn't happened yet (as of this writing). Until the new native-login flow is fully
confirmed end-to-end (playback, persistence, sign-out), the old bridge and tab remain in place as
the working fallback.

## Future OCR tab

A future *"OCR"* tab (scanning text from live camera feed) would register its own wizard or share
the local-camera path, then display `captureFrame()` results and feed them to
`google_mlkit_text_recognition`. This tab is **not** added in v1.2 — it's gated on at least one
backend reporting `textRecognitionOcr: supported` (currently `unvalidated` across the board).

## Risks and open questions

- **Wizard complexity growth** — if future backends have very complex setup (multi-step auth,
  device pairing, etc.), the wizard widget tree could grow large. Consider splitting into separate
  files/modules per backend (e.g., `example/lib/wizards/ezviz_setup_wizard.dart`,
  `example/lib/wizards/onvif_setup_wizard.dart`) to keep each readable.

- **Validation and error recovery** — each wizard's internal flow needs clear error messages and
  recovery paths (e.g., "IP unreachable, try again" with an edit button). The registry's generic
  `build()` contract doesn't enforce this, so implementers must ensure their wizards are UX-solid.

- **Cancellation and partial state** — if a wizard is cancelled halfway (e.g., user taps back
  during EZVIZ sign-in), partial state (e.g., credentials in memory) should be cleaned up. The
  `onCancel` callback signals this intent to the caller.
