import 'package:flutter/material.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

import '../camera_session.dart';
import '../scanning/barcode_decoder.dart';
import '../scanning/frame_scanner.dart';
import '../widgets/camera_bar.dart';
import '../widgets/camera_stage.dart';
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

  /// Runs the scanner iff this tab is visible, a camera is open, **and** that
  /// camera can actually deliver frames.
  ///
  /// The frameCapture gate matters because scanning is built entirely on the
  /// generic `captureFrame()` primitive: a backend whose capture is not wired
  /// (EZVIZ today, pending the native `capturePicture` patch) reports
  /// `unvalidated`, and without this check the loop would fail once per frame
  /// instead of saying "not supported" once.
  void _syncScanner() {
    final shouldRun = widget.active &&
        widget.session.isOpen &&
        widget.session.supports(CameraFeature.frameCapture);
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CameraBar(session: session),
          const SizedBox(height: 12),
          _body(context, session),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, CameraSession session) {
    if (!session.isOpen) {
      return NoCameraPlaceholder(
        icon: widget.icon,
        message: 'Connect a camera to scan a ${widget.subject}.',
      );
    }
    if (!session.supports(CameraFeature.frameCapture)) {
      // Degrade to a clear "not supported" rather than a stream of per-frame
      // errors — the whole point of querying support instead of assuming it.
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.icon,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'This camera cannot capture still frames yet, so '
              '${widget.subject} scanning is unavailable for it.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        CameraStage(
          session: session,
          active: widget.active,
          overlay: _last == null
              ? Align(
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
                )
              : null,
        ),
        const SizedBox(height: 12),
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
