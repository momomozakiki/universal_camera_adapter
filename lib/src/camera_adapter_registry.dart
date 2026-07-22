import 'camera_adapter.dart';

/// A factory that builds a fresh [CameraAdapter] instance.
typedef CameraAdapterFactory = CameraAdapter Function();

/// An **instance-based** (not singleton) registry of camera backends.
///
/// Each app or test builds its own registry, so isolated registries never
/// interfere with one another. Backends register a string `type` → factory;
/// [create] returns a fresh instance each call.
///
/// ```dart
/// final registry = CameraAdapterRegistry();
/// registry.register('builtin', FlutterCameraAdapter.new, asDefault: true);
/// final adapter = registry.createDefault();
/// ```
class CameraAdapterRegistry {
  CameraAdapterRegistry();

  final Map<String, CameraAdapterFactory> _factories = <String, CameraAdapterFactory>{};
  String? _defaultType;

  /// Registers [factory] under [type].
  ///
  /// If [asDefault] is `true`, this backend becomes the default returned by
  /// [createDefault]. Registering is never implicitly "first one wins" — a
  /// default exists only when explicitly requested.
  ///
  /// Throws [ArgumentError] if [type] is empty or already registered.
  void register(
    String type,
    CameraAdapterFactory factory, {
    bool asDefault = false,
  }) {
    if (type.isEmpty) {
      throw ArgumentError.value(type, 'type', 'Backend type must not be empty');
    }
    if (_factories.containsKey(type)) {
      throw ArgumentError.value(type, 'type', 'Backend type already registered');
    }
    _factories[type] = factory;
    if (asDefault) {
      _defaultType = type;
    }
  }

  /// Creates a fresh instance of the backend registered under [type].
  ///
  /// Throws [StateError] if [type] is not registered.
  CameraAdapter create(String type) {
    final factory = _factories[type];
    if (factory == null) {
      throw StateError(
        'No camera backend registered for type "$type". '
        'Registered types: ${registeredTypes.join(', ')}.',
      );
    }
    return factory();
  }

  /// Creates a fresh instance of the default backend.
  ///
  /// Throws [StateError] if no default has been set.
  CameraAdapter createDefault() {
    final type = _defaultType;
    if (type == null) {
      throw StateError(
        'No default camera backend registered. '
        'Register one with asDefault: true, or call create(type).',
      );
    }
    return create(type);
  }

  /// Whether a default backend has been registered.
  bool hasDefault() => _defaultType != null;

  /// The registered type of the default backend, or null if none was set.
  String? get defaultType => _defaultType;

  /// Whether a backend is registered under [type].
  bool isRegistered(String type) => _factories.containsKey(type);

  /// The registered backend types, in registration order.
  List<String> get registeredTypes => List<String>.unmodifiable(_factories.keys);
}
