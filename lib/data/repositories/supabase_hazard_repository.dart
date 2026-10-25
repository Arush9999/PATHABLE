import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/geo_point.dart';
import '../models/hazard.dart';
import '../models/hazard_confirmation.dart';
import '../services/hazard_photo_uploader.dart';
import 'hazard_repository.dart';

/// Production hazard repository backed by Supabase + PostGIS.
class SupabaseHazardRepository implements HazardRepository {
  SupabaseHazardRepository(
    this._client, {
    HazardPhotoUploader? photoUploader,
  }) : _photos = photoUploader ?? HazardPhotoUploader(_client);

  final SupabaseClient _client;
  final HazardPhotoUploader _photos;

  @override
  Future<List<Hazard>> getNearbyHazards({
    required GeoPoint center,
    required double radiusMeters,
  }) async {
    final Object response;
    try {
      response = await _client
          .rpc(
            'nearby_hazards',
            params: {
              'lat': center.latitude,
              'lng': center.longitude,
              'radius_meters': radiusMeters,
            },
          )
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      debugPrint('nearby_hazards timed out');
      return const [];
    }

    final rows = (response as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);

    final hazards = <Hazard>[];
    for (final row in rows) {
      try {
        hazards.add(_fromRow(row));
      } catch (error, stack) {
        debugPrint('Skipping hazard row ${row['id']}: $error\n$stack');
      }
    }
    return hazards;
  }

  @override
  Future<Hazard?> getById(String id) async {
    final Map<String, dynamic>? row;
    try {
      row = await _client
          .from('hazards')
          .select()
          .eq('id', id)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      debugPrint('getById timed out for $id');
      return null;
    }
    if (row == null) {
      return null;
    }
    return _fromRow(row);
  }

