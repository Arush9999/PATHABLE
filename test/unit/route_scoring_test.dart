import 'package:flutter_test/flutter_test.dart';
import 'package:pathable/data/local/demo_data.dart';
import 'package:pathable/data/local/demo_hazard_repository.dart';
import 'package:pathable/data/models/geo_point.dart';
import 'package:pathable/data/models/hazard.dart';
import 'package:pathable/routing/demo_routing_service.dart';
import 'package:pathable/routing/hazard_route_filter.dart';
import 'package:pathable/routing/route_scoring.dart';
import 'package:pathable/routing/routing_models.dart';

void main() {
  test('hazard filter matches nearby corridor hazards', () {
    const filter = HazardRouteFilter(corridorMeters: 50);
    final blocked = DemoData.hazards(now: DateTime.utc(2026, 10, 9))
        .firstWhere((h) => h.category == HazardCategory.blockedSidewalk);
    final geometry = [
      DemoData.startLocation,
      blocked.location,
      DemoData.destinations.first.location,
    ];
    final hazards = DemoData.hazards(now: DateTime.utc(2026, 10, 9));

    final hits = filter.matchHazards(
      geometry: geometry,
      hazards: hazards,
      preferences: const AccessibilityRoutingPreferences(
        avoidImpassableClosures: true,
        avoidStairs: true,
      ),
    );

    expect(hits, isNotEmpty);
    expect(
      hits.any((h) => h.hazard.category == HazardCategory.blockedSidewalk),
      isTrue,
    );
  });

  test('wheelchair preferences hard-exclude active stairs', () {
    final scorer = RouteScorer();
    final stairs = DemoData.hazards(now: DateTime.utc(2026, 10, 9))
        .firstWhere((h) => h.category == HazardCategory.stairsOrInaccessiblePath);

    final result = scorer.score(
      candidates: [
        CandidateRoute(
          id: 'with-stairs',
          geometry: [
            DemoData.startLocation,
            stairs.location,
            DemoData.destinations.first.location,
          ],
          distanceMeters: 400,
          durationSeconds: 300,
          maneuvers: const [],
        ),
        CandidateRoute(
          id: 'clear',
          geometry: [
            DemoData.startLocation,
            const GeoPoint(latitude: 29.54580, longitude: -95.57950),
            DemoData.destinations.first.location,
          ],
          distanceMeters: 700,
          durationSeconds: 500,
          maneuvers: const [],
        ),
      ],
      hazards: [stairs],
      preferences: const AccessibilityRoutingPreferences(
        wheelchairMode: true,
        avoidStairs: true,
        avoidImpassableClosures: true,
      ),
      isDemonstration: true,
    );

    expect(result.routes, isNotEmpty);
    final recommended = result.routes.firstWhere((r) => !r.excluded);
    expect(recommended.id, 'clear');
  });

  test('demo routing returns labeled demonstration routes', () async {
    final repo = DemoHazardRepository();
    final service = DemoRoutingService(hazardRepository: repo);
    final result = await service.planRoute(
      RoutingRequest(
        origin: DemoData.startLocation,
        destination: DemoData.destinations.first.location,
        mode: TravelMode.pedestrian,
        preferences: const AccessibilityRoutingPreferences(
          avoidImpassableClosures: true,
        ),
      ),
    );

    expect(result.isDemonstration, isTrue);
    expect(result.routes, isNotEmpty);
    expect(
      result.limitations.any((l) => l.contains('Demonstration')),
      isTrue,
    );
    repo.dispose();
  });
}
