import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pathable/app/configuration.dart';
import 'package:pathable/app/providers.dart';
import 'package:pathable/features/accessibility_profiles/accessibility_profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('accessibility profile screen lists presets', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigurationProvider.overrideWithValue(
            AppConfiguration.demoDefaults(),
          ),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const MaterialApp(home: AccessibilityProfileScreen()),
      ),
    );

    expect(find.text('Wheelchair / mobility'), findsOneWidget);
    expect(find.text('Blind'), findsOneWidget);
    expect(find.text('Low vision'), findsOneWidget);
    expect(find.text('Avoid stairs / inaccessible paths'), findsOneWidget);

    await tester.tap(find.text('Wheelchair / mobility'));
    await tester.pumpAndSettle();

    final profile = ProviderScope.containerOf(
      tester.element(find.byType(AccessibilityProfileScreen)),
    ).read(accessibilityProfileProvider);
    expect(profile.preferences.avoidStairs, isTrue);
  });
}
