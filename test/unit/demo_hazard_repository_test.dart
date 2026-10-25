import 'package:flutter_test/flutter_test.dart';
import 'package:pathable/data/local/demo_data.dart';
import 'package:pathable/data/local/demo_hazard_repository.dart';
import 'package:pathable/data/models/geo_point.dart';
import 'package:pathable/data/models/hazard.dart';

void main() {
  test('demo repository seeds fictional hazards', () async {
    final repo = DemoHazardRepository();
    final hazards = await repo.getNearbyHazards(
      center: DemoData.startLocation,
      radiusMeters: 5000,
    );

    expect(hazards, isNotEmpty);
    expect(hazards.every((h) => h.isDemonstration), isTrue);
    expect(
      hazards.any((h) => h.category == HazardCategory.blockedSidewalk),
      isTrue,
    );
    expect(
      hazards.any((h) => h.category == HazardCategory.stairsOrInaccessiblePath),
      isTrue,
    );
    repo.dispose();
  });

  test('demo repository persists created reports in session', () async {
    final repo = DemoHazardRepository(seed: const []);
    final created = await repo.create(
      Hazard(
        id: '',
        category: HazardCategory.other,
        severity: HazardSeverity.low,
        status: HazardStatus.provisional,
        location: const GeoPoint(latitude: 29.54847, longitude: -95.58381),
        confidenceScore: 0.2,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        description: '[DEMO] New report',
      ),
    );

    expect(created.id, isNotEmpty);
    expect(created.isDemonstration, isTrue);
    final fetched = await repo.getById(created.id);
    expect(fetched, isNotNull);
    expect(fetched!.description, contains('[DEMO]'));
    repo.dispose();
  });
}
