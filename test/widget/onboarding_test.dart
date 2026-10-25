import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pathable/app/app.dart';
import 'package:pathable/app/configuration.dart';
import 'package:pathable/app/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('onboarding shows PathAble brand and demo banner', (tester) async {
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
        child: const PathAbleApp(showOnboarding: true),
      ),
    );

    expect(find.text('PathAble'), findsWidgets);
    expect(find.textContaining('Demonstration mode'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
  });
}
