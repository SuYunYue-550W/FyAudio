import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fy_audio_player/main.dart';

void main() {
  testWidgets('App loads correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const FyAudioApp());
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('Home screen displays FyAudio title', (WidgetTester tester) async {
    await tester.pumpWidget(const FyAudioApp());
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('FyAudio'), findsOneWidget);
  });
}