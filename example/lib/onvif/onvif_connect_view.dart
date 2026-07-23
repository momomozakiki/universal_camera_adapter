import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

/// Manual hardware test view for [ONVIFCameraAdapter] on Windows.
///
/// Deliberately **outside** the shared `CameraSession`/registry: unlike
/// `EzvizCameraAdapter`, `ONVIFCameraAdapter.credentials` is a `final`
/// constructor field (not settable post-construction) and `open()` ignores
/// its `CameraDevice` argument entirely — so this view owns its own adapter
/// instance and drives `open`/`close`/`buildPreview` directly. While
/// connected here, the other tabs (Preview/QR/PTZ/etc., which all read the
/// shared `CameraSession`) won't see this camera.
class OnvifConnectView extends StatefulWidget {
  const OnvifConnectView({super.key});

  @override
  State<OnvifConnectView> createState() => _OnvifConnectViewState();
}

class _OnvifConnectViewState extends State<OnvifConnectView> {
  static const _prefsHostKey = 'onvif_tab.host';
  static const _prefsUsernameKey = 'onvif_tab.username';
  // Plaintext SharedPreferences. This once matched the EZVIZ wizard's own
  // verification-code persistence; that key is gone as of Epic 2.5 Phase D
  // (secrets now go to CameraSecretStore, keyed by profile id), leaving these
  // three the **last** raw-prefs credentials in the tree. Phase E deletes this
  // whole file — its behavior moves into OnvifSetupWizard, which writes the
  // password to the secret store and keeps only host/port/username in the
  // profile. Do not copy this pattern (`state-management` Rule 6).
  static const _prefsPasswordKey = 'onvif_tab.password';

  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '8000');
  final _usernameController = TextEditingController(text: 'admin');
  final _passwordController = TextEditingController();

  ONVIFCameraAdapter? _adapter;
  bool _busy = false;
  bool _obscurePassword = true;
  String? _error;

  bool get _connected => _adapter?.isOpen ?? false;

  @override
  void initState() {
    super.initState();
    _restorePrefs();
  }

  Future<void> _restorePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString(_prefsHostKey);
    final username = prefs.getString(_prefsUsernameKey);
    final password = prefs.getString(_prefsPasswordKey);
    if (!mounted) return;
    setState(() {
      if (host != null) _hostController.text = host;
      if (username != null) _usernameController.text = username;
      if (password != null) _passwordController.text = password;
    });
  }

  Future<void> _savePref(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  @override
  void dispose() {
    unawaited(_adapter?.close());
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 8000;
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (host.isEmpty) {
      setState(() => _error = "Enter the camera's IP address.");
      return;
    }
    if (port < 1 || port > 65535) {
      setState(() => _error = 'Enter a valid port (1-65535).');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    unawaited(_savePref(_prefsHostKey, host));
    unawaited(_savePref(_prefsUsernameKey, username));
    unawaited(_savePref(_prefsPasswordKey, password));

    final adapter = ONVIFCameraAdapter(
      credentials: OnvifCredentials(
        host: host,
        port: port,
        username: username.isEmpty ? null : username,
        password: password.isEmpty ? null : password,
      ),
      verboseLogging: true,
    );
    try {
      await adapter.open(
        const CameraDevice(id: 'onvif-manual', name: 'ONVIF camera'),
        timeout: const Duration(seconds: 10),
      );
      if (!mounted) return;
      setState(() => _adapter = adapter);
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } on TimeoutException catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Connection timed out.');
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Malformed response from camera: ${e.message}');
    } on Object catch (e) {
      // Should not happen per ONVIFCameraAdapter.open()'s documented typed
      // surface — kept as a safety net so the UI never hangs silently.
      if (!mounted) return;
      setState(() => _error = 'Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyError(BuildContext context) async {
    final error = _error;
    if (error == null) return;
    await Clipboard.setData(ClipboardData(text: error));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Error message copied.'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    try {
      await _adapter?.close();
    } finally {
      if (mounted) {
        setState(() {
          _adapter = null;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_connected) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton(
              onPressed: _busy ? null : _disconnect,
              child: const Text('Disconnect'),
            ),
          ),
          Expanded(child: _adapter!.buildPreview()),
        ],
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _hostController,
            decoration: const InputDecoration(
              labelText: 'Host / IP address',
              hintText: '192.168.0.217',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _portController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'ONVIF port',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: 'Username',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Password / verification code',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SelectableText(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy error message',
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () => _copyError(context),
                  ),
                ],
              ),
            ),
          FilledButton(
            onPressed: _busy ? null : _connect,
            child: _busy
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Connect & preview'),
          ),
        ],
      ),
    );
  }
}
