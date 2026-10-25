import 'package:equatable/equatable.dart';

import 'geo_point.dart';

/// Reportable pedestrian infrastructure problem categories.
enum HazardCategory {
  blockedSidewalk,
  potholeOrDamagedPavement,
  missingOrDamagedCurbRamp,
  stairsOrInaccessiblePath,
  brokenElevator,
  constructionClosure,
  poorLighting,
  excessiveNoise,
  pedestrianSignalProblem,
  other;

  String get label => switch (this) {
        HazardCategory.blockedSidewalk => 'Blocked sidewalk',
        HazardCategory.potholeOrDamagedPavement =>
          'Pothole or damaged pavement',
        HazardCategory.missingOrDamagedCurbRamp =>
          'Missing or damaged curb ramp',
        HazardCategory.stairsOrInaccessiblePath =>
          'Stairs or inaccessible path',
        HazardCategory.brokenElevator => 'Broken elevator',
        HazardCategory.constructionClosure => 'Construction closure',
        HazardCategory.poorLighting => 'Poor lighting',
        HazardCategory.excessiveNoise => 'Excessive noise',
        HazardCategory.pedestrianSignalProblem => 'Pedestrian signal problem',
        HazardCategory.other => 'Other hazard',
      };

  String get shortLabel => switch (this) {
        HazardCategory.blockedSidewalk => 'Blocked sidewalk',
        HazardCategory.potholeOrDamagedPavement => 'Damaged pavement',
        HazardCategory.missingOrDamagedCurbRamp => 'Curb ramp',
        HazardCategory.stairsOrInaccessiblePath => 'Stairs / inaccessible',
        HazardCategory.brokenElevator => 'Elevator',
        HazardCategory.constructionClosure => 'Construction',
        HazardCategory.poorLighting => 'Poor lighting',
        HazardCategory.excessiveNoise => 'Noise',
        HazardCategory.pedestrianSignalProblem => 'Signal problem',
        HazardCategory.other => 'Other',
      };
}

enum HazardSeverity {
  low,
  moderate,
  high,
  critical;

  String get label => switch (this) {
        HazardSeverity.low => 'Low',
        HazardSeverity.moderate => 'Moderate',
        HazardSeverity.high => 'High',
        HazardSeverity.critical => 'Critical',
      };
}

/// Verification / lifecycle status. Unresolved reports are not confirmed facts.
enum HazardStatus {
  provisional,
  active,
  resolved,
  stale,
  underReview;

  String get label => switch (this) {
        HazardStatus.provisional => 'Provisionally reported',
        HazardStatus.active => 'Added to routes',
        HazardStatus.resolved => 'Removed',
        HazardStatus.stale => 'Stale / awaiting verification',
        HazardStatus.underReview => 'Under review',
      };

  /// Whether the hazard should influence routing as a live obstacle.
  ///
  /// Only problems that reached the 25% passer agreement are added.
  bool get affectsRouting => this == HazardStatus.active;
}

/// A community-reported pedestrian infrastructure hazard.
class Hazard extends Equatable {
  const Hazard({
    required this.id,
    required this.category,
    required this.severity,
    required this.status,
    required this.location,
    required this.confidenceScore,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.lastConfirmedAt,
    this.expiresAt,
    this.resolvedAt,
    this.createdBy,
    this.photoPath,
    this.isDemonstration = false,
    this.passerCount = 0,
    this.reporterCount = 0,
    this.removerCount = 0,
  });

  final String id;
  final HazardCategory category;
  final HazardSeverity severity;
  final HazardStatus status;
  final GeoPoint location;
  final double confidenceScore;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? description;
  final DateTime? lastConfirmedAt;
  final DateTime? expiresAt;
  final DateTime? resolvedAt;
  final String? createdBy;
  final String? photoPath;

  /// When true, this record is fictional demonstration data — not a real report.
  final bool isDemonstration;

  /// Distinct people who passed this spot in the agreement window.
  final int passerCount;

  /// Distinct people who reported the problem or confirmed it is still there.
  final int reporterCount;

  /// Distinct people who said the problem is gone.
  final int removerCount;

  /// Plain-language 25% add/remove progress.
  String get agreementSummary {
    if (passerCount <= 0) {
      return 'Added when at least 25% of people who pass report it. '
          'Removed when at least 25% say it is gone.';
    }
    final reportPct = (reporterCount * 100 / passerCount).round();
    final removalPct = (removerCount * 100 / passerCount).round();
    return '$reporterCount of $passerCount people who passed reported this '
        '($reportPct%). $removerCount of $passerCount said it is gone '
        '($removalPct%). A problem is added or removed at 25%.';
  }

  String get accessibilityLabel {
    final demoPrefix = isDemonstration ? 'Demonstration data. ' : '';
    final desc = description == null || description!.isEmpty
        ? ''
        : ' Description: $description.';
    return '$demoPrefix${category.label}. Status: ${status.label}. '
        'Severity: ${severity.label}.$desc';
  }

  Hazard copyWith({
    HazardCategory? category,
    HazardSeverity? severity,
    HazardStatus? status,
    GeoPoint? location,
    double? confidenceScore,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? description,
    DateTime? lastConfirmedAt,
    DateTime? expiresAt,
    DateTime? resolvedAt,
    String? createdBy,
    String? photoPath,
    bool? isDemonstration,
    int? passerCount,
    int? reporterCount,
    int? removerCount,
    bool clearResolvedAt = false,
  }) {
    return Hazard(
      id: id,
      category: category ?? this.category,
      severity: severity ?? this.severity,
      status: status ?? this.status,
      location: location ?? this.location,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      description: description ?? this.description,
      lastConfirmedAt: lastConfirmedAt ?? this.lastConfirmedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      createdBy: createdBy ?? this.createdBy,
      photoPath: photoPath ?? this.photoPath,
      isDemonstration: isDemonstration ?? this.isDemonstration,
      passerCount: passerCount ?? this.passerCount,
      reporterCount: reporterCount ?? this.reporterCount,
      removerCount: removerCount ?? this.removerCount,
      resolvedAt: clearResolvedAt ? null : (resolvedAt ?? this.resolvedAt),
    );
  }

  @override
  List<Object?> get props => [
        id,
        category,
        severity,
        status,
        location,
        confidenceScore,
        createdAt,
        updatedAt,
        description,
        lastConfirmedAt,
        expiresAt,
        resolvedAt,
        createdBy,
        photoPath,
        isDemonstration,
        passerCount,
        reporterCount,
        removerCount,
      ];
}
