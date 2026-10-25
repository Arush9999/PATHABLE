import 'package:flutter_test/flutter_test.dart';
import 'package:pathable/data/models/geo_point.dart';
import 'package:pathable/data/models/hazard.dart';
import 'package:pathable/features/reporting/report_validators.dart';

void main() {
  const validators = ReportValidators();

  test('rejects empty reports', () {
    final result = validators.validate(
      category: null,
      severity: null,
      location: null,
      description: '',
    );
    expect(result.isValid, isFalse);
    expect(result.errors, isNotEmpty);
  });

  test('accepts a quick report with only category and location', () {
    final result = validators.validate(
      category: HazardCategory.blockedSidewalk,
      severity: HazardSeverity.high,
      location: const GeoPoint(latitude: 29.54847, longitude: -95.58381),
      description: '',
    );
    expect(result.isValid, isTrue);
  });

  test('accepts a well-formed report', () {
    final result = validators.validate(
      category: HazardCategory.blockedSidewalk,
      severity: HazardSeverity.high,
      location: const GeoPoint(latitude: 29.54847, longitude: -95.58381),
      description: 'Barriers across the sidewalk',
    );
    expect(result.isValid, isTrue);
  });

  test('finds likely duplicate reports nearby', () {
    final existing = [
      Hazard(
        id: 'a',
        category: HazardCategory.blockedSidewalk,
        severity: HazardSeverity.high,
        status: HazardStatus.provisional,
        location: const GeoPoint(latitude: 29.54847, longitude: -95.58381),
        confidenceScore: 0.3,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    ];

    final duplicates = validators.findLikelyDuplicates(
      existing: existing,
      location: const GeoPoint(latitude: 29.54850, longitude: -95.58385),
      category: HazardCategory.blockedSidewalk,
    );

    expect(duplicates, hasLength(1));
  });
}
