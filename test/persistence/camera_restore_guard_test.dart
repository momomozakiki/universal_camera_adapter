import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = SharedPreferencesCameraRestoreGuard.storageKey;

  group('SharedPreferencesCameraRestoreGuard', () {
    late SharedPreferencesCameraRestoreGuard guard;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      guard = SharedPreferencesCameraRestoreGuard();
    });

    test('a fresh install reports no interrupted restore', () async {
      // The default must be "not interrupted": a first launch that wrongly
      // reported true would skip the user's default camera for no reason.
      expect(await guard.wasRestoreInterrupted(), isFalse);
    });

    test('begin then end leaves nothing set — the survived-restore path',
        () async {
      await guard.beginRestore();
      await guard.endRestore();
      expect(await guard.wasRestoreInterrupted(), isFalse);
    });

    test('a begin with no end is still set on the next read — the crash path',
        () async {
      // This is the whole mechanism: the process dies between these two lines
      // in production, so nothing clears the mark, and the next launch sees it.
      await guard.beginRestore();

      // A *separate instance*, as the next launch would use.
      expect(
        await SharedPreferencesCameraRestoreGuard().wasRestoreInterrupted(),
        isTrue,
      );
    });

    test('the mark really is persisted, under the documented key', () async {
      // Guards the key itself: it is part of the on-disk contract, and a
      // silent rename would break the flag for everyone mid-upgrade.
      await guard.beginRestore();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(key), isTrue);
    });

    test('endRestore is idempotent and safe with nothing set', () async {
      await guard.endRestore();
      await guard.endRestore();
      expect(await guard.wasRestoreInterrupted(), isFalse);
    });

    test('a pre-existing mark survives until explicitly cleared', () async {
      // Simulates launching into prefs left behind by a killed process.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.$key': true,
      });
      final fresh = SharedPreferencesCameraRestoreGuard();

      expect(await fresh.wasRestoreInterrupted(), isTrue);
      await fresh.endRestore();
      expect(await fresh.wasRestoreInterrupted(), isFalse);
    });
  });
}
