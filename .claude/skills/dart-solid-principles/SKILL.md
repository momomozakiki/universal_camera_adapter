---
name: dart-solid-principles
description: >-
  Use when writing or reviewing Dart classes, adapters, interfaces, registries,
  or backends in this package, especially when the request mentions SOLID,
  single responsibility, open/closed, Liskov substitution, interface
  segregation, dependency inversion, code structure, tight coupling, god
  classes, or where a feature should live. Also use for everyday Dart
  programming practices — DRY, code reuse vs duplication, modularity, file or
  class size, naming and visibility, immutability, copyWith, helper extraction,
  test structure/mirroring, "make this reusable", or "clean code". Scoped to
  Dart only.
---

# SOLID principles for Dart (universal_camera_adapter)

Apply these when shaping Dart code in this package — deciding where a class lives, what it
depends on, and how it extends. The point isn't dogma: SOLID is the *reason* this package's rules
work (**one interface, pluggable backends, fully testable without hardware**). The
`CameraAdapter` / `CameraAdapterRegistry` design already embodies all five principles, so use the
real code below as the reference model rather than inventing new abstractions. The **concrete
authoring checklist** for backends is [[camera-adapter-authoring]]; this skill is the *why*.

> This skill is Dart-only. If a second language is ever added (e.g. Kotlin for an Android PTZ SDK),
> create a sibling skill (`kotlin-solid-principles`) — don't stretch this one across languages.

## S — Single Responsibility

A class should have one reason to change. The package splits camera access into layers, each in its
own file, so a change to one never forces edits to the others:

- **contract** — `CameraAdapter` (`lib/src/camera_adapter.dart`): the abstract lifecycle + controls.
- **registry** — `CameraAdapterRegistry` (`lib/src/camera_adapter_registry.dart`): string `type` → factory.
- **value types** — `CameraDevice` / `CameraCapabilities` / `CameraLensFacing` (`lib/src/camera_types.dart`).
- **backends** — `FlutterCameraAdapter` (`lib/src/flutter_camera_adapter.dart`), `ONVIFCameraAdapter`
  (`lib/src/onvif/`): each wraps exactly one hardware/network source.

**Smell:** a backend that both talks to the plugin/SDK *and* owns app-level UI state, or a registry
that also constructs previews. If you'd describe a class with "and", it likely has two responsibilities.

## O — Open/Closed

Open for extension, closed for modification. You add a new camera source by writing a new
`CameraAdapter` implementer and **registering a factory** — never by editing the contract or an
existing backend. The instance registry maps a string `type` → a factory closure:

```dart
// Adding a backend requires zero edits to existing files:
final registry = CameraAdapterRegistry();
registry.register('onvif', ONVIFCameraAdapter.new); // tear-off factory
final adapter = registry.create('onvif');           // fresh instance each call
```

**Smell:** a `switch (type)` over a hardcoded list of backend types that grows every time a camera
source is added. That's modification, not extension.

## L — Liskov Substitution

Any subtype must be usable wherever `CameraAdapter` is expected — which is about **honoring the
contract (postconditions)**, not just matching the method signature. Every backend must obey the
contract: `capabilities` reflects the *real* opened device (queried, never assumed), `open()`
closes any previous device first, and failures come back as the typed error surface.

```dart
Future<void> useCamera(CameraAdapter adapter, CameraDevice device) async {
  await adapter.open(device);
  if (adapter.capabilities.hasZoom) showZoomSlider(); // callers rely on this being honest
}
```

A backend that reported `hasZoom: true` optimistically (before checking the device) or threw a raw
plugin exception instead of a `StateError` would break every caller written against the contract —
even though it compiles. That is the LSP violation here.

**Smell:** a backend that flips a capability flag ahead of implementing it, or throws a
platform/SDK exception where its siblings map to `StateError`/`UnsupportedError`.

## I — Interface Segregation

No client should depend on methods it doesn't use. Not every camera has PTZ, so `setPan`/`setTilt`
**default to throwing `UnsupportedError`** on the contract — a fixed-lens backend inherits the
default and writes no dead no-op, while a PTZ backend overrides only what it supports. Consumers
gate on `capabilities.hasPan`/`hasTilt` before calling, so they never depend on a control the device
lacks:

```dart
// CameraAdapter provides the safe default — fixed-lens backends implement nothing extra:
Future<void> setPan(double angle, {Duration timeout = const Duration(seconds: 15)}) =>
    throw UnsupportedError('This backend does not support pan');
```

This cuts **both ways**. It is not only that an adapter must not be forced to implement a feature it
lacks (the PTZ default-throw case above) — *feature code must equally not depend on a concrete
adapter's type*, only on the shared capability-query surface. A feature module that imports
`ONVIFCameraAdapter` (or any concrete backend) to special-case it, instead of asking
`capabilities`/`featureMatrix`, has the same coupling problem in the opposite direction: it breaks the
moment a second backend needs that feature. The reference-correct example is QR/barcode scanning
(`example/lib/scanning/frame_scanner.dart`), built purely on the generic `captureFrame()` primitive —
it works against every backend without naming any of them. The concrete backend-author checklist for
this is [[camera-adapter-authoring]] section 6.

