import 'camera_setup_wizard.dart';

/// A factory that builds a fresh [CameraSetupWizard] instance.
///
/// Zero-arg, mirroring `CameraAdapterFactory`. A wizard that needs
/// dependencies — an adapter registry to test a connection, a secret store to
/// write to — receives them by closing over them at the registration site:
///
/// ```dart
/// wizards.register('onvif', () => OnvifSetupWizard(
///   registry: registry,
///   secretStore: secrets,
/// ));
/// ```
typedef CameraSetupWizardFactory = CameraSetupWizard Function();

/// An **instance-based** (not singleton) registry of camera setup flows.
///
/// The UI counterpart to `CameraAdapterRegistry`, and deliberately a
/// **separate** registry rather than another field on it (Single
/// Responsibility): one maps a backend type to its *logic*, this one maps a
/// backend type to its *setup UI*. A headless consumer — a service, a test, an
/// app that only ever opens a hardcoded camera — never shows an "add camera"
/// screen and so never needs this class at all.
///
/// The payoff is at the call site: an "Add camera" chooser renders one tile per
/// [registeredTypes] and knows nothing about any backend's steps, so adding
/// backend number ten needs no change to it.
///
/// ```dart
/// final wizards = CameraSetupWizardRegistry();
/// wizards.register('builtin', () => BuiltinCameraSetupWizard(registry: registry));
/// wizards.register('onvif', () => OnvifSetupWizard(registry: registry, secretStore: secrets));
///
/// for (final type in wizards.registeredTypes) {
///   final wizard = wizards.create(type);
///   // …render a tile with wizard.displayName / wizard.icon
/// }
/// ```
///
/// **No `asDefault`/`createDefault`, deliberately.** `CameraAdapterRegistry`
/// has them because an app genuinely needs a backend to fall back to. There is
/// no equivalent notion of a "default setup flow" — the chooser always offers
/// every registered type, and picking one is the user's whole job on that
/// screen. The omission is a decision, not an oversight.
class CameraSetupWizardRegistry {
  CameraSetupWizardRegistry();

  final Map<String, CameraSetupWizardFactory> _factories =
      <String, CameraSetupWizardFactory>{};

  /// Registers [factory] under [type].
  ///
  /// [type] should match the string the corresponding adapter uses in
  /// `CameraAdapterRegistry`, so a profile produced here can be reopened later.
  ///
  /// Throws [ArgumentError] if [type] is empty or already registered.
  void register(String type, CameraSetupWizardFactory factory) {
    if (type.isEmpty) {
      throw ArgumentError.value(type, 'type', 'Backend type must not be empty');
    }
    if (_factories.containsKey(type)) {
      throw ArgumentError.value(
        type,
        'type',
        'A setup wizard is already registered for this backend type',
      );
    }
    _factories[type] = factory;
  }

  /// Creates a fresh wizard for [type].
  ///
  /// Fresh per call, like `CameraAdapterRegistry.create` — a wizard drives a
  /// stateful flow, so two concurrent setups must not share one instance.
  ///
  /// Throws [StateError] if [type] is not registered.
  CameraSetupWizard create(String type) {
    final factory = _factories[type];
    if (factory == null) {
      throw StateError(
        'No camera setup wizard registered for type "$type". '
        'Registered types: ${registeredTypes.join(', ')}.',
      );
    }
    return factory();
  }

  /// Whether a wizard is registered under [type].
  ///
  /// Useful for a UI that offers "set up this camera" only when the backend
  /// actually has a setup flow.
  bool isRegistered(String type) => _factories.containsKey(type);

  /// The registered backend types, in registration order.
  ///
  /// Registration order is the chooser's display order, so register in the
  /// order you want tiles to appear.
  List<String> get registeredTypes => List<String>.unmodifiable(_factories.keys);
}
