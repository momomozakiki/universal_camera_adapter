import 'dart:async';

import 'package:flutter/material.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

/// Build the registry once, at startup — the Golden Rule in practice:
/// the UI below depends only on [CameraAdapter] + [CameraAdapterRegistry],
/// never on the concrete [FlutterCameraAdapter].
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
      home: CameraPage(registry: registry),
    );
  }
}

class CameraPage extends StatefulWidget {
  const CameraPage({super.key, required this.registry});

  final CameraAdapterRegistry registry;

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  late final CameraAdapter _adapter = widget.registry.createDefault();

  List<CameraDevice> _devices = const <CameraDevice>[];
  bool _busy = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _refreshDevices();
  }

  @override
  void dispose() {
    // Lifecycle is strict: always close what we opened.
    unawaited(_adapter.close());
    super.dispose();
  }

  Future<void> _refreshDevices() async {
    setState(() => _busy = true);
    try {
      final devices = await _adapter.listDevices();
      setState(() {
        _devices = devices;
        _status = devices.isEmpty ? 'No cameras found.' : null;
      });
    } on StateError catch (e) {
      setState(() => _status = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(CameraDevice device) async {
    setState(() => _busy = true);
    try {
      await _adapter.open(device);
      setState(() => _status = 'Opened ${device.name} — ${_adapter.capabilities}');
    } on StateError catch (e) {
      setState(() => _status = 'Open failed: ${e.message}');
    } on TimeoutException {
      setState(() => _status = 'Camera took too long to respond.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _capture() async {
    try {
      final bytes = await _adapter.captureFrame();
      setState(() => _status = 'Captured ${bytes.length} bytes.');
    } on StateError catch (e) {
      setState(() => _status = 'Capture failed: ${e.message}');
    } on TimeoutException {
      setState(() => _status = 'Capture timed out.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Universal Camera Adapter'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _refreshDevices,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _adapter.isOpen
                ? _adapter.buildPreview()
                : Center(child: Text(_status ?? 'Select a camera below.')),
          ),
          if (_status != null && _adapter.isOpen)
            Padding(padding: const EdgeInsets.all(8), child: Text(_status!)),
          const Divider(height: 1),
          SizedBox(
            height: 120,
            child: ListView(
              children: [
                for (final device in _devices)
                  ListTile(
                    leading: const Icon(Icons.videocam),
                    title: Text(device.name),
                    subtitle: Text('${device.lensFacing.name} · ${device.id}'),
                    onTap: _busy ? null : () => _open(device),
                  ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _adapter.isOpen
          ? FloatingActionButton(
              onPressed: _capture,
              child: const Icon(Icons.camera),
            )
          : null,
    );
  }
}