  @override
  Future<Hazard> create(Hazard hazard) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Sign in required to submit a hazard report.');
    }
    final photoKey = await _photos.uploadIfLocal(hazard.photoPath);
    final payload = {
      'category': _categoryToDb(hazard.category),
      'severity': hazard.severity.name,
      'status': _statusToDb(hazard.status),
      'description': hazard.description,
      'location':
          'SRID=4326;POINT(${hazard.location.longitude} ${hazard.location.latitude})',
      'confidence_score': hazard.confidenceScore,
      'created_by': userId,
      'photo_path': photoKey,
      'is_demonstration': hazard.isDemonstration,
    };

    final row =
        await _client.from('hazards').insert(payload).select().single();
    return _fromRow(row);
  }

  @override
  Future<Hazard> update(Hazard hazard) async {
    final payload = {
      'category': _categoryToDb(hazard.category),
      'severity': hazard.severity.name,
      'status': _statusToDb(hazard.status),
      'description': hazard.description,
      'confidence_score': hazard.confidenceScore,
      'last_confirmed_at': hazard.lastConfirmedAt?.toIso8601String(),
      'expires_at': hazard.expiresAt?.toIso8601String(),
      'resolved_at': hazard.resolvedAt?.toIso8601String(),
      'photo_path': hazard.photoPath,
    };

    final row = await _client
        .from('hazards')
        .update(payload)
        .eq('id', hazard.id)
        .select()
        .single();
    return _fromRow(row);
  }

  @override
  Future<Hazard> confirm({
    required String hazardId,
    required ConfirmationResponse response,
    EvidenceType? evidenceType,
    String? userId,
  }) async {
    // Optional [userId] is ignored. The database records auth.uid().
    final signedInUserId = _client.auth.currentUser?.id;
    if (signedInUserId == null) {
      throw StateError('Sign in required to confirm a hazard.');
    }
    await _client.from('hazard_confirmations').insert({
      'hazard_id': hazardId,
      'user_id': signedInUserId,
      'response': _responseToDb(response),
      'evidence_type':
          evidenceType == null ? null : _evidenceToDb(evidenceType),
    });

    final row = await _client.rpc(
      'recompute_hazard_verification',
      params: {'target_hazard': hazardId},
    );

    if (row is Map) {
      return _fromRow(Map<String, dynamic>.from(row));
    }
    final refreshed = await getById(hazardId);
    if (refreshed == null) {
      throw StateError('Hazard $hazardId missing after confirmation');
    }
    return refreshed;
  }

  @override
  Future<Hazard?> recordPassage({
    required String hazardId,
    String? userId,
  }) async {
    try {
      final row = await _client.rpc(
        'record_hazard_passage',
        params: {'target_hazard': hazardId},
      );
      final parsed = _hazardFromRpc(row);
      if (parsed != null) return parsed;
      return await getById(hazardId);
    } catch (error, stack) {
      debugPrint(
        'record_hazard_passage unavailable for $hazardId: $error\n$stack',
      );
      try {
        return await getById(hazardId);
      } catch (readError) {
        debugPrint('Could not reload hazard $hazardId: $readError');
        return null;
      }
    }
  }

  Hazard? _hazardFromRpc(Object? row) {
    if (row is Map) {
      return _fromRow(Map<String, dynamic>.from(row));
    }
    if (row is List && row.isNotEmpty && row.first is Map) {
      return _fromRow(Map<String, dynamic>.from(row.first as Map));
    }
    return null;
  }

  @override
  Stream<List<Hazard>> watchNearbyHazards({
    required GeoPoint center,
    required double radiusMeters,
  }) async* {
    yield await getNearbyHazards(center: center, radiusMeters: radiusMeters);
  }

  Hazard _fromRow(Map<String, dynamic> row) {
    final location = GeoPoint.parseLocation(row['location']);
    return Hazard(
      id: row['id'] as String,
      category: _categoryFromDb(row['category'] as String),
      severity: HazardSeverity.values.byName(row['severity'] as String),
      status: _statusFromDb(row['status'] as String),
      location: location,
      confidenceScore: (row['confidence_score'] as num).toDouble(),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      description: row['description'] as String?,
      lastConfirmedAt: _parseDate(row['last_confirmed_at']),
      expiresAt: _parseDate(row['expires_at']),
      resolvedAt: _parseDate(row['resolved_at']),
      createdBy: row['created_by'] as String?,
      photoPath: row['photo_path'] as String?,
      isDemonstration: row['is_demonstration'] as bool? ?? false,
      passerCount: (row['passer_count'] as num?)?.toInt() ?? 0,
      reporterCount: (row['reporter_count'] as num?)?.toInt() ?? 0,
      removerCount: (row['removal_count'] as num?)?.toInt() ??
          (row['remover_count'] as num?)?.toInt() ??
          0,
    );
  }

  DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    return DateTime.parse(value);
  }

  String _categoryToDb(HazardCategory category) {
    return switch (category) {
      HazardCategory.blockedSidewalk => 'blocked_sidewalk',
      HazardCategory.potholeOrDamagedPavement => 'pothole_or_damaged_pavement',
      HazardCategory.missingOrDamagedCurbRamp => 'missing_or_damaged_curb_ramp',
      HazardCategory.stairsOrInaccessiblePath => 'stairs_or_inaccessible_path',
      HazardCategory.brokenElevator => 'broken_elevator',
      HazardCategory.constructionClosure => 'construction_closure',
      HazardCategory.poorLighting => 'poor_lighting',
      HazardCategory.excessiveNoise => 'excessive_noise',
      HazardCategory.pedestrianSignalProblem => 'pedestrian_signal_problem',
      HazardCategory.other => 'other',
    };
  }

  HazardCategory _categoryFromDb(String value) {
    return switch (value) {
      'blocked_sidewalk' => HazardCategory.blockedSidewalk,
      'pothole_or_damaged_pavement' => HazardCategory.potholeOrDamagedPavement,
      'missing_or_damaged_curb_ramp' => HazardCategory.missingOrDamagedCurbRamp,
      'stairs_or_inaccessible_path' => HazardCategory.stairsOrInaccessiblePath,
      'broken_elevator' => HazardCategory.brokenElevator,
      'construction_closure' => HazardCategory.constructionClosure,
      'poor_lighting' => HazardCategory.poorLighting,
      'excessive_noise' => HazardCategory.excessiveNoise,
      'pedestrian_signal_problem' => HazardCategory.pedestrianSignalProblem,
      _ => HazardCategory.other,
    };
  }

  String _statusToDb(HazardStatus status) {
    return switch (status) {
      HazardStatus.underReview => 'under_review',
      _ => status.name,
    };
  }

  HazardStatus _statusFromDb(String value) {
    return switch (value) {
      'under_review' => HazardStatus.underReview,
      _ => HazardStatus.values.byName(value),
    };
  }

  String _responseToDb(ConfirmationResponse response) => switch (response) {
        ConfirmationResponse.stillPresent => 'still_present',
        ConfirmationResponse.resolved => 'resolved',
        ConfirmationResponse.unableToDetermine => 'unable_to_determine',
      };

  String _evidenceToDb(EvidenceType type) => switch (type) {
        EvidenceType.visual => 'visual',
        EvidenceType.traveledThrough => 'traveled_through',
        EvidenceType.other => 'other',
      };
}
