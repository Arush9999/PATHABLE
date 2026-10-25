import 'package:flutter_test/flutter_test.dart';
import 'package:pathable/core/geo/dashed_polyline.dart';
import 'package:pathable/core/geo/geo_math.dart';
import 'package:pathable/data/local/demo_data.dart';
import 'package:pathable/data/models/geo_point.dart';
import 'package:pathable/data/models/hazard.dart';
import 'package:pathable/data/services/geocoding_service.dart';
import 'package:pathable/routing/hazard_route_filter.dart';
import 'package:pathable/routing/route_progress.dart';
import 'package:pathable/routing/route_scoring.dart';
import 'package:pathable/routing/routing_models.dart';
import 'package:pathable/routing/routing_origin.dart';

void main() {
  test('dashed polyline leaves gaps instead of one solid line', () {
    final geometry = [
      const GeoPoint(latitude: 29.54847, longitude: -95.58381),
      const GeoPoint(latitude: 29.55210, longitude: -95.58090),
    ];
    final dashes = dashedPolyline(geometry);
    expect(dashes.length, greaterThan(1));
    final dashLength = dashes.fold<double>(
      0,
      (sum, dash) => sum + pathLengthMeters(dash),
    );
    expect(dashLength, lessThan(pathLengthMeters(geometry) * 0.75));
  });

  test('GPS is the default origin unless the user chose an address', () {
    const gps = GeoPoint(latitude: 29.55, longitude: -95.59);
    const address = GeoPoint(latitude: 29.60, longitude: -95.62);
    final chosen = PlaceSuggestion(
      id: 'place-1',
      name: 'Town Square',
      location: address,
    );

    expect(
      routingOriginFor(selectedOrigin: null, gps: gps),
      gps,
    );
    expect(
      routingOriginFor(selectedOrigin: chosen, gps: gps),
      address,
    );
    final demo = PlaceSuggestion(
      id: demoOriginId,
      name: 'Riverstone demo start',
      location: DemoData.startLocation,
      isDemonstration: true,
    );
    expect(
      routingOriginFor(selectedOrigin: demo, gps: gps),
      DemoData.startLocation,
    );
    expect(
      routingOriginLabel(selectedOrigin: null, gps: gps),
      'My location',
    );
    expect(
      routingOriginLabel(selectedOrigin: null, gps: null),
      isNot('My location'),
    );
  });

  test('route progress advances the maneuver as the user moves', () {
    const start = GeoPoint(latitude: 29.54847, longitude: -95.58381);
    const mid = GeoPoint(latitude: 29.55040, longitude: -95.58120);
    const end = GeoPoint(latitude: 29.55210, longitude: -95.58090);
    final progress = routeProgress(
      geometry: const [start, mid, end],
      maneuvers: [
        RouteManeuver(
          instruction: 'Start walking',
          distanceMeters: pathLengthMeters(const [start, mid]),
          location: start,
        ),
        RouteManeuver(
          instruction: 'Continue to the destination',
          distanceMeters: pathLengthMeters(const [mid, end]),
          location: mid,
        ),
      ],
      user: const GeoPoint(latitude: 29.55120, longitude: -95.58105),
    );

    expect(progress.offRoute, isFalse);
    expect(progress.maneuverIndex, 1);
    expect(progress.remainingMeters, greaterThan(0));
  });

  test('Sugar Land pins penalize or avoid a route that passes through them', () {
    final hazards = DemoData.hazards(now: DateTime.utc(2026, 10, 23));
    final shops = hazards.firstWhere((h) => h.id == 'demo-hazard-shops-telfair');
    final crossing = hazards.firstWhere(
      (h) => h.id == 'demo-hazard-univ-commonwealth',
    );
    final bridge = hazards.firstWhere(
      (h) => h.id == 'demo-hazard-telfair-lake-bridge',
    );

    final scorer = RouteScorer();
    final throughShops = scorer.score(
      candidates: [
        CandidateRoute(
          id: 'through-shops',
          geometry: [
            const GeoPoint(latitude: 29.5940, longitude: -95.6500),
            shops.location,
            const GeoPoint(latitude: 29.5970, longitude: -95.6470),
          ],
          distanceMeters: 500,
          durationSeconds: 400,
          maneuvers: const [],
        ),
      ],
      hazards: [shops],
      preferences: const AccessibilityRoutingPreferences(
        avoidImpassableClosures: true,
      ),
      isDemonstration: true,
    );
    expect(throughShops.routes.single.excluded, isTrue);
    expect(throughShops.routes.single.hazardHits.single.penalty, greaterThan(0));

    final throughCrossing = scorer.score(
      candidates: [
        CandidateRoute(
          id: 'through-crossing',
          geometry: [
            const GeoPoint(latitude: 29.5580, longitude: -95.6410),
            crossing.location,
            const GeoPoint(latitude: 29.5605, longitude: -95.6385),
          ],
          distanceMeters: 400,
          durationSeconds: 300,
          maneuvers: const [],
        ),
      ],
      hazards: [crossing],
      preferences: const AccessibilityRoutingPreferences(lowVisionMode: true),
      isDemonstration: true,
    );
    final hit = throughCrossing.routes.single.hazardHits.single;
    expect(throughCrossing.routes.single.excluded, isFalse);
    expect(hit.penalty, greaterThan(80));
    expect(hit.hazard.category, HazardCategory.pedestrianSignalProblem);

    final general = const HazardRouteFilter().matchHazards(
      geometry: [
        const GeoPoint(latitude: 29.5880, longitude: -95.6565),
        bridge.location,
        const GeoPoint(latitude: 29.5905, longitude: -95.6545),
      ],
      hazards: [bridge],
      preferences: const AccessibilityRoutingPreferences(),
    );
    final wheelchair = const HazardRouteFilter().matchHazards(
      geometry: [
        const GeoPoint(latitude: 29.5880, longitude: -95.6565),
        bridge.location,
        const GeoPoint(latitude: 29.5905, longitude: -95.6545),
      ],
      hazards: [bridge],
      preferences: const AccessibilityRoutingPreferences(
        wheelchairMode: true,
        avoidStairs: true,
      ),
    );
    expect(general.single.isHardExclusion, isFalse);
    expect(general.single.penalty, greaterThan(0));
    expect(wheelchair.single.isHardExclusion, isTrue);
  });
}
