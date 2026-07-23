import 'dart:async';

import 'package:flutter/material.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

import '../adapter_types.dart';

/// `CameraSecretStore` key the ONVIF password is stored under, scoped to a
/// profile id. Shared by this wizard (writer) and `CameraSession` (reader).
const String kOnvifPasswordSecretKey = 'password';

/// The secret-free / secret split for one ONVIF camera being set up.
///
/// Exists so the split can be built and asserted **without a widget, a network,
/// or a platform channel** — it is the security-critical part of this wizard,
/// so it is the part worth unit-testing.
@immutable
class OnvifSetupDraft {
  const OnvifSetupDraft({required this.profile, required this.password});

  /// Secret-free, safe to persist and log. Its `device.metadata` carries only
  /// `host`/`port`/`username`.
  final CameraProfile profile;

  /// The password, to be written to a `CameraSecretStore` under
  /// [CameraProfile.id]. Never present in [profile]. `null` when the camera
  /// needs no authentication.
  final String? password;

  /// A **throwaway** copy of the device with the password merged into its
  /// metadata, for passing to `CameraAdapter.open`.
  ///
  /// This is the transient-merge mechanism the whole design rests on: the
  /// adapter reads credentials from `device.metadata` (see
  /// `OnvifCredentials.fromMetadata`), so the secret only ever exists in a
  /// short-lived copy. **Never persist this** — persist [profile].
  CameraDevice get connectableDevice {
    final secret = password;
    if (secret == null) return profile.device;
    return profile.device.copyWith(
      metadata: <String, dynamic>{...profile.device.metadata, 'password': secret},
    );
  }
}

/// Turns raw form input into an [OnvifSetupDraft], validating as it goes.
///
/// Validation is delegated to [OnvifCredentials.fromMetadata] rather than
/// duplicated here, so the wizard and `ONVIFCameraAdapter.open` can never
/// disagree about what a valid endpoint is. It throws the adapter's own typed
/// errors — [FormatException] for a malformed field, [StateError] for a missing
/// host — which the caller renders inline.
///
/// Called **before** any network attempt: a typo should fail instantly rather
/// than after a connection timeout.
OnvifSetupDraft buildOnvifSetupDraft({
  required String host,
  required String port,
  required String username,
  required String password,
  required String displayName,
}) {
  final trimmedHost = host.trim();
  final trimmedPort = port.trim();
  final trimmedUser = username.trim();
  final trimmedName = displayName.trim();

  final metadata = <String, dynamic>{
    // An empty field means "not supplied", so omit it rather than passing ''.
    // That distinction is load-bearing: an absent host is a StateError
    // ("missing config"), while a present-but-blank one is a FormatException
    // ("malformed"). A user who simply hasn't typed anything yet should get
    // the former.
    if (trimmedHost.isNotEmpty) 'host': trimmedHost,
    if (trimmedPort.isNotEmpty) 'port': trimmedPort,
    if (trimmedUser.isNotEmpty) 'username': trimmedUser,
  };

  // Throws FormatException / StateError on bad input. Also normalizes the port
  // (a blank field becomes kDefaultOnvifPort), which is why the parsed result
  // is written back below rather than the raw text being persisted.
  final credentials = OnvifCredentials.fromMetadata(<String, dynamic>{
    ...metadata,
    if (password.isNotEmpty) 'password': password,
  });

  metadata['host'] = credentials.host;
  metadata['port'] = credentials.port;

  final device = CameraDevice(
    // host:port is the stable identity of an ONVIF endpoint, and is the same
    // key a restored profile is matched on — an ONVIF device has no reliable
    // serial to key off.
    id: '${credentials.host}:${credentials.port}',
    name: trimmedName.isEmpty ? credentials.host : trimmedName,
    lensFacing: CameraLensFacing.external,
    metadata: metadata,
  );

  return OnvifSetupDraft(
    profile: CameraProfile.create(
      backendType: kOnvifAdapterType,
      displayName: device.name,
      device: device,
    ),
    password: password.isEmpty ? null : password,
  );
}

/// Setup flow for any ONVIF-compliant IP camera.
///
/// Vendor-neutral by design: Hikvision, Dahua, Reolink, Axis and EZVIZ all
/// speak the same `host`/`port`/`username`/`password` vocabulary, so one wizard
/// covers every brand and many cameras can be added, each becoming its own
/// `CameraProfile`.
class OnvifSetupWizard extends CameraSetupWizard {
  OnvifSetupWizard({required this.registry, required this.secretStore});

