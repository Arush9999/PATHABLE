import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/errors/app_failure.dart';
import '../core/geo/geo_math.dart';
import '../data/models/geo_point.dart';
import '../data/repositories/hazard_repository.dart';
import 'route_scoring.dart';
import 'routing_models.dart';
import 'routing_service.dart';

/// Footway multiplier. Valhalla's minimum factor is 0.1.
///
/// Applies to `highway=footway` (`Use::kFootway`). Lower than
/// [kValhallaSidewalkFactor] so a path wins again as soon as one is available.
const double kValhallaWalkwayFactor = 0.1;

/// Cost of a road that is tagged with a sidewalk.
///
/// Valhalla prices a separate sidewalk way with [kValhallaWalkwayFactor], the
/// same as a footway. This factor applies only to the road edge itself when
/// that road has `sidewalk=left/right/both`. It is above the path factor and
/// below 1, so the route stays on the path until the path ends, then uses the
/// sidewalk along the road instead of the travel lane.
const double kValhallaSidewalkFactor = 0.85;

/// Alley multiplier. Above 1 so an alley is not the gap bridge.
const double kValhallaAlleyFactor = 3.0;

/// Driveway multiplier. Valhalla's own "avoid private driveways" default.
const double kValhallaDrivewayFactor = 5.0;

/// Bicycle willingness to ride in traffic, from 0 to 1.
///
/// 0 does not forbid roads. It makes cycleways, footways, and paths the
/// cheap edges, and leaves a road legal only when the path has ended.
const double kValhallaBicycleUseRoads = 0.0;

/// Valhalla `costing_options` for [request].
///
/// Pedestrian costing has no `use_roads` field. A factor below 1 makes that
/// kind of edge cheaper; 1 is neutral. Per meter, a footway costs 0.1, a
/// sidewalk (or a road that has a sidewalk) costs 0.85, and a road with no
/// sidewalk costs 1. The route stays on the path until it ends: a footway
/// beats a sidewalk unless the footway is more than 8.5 times longer. After
/// the path ends, the sidewalk is the next choice and still beats a road with
/// no sidewalk. An alley
/// costs 3, so it is not that bridge. Ways with no pedestrian access, such as
/// a motorway, stay excluded by Valhalla's access rules rather than by a factor.
/// Current Valhalla applies `walkway_factor` to footways, not to `highway=path`
/// (`Use::kPath`). Bicycle `use_roads` is what prefers those paths.
///
/// Bicycle costing uses [kValhallaBicycleUseRoads]. At 0, cycleways, paths,
/// and footways are the low-stress edges, and `use_sidepath` is penalized the
/// most, so the route stays on the side path while it exists. A road is still
/// allowed, which is the bridge after the path ends, until a path is cheaper
/// again. Bicycle costing has no `sidewalk_factor`.
Map<String, dynamic> valhallaCostingOptions(RoutingRequest request) {
  if (request.mode == TravelMode.cycling) {
    return {
      'bicycle': {
        'bicycle_type': 'Hybrid',
        'cycling_speed': 16.0, // km/h — shared path pace
        'use_roads': kValhallaBicycleUseRoads,
        'use_hills': 0.35,
        'use_living_streets': 0.85,
        'use_ferry': 0.0,
        'avoid_bad_surfaces': 0.65,
      },
    };
  }

  final walkSpeed = request.preferences.wheelchairMode ? 3.5 : 5.0;
  return {
    'pedestrian': {
      'walking_speed': walkSpeed, // km/h
      'walkway_factor': kValhallaWalkwayFactor,
      'sidewalk_factor': kValhallaSidewalkFactor,
      'alley_factor': kValhallaAlleyFactor,
      'driveway_factor': kValhallaDrivewayFactor,
      'use_hills': request.preferences.wheelchairMode ? 0.05 : 0.4,
      'use_ferry': 0.0,
      'use_living_streets': 0.8,
      'service_penalty': 30,
      'service_factor': 1.5,
      'step_penalty': request.preferences.avoidStairs ||
              request.preferences.wheelchairMode
          ? 45
          : 5,
      'max_hiking_difficulty': 1,
    },
  };
}

/// Valhalla-backed routing. Hazard awareness is applied by PathAble scoring.
class ValhallaRoutingService implements RoutingService {
  ValhallaRoutingService({
    required this.endpoint,
    required HazardRepository hazardRepository,
    http.Client? httpClient,
    RouteScorer? scorer,
  })  : _hazards = hazardRepository,
        _http = httpClient ?? http.Client(),
        _scorer = scorer ?? RouteScorer();

  final String endpoint;
  final HazardRepository _hazards;
  final http.Client _http;
  final RouteScorer _scorer;

  @override
  String get engineName => 'Valhalla';

  @override
  bool get isDemonstration => false;

