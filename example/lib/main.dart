import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

import 'adapter_types.dart';
import 'camera_session.dart';
import 'ezviz/ezviz_camera_adapter.dart';
import 'setup/builtin_camera_setup_wizard.dart';
import 'setup/ezviz_setup_wizard.dart';
import 'setup/onvif_setup_wizard.dart';
import 'tabs/barcode_scanner_tab.dart';
import 'tabs/cameras_tab.dart';
import 'tabs/features_tab.dart';
import 'tabs/gallery_tab.dart';
import 'tabs/preview_tab.dart';
import 'tabs/ptz_tab.dart';
import 'tabs/qr_scanner_tab.dart';

/// Build the registry once, at startup — the Golden Rule in practice:
/// the UI depends only on [CameraAdapter] + [CameraAdapterRegistry], never on
/// the concrete [FlutterCameraAdapter].
CameraAdapterRegistry buildRegistry() {
  final registry = CameraAdapterRegistry();
  registry.register(kBuiltinAdapterType, FlutterCameraAdapter.new, asDefault: true);
  registry.register(kEzvizAdapterType, EzvizCameraAdapter.new);
  // Zero-arg tear-off: the adapter reads its per-camera host/port/credentials
  // from `device.metadata` in open(), so one registration serves every ONVIF
  // camera the user adds, of any brand.
  registry.register(kOnvifAdapterType, ONVIFCameraAdapter.new);
  return registry;
}

/// The setup-UI counterpart to [buildRegistry].
///
/// Registration order is the order tiles appear in the "Add camera" sheet.
/// Wizard dependencies are injected here by closing over them, which is why the
/// registry's factory signature can stay zero-arg.
CameraSetupWizardRegistry buildWizardRegistry({
  required CameraAdapterRegistry registry,
  required CameraSecretStore secretStore,
}) {
  final wizards = CameraSetupWizardRegistry();
  wizards.register(
    kBuiltinAdapterType,
    () => BuiltinCameraSetupWizard(registry: registry),
  );
  wizards.register(
    kOnvifAdapterType,
    () => OnvifSetupWizard(registry: registry, secretStore: secretStore),
  );
  wizards.register(
    kEzvizAdapterType,
    () => EzvizSetupWizard(secretStore: secretStore),
  );
  return wizards;
}

/// One-shot import of the pre-`CameraProfile` credentials that the retired
/// `onvif_connect_view.dart` and EZVIZ wizard kept in loose preferences.
///
/// The legacy ONVIF view never persisted its **port** — the field was a
/// constructor default of `'8000'` — so that value is supplied here rather than
/// the adapter's `kDefaultOnvifPort` of 80, matching what that view actually
/// used. The imported profile is editable afterwards.
///
/// Safe to leave in place: it is guarded and idempotent. Once every install has
/// run it, this call and `migrateLegacyCameraSetup` can both be deleted.
Future<void> runLegacyMigration({
  required CameraProfileStore profileStore,
  required CameraSecretStore secretStore,
}) {
  return migrateLegacyCameraSetup(
    profileStore: profileStore,
    secretStore: secretStore,
    sources: <LegacyCameraSetup>[
      const LegacyCameraSetup(
        backendType: kOnvifAdapterType,
        displayName: 'Imported ONVIF camera',
        metadataKeys: <String, String>{
          'host': 'onvif_tab.host',
          'username': 'onvif_tab.username',
        },
        extraMetadata: <String, dynamic>{'port': 8000},
        secretPrefsKey: 'onvif_tab.password',
        secretName: kOnvifPasswordSecretKey,
        requiredMetadataKey: 'host',
      ),
    ],
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Required once before any media_kit API use (ONVIF's RtspPreview) — see
  // `lib/src/onvif/rtsp_preview.dart`.
  MediaKit.ensureInitialized();

  final registry = buildRegistry();
  final profileStore = SharedPreferencesCameraProfileStore();
  final secretStore = FlutterSecureStorageCameraSecretStore();
  // Without this, a backend that kills the process during startup restore makes
  // the app unlaunchable — see CameraRestoreGuard.
  final restoreGuard = SharedPreferencesCameraRestoreGuard();

  // Before the session loads profiles, so an imported camera is visible on the
  // very first frame rather than after a restart.
  await runLegacyMigration(
    profileStore: profileStore,
    secretStore: secretStore,
  );

  runApp(
    ExampleApp(
      registry: registry,
      profileStore: profileStore,
      secretStore: secretStore,
      restoreGuard: restoreGuard,
      wizards: buildWizardRegistry(
        registry: registry,
        secretStore: secretStore,
      ),
    ),
  );
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({
    super.key,
    required this.registry,
    required this.profileStore,
    required this.secretStore,
    required this.restoreGuard,
    required this.wizards,
  });

  final CameraAdapterRegistry registry;
  final CameraProfileStore profileStore;
  final CameraSecretStore secretStore;
  final CameraRestoreGuard restoreGuard;
  final CameraSetupWizardRegistry wizards;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'universal_camera_adapter example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: CameraToolkitPage(
        registry: registry,
        profileStore: profileStore,
        secretStore: secretStore,
        restoreGuard: restoreGuard,
        wizards: wizards,
      ),
    );
  }
}

