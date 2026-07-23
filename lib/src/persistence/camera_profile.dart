import 'dart:math';

import 'package:flutter/foundation.dart';

import '../camera_types.dart';

/// A user-facing record of a previously set-up camera, safe to persist and
/// re-open later.
///
/// **Invariant: a [CameraProfile] never holds a secret.** It is safe to log,
/// export, or serialize in the clear — every field here is non-sensitive
/// (endpoint/config lives in [device]'s `metadata`; the credential itself does
/// not). Per-camera-type secrets (ONVIF password, EZVIZ verification code) are
/// stored separately in a `CameraSecretStore`, keyed by this profile's [id].
/// Do **not** add a password/token/verification-code field to this class — that
/// would leak a secret into plaintext `shared_preferences`.
///
/// [id] is a stable identifier minted once at save-time (see [CameraProfile.create]),
/// deliberately distinct from [CameraDevice.id] (which can be ephemeral — a USB
/// index, a discovery-time handle). The persisted [device] is a *snapshot* used
/// to re-locate and re-open the camera; a restored profile must still be
/// re-validated against live discovery before use (see `state-management` Rule 4).
@immutable
class CameraProfile {
  const CameraProfile({
    required this.id,
    required this.backendType,
    required this.displayName,
    required this.device,
    required this.createdAt,
    this.isDefault = false,
  });

  /// Builds a new profile with a freshly-minted [id] and `createdAt` = now (UTC).
  factory CameraProfile.create({
    required String backendType,
    required String displayName,
    required CameraDevice device,
    bool isDefault = false,
  }) {
    return CameraProfile(
      id: _generateId(),
      backendType: backendType,
      displayName: displayName,
      device: device,
      createdAt: DateTime.now().toUtc(),
      isDefault: isDefault,
    );
  }

  /// Stable UUID minted at save-time — the key the `CameraSecretStore` uses.
  final String id;

  /// Registry backend-type string (e.g. `'builtin'`, `'onvif'`, `'ezviz'`).
  final String backendType;

  /// User-editable label; defaults to the device name at creation.
  final String displayName;

  /// Snapshot of the [CameraDevice] to re-locate/re-open. Non-secret connection
  /// config (host, port, …) may live in its `metadata`; secrets must not.
  final CameraDevice device;

  /// When this profile was created (UTC).
  final DateTime createdAt;

  /// Whether this is the app's default camera. Exactly one profile is the
  /// default at a time; the store enforces this.
  final bool isDefault;

  CameraProfile copyWith({
    String? id,
    String? backendType,
    String? displayName,
    CameraDevice? device,
    DateTime? createdAt,
    bool? isDefault,
  }) {
    return CameraProfile(
      id: id ?? this.id,
      backendType: backendType ?? this.backendType,
      displayName: displayName ?? this.displayName,
      device: device ?? this.device,
      createdAt: createdAt ?? this.createdAt,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  /// Serializes to a plain JSON map (see the class invariant — no secrets).
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'backendType': backendType,
        'displayName': displayName,
        'device': _deviceToJson(device),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'isDefault': isDefault,
      };

  /// Parses a profile from an untrusted JSON map, returning `null` when the
  /// shape is unusable rather than throwing — a value written by an older app
  /// version, or a corrupt entry, must never crash the load (see
  /// `state-management` Rule 3). No bare `as` casts: every field is read through
  /// a typed reader with a fallback, and the two structurally-required fields
  /// ([id], [device]) reject the whole entry when missing/invalid.
  static CameraProfile? fromJson(Object? json) {
    if (json is! Map) return null;

    final id = _readString(json['id']);
    if (id == null || id.isEmpty) return null;

    final device = _deviceFromJson(json['device']);
    if (device == null) return null;

    return CameraProfile(
      id: id,
      backendType: _readString(json['backendType']) ?? '',
      displayName: _readString(json['displayName']) ?? device.name,
      device: device,
      createdAt: _readDateTime(json['createdAt']) ?? DateTime.now().toUtc(),
      isDefault: json['isDefault'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraProfile &&
          other.id == id &&
          other.backendType == backendType &&
          other.displayName == displayName &&
          other.device == device &&
          other.createdAt == createdAt &&
          other.isDefault == isDefault;

  @override
  int get hashCode =>
      Object.hash(id, backendType, displayName, device, createdAt, isDefault);

  @override
  String toString() => 'CameraProfile(id: $id, backendType: $backendType, '
      'displayName: $displayName, isDefault: $isDefault)';
}

// --- CameraDevice <-> JSON (kept private so the public value type isn't widened) ---

Map<String, dynamic> _deviceToJson(CameraDevice device) => <String, dynamic>{
      'id': device.id,
      'name': device.name,
      'lensFacing': device.lensFacing.name,
      'metadata': device.metadata,
    };

CameraDevice? _deviceFromJson(Object? json) {
  if (json is! Map) return null;
  final id = _readString(json['id']);
  final name = _readString(json['name']);
  if (id == null || name == null) return null;
  return CameraDevice(
    id: id,
    name: name,
    lensFacing: _readLensFacing(json['lensFacing']),
    metadata: _readMetadata(json['metadata']),
  );
}

// --- Typed, fallback-safe readers for untrusted JSON values ---

String? _readString(Object? value) => value is String ? value : null;

DateTime? _readDateTime(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value)?.toUtc();
}

CameraLensFacing _readLensFacing(Object? value) {
  if (value is String) {
    for (final facing in CameraLensFacing.values) {
      if (facing.name == value) return facing;
    }
  }
  return CameraLensFacing.unknown;
}

Map<String, dynamic> _readMetadata(Object? value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
  return const <String, dynamic>{};
}

/// Generates a random RFC-4122 v4 UUID string using [Random.secure], avoiding a
/// `uuid` package dependency for this single use.
String _generateId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  // Set the version (4) and variant (RFC 4122) bits.
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}'
      '-${hex.substring(16, 20)}-${hex.substring(20)}';
}
