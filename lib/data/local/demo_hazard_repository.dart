import 'dart:async';
import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../models/geo_point.dart';
import '../models/hazard.dart';
import '../models/hazard_confirmation.dart';
import '../repositories/hazard_repository.dart';
import '../verification/passage_consensus.dart';
import 'demo_data.dart';
import 'local_hazard_store.dart';

/// In-memory hazard store used only in demonstration mode.
///
/// Seeded demo hazards plus user-created reports persist locally when a
/// [LocalHazardStore] is provided. All records remain labeled as demonstration.
class DemoHazardRepository implements HazardRepository {
  DemoHazardRepository({
    List<Hazard>? seed,
    LocalHazardStore? store,
  })  : _store = store,
        _hazards = List<Hazard>.from(seed ?? const []) {
    if (seed == null) {
      _hazards.addAll(DemoData.hazards());
      final persisted = store?.load() ?? const <Hazard>[];
      for (final hazard in persisted) {
        if (_hazards.every((existing) => existing.id != hazard.id)) {
          _hazards.add(hazard);
        }
      }
    }
    _protectedIds.addAll(_hazards.map((hazard) => hazard.id));
  }

  final LocalHazardStore? _store;
  final List<Hazard> _hazards;
  final List<HazardConfirmation> _confirmations = [];
  final List<_Passage> _passages = [];
  final Set<String> _protectedIds = {};
  final _controller = StreamController<List<Hazard>>.broadcast();
  final _uuid = const Uuid();

  List<Hazard> get all => List.unmodifiable(_hazards);

