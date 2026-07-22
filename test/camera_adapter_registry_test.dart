import 'package:flutter_test/flutter_test.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

import 'mock_camera_adapter.dart';

void main() {
  group('CameraAdapterRegistry', () {
    late CameraAdapterRegistry registry;

    setUp(() => registry = CameraAdapterRegistry());

    test('create() returns a fresh instance each call', () {
      registry.register('mock', MockCameraAdapter.new);
      final a = registry.create('mock');
      final b = registry.create('mock');
      expect(a, isA<MockCameraAdapter>());
      expect(identical(a, b), isFalse);
    });

    test('unknown type throws StateError', () {
      expect(() => registry.create('nope'), throwsStateError);
    });

    test('createDefault throws when no default set', () {
      registry.register('mock', MockCameraAdapter.new);
      expect(registry.hasDefault(), isFalse);
      expect(registry.createDefault, throwsStateError);
    });

    test('asDefault makes createDefault work', () {
      registry.register('mock', MockCameraAdapter.new, asDefault: true);
      expect(registry.hasDefault(), isTrue);
      expect(registry.createDefault(), isA<MockCameraAdapter>());
    });

    test('registering is not implicitly "first one wins"', () {
      registry.register('a', MockCameraAdapter.new);
      registry.register('b', MockCameraAdapter.new);
      expect(registry.hasDefault(), isFalse);
    });

    test('duplicate registration throws ArgumentError', () {
      registry.register('mock', MockCameraAdapter.new);
      expect(
        () => registry.register('mock', MockCameraAdapter.new),
        throwsArgumentError,
      );
    });

    test('empty type throws ArgumentError', () {
      expect(
        () => registry.register('', MockCameraAdapter.new),
        throwsArgumentError,
      );
    });

    test('isRegistered / registeredTypes reflect registrations', () {
      registry.register('a', MockCameraAdapter.new);
      registry.register('b', MockCameraAdapter.new);
      expect(registry.isRegistered('a'), isTrue);
      expect(registry.isRegistered('z'), isFalse);
      expect(registry.registeredTypes, <String>['a', 'b']);
    });

    test('registeredTypes is unmodifiable', () {
      registry.register('a', MockCameraAdapter.new);
      expect(() => registry.registeredTypes.add('x'), throwsUnsupportedError);
    });

    test('defaultType reflects the registered default', () {
      registry.register('a', MockCameraAdapter.new);
      expect(registry.defaultType, isNull);
      registry.register('b', MockCameraAdapter.new, asDefault: true);
      expect(registry.defaultType, 'b');
    });

    test('two registries are isolated', () {
      final r1 = CameraAdapterRegistry()..register('only1', MockCameraAdapter.new);
      final r2 = CameraAdapterRegistry();
      expect(r1.isRegistered('only1'), isTrue);
      expect(r2.isRegistered('only1'), isFalse);
    });
  });
}
