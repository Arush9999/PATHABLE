import 'package:flutter_test/flutter_test.dart';
import 'package:pathable/data/models/geo_point.dart';
import 'package:pathable/data/models/hazard.dart';

void main() {
  group('GeoPoint', () {
    test('accepts valid coordinates', () {
      const point = GeoPoint(latitude: 38.89, longitude: -77.01);
      expect(point.isValid, isTrue);
    });

    test('rejects invalid coordinates', () {
      const point = GeoPoint(latitude: 120, longitude: -77);
      expect(point.isValid, isFalse);
    });

    test('parses PostGIS EWKB hex point', () {
      // SRID=4326;POINT(-95.5824 29.5496) little-endian EWKB
      const hex =
          '0101000020E6100000304CA60A46E557C0B1E1E995B28C3D40';
      final point = GeoPoint.parseLocation(hex);
      expect(point.longitude, closeTo(-95.5824, 0.0001));
      expect(point.latitude, closeTo(29.5496, 0.0001));
    });

    test('parses GeoJSON and WKT', () {
      final geoJson = GeoPoint.parseLocation({
        'type': 'Point',
        'coordinates': [-95.58, 29.55],
      });
      expect(geoJson.latitude, 29.55);
      expect(geoJson.longitude, -95.58);

      final wkt = GeoPoint.parseLocation('SRID=4326;POINT(-95.58 29.55)');
      expect(wkt.latitude, 29.55);
      expect(wkt.longitude, -95.58);
    });
  });

  group('Hazard', () {
    test('accessibility label includes status and demo prefix', () {
      final hazard = Hazard(
        id: 'h1',
        category: HazardCategory.blockedSidewalk,
        severity: HazardSeverity.high,
        status: HazardStatus.provisional,
        location: const GeoPoint(latitude: 1, longitude: 2),
        confidenceScore: 0.4,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        description: 'Barriers',
        isDemonstration: true,
      );

      expect(hazard.accessibilityLabel, contains('Demonstration data'));
      expect(hazard.accessibilityLabel, contains('Blocked sidewalk'));
      expect(hazard.accessibilityLabel, contains('Provisionally reported'));
      expect(hazard.status.affectsRouting, isTrue);
    });

    test('resolved hazards do not affect routing', () {
      expect(HazardStatus.resolved.affectsRouting, isFalse);
      expect(HazardStatus.stale.affectsRouting, isFalse);
      expect(HazardStatus.active.affectsRouting, isTrue);
    });
  });
}
