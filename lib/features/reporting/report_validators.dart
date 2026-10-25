import 'dart:math' as math;

import '../../data/models/geo_point.dart';
import '../../data/models/hazard.dart';

class ReportValidationResult {
  const ReportValidationResult({required this.errors});

  final List<String> errors;

  bool get isValid => errors.isEmpty;
}

/// Validates hazard reports before submission.
class ReportValidators {
  const ReportValidators();

  ReportValidationResult validate({
    required HazardCategory? category,
    required HazardSeverity? severity,
    required GeoPoint? location,
    required String description,
  }) {
    final errors = <String>[];

    if (category == null) {
      errors.add('Choose a hazard category.');
    }
    if (severity == null) {
      errors.add('Choose a severity level.');
    }
    if (location == null || !location.isValid) {
      errors.add('A valid report location is required.');
    }

    // Description is optional (Waze-style quick report). Category + location is enough.
    final trimmed = description.trim();
    if (trimmed.length > 500) {
      errors.add('Description must be 500 characters or fewer.');
    }

    return ReportValidationResult(errors: errors);
  }

  /// Returns nearby existing reports that may be duplicates.
  List<Hazard> findLikelyDuplicates({
    required List<Hazard> existing,
    required GeoPoint location,
    required HazardCategory category,
    double radiusMeters = 40,
  }) {
    return existing
        .where(
          (hazard) =>
              hazard.category == category &&
              hazard.status != HazardStatus.resolved &&
              distanceMeters(hazard.location, location) <= radiusMeters,
        )
        .toList(growable: false);
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