  /// Used to build a throwaway adapter for the connectivity test — via the
  /// registry rather than `ONVIFCameraAdapter()` directly, so even the example
  /// app never names a concrete backend (the Golden Rule).
  final CameraAdapterRegistry registry;

  final CameraSecretStore secretStore;

  @override
  String get backendType => kOnvifAdapterType;

  @override
  String get displayName => 'IP camera (ONVIF)';

  @override
  IconData get icon => Icons.lan_outlined;

  @override
  Widget build(
    BuildContext context, {
    required ValueChanged<CameraProfile> onComplete,
    required VoidCallback onCancel,
  }) {
    return _OnvifSetupForm(
      registry: registry,
      secretStore: secretStore,
      onComplete: onComplete,
      onCancel: onCancel,
    );
  }
}

class _OnvifSetupForm extends StatefulWidget {
  const _OnvifSetupForm({
    required this.registry,
    required this.secretStore,
    required this.onComplete,
    required this.onCancel,
  });

  final CameraAdapterRegistry registry;
  final CameraSecretStore secretStore;
  final ValueChanged<CameraProfile> onComplete;
  final VoidCallback onCancel;

  @override
  State<_OnvifSetupForm> createState() => _OnvifSetupFormState();
}

class _OnvifSetupFormState extends State<_OnvifSetupForm> {
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '$kDefaultOnvifPort');
  final _usernameController = TextEditingController(text: 'admin');
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  bool _busy = false;
  bool _obscurePassword = true;
  String? _error;
  String? _status;

  /// Guards the "exactly one callback, exactly once" invariant against a
  /// double-tap or a late async completion.
  bool _finished = false;

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _testAndSave() async {
    if (_finished) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });

    try {
      // 1. Validate locally — instant feedback on a typo, no network wait.
      final draft = buildOnvifSetupDraft(
        host: _hostController.text,
        port: _portController.text,
        username: _usernameController.text,
        password: _passwordController.text,
        displayName: _nameController.text,
      );

      // 2. Prove the camera is actually reachable and speaks ONVIF before
      //    anything is persisted, so a saved profile is known-good rather than
      //    a guess the user only discovers is wrong on the next launch. This is
      //    a real GetDeviceInformation → GetProfiles → GetStreamUri round-trip.
      if (mounted) setState(() => _status = 'Contacting camera…');
      final adapter = widget.registry.create(kOnvifAdapterType);
      try {
        await adapter.open(draft.connectableDevice);
      } finally {
        // Release the connection and preview regardless of outcome — the
        // session will open its own adapter later.
        await adapter.close();
      }
      if (!mounted) return;

      // 3. Write the secret BEFORE completing. If this throws, neither callback
      //    fires, so the caller never persists a profile whose password is
      //    unreachable.
      final password = draft.password;
      if (password != null) {
        setState(() => _status = 'Saving credentials…');
        await widget.secretStore.setSecret(
          draft.profile.id,
          kOnvifPasswordSecretKey,
          password,
        );
      }
      if (!mounted) return;

      _finished = true;
      widget.onComplete(draft.profile);
    } on FormatException catch (e) {
      // Message names the offending field and its type, never its value.
      _fail(e.message);
    } on StateError catch (e) {
      _fail(e.message);
    } on TimeoutException {
      _fail('The camera did not respond in time. Check the host and port.');
    } on Object catch (e) {
      _fail('$e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  void _fail(String message) {
    if (mounted) setState(() => _error = message);
  }

  void _cancel() {
    if (_finished) return;
    _finished = true;
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Works with any ONVIF-compliant camera — Hikvision, Dahua, Reolink, '
          'Axis, EZVIZ and others. Add as many as you like; each is saved '
          'separately.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _hostController,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Host or IP address',
            hintText: '192.168.0.217',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _portController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Port',
            helperText: 'Usually 80; some cameras use 8000',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _usernameController,
          decoration: const InputDecoration(
            labelText: 'Username (if required)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: 'Password (if required)',
            helperText: 'Stored in encrypted storage, never with the profile',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility : Icons.visibility_off,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Name for this camera',
            hintText: 'Front door',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text(_status!),
              ],
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        FilledButton(
          onPressed: _busy ? null : _testAndSave,
          child: const Text('Test connection & save'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : _cancel,
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
