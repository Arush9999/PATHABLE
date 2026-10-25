import 'dart:math' as math;

import '../core/geo/geo_math.dart';
import '../data/local/demo_data.dart';
import '../data/models/geo_point.dart';
import '../data/repositories/hazard_repository.dart';
import 'route_scoring.dart';
import 'routing_models.dart';
import 'routing_service.dart';

/// Clearly labeled demonstration router for the Riverstone demo district.
///
/// Never claim these geometries are verified real-world routes.
class DemoRoutingService implements RoutingService {
  DemoRoutingService({
    required HazardRepository hazardRepository,
    RouteScorer? scorer,
  })  : _hazards = hazardRepository,
        _scorer = scorer ?? RouteScorer();

  final HazardRepository _hazards;
  final RouteScorer _scorer;

  @override
  String get engineName => 'PathAble demonstration router';

  @override
  bool get isDemonstration => true;

  @override
  Future<RoutingResult> planRoute(RoutingRequest request) async {
    final hazards = await _hazards.getNearbyHazards(
      center: request.origin,
      radiusMeters: hazardSearchRadiusMeters(
        request.origin,
        request.destination,
      ),
    );

    final candidates = [
      _pathCandidate(
        request,
        id: 'demo-direct',
        via: const [
          GeoPoint(latitude: 29.54960, longitude: -95.58240),
          GeoPoint(latitude: 29.55040, longitude: -95.58120),
        ],
        instructions: const [
          'Follow the sidewalk path through Riverstone.',
          'Stay on the pedestrian path toward your destination.',
        ],
      ),
      _pathCandidate(
        request,
        id: 'demo-via-park',
        via: [
          DemoData.destinations
              .firstWhere((d) => d.id == 'demo-dest-park')
              .location,
        ],
        instructions: const [
          'Take the park trail (paths and sidewalks only).',
          'Continue on the trail to your destination.',
        ],
        detourFactor: 1.15,
      ),
      _pathCandidate(
        request,
        id: 'demo-via-shops',
        via: [
          DemoData.destinations
              .firstWhere((d) => d.id == 'demo-dest-shops')
              .location,
        ],
        instructions: const [
          'Use the shared-use path near University Blvd.',
          'Stay on the sidewalk connector to your destination.',
        ],
        detourFactor: 1.05,
      ),
    ];

    final result = _scorer.score(
      candidates: candidates,
      hazards: hazards,
      preferences: request.preferences,
      isDemonstration: true,
    );

    final modeLabel =
        request.mode == TravelMode.cycling ? 'cycling' : 'walking';

    return RoutingResult(
      routes: result.routes,
      isDemonstration: true,
      limitations: [
        ...result.limitations,
        'Demonstration $modeLabel routing for ${DemoData.environmentName} '
            '(paths and sidewalks; a gap follows the sidewalk beside the road '
            'until a path resumes). Not a live Valhalla route.',
      ],
    );
  }

  CandidateRoute _pathCandidate(
    RoutingRequest request, {
    required String id,
    required List<GeoPoint> via,
    required List<String> instructions,
    double detourFactor = 1.0,
  }) {
    final geometry = [request.origin, ...via, request.destination];
    final distance = _pathLengthMeters(geometry) * detourFactor;
    final duration = _durationSeconds(distance, request.mode, request);

    final segment = distance / math.max(instructions.length, 1);
    final maneuvers = [
      for (var i = 0; i < instructions.length; i++)
        RouteManeuver(
          instruction: instructions[i],
          distanceMeters: segment,
        ),
    ];

    return CandidateRoute(
      id: id,
      geometry: geometry,
      distanceMeters: distance,
      durationSeconds: duration,
      maneuvers: maneuvers,
    );
  }

  double _durationSeconds(
    double meters,
    TravelMode mode,
    RoutingRequest request,
  ) {
    // Speeds in meters/second.
    final mps = switch (mode) {
      TravelMode.cycling => 5.0, // ~18 km/h
      TravelMode.pedestrian =>
        request.preferences.wheelchairMode ? 0.97 : 1.4, // ~3.5 / 5.1 km/h
    };
    return meters / mps;
  }

  double _pathLengthMeters(List<GeoPoint> points) {
    var total = 0.0;
    for (var i = 0; i < points.length - 1; i++) {
      total += _haversineMeters(points[i], points[i + 1]);
    }
    return total;
  }

  double _haversineMeters(GeoPoint a, GeoPoint b) {
    const earth = 6371000.0;
    final dLat = _rad(b.latitude - a.latitude);
    final dLon = _rad(b.longitude - a.longitude);
    final lat1 = _rad(a.latitude);
    final lat2 = _rad(b.latitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return 2 * earth * math.asin(math.sqrt(h));
  }

  double _rad(double deg) => deg * math.pi / 180;
}
