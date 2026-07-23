import 'package:flutter/widgets.dart';

import '../persistence/camera_profile.dart';

/// The first-time setup flow for one camera backend.
///
/// Camera *setup* is legitimately backend-specific — a built-in camera needs
/// nothing but a device picker, ONVIF needs host/port/credentials, EZVIZ needs
/// a cloud sign-in and a verification code. What must **not** be
/// backend-specific is how that UI is reached: a chooser that branches
/// `if (type == 'ezviz') … else if (type == 'onvif') …` gains a new arm for
/// every backend, which is the Open/Closed violation this type removes. A
/// wizard is *registered* (see `CameraSetupWizardRegistry`), and the chooser
/// renders whatever is registered without knowing any backend's steps.
///
/// The output of every wizard is uniform even though the input is not: a
/// [CameraProfile] the caller can persist and later re-open through the same
/// `open(device)` path every backend shares.
///
/// ## Two invariants every implementation must honor
///
/// 1. **The profile passed to `onComplete` is secret-free.** A wizard that
///    collects a password, token, or verification code writes it to a
///    `CameraSecretStore` under `profile.id` **before** calling `onComplete`,
///    and puts only non-sensitive connection details (host, port, username) in
///    `profile.device.metadata`. This is the same invariant [CameraProfile]
///    declares for itself — profiles are persisted in plaintext
///    `shared_preferences` and are safe to log or export, so a secret placed
///    there leaks. Write the secret *first*: if the write fails, call neither
///    callback and surface the error, or the caller persists a profile whose
///    secret is unreachable.
///
/// 2. **Exactly one of `onComplete`/`onCancel` is called, exactly once.** The
///    caller typically pushed a route and pops it in either callback, so a
///    second call pops a second route. Guard against the widget firing again
///    after `dispose`, and against a user double-tapping "Save".
///
/// Implementations should also **verify connectivity before completing**, so a
/// persisted profile is known-good rather than a guess the user only discovers
/// is wrong on the next launch. What that means is backend-specific: a network
/// backend can do a real `open()` round-trip; a local one may only be able to
/// confirm the device still enumerates.
///
/// Concrete wizards live in the consuming app (see `example/lib/setup/`), not
/// here — they touch vendor SDKs and a concrete secret-store implementation,
/// neither of which belongs in the published package.
abstract class CameraSetupWizard {
  /// The backend type this wizard sets up.
  ///
  /// Must match the string the corresponding adapter is registered under in
  /// `CameraAdapterRegistry`, since the profile this wizard produces carries it
  /// as [CameraProfile.backendType] and the session uses it to build an adapter.
  String get backendType;

  /// Human-readable label for the "Add camera" tile — e.g. `'Built-in camera'`,
  /// `'IP camera (ONVIF)'`, `'EZVIZ'`.
  String get displayName;

  /// Icon for the "Add camera" tile.
  IconData get icon;

  /// Builds the setup UI.
  ///
  /// Called when the user picks this backend's tile. The returned widget owns
  /// the whole flow — however many steps it takes — and terminates by calling
  /// exactly one of the two callbacks:
  ///
  /// - [onComplete] with a **secret-free** [CameraProfile] once setup succeeded
  ///   and any secret has already been written to the secret store.
  /// - [onCancel] if the user backs out. Any partial state (entered
  ///   credentials, a half-finished sign-in) should be discarded first.
  Widget build(
    BuildContext context, {
    required ValueChanged<CameraProfile> onComplete,
    required VoidCallback onCancel,
  });
}
