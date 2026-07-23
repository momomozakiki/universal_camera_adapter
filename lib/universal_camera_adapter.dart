/// A modular, pluggable camera abstraction for Flutter.
///
/// Unifies local device cameras (Android, Windows) and external network/IP
/// cameras (ONVIF/RTSP — planned) behind a single [CameraAdapter] contract.
///
/// Consumers should follow the Golden Rule: depend on [CameraAdapter] and
/// [CameraAdapterRegistry], not on a concrete backend, and check
/// [CameraCapabilities] at runtime.
library;

// Core contract and value types.
export 'src/camera_adapter.dart' show CameraAdapter, kDefaultCameraTimeout;
export 'src/camera_adapter_registry.dart'
    show CameraAdapterRegistry, CameraAdapterFactory;
export 'src/camera_types.dart'
    show CameraDevice, CameraCapabilities, CameraLensFacing;
export 'src/camera_feature.dart'
    show
        CameraFeature,
        CameraFeatureStatus,
        CameraFeatureSupport,
        CameraFeatureMatrix,
        kFeatureBundles;

// Shipped backend.
export 'src/flutter_camera_adapter.dart' show FlutterCameraAdapter;

// Planned network backend (scaffolding — throws UnimplementedError).
export 'src/onvif/onvif_camera_adapter.dart'
    show ONVIFCameraAdapter, OnvifCredentials;

// Camera profile + secret persistence (Epic 2.5).
export 'src/persistence/camera_profile.dart' show CameraProfile;
export 'src/persistence/camera_profile_store.dart'
    show CameraProfileStore, SharedPreferencesCameraProfileStore;
export 'src/persistence/camera_secret_store.dart'
    show CameraSecretStore, FlutterSecureStorageCameraSecretStore;
