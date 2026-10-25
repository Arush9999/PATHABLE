import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pathable/app/configuration.dart';
import 'package:pathable/app/providers.dart';
import 'package:pathable/data/local/demo_data.dart';
import 'package:pathable/data/local/demo_hazard_repository.dart';
import 'package:pathable/data/models/geo_point.dart';
import 'package:pathable/features/reporting/report_hazard_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('report form supports quick Waze-style submit without photo', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = DemoHazardRepository(seed: const []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigurationProvider.overrideWithValue(
            AppConfiguration.demoDefaults(),
          ),
          sharedPreferencesProvider.overrideWithValue(prefs),
          hazardRepositoryProvider.overrideWithValue(repo),
          userLocationProvider.overrideWith(_FakeLocation.new),
        ],
        child: const MaterialApp(home: ReportHazardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Report a hazard'), findsOneWidget);
    expect(find.textContaining('Quick report'), findsOneWidget);
    expect(find.textContaining('No photo required'), findsOneWidget);

    final submit = find.widgetWithText(FilledButton, 'Submit report');
    await tester.scrollUntilVisible(
      submit,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.textContaining('Choose a hazard category'), findsOneWidget);

    repo.dispose();
  });
}

class _FakeLocation extends UserLocationNotifier {
  @override
  Future<GeoPoint?> build() async => DemoData.startLocation;
}
