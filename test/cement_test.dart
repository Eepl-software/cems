import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_park_groove/cement/cement.dart';

void main() {
  group('Cement Page Tests', () {
    testWidgets('Cement page should render correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CementPage(),
        ),
      );

      // Verify that the page renders without errors
      expect(find.byType(CementPage), findsOneWidget);
      expect(find.text('Cement Management'), findsOneWidget);
      expect(find.text('Upload Weighbridge Slip'), findsOneWidget);
      expect(find.text('Auto-filled Information'), findsOneWidget);
      expect(find.text('Weight Information (Auto-extracted)'), findsOneWidget);
      expect(find.text('Driver Information'), findsOneWidget);
    });

    testWidgets('Form fields should be present', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CementPage(),
        ),
      );

      // Check for form fields
      expect(find.byType(TextFormField), findsWidgets);
      expect(find.text('Date'), findsOneWidget);
      expect(find.text('Latitude'), findsOneWidget);
      expect(find.text('Longitude'), findsOneWidget);
      expect(find.text('Gross Weight'), findsOneWidget);
      expect(find.text('Tare Weight'), findsOneWidget);
      expect(find.text('Net Weight'), findsOneWidget);
      expect(find.text('Driver Number'), findsOneWidget);
      expect(find.text('Contact Number'), findsOneWidget);
    });

    testWidgets('Upload button should be present', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CementPage(),
        ),
      );

      expect(find.text('Upload Image'), findsOneWidget);
      expect(find.text('Submit Cement Data'), findsOneWidget);
    });
  });
}