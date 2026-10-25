import '../core/geo/geo_math.dart';
import '../data/models/geo_point.dart';
import 'routing_models.dart';

/// Where the traveler is along a planned route.
class RouteProgress {
  const RouteProgress({
    required this.alongMeters,
    required this.remainingMeters,
    required this.offsetMeters,
    required this.maneuverIndex,
    required this.maneuverRemainingMeters,
    required this.offRoute,
  });

  final double alongMeters;
  final double remainingMeters;
  final double offsetMeters;
  final int maneuverIndex;
  final double maneuverRemainingMeters;
  final bool offRoute;

  static const empty = RouteProgress(
    alongMeters: 0,
    remainingMeters: 0,
    offsetMeters: 0,
    maneuverIndex: 0,
    maneuverRemainingMeters: 0,
    offRoute: false,
  );
}

RouteProgress routeProgress({
  required List<GeoPoint> geometry,
  required List<RouteManeuver> maneuvers,
  required GeoPoint user,
  double offRouteMeters = 40,
}) {
  final total = pathLengthMeters(geometry);
  final projection = projectOntoPolyline(geometry, user);
  if (projection == null || total <= 0) {
    return RouteProgress.empty;
  }

  final along = projection.alongMeters.clamp(0.0, total);
  final remaining = (total - along).clamp(0.0, total);
  final maneuverSum = maneuvers.fold<double>(
    0,
    (sum, maneuver) => sum + maneuver.distanceMeters,
  );
  final scaledAlong = maneuverSum <= 0 ? 0.0 : along / total * maneuverSum;
  final index = _maneuverIndex(maneuvers, scaledAlong);
  final into = _distanceIntoManeuver(maneuvers, scaledAlong, index);
  final maneuverLength =
      maneuvers.isEmpty ? 0.0 : maneuvers[index].distanceMeters;
  final maneuverRemaining = (maneuverLength - into).clamp(0.0, maneuverLength);

  return RouteProgress(
    alongMeters: along,
    remainingMeters: remaining,
    offsetMeters: projection.offsetMeters,
    maneuverIndex: index,
    maneuverRemainingMeters: maneuverRemaining,
    offRoute: projection.offsetMeters > offRouteMeters,
  );
}

int _maneuverIndex(List<RouteManeuver> maneuvers, double along) {
  if (maneuvers.isEmpty) return 0;
  var cursor = 0.0;
  for (var i = 0; i < maneuvers.length; i++) {
    cursor += maneuvers[i].distanceMeters;
    if (along <= cursor + 0.5) return i;
  }
  return maneuvers.length - 1;
}

double _distanceIntoManeuver(
  List<RouteManeuver> maneuvers,
  double along,
  int index,
) {
  if (maneuvers.isEmpty) return 0;
  var cursor = 0.0;
  for (var i = 0; i < index; i++) {
    cursor += maneuvers[i].distanceMeters;
  }
  return (along - cursor).clamp(0.0, maneuvers[index].distanceMeters);
}
