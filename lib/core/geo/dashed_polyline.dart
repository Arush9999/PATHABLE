import 'dart:math' as math;

import '../../data/models/geo_point.dart';
import 'geo_math.dart';

/// Breaks [geometry] into short pieces separated by gaps.
///
/// MapLibre [LineOptions] has no `line-dasharray`. These segments are drawn
/// as separate lines so the route reads as a dotted path.
List<List<GeoPoint>> dashedPolyline(
  List<GeoPoint> geometry, {
  double dashMeters = 12,
  double gapMeters = 10,
  int maxDashes = 140,
}) {
  if (geometry.length < 2) return const [];
  final total = pathLengthMeters(geometry);
  if (total < 8) return [List<GeoPoint>.from(geometry)];

  var dash = dashMeters;
  var gap = gapMeters;
  final estimated = total / (dash + gap);
  if (estimated > maxDashes) {
    final scale = estimated / maxDashes;
    dash *= scale;
    gap *= scale;
  }

  final result = <List<GeoPoint>>[];
  final current = <GeoPoint>[];
  var drawing = true;
  var budget = dash;

  void flush() {
    if (current.length >= 2) {
      result.add(List<GeoPoint>.from(current));
    }
    current.clear();
  }

  for (var i = 0; i < geometry.length - 1; i++) {
    var start = geometry[i];
    final end = geometry[i + 1];
    var remaining = distanceMeters(start, end);
    if (remaining < 0.4) continue;

    while (remaining > 0.4) {
      final step = math.min(remaining, budget);
      final next = interpolate(start, end, step / remaining);
      if (drawing) {
        if (current.isEmpty) current.add(start);
        current.add(next);
      }
      budget -= step;
      remaining -= step;
      start = next;
      if (budget <= 0.4) {
        if (drawing) flush();
        drawing = !drawing;
        budget = drawing ? dash : gap;
      }
    }
  }

  if (drawing) flush();
  if (result.isEmpty) return [List<GeoPoint>.from(geometry)];
  return result;
}
