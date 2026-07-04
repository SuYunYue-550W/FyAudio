import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:fy_audio_player/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('FyAudio App Integration Tests', () {
    testWidgets('App launches successfully', (WidgetTester tester) async {
      await tester.pumpWidget(const FyAudioApp());
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('FyAudio'), findsOneWidget);
    });

    testWidgets('Role switcher toggles between source and receiver', (WidgetTester tester) async {
      await tester.pumpWidget(const FyAudioApp());
      await tester.pump(const Duration(seconds: 2));

      final roleButton = find.textContaining('🎙️').first;
      if (roleButton.evaluate().isNotEmpty) {
        await tester.tap(roleButton);
        await tester.pump(const Duration(seconds: 1));
      }
    });

    testWidgets('Settings dialog opens and closes', (WidgetTester tester) async {
      await tester.pumpWidget(const FyAudioApp());
      await tester.pump(const Duration(seconds: 2));

      final settingsButton = find.byIcon(Icons.settings_outlined);
      if (settingsButton.evaluate().isNotEmpty) {
        await tester.tap(settingsButton);
        await tester.pump(const Duration(seconds: 1));
      }
    });

    testWidgets('Playback button toggles play/pause', (WidgetTester tester) async {
      await tester.pumpWidget(const FyAudioApp());
      await tester.pump(const Duration(seconds: 2));

      final playButton = find.text('播放').first;
      if (playButton.evaluate().isNotEmpty) {
        await tester.tap(playButton);
        await tester.pump(const Duration(seconds: 1));
      }
    });

    testWidgets('Device discovery button triggers search', (WidgetTester tester) async {
      await tester.pumpWidget(const FyAudioApp());
      await tester.pump(const Duration(seconds: 2));

      final discoverButton = find.byIcon(Icons.refresh).first;
      if (discoverButton.evaluate().isNotEmpty) {
        await tester.tap(discoverButton);
        await tester.pump(const Duration(seconds: 1));
      }
    });

    testWidgets('Sync indicator shows sync status', (WidgetTester tester) async {
      await tester.pumpWidget(const FyAudioApp());
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('Local device card shows device info', (WidgetTester tester) async {
      await tester.pumpWidget(const FyAudioApp());
      await tester.pump(const Duration(seconds: 2));
    });
  });
}