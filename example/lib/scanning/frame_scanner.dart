import 'dart:async';

import '../camera_session.dart';
import 'barcode_decoder.dart';

/// Polls [CameraSession.captureFrame] on an interval, decodes each frame for
/// the given [formats], and reports results via callbacks. Shared by the QR and
/// 1D barcode tabs — each holds its own instance with its own format set.
///
/// Behaviour:
/// - **No code found** is the normal per-frame case → silent, keep polling.
/// - A **capture failure** (`StateError` when the camera closes,
///   `TimeoutException`) → stop the loop and report via [onError] so the tab
///   can show it inline (no snackbar spam).
/// - **Never captures while a capture is in flight** (the [_inFlight] guard),
///   so a slow `captureFrame` just lowers the effective rate instead of
///   queueing captures.
/// - Stops cleanly on [stop]/dispose so no capture outlives the widget.
class FrameScanner {
  FrameScanner({
    required this.session,
    required this.formats,
    required this.onResult,
    required this.onError,
    this.interval = const Duration(milliseconds: 400),
  });

  final CameraSession session;
  final int formats;
  final void Function(ScanResult result) onResult;
  final void Function(String message) onError;
  final Duration interval;

  Timer? _timer;
  bool _inFlight = false;
  bool _running = false;

  bool get isRunning => _running;

  void start() {
    if (_running) return;
    _running = true;
    _timer = Timer.periodic(interval, (_) => _tick());
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    if (!_running || _inFlight || !session.isOpen) return;
    _inFlight = true;
    try {
      final bytes = await session.captureFrame();
      if (!_running) return;
      final result = decodeBarcode(bytes, formats: formats);
      if (result != null && _running) onResult(result);
    } on StateError catch (e) {
      stop();
      onError(e.message);
    } on TimeoutException {
      stop();
      onError('The camera took too long to respond.');
    } on Object {
      // A decode failure (corrupt/blurred frame) is non-fatal — skip this
      // frame and keep polling.
    } finally {
      _inFlight = false;
    }
  }
}
