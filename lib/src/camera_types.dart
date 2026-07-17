import 'package:flutter/foundation.dart';

/// The direction a camera lens faces.
///
/// This is deliberately our *own* enum rather than the `camera` plugin's
/// `CameraLensDirection`, so the [CameraAdapter] contract does not force a
/// future non-plugin backend (e.g. an ONVIF/IP camera) to depend on the
/// `camera` plugin just to report a lens direction.
enum CameraLensFacing {
  /// Faces away from the user (rear camera).
  back,

  /// Faces toward the user (selfie camera).
  front,

  /// External or otherwise unspecified (webcams, IP cameras).
  external,

  /// The backend could not determine the lens direction.
  unknown,
}

/// A physical camera device discovered on the system.
///
/// The [metadata] map is intentionally flexible; consumers should not rely on
/// specific keys being present. Backends are *encouraged* to provide, where
/// available: `brand`, `model`, `connectionType` (`usb`/`wifi`/`ethernet`),
/// and `ipAddress` (network cameras).
@immutable
class CameraDevice {
  const CameraDevice({
    required this.id,
    required this.name,
    this.lensFacing = CameraLensFacing.unknown,
    this.metadata = const <String, dynamic>{},
  });

  /// Backend-specific identifier, e.g. `"0"` or `"192.168.1.100"`.
  final String id;

  /// Human-readable name, e.g. `"Logitech C920"` or `"EZVIZ Office"`.
  final String name;

  /// The lens direction, when the backend can report it.
  final CameraLensFacing lensFacing;

  /// Free-form, backend-specific extra information. Treat as advisory.
  final Map<String, dynamic> metadata;

  CameraDevice copyWith({
    String? id,
    String? name,
    CameraLensFacing? lensFacing,
    Map<String, dynamic>? metadata,
  }) {
    return CameraDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      lensFacing: lensFacing ?? this.lensFacing,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraDevice &&
          other.id == id &&
          other.name == name &&
          other.lensFacing == lensFacing &&
          mapEquals(other.metadata, metadata);

  @override
  int get hashCode => Object.hash(id, name, lensFacing, Object.hashAll(metadata.values));

  @override
  String toString() => 'CameraDevice(id: $id, name: $name, lensFacing: $lensFacing)';
}

/// What an *opened* camera can do, as reported by the device/SDK itself.
///
/// Capabilities are **queried after a successful [CameraAdapter.open]**, never
/// assumed. A capability a backend cannot report comes back `false`/trivial,
/// not an optimistic guess.
@immutable
class CameraCapabilities {
  const CameraCapabilities({
    this.hasZoom = false,
    this.minZoomLevel = 1.0,
    this.maxZoomLevel = 1.0,
    this.hasPan = false,
    this.hasTilt = false,
  });

  /// Whether the device reports a usable (non-trivial) zoom range.
  final bool hasZoom;

  /// Minimum zoom factor (`1.0` when zoom is unavailable).
  final double minZoomLevel;

  /// Maximum zoom factor (`1.0` when zoom is unavailable).
  final double maxZoomLevel;

  /// Whether the device supports pan (PTZ). Only `true` once the backend
  /// actually implements [CameraAdapter.setPan].
  final bool hasPan;

  /// Whether the device supports tilt (PTZ). Only `true` once the backend
  /// actually implements [CameraAdapter.setTilt].
  final bool hasTilt;

  CameraCapabilities copyWith({
    bool? hasZoom,
    double? minZoomLevel,
    double? maxZoomLevel,
    bool? hasPan,
    bool? hasTilt,
  }) {
    return CameraCapabilities(
      hasZoom: hasZoom ?? this.hasZoom,
      minZoomLevel: minZoomLevel ?? this.minZoomLevel,
      maxZoomLevel: maxZoomLevel ?? this.maxZoomLevel,
      hasPan: hasPan ?? this.hasPan,
      hasTilt: hasTilt ?? this.hasTilt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraCapabilities &&
          other.hasZoom == hasZoom &&
          other.minZoomLevel == minZoomLevel &&
          other.maxZoomLevel == maxZoomLevel &&
          other.hasPan == hasPan &&
          other.hasTilt == hasTilt;

  @override
  int get hashCode =>
      Object.hash(hasZoom, minZoomLevel, maxZoomLevel, hasPan, hasTilt);

  @override
  String toString() => 'CameraCapabilities(hasZoom: $hasZoom '
      '[$minZoomLevel–$maxZoomLevel], hasPan: $hasPan, hasTilt: $hasTilt)';
}
