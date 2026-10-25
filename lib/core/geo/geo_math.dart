import 'dart:math' as math;

import '../../data/models/geo_point.dart';

double distanceMeters(GeoPoint a, GeoPoint b) {
  const earthRadius = 6371000.0;
  final dLat = _radians(b.latitude - a.latitude);
  final dLon = _radians(b.longitude - a.longitude);
  final lat1 = _radians(a.latitude);
  final lat2 = _radians(b.latitude);
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * earthRadius * math.asin(math.min(1, math.sqrt(h)));
}

double pathLengthMeters(List<GeoPoint> points) {
  var total = 0.0;
  for (var i = 0; i < points.length - 1; i++) {
    total += distanceMeters(points[i], points[i + 1]);
  }
  return total;
}

GeoPoint interpolate(GeoPoint a, GeoPoint b, double t) {
  final clamped = t.clamp(0.0, 1.0);
  return GeoPoint(
    latitude: a.latitude + (b.latitude - a.latitude) * clamped,
    longitude: a.longitude + (b.longitude - a.longitude) * clamped,
  );
}

class PolylineProjection {
  const PolylineProjection({
    required this.alongMeters,
    required this.offsetMeters,
  });

  final double alongMeters;
  final double offsetMeters;
}

/// Closest point of [point] on [geometry], measured along the path.
PolylineProjection? projectOntoPolyline(
  List<GeoPoint> geometry,
  GeoPoint point,
) {
  if (geometry.length < 2) return null;

  var bestOffset = double.infinity;
  var bestAlong = 0.0;
  var traveled = 0.0;

  for (var i = 0; i < geometry.length - 1; i++) {
    final a = geometry[i];
    final b = geometry[i + 1];
    final segmentLength = distanceMeters(a, b);
    final projection = _project(point, a, b, segmentLength);
    if (projection.offset < bestOffset) {
      bestOffset = projection.offset;
      bestAlong = traveled + projection.along;
    }
    traveled += segmentLength;
  }

  if (bestOffset.isInfinite) return null;
  return PolylineProjection(
    alongMeters: bestAlong,
    offsetMeters: bestOffset,
  );
}

/// Circle around the trip that still includes the destination and nearby pins.
double hazardSearchRadiusMeters(GeoPoint origin, GeoPoint destination) {
  final span = distanceMeters(origin, destination);
  final padded = span + 1500;
  if (padded < 4000) return 4000;
  if (padded > 20000) return 20000;
  return padded;
}

({double along, double offset}) _project(
  GeoPoint p,
  GeoPoint a,
  GeoPoint b,
  double segmentLength,
) {
  if (segmentLength < 0.5) {
    return (along: 0, offset: distanceMeters(p, a));
  }

  final ax = a.longitude;
  final ay = a.latitude;
  final bx = b.longitude;
  final by = b.latitude;
  final dx = bx - ax;
  final dy = by - ay;
  final length2 = dx * dx + dy * dy;
  if (length2 == 0) {
    return (along: 0, offset: distanceMeters(p, a));
  }

  var t = ((p.longitude - ax) * dx + (p.latitude - ay) * dy) / length2;
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

double _radians(double degrees) => degrees * math.pi / 180;
