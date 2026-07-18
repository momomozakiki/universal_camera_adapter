import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart' show Format;

import '../camera_session.dart';
import 'scanner_tab.dart';

/// The 1D-barcode scanner (EAN/UPC/Code128/…): a thin wrapper over the shared
/// [ScannerTab], differing from the QR tab only in the format set and copy.
class BarcodeScannerTab extends StatelessWidget {
  const BarcodeScannerTab({
    super.key,
    required this.session,
    required this.active,
  });

  final CameraSession session;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return ScannerTab(
      session: session,
      active: active,
      formats: Format.linearCodes,
      subject: 'barcode',
      hint: 'Point the camera at a 1D barcode',
      icon: Icons.barcode_reader,
    );
  }
}