**Smell:** forcing every backend to implement a full PTZ surface with `=> throw Unimplemented`
stubs; a consumer calling `setPan` without checking `capabilities.hasPan` first; or feature code that
does `if (adapter is SomeConcreteAdapter)` / a registry-type `switch` instead of querying capability.

## D — Dependency Inversion

Depend on abstractions; inject concretions. **The Golden Rule is DIP made concrete:** UI and
business logic depend only on `CameraAdapter` + `CameraAdapterRegistry`, never on a concrete backend.
The app injects factories at startup:

```dart
// In the app's main() — not in any widget/controller:
final registry = CameraAdapterRegistry();
registry.register('builtin', FlutterCameraAdapter.new, asDefault: true);
```

A widget receives a `CameraAdapter` (or asks the registry for one) — it must never
`import '.../flutter_camera_adapter.dart'` directly. That is what keeps a backend swappable and lets
tests inject `MockCameraAdapter`.

**Smell:** any `import` of a concrete backend inside consumer/UI code; a widget that news up
`FlutterCameraAdapter()` instead of taking a `CameraAdapter`.

## Error types (the typed surface)

Use the contract's errors precisely so the LSP and ISP rules don't read as a contradiction (full
table in [[camera-adapter-authoring]]):

- **ISP / not-supported:** throw `UnsupportedError` for a capability the backend genuinely lacks
  (the default `setPan`/`setTilt`).
- **Fatal:** `StateError` (open/capture failure, permission denied, used-before-open),
  `TimeoutException` (network/timeout), `FormatException` (malformed SOAP/XML).
- Never leak a raw platform/SDK/socket exception through the contract.

## Applying this — PR litmus test

- ✅ Does this class have only one reason to change?
- ✅ Can I extend behaviour by adding a new backend and registering it, without editing the contract?
- ✅ Can I replace any backend without breaking the caller (same `CameraAdapter` contract + capabilities)?
- ✅ Do clients depend only on the controls they actually use (gated on `capabilities`)?
- ✅ Does consumer/UI code depend only on the interface + registry, never a concrete backend?

## Practices — applying SOLID in everyday Dart

SOLID is the *why*; these are the daily habits that keep code modular, reusable, and DRY. They name
what the package already does, so new code matches it.

### DRY & reuse-before-build

Prefer reusing an existing primitive or seam over writing a new one; a near-duplicate is a smell.

- **Reuse the mock, don't re-roll one.** `test/mock_camera_adapter.dart` is the single contract-faithful
  fake; consumers and new backend tests build on it rather than hand-rolling a partial stub.
- **Extract a private helper** when logic is duplicated or a method grows past ~30 lines. Keep it
  private in the same file until a *second* file needs it — then promote it. Don't generalize on first use.
- **One generic, never a second copy.** If two classes differ only by a type parameter and a label,
  that's one generic. A second copy-pasted registry/store parameterizable by a type is a must-fix in review.
- **Build SOAP/frames from one place.** ONVIF envelopes, op strings, and namespaces are declared in
  exactly one module (`lib/src/onvif/onvif_soap.dart`) and every service consumes it — two services
  hand-building the same XML shape is drift waiting to happen.
- **Lint parity.** The package carries `analysis_options.yaml` with the baseline lints (incl.
  strict-casts, `prefer_final_locals`, `prefer_const_constructors`, `avoid_print`) so it stays
  self-contained when published.

### File & class size

Small, single-purpose files (aim ≤200 lines; ≤300 for a genuinely complex backend). If you'd describe
a class with "*and*", it has two responsibilities — split it (this is the S smell, made concrete).

### Immutability & `copyWith`

Value types (`CameraDevice`, `CameraCapabilities`) take `const` constructors and stay immutable;
derive a variant with `copyWith` rather than mutation. Immutability is what lets capabilities flow to
the UI without spooky action at a distance.

### Naming & visibility

Private helpers `_camelCase`; class constants `static const camelCase`. Our own `CameraLensFacing`
enum (not the plugin's) keeps the contract backend-agnostic. Names carry intent — a reader should not
need the body to know what a helper does.

### Test-mirroring & determinism

One test file per source file, **mirroring its name**; cover happy + not-supported + error paths. Make
logic testable without hardware by **injecting** the adapter — `MockCameraAdapter` with configurable
returns and injectable exceptions is how registry/consumer logic is unit-tested deterministically.
No live-hardware tests in CI.

## References

- `lib/src/camera_adapter.dart` / `camera_adapter_registry.dart` / `camera_types.dart` — the contract,
  registry, and value types (the S/O/I/D reference model).
- `lib/src/flutter_camera_adapter.dart` — the reference backend (capabilities queried, typed errors).
- `test/mock_camera_adapter.dart` — the deterministic testing seam.
- [[camera-adapter-authoring]] — the concrete backend-authoring checklist.
- `CLAUDE.md` → **Architecture** — the contract, registry, and Golden Rule.

> If those paths move, update this skill — it's internal to this repo, so the references are
> intentionally concrete.