  List<HazardConfirmation> confirmationsFor(String hazardId) {
    return _confirmations
        .where((c) => c.hazardId == hazardId)
        .toList(growable: false);
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(List.unmodifiable(_hazards));
    }
  }

  Future<void> _persist() async {
    await _store?.save(_hazards);
  }

  double _distanceMeters(GeoPoint a, GeoPoint b) {
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

  @override
  Future<List<Hazard>> getNearbyHazards({
    required GeoPoint center,
    required double radiusMeters,
  }) async {
    return _hazards
        .where((h) => _distanceMeters(center, h.location) <= radiusMeters)
        .toList(growable: false);
  }

  @override
  Future<Hazard?> getById(String id) async {
    for (final hazard in _hazards) {
      if (hazard.id == id) {
        return hazard;
      }
    }
    return null;
  }

  @override
  Future<Hazard> create(Hazard hazard) async {
    final now = DateTime.now().toUtc();
    final withId = Hazard(
      id: hazard.id.isEmpty ? _uuid.v4() : hazard.id,
      category: hazard.category,
      severity: hazard.severity,
      status: hazard.status,
      location: hazard.location,
      confidenceScore: hazard.confidenceScore,
      createdAt: hazard.createdAt,
      updatedAt: now,
      description: hazard.description,
      lastConfirmedAt: hazard.lastConfirmedAt,
      expiresAt: hazard.expiresAt,
      resolvedAt: hazard.resolvedAt,
      createdBy: hazard.createdBy ?? 'local-reporter',
      photoPath: hazard.photoPath,
      isDemonstration: true,
    );
    _hazards.add(withId);
    _passages.add(
      _Passage(
        hazardId: withId.id,
        userId: withId.createdBy!,
        at: now,
      ),
    );
    final agreed = _withConsensus(withId);
    await _persist();
    _emit();
    return agreed;
  }

  @override
  Future<Hazard> update(Hazard hazard) async {
    final index = _hazards.indexWhere((h) => h.id == hazard.id);
    if (index < 0) {
      throw StateError('Hazard ${hazard.id} not found in demonstration store');
    }
    final updated = hazard.copyWith(
      updatedAt: DateTime.now().toUtc(),
      isDemonstration: true,
    );
    _hazards[index] = updated;
    await _persist();
    _emit();
    return updated;
  }

  @override
  Future<Hazard> confirm({
    required String hazardId,
    required ConfirmationResponse response,
    EvidenceType? evidenceType,
    String? userId,
  }) async {
    final hazard = await getById(hazardId);
    if (hazard == null) {
      throw StateError('Hazard $hazardId not found');
    }

    final uid = userId;
    if (uid != null) {
      final recent = _confirmations.any(
        (c) =>
            c.hazardId == hazardId &&
            c.userId == uid &&
            DateTime.now().toUtc().difference(c.createdAt) <
                const Duration(hours: 24),
      );
      if (recent) {
        throw StateError(
          'This account already submitted a confirmation for this report '
          'within the last 24 hours.',
        );
      }
    }

    final confirmation = HazardConfirmation(
      id: _uuid.v4(),
      hazardId: hazardId,
      response: response,
      createdAt: DateTime.now().toUtc(),
      userId: uid,
      evidenceType: evidenceType,
    );
    _confirmations.add(confirmation);

    final now = DateTime.now().toUtc();
    Hazard updated;
    switch (response) {
      case ConfirmationResponse.stillPresent:
        updated = hazard.copyWith(
          status: HazardStatus.active,
          confidenceScore: (hazard.confidenceScore + 0.1).clamp(0, 1),
          lastConfirmedAt: now,
          updatedAt: now,
        );
      case ConfirmationResponse.resolved:
        updated = hazard.copyWith(
          status: HazardStatus.underReview,
          confidenceScore: (hazard.confidenceScore - 0.15).clamp(0, 1),
          updatedAt: now,
        );
      case ConfirmationResponse.unableToDetermine:
        updated = hazard.copyWith(updatedAt: now);
    }

    return update(updated);
  }

  @override
  Future<Hazard?> recordPassage({
    required String hazardId,
    String? userId,
  }) async {
    final hazard = await getById(hazardId);
    if (hazard == null || userId == null || userId.isEmpty) return null;
    // Seeded demonstration pins stay as authored. Resolved reports are closed.
    if (hazard.isDemonstration ||
        hazard.status == HazardStatus.resolved ||
        _protectedIds.contains(hazard.id)) {
      return null;
    }

    final now = DateTime.now().toUtc();
    final alreadyToday = _passages.any(
      (passage) =>
          passage.hazardId == hazardId &&
          passage.userId == userId &&
          now.difference(passage.at) < const Duration(days: 1),
    );
    if (!alreadyToday) {
      _passages.add(
        _Passage(hazardId: hazardId, userId: userId, at: now),
      );
    }
    final agreed = _withConsensus(hazard);
    await _persist();
    _emit();
    return agreed;
  }

  /// Applies the 25% rule. Seeded demonstration hazards are left unchanged.
  Hazard _withConsensus(Hazard hazard) {
    if (_protectedIds.contains(hazard.id)) return hazard;

    final cutoff = DateTime.now().toUtc().subtract(PassageConsensus.window);
    final passerIds = _passages
        .where(
          (passage) =>
              passage.hazardId == hazard.id && !passage.at.isBefore(cutoff),
        )
        .map((passage) => passage.userId)
        .toSet();
    final reporterIds = <String>{
      if (hazard.createdBy != null && hazard.createdBy!.isNotEmpty)
        hazard.createdBy!,
      ..._confirmations
          .where(
            (confirmation) =>
                confirmation.hazardId == hazard.id &&
                confirmation.response == ConfirmationResponse.stillPresent &&
                confirmation.userId != null &&
                confirmation.userId!.isNotEmpty,
          )
          .map((confirmation) => confirmation.userId!),
    };
    final removerIds = _confirmations
        .where(
          (confirmation) =>
              confirmation.hazardId == hazard.id &&
              confirmation.response == ConfirmationResponse.resolved &&
              confirmation.userId != null &&
              confirmation.userId!.isNotEmpty,
        )
        .map((confirmation) => confirmation.userId!)
        .toSet();

    final decision = PassageConsensus.decide(
      passerIds: passerIds,
      reporterIds: reporterIds,
      removerIds: removerIds,
    );
    final now = DateTime.now().toUtc();
    final agreed = hazard.copyWith(
      status: decision.status,
      confidenceScore: decision.status == HazardStatus.resolved
          ? decision.removalShare
          : decision.reportShare,
      passerCount: decision.passerCount,
      reporterCount: decision.reporterCount,
      removerCount: decision.removerCount,
      updatedAt: now,
      lastConfirmedAt: decision.status == HazardStatus.active
          ? now
          : hazard.lastConfirmedAt,
      resolvedAt: decision.status == HazardStatus.resolved
          ? (hazard.resolvedAt ?? now)
          : null,
      clearResolvedAt: decision.status != HazardStatus.resolved,
    );
    final index = _hazards.indexWhere((existing) => existing.id == hazard.id);
    if (index >= 0) _hazards[index] = agreed;
    return agreed;
  }

  @override
  Stream<List<Hazard>> watchNearbyHazards({
    required GeoPoint center,
    required double radiusMeters,
  }) async* {
    yield await getNearbyHazards(center: center, radiusMeters: radiusMeters);
    await for (final _ in _controller.stream) {
      yield await getNearbyHazards(center: center, radiusMeters: radiusMeters);
    }
  }

  void dispose() {
    _controller.close();
  }
}

class _Passage {
  const _Passage({
    required this.hazardId,
    required this.userId,
    required this.at,
  });

  final String hazardId;
  final String userId;
  final DateTime at;
}
