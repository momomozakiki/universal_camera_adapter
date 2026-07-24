import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';
import 'package:universal_camera_adapter_example/camera_session.dart';
import 'package:universal_camera_adapter_example/widgets/camera_stage.dart';

import 'support/session_fakes.dart';

Future<CameraSession> openedSession() async {
  final adapter = RecordingAdapter(const [
    CameraDevice(id: 'dev-p1', name: 'Cam'),
  ]);
  final registry = CameraAdapterRegistry()
    ..register('builtin', () => adapter, asDefault: true);
  final store = FakeProfileStore([buildProfile(id: 'p1', isDefault: true)]);
  final session = CameraSession(registry, profileStore: store);
  await session.restore();
  return session;
}

void main() {
  testWidgets('frames the preview in a fixed 16:9 box', (tester) async {
    final session = await openedSession();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: CameraStage(session: session))),
    );

    final aspect = tester.widget<AspectRatio>(find.byType(AspectRatio));
    expect(aspect.aspectRatio, 16 / 9);
    expect(find.byType(ClipRRect), findsOneWidget);
    // The adapter's preview is rendered inside the stage.
    expect(find.byKey(const Key('preview')), findsOneWidget);
  });

  testWidgets('stacks the overlay above the preview when provided',
      (tester) async {
    final session = await openedSession();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CameraStage(
            session: session,
            overlay: const Text('scan hint'),
          ),
        ),
      ),
    );

    // The overlay and the preview coexist inside the stage's Stack (Scaffold
    // itself also uses a Stack, so don't count them).
    expect(find.text('scan hint'), findsOneWidget);
    expect(find.byKey(const Key('preview')), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(const Key('preview')),
        matching: find.byType(Stack),
      ),
      findsWidgets,
    );
  });

  testWidgets('renders no overlay stack when none is given', (tester) async {
    final session = await openedSession();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: CameraStage(session: session))),
    );

    expect(find.text('scan hint'), findsNothing);
    expect(find.byKey(const Key('preview')), findsOneWidget);
  });
}
