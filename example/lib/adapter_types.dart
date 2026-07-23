/// Registered [CameraAdapterRegistry] backend-type strings, shared by
/// `main.dart` (registration) and any UI that needs to check or select a
/// specific backend (e.g. `EzvizBridgeView`'s "use phone camera" button).
const kBuiltinAdapterType = 'builtin';
const kEzvizAdapterType = 'ezviz';

/// Open-standard IP cameras. Vendor-neutral: any ONVIF-compliant device
/// (Hikvision, Dahua, Reolink, Axis, EZVIZ, …) connects through this one type,
/// configured per-camera via `host`/`port`/`username`/`password` in
/// `CameraDevice.metadata`. Distinct from [kEzvizAdapterType], which is the
/// EZVIZ *cloud* account path — a different setup flow, not a different brand.
const kOnvifAdapterType = 'onvif';
