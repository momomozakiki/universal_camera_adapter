import 'package:flutter/material.dart';

import '../camera_session.dart';
import '../scanning/barcode_decoder.dart';
import '../scanning/frame_scanner.dart';
import '../widgets/no_camera.dart';

/// Shared UI + lifecycle for the QR and 1D barcode tabs. Shows the live preview
/// with a scan hint, runs a [FrameScanner] over the shared session **only while
/// this tab is active and a camera is open**, and shows the latest decoded
/// value (or an inline error if the poll loop stops). The QR and barcode tabs
/// differ only in [formats] and copy — see `qr_scanner_tab.dart` /
/// `barcode_scanner_tab.dart`.
class ScannerTab extends StatefulWidget {
  const ScannerTab({
    super.key,
    required this.session,
    required this.active,
    required this.formats,
    required this.subject,
    required this.hint,
    required this.icon,
  });

  final CameraSession session;

  /// True when this is the visible tab. Scanning pauses when false so a hidden
  /// tab never fights for the shared camera.
  final bool active;

  /// `flutter_zxing` `Format` bitmask (e.g. `Format.qrCode`, `Format.linearCodes`).
  final int formats;

  /// Short noun for copy, e.g. "QR code" / "barcode".
  final String subject;
  final String hint;
  final IconData icon;

  @override
  State<ScannerTab> createState() => _ScannerTabState();
}

class _ScannerTabState extends State<ScannerTab> {
  late final FrameScanner _scanner = FrameScanner(
    session: widget.session,
    formats: widget.formats,
    onResult: _onResult,
    onError: _onError,
  );

  ScanResult? _last;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSessionChanged);
    _syncScanner();
  }

  @override
  void didUpdateWidget(covariant ScannerTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _syncScanner();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    // The camera may have opened/closed underneath us (e.g. inline Connect):
    // rebuild to swap between preview and placeholder, and (re)sync the loop.
    setState(() {});
    _syncScanner();
  }

  /// Runs the scanner iff this tab is visible AND a camera is open.
  void _syncScanner() {
    final shouldRun = widget.active && widget.session.isOpen;
    if (shouldRun && !_scanner.isRunning) {
      _error = null;
      _scanner.start();
    } else if (!shouldRun && _scanner.isRunning) {
      _scanner.stop();
    }
  }

  void _onResult(ScanResult result) {
    if (!mounted) return;
    setState(() {
      _last = result;
      _error = null;
    });
  }

  void _onError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    _scanner.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    if (!session.isOpen) {
      return NoCameraPlaceholder(
        session: session,
        icon: widget.icon,
        message: 'Connect a camera to scan a ${widget.subject}.',
      );
    }
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(child: session.buildPreview()),
              if (_last == null)
                Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      widget.hint,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
        _ResultPanel(subject: widget.subject, result: _last, error: _error),
      ],
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({
    required this.subject,
    required this.result,
    required this.error,
  });

  final String subject;
  final ScanResult? result;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color background;
    final Widget content;
    if (error != null) {
      background = theme.colorScheme.errorContainer;
      content = Text(
        'Scanning stopped: $error',
        style: TextStyle(color: theme.colorScheme.onErrorContainer),
      );
    } else if (result != null) {
      background = theme.colorScheme.secondaryContainer;
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result!.formatName,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            result!.text,
            style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
          ),
        ],
      );
    } else {
      background = theme.colorScheme.surfaceContainerHighest;
      content = Text('Waiting for a $subject…');
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: background,
      child: content,
    );
  }
}
