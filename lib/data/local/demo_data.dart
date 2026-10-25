import '../models/geo_point.dart';
import '../models/hazard.dart';

/// Fictional demonstration environment in Riverstone (Sugar Land, TX 77479).
///
/// All hazards and destinations are labeled demonstration data and must not be
/// treated as verified real-world reports.
abstract final class DemoData {
  static const String environmentName = 'Riverstone Demo District (Sugar Land)';

  /// Near University Boulevard / Riverstone community core (77479).
  static const GeoPoint startLocation = GeoPoint(
    latitude: 29.54847,
    longitude: -95.58381,
  );

  static const List<DemoDestination> destinations = [
    DemoDestination(
      id: 'demo-dest-club',
      name: 'Riverstone Clubhouse',
      location: GeoPoint(latitude: 29.55210, longitude: -95.58090),
    ),
    DemoDestination(
      id: 'demo-dest-shops',
      name: 'University Blvd Shops',
      location: GeoPoint(latitude: 29.55171, longitude: -95.58646),
    ),
    DemoDestination(
      id: 'demo-dest-park',
      name: 'Riverstone Neighborhood Park',
      location: GeoPoint(latitude: 29.54580, longitude: -95.57950),
    ),
    DemoDestination(
      id: 'demo-dest-sugar-land',
      name: 'Sugar Land Town Square',
      location: GeoPoint(latitude: 29.59800, longitude: -95.62250),
    ),
    DemoDestination(
      id: 'demo-dest-crossing',
      name: 'Riverstone Crossing',
      location: GeoPoint(latitude: 29.55620, longitude: -95.57540),
    ),
  ];

  static List<Hazard> hazards({DateTime? now}) {
    final clock = now ?? DateTime.now().toUtc();
    return [
      Hazard(
        id: 'demo-hazard-blocked-sidewalk',
        category: HazardCategory.blockedSidewalk,
        severity: HazardSeverity.high,
        status: HazardStatus.active,
        location: const GeoPoint(latitude: 29.54960, longitude: -95.58240),
        confidenceScore: 0.82,
        createdAt: clock.subtract(const Duration(hours: 6)),
        updatedAt: clock.subtract(const Duration(hours: 1)),
        lastConfirmedAt: clock.subtract(const Duration(hours: 1)),
        description:
            '[DEMO] Construction barriers blocking a sidewalk near University Blvd. '
            'Not a verified real-world report.',
        isDemonstration: true,
      ),
      Hazard(
        id: 'demo-hazard-stairs',
        category: HazardCategory.stairsOrInaccessiblePath,
        severity: HazardSeverity.critical,
        status: HazardStatus.active,
        location: const GeoPoint(latitude: 29.55040, longitude: -95.58120),
        confidenceScore: 0.9,
        createdAt: clock.subtract(const Duration(days: 2)),
        updatedAt: clock.subtract(const Duration(hours: 3)),
        lastConfirmedAt: clock.subtract(const Duration(hours: 3)),
        description:
            '[DEMO] Stair-only connector on a pedestrian path with no ramp. '
            'Not a verified real-world report.',
        isDemonstration: true,
      ),
      Hazard(
        id: 'demo-hazard-curb-ramp',
        category: HazardCategory.missingOrDamagedCurbRamp,
        severity: HazardSeverity.high,
        status: HazardStatus.provisional,
        location: const GeoPoint(latitude: 29.54720, longitude: -95.58510),
        confidenceScore: 0.45,
        createdAt: clock.subtract(const Duration(hours: 4)),
        updatedAt: clock.subtract(const Duration(hours: 4)),
        description:
            '[DEMO] Reported missing curb ramp at a crosswalk in Riverstone. '
            'Provisionally reported — not independently confirmed.',
        isDemonstration: true,
      ),
      Hazard(
        id: 'demo-hazard-elevator',
        category: HazardCategory.brokenElevator,
        severity: HazardSeverity.critical,
        status: HazardStatus.active,
        location: const GeoPoint(latitude: 29.55120, longitude: -95.58720),
        confidenceScore: 0.78,
        createdAt: clock.subtract(const Duration(hours: 12)),
        updatedAt: clock.subtract(const Duration(minutes: 40)),
        lastConfirmedAt: clock.subtract(const Duration(minutes: 40)),
        description:
            '[DEMO] Elevator at Demo University Blvd Shops out of service. '
            'Not a verified real-world report.',
        isDemonstration: true,
      ),
      Hazard(
        id: 'demo-hazard-lighting',
        category: HazardCategory.poorLighting,
        severity: HazardSeverity.moderate,
        status: HazardStatus.provisional,
        location: const GeoPoint(latitude: 29.54650, longitude: -95.58180),
        confidenceScore: 0.4,
        createdAt: clock.subtract(const Duration(days: 1)),
        updatedAt: clock.subtract(const Duration(days: 1)),
        description:
            '[DEMO] Poorly lit trail segment after dusk near the park path. '
            'Demonstration data only.',
        isDemonstration: true,
      ),
      Hazard(
        id: 'demo-hazard-pothole',
        category: HazardCategory.potholeOrDamagedPavement,
        severity: HazardSeverity.moderate,
        status: HazardStatus.stale,
        location: const GeoPoint(latitude: 29.54910, longitude: -95.57890),
        confidenceScore: 0.3,
        createdAt: clock.subtract(const Duration(days: 21)),
        updatedAt: clock.subtract(const Duration(days: 14)),
        lastConfirmedAt: clock.subtract(const Duration(days: 14)),
        description:
            '[DEMO] Older pavement damage awaiting re-verification. '
            'Stale demonstration data — not treated as confirmed.',
        isDemonstration: true,
      ),
      ..._sugarLandPlaces(clock),
    ];
  }

