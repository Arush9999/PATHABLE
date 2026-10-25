import 'dart:math' as math;

import '../data/models/geo_point.dart';
import '../data/models/hazard.dart';
import 'routing_models.dart';

/// Associates hazards with nearby route geometry segments.
class HazardRouteFilter {
  const HazardRouteFilter({this.corridorMeters = 50});

  final double corridorMeters;

  List<RouteHazardHit> matchHazards({
    required List<GeoPoint> geometry,
    required List<Hazard> hazards,
    required AccessibilityRoutingPreferences preferences,
  }) {
    final hits = <RouteHazardHit>[];
    for (final hazard in hazards) {
      if (!hazard.status.affectsRouting) {
        continue;
      }
      final match = _nearestOffset(geometry, hazard.location);
      if (match == null || match.offsetMeters > corridorMeters) {
        continue;
      }

      final hard = _isHardExclusion(hazard, preferences);
      final penalty = _penalty(hazard, preferences, hard);
      hits.add(
        RouteHazardHit(
          hazard: hazard,
          distanceAlongRouteMeters: match.alongMeters,
          offsetMeters: match.offsetMeters,
          isHardExclusion: hard,
          penalty: penalty,
        ),
      );
    }
    return hits;
  }

  bool _isHardExclusion(
    Hazard hazard,
    AccessibilityRoutingPreferences preferences,
  ) {
    if (hazard.status != HazardStatus.active &&
        hazard.status != HazardStatus.provisional) {
      return false;
    }

    final confirmedClosure = hazard.status == HazardStatus.active &&
        (hazard.category == HazardCategory.constructionClosure ||
            hazard.category == HazardCategory.blockedSidewalk) &&
        preferences.avoidImpassableClosures;

    final stairs = preferences.avoidStairs &&
        hazard.category == HazardCategory.stairsOrInaccessiblePath &&
        hazard.status == HazardStatus.active;

    final curb = preferences.avoidMissingCurbRamps &&
        hazard.category == HazardCategory.missingOrDamagedCurbRamp &&
        hazard.status == HazardStatus.active;

    final elevator = preferences.wheelchairMode &&
        hazard.category == HazardCategory.brokenElevator &&
        hazard.status == HazardStatus.active;

    return confirmedClosure || stairs || curb || elevator;
  }

  double _penalty(
    Hazard hazard,
    AccessibilityRoutingPreferences preferences,
    bool hard,
  ) {
    if (hard) {
      return 1e6;
    }

    var penalty = switch (hazard.severity) {
      HazardSeverity.low => 8.0,
      HazardSeverity.moderate => 18.0,
      HazardSeverity.high => 40.0,
      HazardSeverity.critical => 70.0,
    };

    penalty *= (0.5 + hazard.confidenceScore);

    if (hazard.status == HazardStatus.provisional) {
      penalty *= 0.65;
    }
    if (hazard.status == HazardStatus.stale) {
      penalty *= 0.35;
    }

    if (preferences.preferWellLit &&
        hazard.category == HazardCategory.poorLighting) {
      penalty += 25;
    }
    if (preferences.warnExcessiveNoise &&
        hazard.category == HazardCategory.excessiveNoise) {
      penalty += 12;
    }
    if (preferences.cyclistMode &&
        hazard.category == HazardCategory.potholeOrDamagedPavement) {
      penalty += 20;
    }
    if (preferences.lowVisionMode &&
        hazard.category == HazardCategory.pedestrianSignalProblem) {
      penalty += 35;
    }
    if (preferences.lowVisionMode &&
        hazard.category == HazardCategory.stairsOrInaccessiblePath &&
        !hard) {
      penalty += 20;
    }

    return penalty;
  }

  ({double alongMeters, double offsetMeters})? _nearestOffset(
    List<GeoPoint> geometry,
    GeoPoint point,
  ) {
    if (geometry.length < 2) {
      return null;
    }

    var bestOffset = double.infinity;
    var bestAlong = 0.0;
    var traveled = 0.0;

    for (var i = 0; i < geometry.length - 1; i++) {
      final a = geometry[i];
      final b = geometry[i + 1];
      final segmentLength = distanceMeters(a, b);
      final projection = _project(point, a, b);
      if (projection.offset < bestOffset) {
        bestOffset = projection.offset;
        bestAlong = traveled + projection.along;
      }
      traveled += segmentLength;
    }

    if (bestOffset.isInfinite) {
      return null;
    }
    return (alongMeters: bestAlong, offsetMeters: bestOffset);
  }

  ({double along, double offset}) _project(
    GeoPoint p,
    GeoPoint a,
    GeoPoint b,
  ) {
    final ax = a.longitude;
    final ay = a.latitude;
    final bx = b.longitude;
    final by = b.latitude;
    final px = p.longitude;
    final py = p.latitude;

    final dx = bx - ax;
    final dy = by - ay;
    final length2 = dx * dx + dy * dy;
    if (length2 == 0) {
      return (along: 0, offset: distanceMeters(p, a));
    }

    var t = ((px - ax) * dx + (py - ay) * dy) / length2;
    t = t.clamp(0.0, 1.0);
    final proj = GeoPoint(
      latitude: ay + t * dy,
      longitude: ax + t * dx,
    );
    return (
      along: distanceMeters(a, proj),
      offset: distanceMeters(p, proj),
    );
  }

  double distanceMeters(GeoPoint a, GeoPoint b) {
    const earthRadius = 6371000.0;
    final dLat = _radians(b.latitude - a.latitude);
    final dLon = _radians(b.longitude - a.longitude);
    final lat1 = _radians(a.latitude);
    final lat2 = _radians(b.latitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * earthRadius * math.asin(math.min(1, math.sqrt(h)));
  }

  double _radians(double degrees) => degrees * math.pi / 180;
}
