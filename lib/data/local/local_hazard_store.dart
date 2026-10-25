import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/geo_point.dart';
import '../models/hazard.dart';

/// Session + disk persistence for demonstration / offline draft reports.
class LocalHazardStore {
  LocalHazardStore(this._prefs);

  static const storageKey = 'pathable_local_hazards_v1';

  final SharedPreferences _prefs;

  List<Hazard> load() {
    final raw = _prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => _fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<void> save(List<Hazard> hazards) async {
    final payload = jsonEncode(hazards.map(_toJson).toList(growable: false));
    await _prefs.setString(storageKey, payload);
  }

  Map<String, dynamic> _toJson(Hazard hazard) {
    return {
      'id': hazard.id,
      'category': hazard.category.name,
      'severity': hazard.severity.name,
      'status': hazard.status.name,
      'latitude': hazard.location.latitude,
      'longitude': hazard.location.longitude,
      'confidenceScore': hazard.confidenceScore,
      'createdAt': hazard.createdAt.toIso8601String(),
      'updatedAt': hazard.updatedAt.toIso8601String(),
      'description': hazard.description,
      'lastConfirmedAt': hazard.lastConfirmedAt?.toIso8601String(),
      'expiresAt': hazard.expiresAt?.toIso8601String(),
      'resolvedAt': hazard.resolvedAt?.toIso8601String(),
      'createdBy': hazard.createdBy,
      'photoPath': hazard.photoPath,
      'isDemonstration': hazard.isDemonstration,
    };
  }

  Hazard _fromJson(Map<String, dynamic> json) {
    return Hazard(
      id: json['id'] as String,
      category: HazardCategory.values.byName(json['category'] as String),
      severity: HazardSeverity.values.byName(json['severity'] as String),
      status: HazardStatus.values.byName(json['status'] as String),
      location: GeoPoint(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
      ),
      confidenceScore: (json['confidenceScore'] as num).toDouble(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      description: json['description'] as String?,
      lastConfirmedAt: _parseDate(json['lastConfirmedAt']),
      expiresAt: _parseDate(json['expiresAt']),
      resolvedAt: _parseDate(json['resolvedAt']),
      createdBy: json['createdBy'] as String?,
      photoPath: json['photoPath'] as String?,
      isDemonstration: json['isDemonstration'] as bool? ?? true,
    );
  }

  DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    return DateTime.parse(value);
  }
}
