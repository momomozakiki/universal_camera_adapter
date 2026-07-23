import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

/// A minimal [CameraSetupWizard] with no UI and no dependencies.
///
/// The registry's job is registration and lookup — it never calls [build] — so
/// a stub keeps these tests free of widgets, platform channels, and hardware.
class _StubWizard extends CameraSetupWizard {
  _StubWizard({this.backendType = 'stub', this.displayName = 'Stub camera'});

  @override
  final String backendType;

  @override
  final String displayName;

  @override
  IconData get icon => const IconData(0xe000, fontFamily: 'MaterialIcons');

  @override
  Widget build(
    BuildContext context, {
    required ValueChanged<CameraProfile> onComplete,
    required VoidCallback onCancel,
  }) {
    return const SizedBox.shrink();
  }
}

void main() {
  group('CameraSetupWizardRegistry', () {
    late CameraSetupWizardRegistry wizards;

    setUp(() => wizards = CameraSetupWizardRegistry());

    test('create() returns a fresh instance each call', () {
      // Fresh per call matters: a wizard drives a stateful multi-step flow, so
      // two concurrent setups must not share one.
      wizards.register('stub', _StubWizard.new);
      final a = wizards.create('stub');
      final b = wizards.create('stub');
      expect(a, isA<_StubWizard>());
      expect(identical(a, b), isFalse);
    });

    test('create() surfaces the wizard descriptors used to build a tile', () {
      wizards.register(
        'onvif',
        () => _StubWizard(backendType: 'onvif', displayName: 'IP camera'),
      );
      final wizard = wizards.create('onvif');
      expect(wizard.backendType, 'onvif');
      expect(wizard.displayName, 'IP camera');
      expect(wizard.icon, isA<IconData>());
    });

    test('unknown type throws StateError listing what is registered', () {
      wizards.register('stub', _StubWizard.new);
      expect(
        () => wizards.create('nope'),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', contains('stub')),
        ),
      );
    });

    test('duplicate type throws ArgumentError', () {
      wizards.register('stub', _StubWizard.new);
      expect(() => wizards.register('stub', _StubWizard.new), throwsArgumentError);
    });

    test('empty type throws ArgumentError', () {
      expect(() => wizards.register('', _StubWizard.new), throwsArgumentError);
    });

    test('isRegistered / registeredTypes reflect registrations', () {
      expect(wizards.isRegistered('stub'), isFalse);
      expect(wizards.registeredTypes, isEmpty);
      wizards.register('stub', _StubWizard.new);
      expect(wizards.isRegistered('stub'), isTrue);
      expect(wizards.registeredTypes, <String>['stub']);
    });

    test('registeredTypes preserves registration order', () {
      // Registration order is the chooser's display order.
      wizards.register('builtin', _StubWizard.new);
      wizards.register('onvif', _StubWizard.new);
      wizards.register('ezviz', _StubWizard.new);
      expect(wizards.registeredTypes, <String>['builtin', 'onvif', 'ezviz']);
    });

    test('registeredTypes is unmodifiable', () {
      wizards.register('stub', _StubWizard.new);
      expect(
        () => wizards.registeredTypes.add('sneaky'),
        throwsUnsupportedError,
      );
    });

    test('two registries are isolated', () {
      // Instance-based, not a singleton — the same property CameraAdapterRegistry
      // has, so tests and multiple app instances never leak into each other.
      final other = CameraSetupWizardRegistry();
      wizards.register('stub', _StubWizard.new);
      expect(other.isRegistered('stub'), isFalse);
      expect(other.registeredTypes, isEmpty);
    });

    test('has no notion of a default wizard', () {
      // Deliberate asymmetry with CameraAdapterRegistry: a default *backend* is
      // meaningful, a default *setup flow* is not. This test documents the
      // omission so it is not "fixed" by adding asDefault later.
      wizards.register('stub', _StubWizard.new);
      expect(wizards, isNot(isA<CameraAdapterRegistry>()));
      expect(wizards.registeredTypes.length, 1);
    });
  });
}
