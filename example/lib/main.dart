import 'package:flutter/material.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

import 'camera_session.dart';
import 'tabs/barcode_scanner_tab.dart';
import 'tabs/ezviz_tab.dart';
import 'tabs/gallery_tab.dart';
import 'tabs/preview_tab.dart';
import 'tabs/ptz_tab.dart';
import 'tabs/qr_scanner_tab.dart';

/// Build the registry once, at startup — the Golden Rule in practice:
/// the UI depends only on [CameraAdapter] + [CameraAdapterRegistry], never on
/// the concrete [FlutterCameraAdapter].
CameraAdapterRegistry buildRegistry() {
  final registry = CameraAdapterRegistry();
  registry.register('builtin', FlutterCameraAdapter.new, asDefault: true);
  // Future: registry.register('onvif', ONVIFCameraAdapter.new);
  return registry;
}

void main() {
  runApp(ExampleApp(registry: buildRegistry()));
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key, required this.registry});

  final CameraAdapterRegistry registry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'universal_camera_adapter example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: CameraToolkitPage(registry: registry),
    );
  }
}

/// A bottom-nav "camera testing toolkit": one shared [CameraSession] (so at
/// most one device is ever open) surfaced through several self-contained
/// testing tabs — Preview/Capture, QR scanner, 1D barcode scanner, a
/// capture gallery, and a PTZ/zoom capability tester.
class CameraToolkitPage extends StatefulWidget {
  const CameraToolkitPage({super.key, required this.registry});

  final CameraAdapterRegistry registry;

  @override
  State<CameraToolkitPage> createState() => _CameraToolkitPageState();
}

class _CameraToolkitPageState extends State<CameraToolkitPage> {
  late final CameraSession _session =
      CameraSession(widget.registry.createDefault());

  int _index = 0;

  static const _titles = <String>[
    'Preview',
    'QR scanner',
    'Barcode scanner',
    'Gallery',
    'PTZ / Zoom',
    'EZVIZ bridge',
  ];

  @override
  void initState() {
    super.initState();
    // List devices only — the camera stays off until the user taps Connect.
    _session.refreshDevices();
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
      PreviewTab(session: _session),
      QrScannerTab(session: _session, active: _index == 1),
      BarcodeScannerTab(session: _session, active: _index == 2),
      GalleryTab(session: _session),
      PtzTab(session: _session),
      const EzvizTab(),
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
            icon: Icon(Icons.cloud_outlined),
            selectedIcon: Icon(Icons.cloud),
            label: 'EZVIZ',
          ),
        ],
      ),
    );
  }
}