/// A bottom-nav "camera testing toolkit". **Cameras comes first**: every other
/// tab operates on an already-chosen camera, so choosing one precedes using it.
/// The feature tabs stay visible but soft-gate on `NoCameraPlaceholder` until
/// something is open.
class CameraToolkitPage extends StatefulWidget {
  const CameraToolkitPage({
    super.key,
    required this.registry,
    required this.profileStore,
    required this.secretStore,
    required this.restoreGuard,
    required this.wizards,
  });

  final CameraAdapterRegistry registry;
  final CameraProfileStore profileStore;
  final CameraSecretStore secretStore;
  final CameraRestoreGuard restoreGuard;
  final CameraSetupWizardRegistry wizards;

  @override
  State<CameraToolkitPage> createState() => _CameraToolkitPageState();
}

class _CameraToolkitPageState extends State<CameraToolkitPage> {
  late final CameraSession _session = CameraSession(
    widget.registry,
    profileStore: widget.profileStore,
    secretStore: widget.secretStore,
    restoreGuard: widget.restoreGuard,
  );

  int _index = 0;

  static const _titles = <String>[
    'Cameras',
    'Preview',
    'QR scanner',
    'Barcode scanner',
    'Gallery',
    'PTZ / Zoom',
    'Features',
  ];

  @override
  void initState() {
    super.initState();
    // Loads saved cameras and opens the default one; falls back to live
    // discovery (listing only, camera stays off) when nothing is saved.
    _session.restore();
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilt on every tab switch so `active` flows to the scanner tabs; the
    // IndexedStack keeps all tabs (and the shared preview) alive across
    // switches, so scanners just pause rather than tear down.
    final tabs = <Widget>[
      CamerasTab(session: _session, wizards: widget.wizards),
      PreviewTab(session: _session),
      QrScannerTab(session: _session, active: _index == 2),
      BarcodeScannerTab(session: _session, active: _index == 3),
      GalleryTab(session: _session),
      PtzTab(session: _session),
      FeaturesTab(session: _session),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('Camera Toolkit · ${_titles[_index]}'),
        actions: [
          IconButton(
            tooltip: 'Refresh camera list',
            icon: const Icon(Icons.refresh),
            onPressed: _session.refreshDevices,
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.video_camera_back_outlined),
            selectedIcon: Icon(Icons.video_camera_back),
            label: 'Cameras',
          ),
          NavigationDestination(
            icon: Icon(Icons.videocam_outlined),
            selectedIcon: Icon(Icons.videocam),
            label: 'Preview',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner),
            label: 'QR',
          ),
          NavigationDestination(
            icon: Icon(Icons.barcode_reader),
            label: 'Barcode',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library),
            label: 'Gallery',
          ),
          NavigationDestination(
            icon: Icon(Icons.control_camera_outlined),
            selectedIcon: Icon(Icons.control_camera),
            label: 'PTZ',
          ),
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(Icons.fact_check),
            label: 'Features',
          ),
        ],
      ),
    );
  }
}
