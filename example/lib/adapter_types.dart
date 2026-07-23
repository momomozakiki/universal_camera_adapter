/// Registered [CameraAdapterRegistry] backend-type strings, shared by
/// `main.dart` (registration) and any UI that needs to check or select a
/// specific backend, and by `CameraSession` to key its profile matchers.
const kBuiltinAdapterType = 'builtin';
const kEzvizAdapterType = 'ezviz';

/// Open-standard IP cameras. Vendor-neutral: any ONVIF-compliant device
/// (Hikvision, Dahua, Reolink, Axis, EZVIZ, …) connects through this one type,
/// configured per-camera via `host`/`port`/`username`/`password` in
/// `CameraDevice.metadata`. Distinct from [kEzvizAdapterType], which is the
/// EZVIZ *cloud* account path — a different setup flow, not a different brand.
const kOnvifAdapterType = 'onvif';

/// `CameraSecretStore` key an ONVIF password is stored under, scoped to a
/// profile id. Written by `OnvifSetupWizard`, read by `CameraSession`.
const String kOnvifPasswordSecretKey = 'password';

/// `CameraSecretStore` key an EZVIZ verification code is stored under.
///
/// Replaces the old bespoke `ezviz_tab.verification_code` `SharedPreferences`
/// key, which kept the code in plaintext outside any profile
/// (`state-management` Rule 6).
const String kEzvizVerificationCodeSecretKey = 'verificationCode';

/// Every secret key this app may have stored for a camera.
///
/// `CameraSession` merges **all** of these into the transient device it opens,
/// without asking which backend it is talking to — a backend simply ignores a
/// metadata key it does not use. That keeps the secret-transport path free of
/// per-type branching; adding a backend with a new secret means appending one
/// entry here, not a new conditional.
const List<String> kCameraSecretKeys = <String>[
  kOnvifPasswordSecretKey,
  kEzvizVerificationCodeSecretKey,
];
