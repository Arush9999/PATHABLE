import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pathable/app/configuration.dart';
import 'package:pathable/app/providers.dart';
import 'package:pathable/app/theme.dart';
import 'package:pathable/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('dark mode switch stays green and persists', (tester) async {
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
        child: const _ThemedSettings(),
      ),
    );

    expect(Theme.of(tester.element(find.text('Dark mode'))).brightness,
        Brightness.light);
    expect(
      Theme.of(tester.element(find.text('Dark mode'))).colorScheme.primary,
      PathAbleTheme.seed,
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    final context = tester.element(find.text('Dark mode'));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(Theme.of(context).colorScheme.primary, const Color(0xFF34D399));
    expect(prefs.getBool('dark_mode'), isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('Dark mode'))).brightness,
      Brightness.light,
    );
    expect(prefs.getBool('dark_mode'), isFalse);
  });
}

class _ThemedSettings extends ConsumerWidget {
  const _ThemedSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = ref.watch(darkModeProvider);
    return MaterialApp(
      theme: PathAbleTheme.light(),
      darkTheme: PathAbleTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: const SettingsScreen(),
    );
  }
}
