import '../data/models/geo_point.dart';
import '../data/models/hazard.dart';
import 'hazard_route_filter.dart';
import 'routing_models.dart';

class CandidateRoute {
  const CandidateRoute({
    required this.id,
    required this.geometry,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.maneuvers,
  });

  final String id;
  final List<GeoPoint> geometry;
  final double distanceMeters;
  final double durationSeconds;
  final List<RouteManeuver> maneuvers;
}

/// Ranks candidate routes using travel cost + hazard penalties/exclusions.
class RouteScorer {
  RouteScorer({
    this.filter = const HazardRouteFilter(),
    this.timeWeight = 1.0,
    this.distanceWeight = 0.15,
  });

  final HazardRouteFilter filter;
  final double timeWeight;
  final double distanceWeight;

  RoutingResult score({
    required List<CandidateRoute> candidates,
    required List<Hazard> hazards,
    required AccessibilityRoutingPreferences preferences,
    required bool isDemonstration,
  }) {
    if (candidates.isEmpty) {
      return RoutingResult(
        routes: const [],
        isDemonstration: isDemonstration,
        limitations: const [
          'No candidate routes were returned by the routing engine.',
        ],
      );
    }

    final scored = <ScoredRoute>[];
    for (final candidate in candidates) {
      final hits = filter.matchHazards(
        geometry: candidate.geometry,
        hazards: hazards,
        preferences: preferences,
      );

      final hardHits = hits.where((h) => h.isHardExclusion).toList();
      final softPenalty = hits
          .where((h) => !h.isHardExclusion)
          .fold<double>(0, (s, h) => s + h.penalty);

      final base = candidate.durationSeconds * timeWeight +
          candidate.distanceMeters * distanceWeight;
      final score = base + softPenalty + (hardHits.isEmpty ? 0 : 1e6);

      final explanations = <String>[
        'Travel time about ${_formatMinutes(candidate.durationSeconds)}.',
        'Distance about ${_formatMiles(candidate.distanceMeters)}.',
      ];

      for (final hit in hits) {
        final certainty = hit.hazard.status == HazardStatus.active
            ? 'Confirmed active'
            : hit.hazard.status.label;
        explanations.add(
          '$certainty ${hit.hazard.category.shortLabel.toLowerCase()} '
          'about ${hit.distanceAlongRouteMeters.round()} meters along the route '
          '(${hit.offsetMeters.round()} m from the path).',
        );
      }

      if (hardHits.isNotEmpty) {
        explanations.add(
          'Contains a barrier your preferences treat as impassable.',
        );
      }

      if (isDemonstration) {
        explanations.add(
          'Demonstration routing — not a verified real-world route.',
        );
      }

      scored.add(
        ScoredRoute(
          id: candidate.id,
          geometry: candidate.geometry,
          distanceMeters: candidate.distanceMeters,
          durationSeconds: candidate.durationSeconds,
          maneuvers: candidate.maneuvers,
          score: score,
          label: RouteLabel.onlyAvailable,
          hazardHits: hits,
          explanations: explanations,
          isDemonstration: isDemonstration,
          excluded: hardHits.isNotEmpty,
          exclusionReason: hardHits.isEmpty
              ? null
              : hardHits.first.hazard.category.label,
        ),
      );
    }

    scored.sort((a, b) => a.score.compareTo(b.score));

    final usable = scored.where((r) => !r.excluded).toList();
    final limitations = <String>[];
    if (usable.isEmpty) {
      limitations.add(
        'Every available route contains a serious barrier for the selected '
        'preferences. PathAble will not pretend an accessible alternative exists.',
      );
    }

    final labeled = _assignLabels(usable.isEmpty ? scored : usable);
    return RoutingResult(
      routes: labeled.take(3).toList(growable: false),
      isDemonstration: isDemonstration,
      limitations: limitations,
    );
  }

  List<ScoredRoute> _assignLabels(List<ScoredRoute> routes) {
    if (routes.isEmpty) {
      return const [];
    }
    if (routes.length == 1) {
      return [
        _withLabel(routes.first, RouteLabel.onlyAvailable),
      ];
    }

    final byDuration = [...routes]
      ..sort((a, b) => a.durationSeconds.compareTo(b.durationSeconds));
    final byAccess = [...routes]
      ..sort((a, b) {
        final aPen = a.hazardHits.fold<double>(0, (s, h) => s + h.penalty);
        final bPen = b.hazardHits.fold<double>(0, (s, h) => s + h.penalty);
        return aPen.compareTo(bPen);
      });

    final result = <ScoredRoute>[];
    final used = <String>{};

    void add(ScoredRoute route, RouteLabel label) {
      if (used.contains(route.id)) {
        return;
      }
      used.add(route.id);
      result.add(_withLabel(route, label));
    }

    add(byDuration.first, RouteLabel.fastest);
    add(byAccess.first, RouteLabel.accessibilityPrioritized);
    add(routes.first, RouteLabel.preferencePrioritized);
    return result;
  }

  ScoredRoute _withLabel(ScoredRoute route, RouteLabel label) {
    return ScoredRoute(
      id: route.id,
      geometry: route.geometry,
      distanceMeters: route.distanceMeters,
      durationSeconds: route.durationSeconds,
      maneuvers: route.maneuvers,
      score: route.score,
      label: label,
      hazardHits: route.hazardHits,
      explanations: route.explanations,
      isDemonstration: route.isDemonstration,
      excluded: route.excluded,
      exclusionReason: route.exclusionReason,
    );
  }

  static String _formatMinutes(double seconds) {
    final minutes = (seconds / 60).round().clamp(1, 24 * 60);
    if (minutes < 60) return '$minutes minutes';
    final hours = minutes ~/ 60;
    final rem = minutes % 60;
    if (rem == 0) return '$hours hours';
    return '$hours hr $rem min';
  }

  static String _formatMiles(double meters) {
    final miles = meters / 1609.344;
    if (miles < 0.1) {
      return '${(meters * 3.28084).round()} feet';
    }
    return '${miles.toStringAsFixed(miles < 10 ? 1 : 0)} miles';
  }
}
