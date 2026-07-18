import 'dart:typed_data';

import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:image/image.dart' as img;

/// A decoded QR / barcode result: the payload and a human-readable format name.
class ScanResult {
  const ScanResult({required this.text, required this.formatName});

  final String text;
  final String formatName;
}

/// Longest edge (px) the frame is downsampled to before decoding. `captureFrame`
/// hands back a full-resolution JPEG (often 8–12 MP); decoding at full size
/// would stall the poll loop, and zxing-cpp reads codes fine at this size.
const int _maxEdge = 768;

/// Decodes a QR or 1D barcode from a JPEG frame — the bytes
/// `CameraAdapter.captureFrame()` returns.
///
/// Pure and cross-platform (Android + Windows): decodes the JPEG with the
/// `image` package, downsamples to [_maxEdge], then runs zxing-cpp
/// (`flutter_zxing`) over the RGB pixels. Returns `null` when no code matching
/// [formats] is present — the common per-frame case.
///
/// [formats] is a `flutter_zxing` `Format` bitmask: `Format.qrCode` for the QR
/// tab, `Format.linearCodes` for the 1D barcode tab.
ScanResult? decodeBarcode(Uint8List jpegBytes, {required int formats}) {
  final decoded = img.decodeImage(jpegBytes);
  if (decoded == null) return null;

  final image = (decoded.width > _maxEdge || decoded.height > _maxEdge)
      ? img.copyResize(
          decoded,
          // Scale the longer edge to _maxEdge; the other is inferred to keep
          // the aspect ratio (a distorted frame decodes worse).
          width: decoded.width >= decoded.height ? _maxEdge : null,
          height: decoded.height > decoded.width ? _maxEdge : null,
        )
      : decoded;

  final code = zx.readBarcode(
    image.getBytes(order: img.ChannelOrder.rgb),
    DecodeParams(
      imageFormat: ImageFormat.rgb,
      format: formats,
      width: image.width,
      height: image.height,
      tryHarder: true,
      tryRotate: true,
    ),
  );

  final text = code.text;
  if (!code.isValid || text == null || text.isEmpty) return null;
  return ScanResult(
    text: text,
    formatName: zx.barcodeFormatName(code.format ?? 0),
  );
}
