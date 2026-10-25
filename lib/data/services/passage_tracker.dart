import 'package:flutter/foundation.dart';

import '../../core/geo/geo_math.dart';
import '../models/geo_point.dart';
import '../models/hazard.dart';
import '../repositories/hazard_repository.dart';
import '../verification/passage_consensus.dart';

/// Records that the signed-in person passed a live report.
///
/// One passage per hazard per app session. The server also keeps a person
/// from counting more than once per day. Demonstration pins are skipped.
class PassageTracker {
  PassageTracker({required this.repository});

  final HazardRepository repository;
  final Set<String> _recorded = {};
  GeoPoint? _lastFetchAt;
  DateTime? _lastFetchTime;
  List<Hazard> _nearby = const [];

  Future<bool> onFix(GeoPoint point) async {
    try {
      final now = DateTime.now().toUtc();
      final moved = _lastFetchAt == null ||
          distanceMeters(_lastFetchAt!, point) >= 25;
      final stale = _lastFetchTime == null ||
          now.difference(_lastFetchTime!) > const Duration(seconds: 20);
      if (moved || stale) {
        _nearby = await repository.getNearbyHazards(
          center: point,
          radiusMeters: 80,
        );
        _lastFetchAt = point;
        _lastFetchTime = now;
      }

      var changed = false;
      for (final hazard in _nearby) {
        if (hazard.isDemonstration || hazard.status == HazardStatus.resolved) {
          continue;
        }
        if (distanceMeters(point, hazard.location) >
            PassageConsensus.passageRadiusMeters) {
          continue;
        }
        if (!_recorded.add(hazard.id)) continue;
        try {
          final updated = await repository.recordPassage(hazardId: hazard.id);
          if (updated != null && updated.status != hazard.status) {
            changed = true;
          }
        } catch (error) {
          _recorded.remove(hazard.id);
          debugPrint('Passage was not recorded for ${hazard.id}: $error');
        }
      }
      return changed;
    } catch (error) {
      debugPrint('Passage check skipped: $error');
      return false;
    }
  }
}
