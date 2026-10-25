import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pathable/data/local/demo_data.dart';
import 'package:pathable/features/map/widgets/hazard_list_sheet.dart';

void main() {
  testWidgets('hazard list shows category labels and demo status text', (
    tester,
  ) async {
    final hazards = DemoData.hazards(now: DateTime.utc(2026, 10, 9));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HazardListSheet(hazards: hazards),
        ),
      ),
    );

    expect(find.text('Blocked sidewalk'), findsWidgets);
    expect(find.textContaining('Demonstration data'), findsWidgets);
    expect(find.textContaining('Provisionally reported'), findsWidgets);
  });
}