  /// Community-style demonstration pins around University Blvd, Telfair, and
  /// Highway 6. Coordinates come from OpenStreetMap where a feature was found.
  /// Pins marked approximate were placed on the named corridor when OSM had
  /// no exact place. None of these are verified inspections.
  static List<Hazard> _sugarLandPlaces(DateTime clock) {
    Hazard place({
      required String id,
      required HazardCategory category,
      required HazardSeverity severity,
      required HazardStatus status,
      required double latitude,
      required double longitude,
      required double confidence,
      required String description,
    }) {
      return Hazard(
        id: id,
        category: category,
        severity: severity,
        status: status,
        location: GeoPoint(latitude: latitude, longitude: longitude),
        confidenceScore: confidence,
        createdAt: clock.subtract(const Duration(days: 3)),
        updatedAt: clock.subtract(const Duration(hours: 6)),
        lastConfirmedAt: status == HazardStatus.active
            ? clock.subtract(const Duration(hours: 6))
            : null,
        description: description,
        isDemonstration: true,
      );
    }

    return [
      place(
        id: 'demo-hazard-shops-telfair',
        category: HazardCategory.blockedSidewalk,
        severity: HazardSeverity.high,
        status: HazardStatus.active,
        latitude: 29.5955017,
        longitude: -95.6489237,
        confidence: 0.72,
        description:
            '[DEMO] Community-style report at The Shops at Telfair, '
            '12920 University Blvd. The parking-lot crossing is unclear, and '
            'outdoor seating or signage may obstruct the pedestrian path. '
            'Not a verified inspection.',
      ),
      place(
        id: 'demo-hazard-univ-commonwealth',
        category: HazardCategory.pedestrianSignalProblem,
        severity: HazardSeverity.critical,
        status: HazardStatus.active,
        latitude: 29.5591462,
        longitude: -95.6398278,
        confidence: 0.7,
        description:
            '[DEMO] Community-style report at University Blvd and Commonwealth '
            'Blvd. The crosswalk is long and difficult for visually impaired '
            'pedestrians. Not a verified inspection.',
      ),
      place(
        id: 'demo-hazard-univ-new-territory',
        category: HazardCategory.pedestrianSignalProblem,
        severity: HazardSeverity.high,
        status: HazardStatus.active,
        latitude: 29.5940148,
        longitude: -95.6486578,
        confidence: 0.66,
        description:
            '[DEMO] Community-style report at University Blvd and New Territory '
            'Blvd. The intersection is wide and pedestrian guidance is limited. '
            'Not a verified inspection.',
      ),
      place(
        id: 'demo-hazard-telfair-central-park',
        category: HazardCategory.stairsOrInaccessiblePath,
        severity: HazardSeverity.high,
        status: HazardStatus.provisional,
        latitude: 29.59240,
        longitude: -95.65320,
        confidence: 0.5,
        description:
            '[DEMO] Community-style report near Telfair Central Park. A trail '
            'split is hard to follow and may hide an obstacle. Approximate pin '
            'near Telfair Central. Not a verified inspection.',
      ),
      place(
        id: 'demo-hazard-telfair-lake-bridge',
        category: HazardCategory.stairsOrInaccessiblePath,
        severity: HazardSeverity.critical,
        status: HazardStatus.active,
        latitude: 29.58920,
        longitude: -95.65560,
        confidence: 0.55,
        description:
            '[DEMO] Community-style report for the Telfair Lake trail bridge. '
            'Sharp turns, water nearby, and limited tactile guidance. Approximate '
            'pin in central Telfair. Not a verified inspection.',
      ),
      place(
        id: 'demo-hazard-crossing-telfair',
        category: HazardCategory.pedestrianSignalProblem,
        severity: HazardSeverity.high,
        status: HazardStatus.active,
        latitude: 29.60380,
        longitude: -95.64740,
        confidence: 0.64,
        description:
            '[DEMO] Community-style report for the Crossing at Telfair near '
            'Highway 6. A large parking lot has several vehicle conflict points '
            'and weak pedestrian wayfinding. Not a verified inspection.',
      ),
      place(
        id: 'demo-hazard-university-commons',
        category: HazardCategory.blockedSidewalk,
        severity: HazardSeverity.moderate,
        status: HazardStatus.provisional,
        latitude: 29.5522335,
        longitude: -95.6190438,
        confidence: 0.48,
        description:
            '[DEMO] Community-style report along University Commons. Driveways '
            'cross the sidewalk and pedestrian-vehicle interactions are busy. '
            'Approximate pin on University Blvd. Not a verified inspection.',
      ),
      place(
        id: 'demo-hazard-univ-bus-stop',
        category: HazardCategory.blockedSidewalk,
        severity: HazardSeverity.critical,
        status: HazardStatus.provisional,
        latitude: 29.5539660,
        longitude: -95.6210913,
        confidence: 0.5,
        description:
            '[DEMO] Community-style report for a bus stop on University Blvd. '
            'The sidewalk connection is missing and the access path is grass or '
            'mud. Approximate stop pin. Not a verified inspection.',
      ),
      place(
        id: 'demo-hazard-heb-riverstone',
        category: HazardCategory.blockedSidewalk,
        severity: HazardSeverity.high,
        status: HazardStatus.provisional,
        latitude: 29.5785263,
        longitude: -95.5826764,
        confidence: 0.6,
        description:
            '[DEMO] Community-style report at the Riverstone H-E-B near '
            'University Blvd. Shopping carts and parking-lot traffic make the '
            'pedestrian path harder to follow. Not a verified inspection.',
      ),
      place(
        id: 'demo-hazard-costco',
        category: HazardCategory.other,
        severity: HazardSeverity.critical,
        status: HazardStatus.active,
        latitude: 29.5854859,
        longitude: -95.6434803,
        confidence: 0.62,
        description:
            '[DEMO] Community-style report at the Sugar Land Costco on Southwest '
            'Freeway. The parking lot is very large and wayfinding on foot is '
            'difficult. Not a verified inspection.',
      ),
      place(
        id: 'demo-hazard-town-square',
        category: HazardCategory.blockedSidewalk,
        severity: HazardSeverity.high,
        status: HazardStatus.provisional,
        latitude: 29.5958438,
        longitude: -95.6222566,
        confidence: 0.58,
        description:
            '[DEMO] Community-style report at Sugar Land Town Square. Sidewalks '
            'get crowded and outdoor dining can block the walking path. '
            'Not a verified inspection.',
      ),
    ];
  }
}

class DemoDestination {
  const DemoDestination({
    required this.id,
    required this.name,
    required this.location,
  });

  final String id;
  final String name;
  final GeoPoint location;
}
