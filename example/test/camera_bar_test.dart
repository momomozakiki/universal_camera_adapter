import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';
import 'package:universal_camera_adapter_example/camera_session.dart';
import 'package:universal_camera_adapter_example/widgets/camera_bar.dart';

import 'support/session_fakes.dart';

/// Pumps [CameraBar] wrapped in an AnimatedBuilder, the way the tabs host it, so
/// it rebuilds on session changes.
Future<void> pumpBar(WidgetTester tester, CameraSession session) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AnimatedBuilder(
          animation: session,
          builder: (_, __) => CameraBar(session: session),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('lists every saved profile in the dropdown', (tester) async {
    final adapter = RecordingAdapter(const [
      CameraDevice(id: 'dev-a', name: 'A'),
    ]);
    final registry = CameraAdapterRegistry()
      ..register('builtin', () => adapter, asDefault: true);
    final store = FakeProfileStore([
      buildProfile(id: 'a', name: 'Front door'),
      buildProfile(id: 'b', name: 'Garage'),
    ]);

    final session = CameraSession(registry, profileStore: store);
    await session.loadProfiles();
    await pumpBar(tester, session);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();

    // Both saved cameras are offered (menu duplicates the selected item).
    expect(find.text('Front door'), findsWidgets);
    expect(find.text('Garage'), findsWidgets);
  });

  testWidgets('shows the empty hint and no Connect target with no profiles',
      (tester) async {
    final adapter = RecordingAdapter(const []);
    final registry = CameraAdapterRegistry()
      ..register('builtin', () => adapter, asDefault: true);

    final session = CameraSession(registry, profileStore: FakeProfileStore());
    await session.loadProfiles();
    await pumpBar(tester, session);

    expect(find.text('No saved cameras'), findsOneWidget);
    final connect = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(connect.onPressed, isNull, reason: 'nothing to connect to');
  });

  testWidgets('Connect opens the selected profile', (tester) async {
    final adapter = RecordingAdapter(const [], enumerable: false);
    final registry = CameraAdapterRegistry()
      ..register('onvif', () => adapter, asDefault: true);
    final store = FakeProfileStore([
      buildProfile(id: 'p1', backendType: 'onvif', name: 'Front door'),
    ]);

    final session = CameraSession(registry, profileStore: store);
    await session.loadProfiles();
    session.selectProfile('p1');
    await pumpBar(tester, session);

    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();

    expect(session.isOpen, isTrue);
    // Toggled to Disconnect once open.
    expect(find.widgetWithText(OutlinedButton, 'Disconnect'), findsOneWidget);
  });

  testWidgets('Disconnect closes the open camera', (tester) async {
    final adapter = RecordingAdapter(const [
      CameraDevice(id: 'dev-p1', name: 'Cam'),
    ]);
    final registry = CameraAdapterRegistry()
      ..register('builtin', () => adapter, asDefault: true);
    final store = FakeProfileStore([buildProfile(id: 'p1', isDefault: true)]);

    final session = CameraSession(registry, profileStore: store);
    await session.restore();
    await pumpBar(tester, session);
    expect(session.isOpen, isTrue);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Disconnect'));
    await tester.pumpAndSettle();

    expect(session.isOpen, isFalse);
    expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
  });

  testWidgets('renders the shared error banner when the session has an error',
      (tester) async {
    final adapter = RecordingAdapter(const []);
    final registry = CameraAdapterRegistry()
      ..register('builtin', () => adapter, asDefault: true);
    final session = CameraSession(registry, profileStore: FakeProfileStore());
    await session.loadProfiles();

    // Provoke the "no longer saved" error surface.
    session.selectProfile('ghost');
    await session.connectSelectedProfile();
    await pumpBar(tester, session);

    expect(find.byType(CameraErrorBanner), findsOneWidget);
    expect(find.text('That camera is no longer saved.'), findsOneWidget);
  });
}
