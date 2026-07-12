import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inklist/screens/placeholder_screen.dart';

void main() {
  testWidgets('PlaceholderScreen renders its title and message', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: PlaceholderScreen(title: 'Focus', message: 'Coming soon.'),
    ));
    expect(find.text('Focus'), findsOneWidget);
    expect(find.text('Coming soon.'), findsOneWidget);
  });
}
