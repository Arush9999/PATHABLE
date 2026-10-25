import '../models/geo_point.dart';
import '../models/hazard.dart';
import '../models/hazard_confirmation.dart';

/// Abstraction over hazard persistence so the UI is not coupled to Supabase.
abstract class HazardRepository {
  Future<List<Hazard>> getNearbyHazards({
    required GeoPoint center,
    required double radiusMeters,
  });

  Future<Hazard?> getById(String id);

  Future<Hazard> create(Hazard hazard);

  Future<Hazard> update(Hazard hazard);

  Future<Hazard> confirm({
    required String hazardId,
    required ConfirmationResponse response,
    EvidenceType? evidenceType,
    String? userId,
  });

  /// Counts the signed-in person as having passed [hazardId] once per day.
  ///
  /// Returns the hazard after the 25% agreement rule runs, or null when the
  /// passage was skipped (signed out, demonstration pin, or already removed).
  Future<Hazard?> recordPassage({required String hazardId, String? userId});

  Stream<List<Hazard>> watchNearbyHazards({
    required GeoPoint center,
    required double radiusMeters,
  });
}
