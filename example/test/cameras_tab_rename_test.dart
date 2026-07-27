import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';
import 'package:universal_camera_adapter_example/camera_session.dart';
import 'package:universal_camera_adapter_example/tabs/cameras_tab.dart';

import 'support/session_fakes.dart';

/// Regression coverage for the rename-crash root cause: renaming used to
/// dispose the dialog's `TextEditingController` immediately after
/// `Navigator.pop`, while the `AlertDialog` route's exit transition was still
/// rebuilding that `TextField`'s subtree for one more frame — crashing with
/// "A TextEditingController was used after being disposed", cascading into a
/// `_dependents.isEmpty` framework assertion (captured via `flutter run` on a
/// physical Android device; see `history/2026-W31.md`).
///
/// Driving `pumpAndSettle()` alone would skip past the vulnerable frames and
/// could pass even on the buggy code, so this steps through the transition
/// explicitly and checks for a thrown exception after each step.
void main() {
  testWidgets(
    'renaming a camera survives the dialog exit-transition frames',
    (tester) async {
      final adapter = RecordingAdapter(const [
        CameraDevice(id: 'dev-p1', name: 'Cam'),
      ]);
      final registry = CameraAdapterRegistry()
        ..register('builtin', () => adapter, asDefault: true);
      final store = FakeProfileStore([
        buildProfile(id: 'p1', name: 'Old name'),
      ]);
      final session = CameraSession(registry, profileStore: store);
      await session.loadProfiles();

      await tester.pumpWidget(
        MaterialApp(
          home: CamerasTab(
            session: session,
            wizards: CameraSetupWizardRegistry(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'New name');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));

      // Step through the dialog's exit transition instead of jumping straight
      // to pumpAndSettle — this is the window where the old code's premature
      // controller.dispose() raced the outgoing route.
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.text('New name'), findsOneWidget);
      expect(session.profiles.single.displayName, 'New name');
    },
  );
}
