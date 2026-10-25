import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/errors/app_failure.dart';
import '../data/models/geo_point.dart';
import '../data/repositories/hazard_repository.dart';
import 'route_scoring.dart';
import 'routing_models.dart';
import 'routing_service.dart';

/// OpenStreetMap routing via the public OSRM demo server.
///
/// Not used by PathAble navigation: the public foot/cycling profiles follow
/// vehicle travel lanes. PathAble uses Valhalla pedestrian factors
/// (`walkway_factor` below `sidewalk_factor`, both below 1) and bicycle
/// `use_roads: 0`, so directions stay on paths and sidewalks. A gap follows
/// the sidewalk beside the road until a path resumes.
class OsrmRoutingService implements RoutingService {
  OsrmRoutingService({
    required HazardRepository hazardRepository,
    this.baseUrl = 'https://router.project-osrm.org',
    http.Client? httpClient,
    RouteScorer? scorer,
  })  : _hazards = hazardRepository,
        _http = httpClient ?? http.Client(),
        _scorer = scorer ?? RouteScorer();

  final String baseUrl;
  final HazardRepository _hazards;
  final http.Client _http;
  final RouteScorer _scorer;

  @override
  String get engineName => 'OSRM';

  @override
  bool get isDemonstration => false;

  @override
  Future<RoutingResult> planRoute(RoutingRequest request) async {
    final profile =
        request.mode == TravelMode.cycling ? 'cycling' : 'foot';
    final coords =
        '${request.origin.longitude},${request.origin.latitude};'
        '${request.destination.longitude},${request.destination.latitude}';
    final uri = Uri.parse(
      '$baseUrl/route/v1/$profile/$coords',
    ).replace(
      queryParameters: {
        'overview': 'full',
        'geometries': 'geojson',
        'steps': 'true',
        'alternatives': 'true',
      },
    );

    final response = await _http.get(uri);
    if (response.statusCode >= 400) {
      throw AppFailure(
        code: 'osrm_error',
        message: 'Street routing unavailable (HTTP ${response.statusCode}).',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['code'] != 'Ok') {
      throw AppFailure(
        code: 'osrm_error',
        message: 'Street routing failed: ${decoded['code'] ?? 'unknown'}.',
      );
    }

    final routes = (decoded['routes'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    if (routes.isEmpty) {
      throw const AppFailure(
        code: 'osrm_empty',
        message: 'No street route found between those points.',
      );
    }

    final candidates = <CandidateRoute>[];
    for (var i = 0; i < routes.length && i < 3; i++) {
      final route = routes[i];
      final geometry = _geometryFromGeoJson(route['geometry']);
      if (geometry.length < 2) continue;

      final maneuvers = <RouteManeuver>[];
      final legs = (route['legs'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      for (final leg in legs) {
        final steps = (leg['steps'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>();
        for (final step in steps) {
          final maneuver = step['maneuver'] as Map<String, dynamic>? ?? {};
          final name = (step['name'] as String?)?.trim();
          final type = (maneuver['type'] as String?) ?? 'continue';
          final modifier = maneuver['modifier'] as String?;
          final instruction = _instructionFor(
            type: type,
            modifier: modifier,
            name: name,
          );
          maneuvers.add(
            RouteManeuver(
              instruction: instruction,
              distanceMeters: (step['distance'] as num?)?.toDouble() ?? 0,
            ),
          );
        }
      }

      candidates.add(
        CandidateRoute(
          id: 'osrm-$i',
          geometry: geometry,
          distanceMeters: (route['distance'] as num?)?.toDouble() ?? 0,
          durationSeconds: (route['duration'] as num?)?.toDouble() ?? 0,
          maneuvers: maneuvers,
        ),
      );
    }

    if (candidates.isEmpty) {
      throw const AppFailure(
        code: 'osrm_empty',
        message: 'Street route geometry was empty.',
      );
    }

    final hazards = await _hazards.getNearbyHazards(
      center: request.origin,
      radiusMeters: 3000,
    );

    final scored = _scorer.score(
      candidates: candidates,
      hazards: hazards,
      preferences: request.preferences,
      isDemonstration: false,
    );

    return RoutingResult(
      routes: scored.routes,
      isDemonstration: false,
      limitations: [
        ...scored.limitations,
        'Using OpenStreetMap street routing for path geometry.',
      ],
    );
  }

  List<GeoPoint> _geometryFromGeoJson(Object? geometry) {
    if (geometry is! Map) return const [];
    final coords = geometry['coordinates'];
    if (coords is! List) return const [];
    final points = <GeoPoint>[];
    for (final c in coords) {
      if (c is List && c.length >= 2 && c[0] is num && c[1] is num) {
        points.add(
          GeoPoint(
            latitude: (c[1] as num).toDouble(),
            longitude: (c[0] as num).toDouble(),
          ),
        );
      }
    }
    return points;
  }

  String _instructionFor({
    required String type,
    String? modifier,
    String? name,
  }) {
    final road = (name == null || name.isEmpty) ? 'the path' : name;
    final mod = modifier == null ? '' : ' $modifier';
    return switch (type) {
      'depart' => 'Start on $road',
      'arrive' => 'You have arrived',
      'turn' => 'Turn$mod onto $road',
      'new name' => 'Continue on $road',
      'merge' => 'Merge$mod onto $road',
      'ramp' => 'Take the ramp$mod onto $road',
      'fork' => 'Keep$mod at the fork onto $road',
      'end of road' => 'At the end of the road, turn$mod onto $road',
      'roundabout' || 'rotary' => 'Enter the roundabout toward $road',
      _ => 'Continue on $road',
    };
  }
}