  @override
  Future<RoutingResult> planRoute(RoutingRequest request) async {
    final costing =
        request.mode == TravelMode.cycling ? 'bicycle' : 'pedestrian';
    final body = {
      'locations': [
        {
          'lat': request.origin.latitude,
          'lon': request.origin.longitude,
        },
        {
          'lat': request.destination.latitude,
          'lon': request.destination.longitude,
        },
      ],
      'costing': costing,
      'costing_options': valhallaCostingOptions(request),
      // Valhalla accepts kilometers or miles (not meters).
      'directions_options': {'units': 'kilometers'},
      'alternates': (request.alternatives - 1).clamp(0, 2),
    };

    final response = await _postRoute(jsonEncode(body));

    if (response.statusCode >= 400) {
      throw AppFailure(
        code: 'valhalla_error',
        message:
            'Path routing unavailable (HTTP ${response.statusCode}). '
            'Try start/end points closer to a sidewalk, path, or trail.',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final trips = <Map<String, dynamic>>[];
    if (decoded['trip'] is Map<String, dynamic>) {
      trips.add(decoded['trip'] as Map<String, dynamic>);
    }
    final alternates = decoded['alternates'];
    if (alternates is List) {
      for (final item in alternates) {
        if (item is Map<String, dynamic> &&
            item['trip'] is Map<String, dynamic>) {
          trips.add(item['trip'] as Map<String, dynamic>);
        }
      }
    }

    final candidates = <CandidateRoute>[];
    for (var i = 0; i < trips.length; i++) {
      final trip = trips[i];
      final summary = trip['summary'] as Map<String, dynamic>? ?? {};
      final legs = (trip['legs'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      final geometry = <GeoPoint>[];
      final maneuvers = <RouteManeuver>[];

      for (final leg in legs) {
        final shape = leg['shape'] as String?;
        if (shape != null) {
          geometry.addAll(_decodePolyline6(shape));
        }
        final man = (leg['maneuvers'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>();
        for (final m in man) {
          maneuvers.add(
            RouteManeuver(
              instruction: (m['instruction'] as String?) ?? 'Continue',
              distanceMeters:
                  ((m['length'] as num?)?.toDouble() ?? 0) * 1000,
            ),
          );
        }
      }

      candidates.add(
        CandidateRoute(
          id: 'valhalla-$i',
          geometry: geometry,
          distanceMeters:
              ((summary['length'] as num?)?.toDouble() ?? 0) * 1000,
          // Valhalla summary.time is seconds.
          durationSeconds: (summary['time'] as num?)?.toDouble() ?? 0,
          maneuvers: maneuvers,
        ),
      );
    }

    final hazards = await _hazards.getNearbyHazards(
      center: request.origin,
      radiusMeters: hazardSearchRadiusMeters(
        request.origin,
        request.destination,
      ),
    );

    return _scorer.score(
      candidates: candidates,
      hazards: hazards,
      preferences: request.preferences,
      isDemonstration: false,
    );
  }

  Future<http.Response> _postRoute(String body) async {
    final targets = _routeUris(endpoint);
    try {
      if (targets.length == 1) {
        return await _postOne(targets.single, body);
      }
      return await _firstSuccess([
        for (final uri in targets) _postOne(uri, body),
      ]);
    } catch (error) {
      throw AppFailure(
        code: 'valhalla_unreachable',
        message: _unreachableMessage(targets.first, error),
      );
    }
  }

  static Future<T> _firstSuccess<T>(List<Future<T>> attempts) {
    final done = Completer<T>();
    var pending = attempts.length;
    Object? lastError;
    for (final attempt in attempts) {
      attempt.then(
        (value) {
          if (!done.isCompleted) done.complete(value);
        },
        onError: (Object error) {
          lastError = error;
          pending -= 1;
          if (pending == 0 && !done.isCompleted) {
            done.completeError(lastError ?? error);
          }
        },
      );
    }
    return done.future;
  }

  Future<http.Response> _postOne(Uri uri, String body) {
    return _http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(const Duration(seconds: 8));
  }

  /// Emulator builds use `10.0.2.2`. A phone cannot reach that address, so
  /// also try `127.0.0.1`, which works while `adb reverse tcp:8002 tcp:8002`
  /// is forwarding the phone to this computer.
  static List<Uri> _routeUris(String endpoint) {
    final root = endpoint.endsWith('/')
        ? endpoint.substring(0, endpoint.length - 1)
        : endpoint;
    final primary = Uri.parse('$root/route');
    if (primary.host != '10.0.2.2') return [primary];
    return [primary, primary.replace(host: '127.0.0.1')];
  }

  static String _unreachableMessage(Uri uri, Object? error) {
    if (uri.host == '10.0.2.2') {
      return 'Routing did not answer. The address 10.0.2.2 only works in '
          'the Android emulator. On a phone, keep the USB cable connected '
          'so PathAble can use this computer, and make sure Valhalla is running.';
    }
    return 'Routing server at ${uri.host} did not answer. $error';
  }

  /// Valhalla uses precision-6 encoded polylines.
  List<GeoPoint> _decodePolyline6(String encoded) {
    final points = <GeoPoint>[];
    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < encoded.length) {
      var result = 0;
      var shift = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      result = 0;
      shift = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(
        GeoPoint(latitude: lat / 1e6, longitude: lng / 1e6),
      );
    }
    return points;
  }
}
