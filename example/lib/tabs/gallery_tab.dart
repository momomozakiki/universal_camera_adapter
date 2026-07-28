import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../camera_session.dart';
import '../error_messages.dart';
import '../widgets/camera_bar.dart';
import '../widgets/camera_empty_state.dart';

/// Capture-and-collect: tap Capture to append a frame from
/// [CameraSession.captureFrame] to an in-memory strip of thumbnails (tap one to
/// enlarge), with a Clear-all. A pure exercise of the existing `captureFrame`
/// API — no scanning, no new adapter surface.
class GalleryTab extends StatefulWidget {
  const GalleryTab({super.key, required this.session});

  final CameraSession session;

  @override
  State<GalleryTab> createState() => _GalleryTabState();
}

class _GalleryTabState extends State<GalleryTab> {
  final List<Uint8List> _shots = <Uint8List>[];
  bool _capturing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSessionChanged);
  }

  void _onSessionChanged() {
    // Swap between the placeholder and the gallery when the camera opens/closes.
    if (mounted) setState(() {});
  }

  Future<void> _capture() async {
    setState(() {
      _capturing = true;
      _error = null;
    });
    try {
      final bytes = await widget.session.captureFrame();
      if (!mounted) return;
      setState(() => _shots.insert(0, bytes));
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = describeCameraError(e, action: 'capturing a frame'));
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _clear() => setState(() {
        _shots.clear();
        _error = null;
      });

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: CameraBar(session: session),
        ),
        if (!session.isOpen)
          const Expanded(
            child: CameraEmptyState(
              icon: Icons.photo_library_outlined,
              headline: 'Connect a camera to capture photos.',
              hint: kConnectACameraHint,
            ),
          )
        else ...[
          Expanded(
            child: _shots.isEmpty
              ? Center(
                  child: Text(
                    'No captures yet.\nTap Capture to grab a frame.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _shots.length,
                  itemBuilder: (context, i) => GestureDetector(
                    onTap: () => _enlarge(_shots[i]),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(_shots[i], fit: BoxFit.cover),
                    ),
                  ),
                ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              // _error is already a complete sentence from describeCameraError;
              // a "Capture failed:" prefix would say it twice.
              _error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _capturing ? null : _capture,
                  icon: _capturing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.camera),
                  label: Text(
                    _shots.isEmpty
                        ? 'Capture'
                        : 'Capture (${_shots.length})',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _shots.isEmpty ? null : _clear,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear all'),
              ),
            ],
          ),
        ),
        ],
      ],
    );
  }

  void _enlarge(Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: InteractiveViewer(
          child: Image.memory(bytes),
        ),
      ),
    );
  }
}
