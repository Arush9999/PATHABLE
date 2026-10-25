import 'package:equatable/equatable.dart';

import '../data/models/geo_point.dart';
import '../data/models/hazard.dart';

enum TravelMode {
  pedestrian,
  cycling;

  String get label => switch (this) {
        TravelMode.pedestrian => 'Walking',
        TravelMode.cycling => 'Cycling',
      };
}

enum RouteLabel {
  fastest,
  accessibilityPrioritized,
  preferencePrioritized,
  onlyAvailable;

  String get displayName => switch (this) {
        RouteLabel.fastest => 'Fastest',
        RouteLabel.accessibilityPrioritized => 'Accessibility-prioritized',
        RouteLabel.preferencePrioritized => 'Preference-prioritized',
        RouteLabel.onlyAvailable => 'Available route',
      };
}

class RouteManeuver extends Equatable {
  const RouteManeuver({
    required this.instruction,
    required this.distanceMeters,
    this.location,
  });

  final String instruction;
  final double distanceMeters;
  final GeoPoint? location;

  @override
  List<Object?> get props => [instruction, distanceMeters, location];
}

class RouteHazardHit extends Equatable {
  const RouteHazardHit({
    required this.hazard,
    required this.distanceAlongRouteMeters,
    required this.offsetMeters,
    required this.isHardExclusion,
    required this.penalty,
  });

  final Hazard hazard;
  final double distanceAlongRouteMeters;
  final double offsetMeters;
  final bool isHardExclusion;
  final double penalty;

  @override
  List<Object?> get props =>
      [hazard, distanceAlongRouteMeters, offsetMeters, isHardExclusion, penalty];
}

class ScoredRoute extends Equatable {
  const ScoredRoute({
    required this.id,
    required this.geometry,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.maneuvers,
    required this.score,
    required this.label,
    required this.hazardHits,
    required this.explanations,
    required this.isDemonstration,
    this.excluded = false,
    this.exclusionReason,
  });

  final String id;
  final List<GeoPoint> geometry;
  final double distanceMeters;
  final double durationSeconds;
  final List<RouteManeuver> maneuvers;
  final double score;
  final RouteLabel label;
  final List<RouteHazardHit> hazardHits;
  final List<String> explanations;
  final bool isDemonstration;
  final bool excluded;
  final String? exclusionReason;

  @override
  List<Object?> get props => [
        id,
        geometry,
        distanceMeters,
        durationSeconds,
        maneuvers,
        score,
        label,
        hazardHits,
        explanations,
        isDemonstration,
        excluded,
        exclusionReason,
      ];
}

class RoutingRequest extends Equatable {
  const RoutingRequest({
    required this.origin,
    required this.destination,
    required this.mode,
    required this.preferences,
    this.alternatives = 3,
  });

  final GeoPoint origin;
  final GeoPoint destination;
  final TravelMode mode;
  final AccessibilityRoutingPreferences preferences;
  final int alternatives;

  @override
  List<Object?> get props =>
      [origin, destination, mode, preferences, alternatives];
}

/// Preferences that influence hard exclusions and soft penalties.
class AccessibilityRoutingPreferences extends Equatable {
  const AccessibilityRoutingPreferences({
    this.avoidStairs = false,
    this.avoidMissingCurbRamps = false,
    this.avoidImpassableClosures = true,
    this.warnPoorLighting = false,
    this.warnExcessiveNoise = false,
    this.preferWellLit = false,
    this.spokenInstructions = false,
    this.wheelchairMode = false,
    this.lowVisionMode = false,
    this.blindMode = false,
    this.cyclistMode = false,
  });

  final bool avoidStairs;
  final bool avoidMissingCurbRamps;
  final bool avoidImpassableClosures;
  final bool warnPoorLighting;
  final bool warnExcessiveNoise;
  final bool preferWellLit;
  final bool spokenInstructions;
  final bool wheelchairMode;
  final bool lowVisionMode;

  /// Voice-only screen. Every other profile still shows the map.
  final bool blindMode;
  final bool cyclistMode;

  AccessibilityRoutingPreferences copyWith({
    bool? avoidStairs,
    bool? avoidMissingCurbRamps,
    bool? avoidImpassableClosures,
    bool? warnPoorLighting,
    bool? warnExcessiveNoise,
    bool? preferWellLit,
    bool? spokenInstructions,
    bool? wheelchairMode,
    bool? lowVisionMode,
    bool? blindMode,
    bool? cyclistMode,
  }) {
    return AccessibilityRoutingPreferences(
      avoidStairs: avoidStairs ?? this.avoidStairs,
      avoidMissingCurbRamps:
          avoidMissingCurbRamps ?? this.avoidMissingCurbRamps,
      avoidImpassableClosures:
          avoidImpassableClosures ?? this.avoidImpassableClosures,
      warnPoorLighting: warnPoorLighting ?? this.warnPoorLighting,
      warnExcessiveNoise: warnExcessiveNoise ?? this.warnExcessiveNoise,
      preferWellLit: preferWellLit ?? this.preferWellLit,
      spokenInstructions: spokenInstructions ?? this.spokenInstructions,
      wheelchairMode: wheelchairMode ?? this.wheelchairMode,
      lowVisionMode: lowVisionMode ?? this.lowVisionMode,
      blindMode: blindMode ?? this.blindMode,
      cyclistMode: cyclistMode ?? this.cyclistMode,
    );
  }

  @override
  List<Object?> get props => [
        avoidStairs,
        avoidMissingCurbRamps,
        avoidImpassableClosures,
        warnPoorLighting,
        warnExcessiveNoise,
        preferWellLit,
        spokenInstructions,
        wheelchairMode,
        lowVisionMode,
        blindMode,
        cyclistMode,
      ];
}

class RoutingResult extends Equatable {
  const RoutingResult({
    required this.routes,
    required this.isDemonstration,
    this.limitations = const [],
  });

  final List<ScoredRoute> routes;
  final bool isDemonstration;
  final List<String> limitations;

  @override
  List<Object?> get props => [routes, isDemonstration, limitations];
}
